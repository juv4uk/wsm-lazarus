{ G6.141 — близнюк навантаження `loop` мовою Free Pascal.
  Те саме тіло: N разів додати K, код виходу = сума & 255. }
program loop;
{$mode objfpc}{$H+}
uses SysUtils;
var
  N, K, I: QWord;
  Acc: QWord;
begin
  N := 1000000;
  K := 1;
  if ParamStr(1) <> '' then N := StrToInt64(ParamStr(1));
  if ParamStr(2) <> '' then K := StrToInt64(ParamStr(2));
  Acc := 0;
  I := 0;
  while I < N do begin
    Acc := Acc + K;
    Inc(I);
  end;
  Halt(Integer(Acc and 255));
end.
