unit test_support;

{$mode objfpc}{$H+}

interface

var
  TestPasses: LongInt;
  TestFailures: LongInt;

procedure Check(Condition: Boolean; const Name: string);
procedure Finish;

implementation

procedure Check(Condition: Boolean; const Name: string);
begin
  if Condition then
    Inc(TestPasses)
  else
  begin
    Inc(TestFailures);
    WriteLn('FAIL: ', Name);
  end;
end;

procedure Finish;
begin
  WriteLn('TEST-HARNESS: pass=', TestPasses, ' fail=', TestFailures);
  if TestFailures <> 0 then
    Halt(1);
end;

initialization
  TestPasses := 0;
  TestFailures := 0;

end.
