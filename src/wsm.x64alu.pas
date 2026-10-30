{ G6.92 — лише host x86-64 ALU, не мовний закон SENS.
  Вхід: TX64Code (managed RawByteString) і два x86-64 r32.
  Вихід: дописані 2/3 машинні байти; старе значення лишається
  незмінним при invalid opcode/регістрі/перевищенні квоти.
  Lifetime: TX64Code володіє managed байтами; ELF створює caller.

  Перевір: 1) Чому ModRM для IMUL обернений?
  2) Чому тут немає dispatch за назвами SENS?
  3) Як не втратити код при overflow?
  4) Як відрізнити host XOR від закону Dn? }
unit wsm.x64alu;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type
  TX64ALU=(xaAdd,xaSub,xaXor,xaAnd,xaCmp,xaImul,xaOr);
procedure X64ALU32(var Code:TX64Code;Operation:TX64ALU;
                   Destination,Source:TX64Reg);
implementation
const MaxMachineBytes=256;
procedure X64ALU32(var Code:TX64Code;Operation:TX64ALU;
                   Destination,Source:TX64Reg);
var Instruction:RawByteString; ModRM:Byte; First:Byte;
begin
  if (Ord(Destination)>7) or (Ord(Source)>7) then
    raise EX64CodeError.Create('недопустимий регістр host r32');
  case Operation of
    xaAdd:First:=$01;  { ADD r/m32, r32 }
    xaSub:First:=$29;  { SUB r/m32, r32 }
    xaXor:First:=$31;  { XOR r/m32, r32 }
    xaAnd:First:=$21;  { AND r/m32, r32 }
    xaOr:First:=$09;   { OR r/m32, r32; тільки host machine, не SENS закон }
    xaCmp:First:=$39;  { CMP r/m32, r32 }
    xaImul:First:=$AF; { 0F AF /r: IMUL r32, r/m32 }
  else
    raise EX64CodeError.Create('невідомий host ALU opcode');
  end;
  if Operation=xaImul then begin
    ModRM:=$C0 or (Ord(Destination) shl 3) or Ord(Source);
    Instruction:=#$0F+AnsiChar(First)+AnsiChar(ModRM);
  end else begin
    ModRM:=$C0 or (Ord(Source) shl 3) or Ord(Destination);
    Instruction:=AnsiChar(First)+AnsiChar(ModRM);
  end;
  { xaOr використовує стандартний x86 ModRM: Source→reg, Dest→r/m.
    Результат: owned managed Code.Bytes; немає new ELF чи host allocation
    поза managed copy. Відмова не змінює попередніх байтів.
    Питання: 1) Чому OR opcode 09, а не 0B? 2) Чому xaOr останній в enum?
    3) Чим CPU OR відрізняється від закону Dn? 4) Хто перевіряє ELF?
  }
  { Спершу повна перевірка, потім одна конкатенація.
    Самостійна межа точно збігається з існуючим TX64Code. }
  if (Length(Code.Bytes)>MaxMachineBytes-Length(Instruction)) then
    raise EX64CodeError.Create('ALU перевищує квоту host-коду 256 байтів');
  Code.Bytes:=Code.Bytes+Instruction;
end;
end.
