program wsm_headless;

{$mode objfpc}{$H+}

const
  HarnessVersion = '0.0.0-m0.2';
  FpcBaseline = '3.2.2';

procedure PrintUsage;
begin
  WriteLn('usage: wsm-headless --version|--self-test');
end;

begin
  if ParamCount <> 1 then
  begin
    PrintUsage;
    Halt(64);
  end;

  if ParamStr(1) = '--version' then
  begin
    WriteLn('WSM-LAZARUS-HEADLESS version=', HarnessVersion);
    WriteLn('FPC-BASELINE >=', FpcBaseline);
    Halt(0);
  end;

  if ParamStr(1) = '--self-test' then
  begin
    WriteLn('HEADLESS-HARNESS-OK');
    Halt(0);
  end;

  PrintUsage;
  Halt(64);
end.
