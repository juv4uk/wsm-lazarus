{ Попередній обмежений допуск фізичного двійкового потоку SENS до D2.
  Це НЕ новий декодер, не мовний закон і не українська проєкція.
  Точні слова й D2 AST визначають уже злиті wsm.t5m та wsm.d2source.
  Під час перевірки не повертаємо часткових вузлів/результатів. }
unit wsm.t5madmission;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, wsm.d2source;

type
  ET5MAdmissionError = class(Exception);
function ReadCheckedD2Stream(Input: TStream): TD2Document;
{ Механічний потоковий допуск широких exact слів. W12/24 — не
  числовий semantic admission; немає виконавчих повноважень. }
function ReadCheckedD2WideStream(Input: TStream): TD2Document;

implementation
uses wsm.t5m;

function ReadCheckedD2StreamBounded(Input: TStream;
  MaxWordBits: SizeInt): TD2Document;
const
  Divisors: array[0..4] of Integer = (81, 27, 9, 3, 1);
var
  Chunk: array[0..4095] of Byte;
  Physical: RawByteString;
  Used, Capacity, N, I, K, Digit, B: SizeInt;
  CurrentWidth, Padding, WordCount: SizeInt;

  procedure FinishWord;
  begin
    Inc(WordCount);
    if WordCount > MaxD2Words then
      raise ET5MAdmissionError.Create('перевищено межу фізичних слів D2');
    CurrentWidth := 0;
  end;

begin
  if Input = nil then
    raise ET5MAdmissionError.Create('відсутній фізичний потік');
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
      raise ET5MAdmissionError.Create('некоректний обсяг читання потоку');
    if N > MAX_T5M_FILE_BYTES - Used then
      raise ET5MAdmissionError.Create('фізичний файл перевищує 4 МіБ');
    for I := 0 to N - 1 do begin
      B := Chunk[I];
      if B >= 243 then
        raise ET5MAdmissionError.Create('неприпустимий фізичний байт T5M');
      for K := 0 to 4 do begin
        Digit := (B div Divisors[K]) mod 3;
        if Digit = 2 then begin
          if CurrentWidth > 0 then begin
            FinishWord;
            Padding := 1;
          end else begin
            Inc(Padding);
            if Padding >= 5 then
              raise ET5MAdmissionError.Create('більше чотирьох кінцевих тритів заповнення');
          end;
        end else begin
          if Padding > 1 then
            raise ET5MAdmissionError.Create('повторний роздільник між словами');
          if (Padding > 0) and (WordCount = 0) then
            raise ET5MAdmissionError.Create('роздільник на початку потоку');
          Padding := 0;
          Inc(CurrentWidth);
          if CurrentWidth > MaxWordBits then
            raise ET5MAdmissionError.Create('слово ширше ніж фізична межа W1–W' + IntToStr(MaxWordBits));
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
  if CurrentWidth > 0 then FinishWord;
  if WordCount = 0 then
    raise ET5MAdmissionError.Create('порожня фізична двійкова програма');
  SetLength(Physical, Used);
  { Після фізичного preflight використовуємо тільки чинний читач.
    Ніякого нового правила D2, викличності чи назви операції тут немає. }
  if MaxWordBits = MaxWideD2WordBits then
    Result := ReadD2T5MWide(Physical)
  else
    Result := ReadD2T5M(Physical);
end;

function ReadCheckedD2Stream(Input: TStream): TD2Document;
begin
  Result := ReadCheckedD2StreamBounded(Input, 9);
end;

function ReadCheckedD2WideStream(Input: TStream): TD2Document;
begin
  Result := ReadCheckedD2StreamBounded(Input, MaxWideD2WordBits);
end;

end.
