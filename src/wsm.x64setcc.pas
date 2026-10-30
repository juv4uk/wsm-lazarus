{ G6.247 — вузький machine-only SETcc r/m8 для x86-64.
  Без REX доступні лише низькі байти AL/CL/DL/BL: SP/BP/SI/DI
  потребують REX і тут навмисно відхиляються.
  Вхід: код, host cc 0..15 та host регістр; вихід: рівно 3 байти
  0F (90+cc) (C0+reg). Немає SENS доменів, проєкцій чи законів.
  Code.Bytes володіє керованим буфером; відмова не змінює його.
  Питання: 1) Чому лише AL/CL/DL/BL без REX?
  2) Чому ModRM.reg для SETcc дорівнює нулю?
  3) Хто встановлює FLAGS до виклику?
  4) Чому host cc не стає мовним SENS оператором?
  5) Чому квоту перевіряємо до дописування? }
unit wsm.x64setcc;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64SetCondition8(var Code:TX64Code;Condition:Integer;
                           Destination:TX64Reg);
implementation
const MaxMachineBytes=256;
procedure X64SetCondition8(var Code:TX64Code;Condition:Integer;
                           Destination:TX64Reg);
var Machine:RawByteString;
begin
  if (Condition<0) or (Condition>15) then
    raise EX64CodeError.Create('SETcc: host умова має бути 0..15');
  if Ord(Destination)>Ord(xrBX) then
    raise EX64CodeError.Create('SETcc: low-byte регістр потребує REX');
  if Length(Code.Bytes)>MaxMachineBytes-3 then
    raise EX64CodeError.Create('SETcc: перевищено host-квоту 256 байтів');
  Machine:=#$0F+AnsiChar($90+Condition)+AnsiChar($C0+Ord(Destination));
  Code.Bytes:=Code.Bytes+Machine;
end;
end.
