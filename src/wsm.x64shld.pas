{ G6.249 — обмежений host x86-64 SHLD r32,r32,imm8.
  Це машинна інструкція для майбутнього lowering, не закон SENS.
  Вхід: два реєстри r32 (0..7), фізичний host-зсув 1..31.
  Вихід: 0F A4 /r ib; ModRM.reg=source, ModRM.r/m=destination.
  Код належить TX64Code; перевірка ПЕРЕД записом зберігає атомарність
  відмови та вже застосовані RIP-позначки.
  Навіщо не дозволяти count=0 або >=32 з їх залежною від CPU поведінкою?
  Чим інструкція SHLD відрізняється від ратифікованого SENS закону? }
unit wsm.x64shld;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64SHLD32(var Code:TX64Code; Destination,Source:TX64Reg;
                    Count:Integer);
implementation
const MaxMachineBytes=256;
procedure X64SHLD32(var Code:TX64Code; Destination,Source:TX64Reg;
                    Count:Integer);
var Instruction:RawByteString; ModRM:Byte;
begin
  if (Ord(Destination)>7) or (Ord(Source)>7) then
    raise EX64CodeError.Create('SHLD: недопустимий host-регістр r32');
  if (Count<1) or (Count>31) then
    raise EX64CodeError.Create('SHLD: host-зсув має бути у межах 1..31');
  if Length(Code.Bytes)>MaxMachineBytes-4 then
    raise EX64CodeError.Create('SHLD: переповнення host-квоти 256 байтів');
  ModRM:=$C0 or (Ord(Source) shl 3) or Ord(Destination);
  Instruction:=#$0F#$A4+AnsiChar(ModRM)+AnsiChar(Byte(Count));
  Code.Bytes:=Code.Bytes+Instruction;
end;
end.
