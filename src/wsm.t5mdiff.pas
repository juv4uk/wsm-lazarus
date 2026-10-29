{ Порівняння двох ФІЗИЧНИХ T5M SENS без другого reader чи семантики. }
unit wsm.t5mdiff;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.physloc;
type
  ET5MDiffError=class(Exception);
  TPhysicalDifference=record
    Equal:Boolean;
    WordIndex:SizeInt; { 1-based; 0 = без розходжень }
    LeftPresent,RightPresent:Boolean;
    LeftBits,RightBits:RawByteString;
    LeftSpan,RightSpan:TPhysicalWordSpan;
  end;
procedure ComparePhysical(const Left,Right:RawByteString;
  out Difference:TPhysicalDifference);
implementation
uses wsm.t5m;

procedure ComparePhysical(const Left,Right:RawByteString;
  out Difference:TPhysicalDifference);
var LW,RW:TExactWords; LS,RS:TPhysicalWordSpans;
    I,N,First:SizeInt; Candidate:TPhysicalDifference;
begin
  Difference.Equal:=False;
  Difference.WordIndex:=0;
  Difference.LeftPresent:=False;Difference.RightPresent:=False;
  Difference.LeftBits:='';Difference.RightBits:='';
  { Обидва документи мають пройти перевірку до першого результату. }
  DecodeT5MWithLocations(Left,LW,LS);
  DecodeT5MWithLocations(Right,RW,RS);
  N:=Length(LW);
  if Length(RW)<N then N:=Length(RW);
  First:=0;
  for I:=0 to N-1 do
    if LW[I]<>RW[I] then begin First:=I+1;Break end;
  if (First=0) and (Length(LW)<>Length(RW)) then First:=N+1;
  Candidate.Equal:=First=0;
  Candidate.WordIndex:=First;
  Candidate.LeftPresent:=(First>0) and (First<=Length(LW));
  Candidate.RightPresent:=(First>0) and (First<=Length(RW));
  Candidate.LeftBits:='';Candidate.RightBits:='';
  if First>0 then begin
    Candidate.LeftSpan:=LocatePhysicalWord(Left,LS,First);
    Candidate.RightSpan:=LocatePhysicalWord(Right,RS,First);
    if Candidate.LeftPresent then Candidate.LeftBits:=LW[First-1];
    if Candidate.RightPresent then Candidate.RightBits:=RW[First-1];
  end;
  Difference:=Candidate;
end;
end.
