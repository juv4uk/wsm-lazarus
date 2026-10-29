{ Попередній обмежений допуск фізичного двійкового потоку SENS до D2.
  Це НЕ новий декодер, не мовний закон і не українська проєкція.
  Точні слова й D2 AST визначають уже злиті wsm.t5m та wsm.d2source.
  Під час перевірки не повертаємо часткових вузлів/результатів. }
unit wsm.t5madmission;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, wsm.d2source, wsm.physloc;

type
  { G1.32: адреса ФІЗИЧНОГО транспортного збою до D2 parser.
    Байти/трити — 0-based, слово — 1-based. Для EOF і nil
    адреса вказує на межу отриманих байтів, а не мовний закон. }
  ET5MAdmissionError = class(Exception)
  public
    ByteOffset, TritOffset, WordIndex: SizeInt;
    constructor CreateAt(const Problem: String;
      AtByte, AtTrit, AtWord: SizeInt);
  end;
function ReadCheckedD2Stream(Input: TStream): TD2Document;
{ Механічний потоковий допуск широких exact слів. W12/24 — не
  числовий semantic admission; немає виконавчих повноважень. }
function ReadCheckedD2WideStream(Input: TStream): TD2Document;
{ G1.30: один прохід фізичного TStream, потім чинні точні
  тритові/байтові адреси та D2-діагностика; out Spans атомарний. }
function ReadCheckedD2WideLocatedStream(Input: TStream;
  out Spans: TPhysicalWordSpans): TD2Document;

implementation
uses wsm.t5m;

constructor ET5MAdmissionError.CreateAt(const Problem: String;
  AtByte, AtTrit, AtWord: SizeInt);
begin
  inherited Create(Problem);
  ByteOffset := AtByte;
  TritOffset := AtTrit;
  WordIndex := AtWord;
end;

function ReadCheckedD2StreamBounded(Input: TStream;
  MaxWordBits: SizeInt; WithLocations: Boolean;
  out Spans: TPhysicalWordSpans): TD2Document;
const
  Divisors: array[0..4] of Integer = (81, 27, 9, 3, 1);
var
  Chunk: array[0..4095] of Byte;
  Physical: RawByteString;
  Used, Capacity, N, I, K, Digit, B: SizeInt;
  CurrentWidth, Padding, WordCount: SizeInt;

  procedure FailAt(const Problem:String; AtByte,AtTrit,AtWord:SizeInt);
  begin
    raise ET5MAdmissionError.CreateAt(Problem,AtByte,AtTrit,AtWord);
  end;

  procedure FinishWord(AtByte,AtTrit:SizeInt);
  begin
    Inc(WordCount);
    if WordCount > MaxD2Words then
      FailAt('перевищено межу фізичних слів D2',
        AtByte,AtTrit,WordCount);
    CurrentWidth := 0;
  end;

