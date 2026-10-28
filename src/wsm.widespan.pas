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
var I:SizeInt; W:TWideWord; Candidate:RawByteString;
begin
  Candidate:='слово'#9'ширина'#9'точні-біти'#9'трити'#9'байти'#10;
  for I:=0 to High(Wide) do begin
    W:=Wide[I];
    if (W.Width < FirstWideNumericPlane) or
       (W.Width<>Length(W.Bits)) or
       (W.Span.IsEOF) or (W.Span.WordIndex<1) or
       (W.Span.TritEnd-W.Span.TritStart<>W.Width) or
       (W.Span.ByteStart<>W.Span.TritStart div 5) or
       (W.Span.ByteEnd<>(W.Span.TritEnd+4) div 5) then
      raise EWideSpanError.Create('некоректний широкий запис TSV');
    Candidate:=Candidate+
      IntToStr(W.Span.WordIndex)+#9+'D'+IntToStr(W.Width)+#9+
      W.Bits+#9+
      '['+IntToStr(W.Span.TritStart)+','+IntToStr(W.Span.TritEnd)+')'+#9+
      '['+IntToStr(W.Span.ByteStart)+','+IntToStr(W.Span.ByteEnd)+')'+#10;
  end;
  Result:=Candidate;
end;
end.
