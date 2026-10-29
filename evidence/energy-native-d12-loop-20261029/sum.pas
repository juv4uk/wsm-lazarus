program SumBench;
{$mode objfpc}{$H+}
uses SysUtils;

var
  Count, I: QWord;
  Sum: LongWord;

begin
  if ParamCount <> 1 then Halt(64);
  Count := StrToQWord(ParamStr(1));
  Sum := 0;
  I := Count;
  while I > 0 do begin
    Inc(Sum, LongWord(I));
    Dec(I);
  end;
  Halt(Sum and 255);
end.
