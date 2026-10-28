{ G1.12: фізичні T5M-свідки. Лише чинні wsm.t5m/wsm.physloc
  визначають допуск і адреси. Жодної нової семантики SENS. }
unit wsm.t5mdiff;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.physloc;
type
  TPhysicalDiffKind = (pdNotChecked, pdEqual, pdBits, pdWidth, pdWordCount);
  TPhysicalComparison = record
    Kind: TPhysicalDiffKind;
    WordIndex, BitIndex, LeftWidth, RightWidth: SizeInt;
    LeftCount, RightCount: SizeInt;
    LeftSpan, RightSpan: TPhysicalWordSpan;
  end;
procedure ComparePhysicalWords(const LeftPhysical, RightPhysical: RawByteString;
  out Comparison: TPhysicalComparison);
function DiffKindName(K: TPhysicalDiffKind): UnicodeString;
implementation
uses wsm.t5m;

function DiffKindName(K: TPhysicalDiffKind): String;
begin
  case K of
    pdEqual: Result:='тотожні';
    pdBits: Result:='біти';
    pdWidth: Result:='ширина';
    pdWordCount: Result:='кількість-слів';
  else Result:='не-перевірено';
  end;
end;

procedure ComparePhysicalWords(const LeftPhysical, RightPhysical: RawByteString;
  out Comparison: TPhysicalComparison);
var A,B: TExactWords; ASps,BSps:TPhysicalWordSpans;
    C:TPhysicalComparison; I,J,Common:SizeInt;
begin
  { Проміжний результат не виходить із функції, доки не допущено ОБИДВА
    фізичні джерела. Ніякого спелінг-розпізнавання чи D12 обчислень. }
  FillChar(Comparison,SizeOf(Comparison),0);
  Comparison.Kind:=pdNotChecked;
  DecodeT5MWithLocations(LeftPhysical,A,ASps);
  DecodeT5MWithLocations(RightPhysical,B,BSps);
  FillChar(C,SizeOf(C),0);
  C.Kind:=pdEqual;
  C.LeftCount:=Length(A); C.RightCount:=Length(B);
  if Length(A)<Length(B) then Common:=Length(A) else Common:=Length(B);
  for I:=0 to Common-1 do begin
    if A[I]=B[I] then Continue;
    C.WordIndex:=I+1;
    C.LeftSpan:=LocatePhysicalWord(LeftPhysical,ASps,I+1);
    C.RightSpan:=LocatePhysicalWord(RightPhysical,BSps,I+1);
    C.LeftWidth:=Length(A[I]); C.RightWidth:=Length(B[I]);
    if C.LeftWidth<>C.RightWidth then C.Kind:=pdWidth
    else begin
      C.Kind:=pdBits;
      for J:=1 to Length(A[I]) do
        if A[I][J]<>B[I][J] then begin C.BitIndex:=J; Break; end;
    end;
    Comparison:=C; Exit;
  end;
  if Length(A)<>Length(B) then begin
    C.Kind:=pdWordCount; C.WordIndex:=Common+1;
    C.LeftSpan:=LocatePhysicalWord(LeftPhysical,ASps,Common+1);
    C.RightSpan:=LocatePhysicalWord(RightPhysical,BSps,Common+1);
    if Common<Length(A) then C.LeftWidth:=Length(A[Common]);
    if Common<Length(B) then C.RightWidth:=Length(B[Common]);
  end else if LeftPhysical<>RightPhysical then
    raise EPhysicalLocationError.Create('однакові слова, але різні байти T5M');
  Comparison:=C;
end;
end.
