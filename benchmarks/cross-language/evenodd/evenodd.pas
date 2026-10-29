{ G6.150 — близнюк навантаження `evenodd` мовою Free Pascal. }
program evenodd;
{$mode objfpc}{$H+}
uses SysUtils;
function Odd1(N: QWord): QWord; forward;
function Even1(N: QWord): QWord;
begin
  if N < 1 then Exit(1);
  Result := Odd1(N - 1);
end;
function Odd1(N: QWord): QWord;
begin
  if N < 1 then Exit(0);
  Result := Even1(N - 1);
end;
var
  N: QWord;
begin
  N := 0;
  if ParamStr(1) <> '' then N := StrToInt64(ParamStr(1));
  Halt(Integer(Even1(N) and 255));
end.
