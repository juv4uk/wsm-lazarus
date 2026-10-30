{ G6.156 — близнюк хвостової рекурсії мовою Free Pascal.
  Тіло: лічильник униз із накопичувачем; самовиклик — ХВІСТ. }
program tailrec;
{$mode objfpc}{$H+}
uses SysUtils;
function CountDown(N, Acc: QWord): QWord;
begin
  if N < 1 then Exit(Acc);
  Result := CountDown(N - 1, Acc + 1);   { хвіст }
end;
var N: QWord;
begin
  N := 0;
  if ParamStr(1) <> '' then N := StrToQWord(ParamStr(1));
  Halt(Integer(CountDown(N, 0) and 255));
end.
