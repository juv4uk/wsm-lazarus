{ G1.8 — фізична D12+ ширина, не числова семантика.
  Джерело істини про байти, роздільники, адреси: wsm.physloc.
  Ширина >= 12 не дає автоматично числового значення чи викличності. }
unit wsm.widespan;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.physloc;
const
  FirstWideNumericPlane = 12; { межа обліку, НЕ новий закон D12 }
  MaxWideWords = 4096;
type
  EWideSpanError = class(Exception);
  TWideWord = record
    Width: SizeInt;             { фізична довжина бітів, не host integer }
    Bits: RawByteString;        { точні 0/1 включно з провідними нулями }
    Span: TPhysicalWordSpan;    { 1-based слово, 0-based напіввідкриті адреси }
  end;
  TWideWords = array of TWideWord;

procedure CollectWideWords(const Physical: RawByteString;
  out Wide: TWideWords);
function WideTSV(const Wide: TWideWords): RawByteString;

implementation
uses wsm.t5m;

procedure CollectWideWords(const Physical: RawByteString;
  out Wide: TWideWords);
var Words: TExactWords; Spans: TPhysicalWordSpans;
    Staged: TWideWords; I, N, Capacity: SizeInt;
begin
  SetLength(Wide,0);
  SetLength(Staged,0);
  DecodeT5MWithLocations(Physical,Words,Spans);
  if Length(Words) <> Length(Spans) then
    raise EWideSpanError.Create('різна кількість слів і фізичних адрес');
  N:=0; Capacity:=0;
  for I:=0 to High(Words) do begin
    if Length(Words[I]) < FirstWideNumericPlane then Continue;
    if N >= MaxWideWords then
      raise EWideSpanError.Create('перевищено межу 4096 широких слів');
    if (Spans[I].IsEOF) or (Spans[I].WordIndex<>I+1) or
       (Spans[I].TritStart<0) or
       (Spans[I].TritEnd-Spans[I].TritStart<>Length(Words[I])) or
       (Spans[I].ByteStart<>Spans[I].TritStart div 5) or
       (Spans[I].ByteEnd<>(Spans[I].TritEnd+4) div 5) or
       (Spans[I].ByteEnd>Length(Physical)) then
      raise EWideSpanError.Create('зіпсовано фізичну адресу широкого слова');
    if N=Capacity then begin
      if Capacity=0 then Capacity:=16 else Capacity:=Capacity*2;
      if Capacity>MaxWideWords then Capacity:=MaxWideWords;
      SetLength(Staged,Capacity);
    end;
    Staged[N].Width:=Length(Words[I]);
    Staged[N].Bits:=Words[I];
    Staged[N].Span:=Spans[I];
    Inc(N);
  end;
  SetLength(Staged,N);
  Wide:=Staged; { єдина атомарна публікація }
end;

function WideTSV(const Wide: TWideWords): RawByteString;
var I,J,LastWord,LastEnd,Gap,Distance:SizeInt;
    W:TWideWord; Candidate:RawByteString;
