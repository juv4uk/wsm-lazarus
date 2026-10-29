{ Близнюк Free Pascal для навантаження `fib`.
  Те саме тіло: рекурсивне fib на стеку.
  Протокол: Halt(fib(N) and 255), N вшитий у код. }
program fibpas;
{$mode objfpc}{$H+}
{ N приходить із файла-включення, який генерує runner: так N вшитий
  у код так само, як у C-близнюка через -D, а не читається в рантаймі. }
{$I fib_n.inc}

function Fib(N: QWord): QWord;
begin
  if N < 2 then Exit(N);
  Result := Fib(N - 1) + Fib(N - 2);
end;

begin
  Halt(Integer(Fib(QWord(FIB_N)) and 255));
end.
