{ G6.145 — близнюк навантаження `ackermann` мовою Free Pascal. }
program ackermann;
{$mode objfpc}{$H+}
uses SysUtils;
function Ack(M, N: QWord): QWord;
begin
  if M = 0 then Exit(N + 1);
  if N = 0 then Exit(Ack(M - 1, 1));
  Result := Ack(M - 1, Ack(M, N - 1));
end;
var
  M, N: QWord;
begin
  M := 2; N := 2;
  if ParamStr(1) <> '' then M := StrToInt64(ParamStr(1));
  if ParamStr(2) <> '' then N := StrToInt64(ParamStr(2));
  Halt(Integer(Ack(M, N) and 255));
end.