begin
  { G1.35: WideTSV — ПУБЛІЧНИЙ API, а не лише результат CollectWideWords.
    Сторонній викликач може передати forged записи поза фізичною T5M
    квотою: до формування тексту застосовуємо ТУ САМУ верхню межу
    кількості wide слів, що і фізичний збирач. }
  if Length(Wide)>MaxWideWords then
    raise EWideSpanError.Create('перевищено межу 4096 широких записів TSV');
  Candidate:='слово'#9'ширина'#9'точні-біти'#9'трити'#9'байти'#10;
  LastWord:=0;
  LastEnd:=-1;
  for I:=0 to High(Wide) do begin
    W:=Wide[I];
    { Публічний API приймає записи також від інших FPC викликачів.
      Перевірка локальних довжин не доводить точних двійкових бітів
      або фізичного порядку. Валідувати ДО публікації TSV. }
    if (W.Width < FirstWideNumericPlane) or
       (W.Width<>Length(W.Bits)) or
       (W.Span.IsEOF) or (W.Span.WordIndex<1) or
       (W.Span.TritStart<0) or
       (W.Span.TritEnd<=W.Span.TritStart) or
       (W.Span.TritEnd-W.Span.TritStart<>W.Width) or
       (W.Span.ByteStart<0) or
       (W.Span.ByteEnd<=W.Span.ByteStart) or
       (W.Span.ByteStart<>W.Span.TritStart div 5) or
       { Фізичне джерело T5M не може перевищувати 4 МіБ.
         Додатна ширина та валідні локальні spans не доводять цього. }
       (W.Span.TritEnd>MAX_T5M_FILE_BYTES*5) or
       (W.Span.ByteEnd>MAX_T5M_FILE_BYTES) or
       { Ceil(trit_end/5), без додавання +4 до SizeInt. }
       (W.Span.ByteEnd<>((W.Span.TritEnd-1) div 5)+1) then
      raise EWideSpanError.Create('некоректний широкий запис TSV');
    { Фізична геометрія також обмежує пропущені НЕШИРОКІ слова.
      Навіть мінімальне W1 займає один трит; між КОЖНИМИ сусідніми
      словами є ще один трит-роздільник 2. Тому для #a -> #b
      після попереднього кінця потрібен розрив >= 2*(b-a)-1.
      Для першого видимого #k перед ним потрібно >=2*(k-1)
      тритів. Перевіряємо через ділення, без небезпечного 2*k. }
    if I=0 then begin
      if ((W.Span.WordIndex=1) and (W.Span.TritStart<>0)) or
         (W.Span.WordIndex-1>W.Span.TritStart div 2) then
        raise EWideSpanError.Create(
          'неможливий фізичний початок широкого слова');
      { Усі попередні невидимі wide-відбору слова мають W1..W11,
        після кожного рівно один роздільник. Для #k фізичний
        старт обмежено 2*(k-1) .. 12*(k-1), без множення й overflow.
        TritStart-1 безпечний тут лише за додатної адреси. }
      if (W.Span.TritStart>0) and
         ((W.Span.TritStart-1) div 12>=W.Span.WordIndex-1) then
        raise EWideSpanError.Create(
          'надто великий початковий проміжок до широкого слова');
    end else begin
      if (W.Span.WordIndex<=LastWord) or
         (W.Span.TritStart<=LastEnd) then
        raise EWideSpanError.Create(
          'порушено порядок фізичних широких слів');
      Distance:=W.Span.WordIndex-LastWord;
      Gap:=W.Span.TritStart-LastEnd;
      if (Distance-1>(Gap-1) div 2) then
        raise EWideSpanError.Create(
          'бракує фізичних слів або T5M-роздільників у проміжку');
      { Між двома видимими W12+ може бути тільки Distance-1
        невидимих W1..W11. Кожен має 1..11 точних бітів;
        всі Distance роздільників займають рівно по одному триту.
        Верхня межа Gap<=12*(Distance-1)+1; перевірка через
        ділення, без потенційного переповнення 12*Distance. }
      if (Gap>=2) and ((Gap-2) div 12>=Distance-1) then
        raise EWideSpanError.Create(
          'неможливо довгий проміжок між фізичними словами');
    end;
    for J:=1 to Length(W.Bits) do
      if (W.Bits[J]<>'0') and (W.Bits[J]<>'1') then
        raise EWideSpanError.Create('не двійковий біт у фізичному TSV');
    LastWord:=W.Span.WordIndex;
    LastEnd:=W.Span.TritEnd;
    Candidate:=Candidate+
      IntToStr(W.Span.WordIndex)+#9+'D'+IntToStr(W.Width)+#9+
      W.Bits+#9+
      '['+IntToStr(W.Span.TritStart)+','+IntToStr(W.Span.TritEnd)+')'+#9+
      '['+IntToStr(W.Span.ByteStart)+','+IntToStr(W.Span.ByteEnd)+')'+#10;
  end;
  Result:=Candidate;
end;
end.
