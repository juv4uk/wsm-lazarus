{ Компілятор G6: точний host-кодер x86-64 BSF/BSR, а не закон SENS.
  Вхід: TX64Code (managed RawByteString), операція та два регістри r32.
  Вихід: три машинні байти 0F BC/BD ModRM у тому самому буфері.
  Allocation/lifetime: caller володіє TX64Code; тимчасові байти managed.
  Відмова не змінює Code.Bytes; межа спільного host-коду 256 байтів.
  ВАЖЛИВО: при нульовому операнді BSF/BSR залишає результат undefined.
  Допуск ненульового входу — відповідальність майбутнього lowering;
  цей механізм не вводить мовної операції чи Dn-dispatch.
  Питання: 1) Чому Dn не можна вивести з opcode?
  2) Чому порядок ModRM reg/rm важливий?
  3) Чому результат BSF/BSR на нулі не можна використовувати?
  4) Чому квота перевіряється до конкатенації?
  5) Чому GNU as перевіряє механізм, але не SENS паритет? }
unit wsm.x64bitscan;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type
  TX64BitScan=(xbFirstSet,xbLastSet);
procedure X64BitScan32(var Code:TX64Code;Operation:TX64BitScan;
                       Destination,Source:TX64Reg);
implementation
const MaxMachineBytes=256;
procedure X64BitScan32(var Code:TX64Code;Operation:TX64BitScan;
                       Destination,Source:TX64Reg);
var Opcode,ModRM:Byte; Instruction:RawByteString;
begin
  if (Ord(Destination)>7) or (Ord(Source)>7) then
    raise EX64CodeError.Create('BSF/BSR: недопустимий host r32');
  case Operation of
    xbFirstSet:Opcode:=$BC;
    xbLastSet:Opcode:=$BD;
  else
    raise EX64CodeError.Create('BSF/BSR: невідомий host opcode');
  end;
  ModRM:=$C0 or (Ord(Destination) shl 3) or Ord(Source);
  Instruction:=#$0F+AnsiChar(Opcode)+AnsiChar(ModRM);
  if Length(Code.Bytes)>MaxMachineBytes-Length(Instruction) then
    raise EX64CodeError.Create('BSF/BSR: квота host-коду 256 байтів');
  Code.Bytes:=Code.Bytes+Instruction;
end;
end.
