{ G6.251 — обмежений host x86-64 SHRD r32,r32,imm8.
  Це машинна інструкція подвійного зсуву вправо для D24+ lowering,
  але НЕ закон SENS і не визначення жодної мовної операції.
  Вхід: два реєстри r32 (0..7), фізичний host-зсув 1..31.
  Вихід: 0F AC /r ib; ModRM.reg=source, ModRM.r/m=destination.
  Код належить TX64Code; перевірка ПЕРЕД записом зберігає атомарність
  відмови та вже застосовані RIP-позначки.
  Навіщо не дозволяти count=0 або >=32 з їх залежною від CPU поведінкою?
  Чому SHRD вставляє старший біт саме з молодшого біта джерела?
  Чим інструкція SHRD відрізняється від ратифікованого SENS закону? }
unit wsm.x64shrd;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64SHRD32(var Code:TX64Code; Destination,Source:TX64Reg;
                    Count:Integer);
implementation
const MaxMachineBytes=256;
procedure X64SHRD32(var Code:TX64Code; Destination,Source:TX64Reg;
                    Count:Integer);
var Instruction:RawByteString; ModRM:Byte;
begin
  if (Ord(Destination)<0) or (Ord(Destination)>7) or
     (Ord(Source)<0) or (Ord(Source)>7) then
    raise EX64CodeError.Create('SHRD: недопустимий host-регістр r32');
  if (Count<1) or (Count>31) then
    raise EX64CodeError.Create('SHRD: host-зсув має бути у межах 1..31');
  if Length(Code.Bytes)>MaxMachineBytes-4 then
    raise EX64CodeError.Create('SHRD: переповнення host-квоти 256 байтів');
  ModRM:=$C0 or (Ord(Source) shl 3) or Ord(Destination);
  Instruction:=#$0F#$AC+AnsiChar(ModRM)+AnsiChar(Byte(Count));
  Code.Bytes:=Code.Bytes+Instruction;
end;
end.