begin
  { Fail-closed: навіть пізній збій T5M/D2 не залишить попередніх
    trusted фізичних адрес у виклику з уже заповненим out. }
  SetLength(Spans, 0);
  if Input = nil then
    FailAt('відсутній фізичний потік',0,0,1);
  Physical := '';
  Used := 0;
  Capacity := 0;
  CurrentWidth := 0;
  Padding := 0;
  WordCount := 0;
  while True do begin
    N := Input.Read(Chunk, SizeOf(Chunk));
    if N = 0 then Break;
    if (N < 0) or (N > SizeOf(Chunk)) then
      FailAt('некоректний обсяг читання потоку',Used,Used*5,WordCount+1);
    if N > MAX_T5M_FILE_BYTES - Used then
      FailAt('фізичний файл перевищує 4 МіБ',
        MAX_T5M_FILE_BYTES,MAX_T5M_FILE_BYTES*5,WordCount+1);
    for I := 0 to N - 1 do begin
      B := Chunk[I];
      if B >= 243 then
        FailAt('неприпустимий фізичний байт T5M',
          Used+I,(Used+I)*5,WordCount+1);
      for K := 0 to 4 do begin
        Digit := (B div Divisors[K]) mod 3;
        if Digit = 2 then begin
          if CurrentWidth > 0 then begin
            FinishWord(Used+I,(Used+I)*5+K);
            Padding := 1;
          end else begin
            Inc(Padding);
            if Padding >= 5 then
              FailAt('більше чотирьох кінцевих тритів заповнення',
                Used+I,(Used+I)*5+K,WordCount+1);
          end;
        end else begin
          if Padding > 1 then
            FailAt('повторний роздільник між словами',
              Used+I,(Used+I)*5+K,WordCount+1);
          if (Padding > 0) and (WordCount = 0) then
            FailAt('роздільник на початку потоку',
              Used+I,(Used+I)*5+K,WordCount+1);
          Padding := 0;
          Inc(CurrentWidth);
          if CurrentWidth > MaxWordBits then
            FailAt('слово ширше ніж фізична межа W1–W' +
              IntToStr(MaxWordBits),Used+I,(Used+I)*5+K,WordCount+1);
        end;
      end;
    end;
    if Used + N > Capacity then begin
      if Capacity = 0 then Capacity := 4096;
      while Capacity < Used + N do begin
        if Capacity > MAX_T5M_FILE_BYTES div 2 then
          Capacity := MAX_T5M_FILE_BYTES
        else
          Capacity := Capacity * 2;
      end;
      SetLength(Physical, Capacity);
    end;
    Move(Chunk[0], Physical[Used+1], N);
    Inc(Used, N);
  end;
  if CurrentWidth > 0 then FinishWord(Used,Used*5);
  if WordCount = 0 then
    FailAt('порожня фізична двійкова програма',Used,Used*5,1);
  SetLength(Physical, Used);
  { Після фізичного preflight використовуємо тільки чинний читач.
    Ніякого нового правила D2, викличності чи назви операції тут немає. }
  if WithLocations then begin
    { Ніякого другого адресного декодера: після потокового preflight
      єдина семантично нейтральна карта — вже існуючий wsm.physloc. }
    if MaxWordBits = MaxWideD2WordBits then
      Result := ReadD2WideWithPhysicalLocations(Physical, Spans)
    else
      Result := ReadD2WithPhysicalLocations(Physical, Spans);
  end else if MaxWordBits = MaxWideD2WordBits then
    Result := ReadD2T5MWide(Physical)
  else
    Result := ReadD2T5M(Physical);
end;

function ReadCheckedD2Stream(Input: TStream): TD2Document;
var UnusedSpans: TPhysicalWordSpans;
begin
  Result := ReadCheckedD2StreamBounded(Input, 9, False, UnusedSpans);
end;

function ReadCheckedD2WideStream(Input: TStream): TD2Document;
var UnusedSpans: TPhysicalWordSpans;
begin
  Result := ReadCheckedD2StreamBounded(Input, MaxWideD2WordBits,
    False, UnusedSpans);
end;

function ReadCheckedD2WideLocatedStream(Input: TStream;
  out Spans: TPhysicalWordSpans): TD2Document;
begin
  Result := ReadCheckedD2StreamBounded(Input, MaxWideD2WordBits,
    True, Spans);
end;

{ Типи/ресурси: Input — borrowed TStream, не закриваємо й не шукаємо
  довільні позиції; Physical — owned bounded RawByteString (<=4МіБ),
  звільняється після виходу; Spans — owned масив exact-record,
  очищується до читання і публікується лише після всього D2.
  Повернений TD2Document — owned caller і мусить бути Free.
  Діагностика ET5MAdmissionError (byte/trit/word) та ED2PhysicalError
  є фізичною, а не SENS law.
  Питання: 1) Чому W24 ще не є D24? 2) Чому T5M початковий
  preflight не задає закон? 3) Хто володіє TD2Document?
  4) Як відрізнити byte span від точного trit span?
  5) Чому порожній out важливий після пізнього EOF? }

end.
