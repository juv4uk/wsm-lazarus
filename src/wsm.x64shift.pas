{ G6.97. Обмежений host-кодер x86-64 зсувів та обертань r32.
  Це машинні механізми для майбутнього lowering, НЕ закони SENS.
  Вхід: TX64Code (managed RawByteString), opcode, регістр r32 і imm5
  або фізичний регістр CL. Вихід: 2/3 байти машинного коду.
  Lifetime: байтами володіє caller TX64Code; ELF тут не створюється.
  При відмові байти залишаються незмінними; quota = 256.

  Питання: 1) Чому host SAR не можна автоматично назвати Dn-операцією?
  2) Чому imm=32 відхиляємо, хоча x86 маскує count?
  3) Як ModRM відрізняє SAR від ROR для того самого регістра?
  4) Чому x86-64 CL-зсув використовує молодші 5 біт?
  5) Чому відмова не повинна пошкодити попередній code buffer? }
unit wsm.x64shift;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type
  TX64Shift=(xsShl,xsShr,xsSar,xsRol,xsRor);

procedure X64ShiftImm32(var Code:TX64Code;Operation:TX64Shift;
                         Destination:TX64Reg;Count:Byte);
procedure X64ShiftCL32(var Code:TX64Code;Operation:TX64Shift;
                        Destination:TX64Reg);
implementation
const MaxMachineBytes=256;

function ShiftGroup(Operation:TX64Shift):Byte;
begin
  case Operation of
    xsRol:Result:=0; { ROL r/m32, imm8 /0 }
    xsRor:Result:=1; { ROR r/m32, imm8 /1 }
    xsShl:Result:=4; { SHL r/m32, imm8 /4 }
    xsShr:Result:=5; { SHR r/m32, imm8 /5 }
    xsSar:Result:=7; { SAR r/m32, imm8 /7 }
  else
    raise EX64CodeError.Create('невідомий host shift opcode');
  end;
end;

procedure AppendShift(var Code:TX64Code;const Bytes:RawByteString);
var Candidate:RawByteString;
begin
  if (Length(Bytes)<2) or (Length(Bytes)>3) or
     (Length(Code.Bytes)>MaxMachineBytes-Length(Bytes)) then
    raise EX64CodeError.Create('shift перевищує host-квоту 256 байтів');
  Candidate:=Code.Bytes+Bytes;
  Code.Bytes:=Candidate;
end;

procedure X64ShiftImm32(var Code:TX64Code;Operation:TX64Shift;
                         Destination:TX64Reg;Count:Byte);
var Group:Byte; ModRM:Byte;
begin
  { G6.261: обидві межі 0..7 до складання ModRM. }
  if (Ord(Destination)<0) or (Ord(Destination)>7) then
    raise EX64CodeError.Create('недопустимий host регістр r32');
  if Count>31 then
    raise EX64CodeError.Create('shift immediate поза точним 0..31');
  Group:=ShiftGroup(Operation);
  ModRM:=$C0 or (Group shl 3) or Byte(Ord(Destination));
  AppendShift(Code,#$C1+AnsiChar(ModRM)+AnsiChar(Count));
end;

procedure X64ShiftCL32(var Code:TX64Code;Operation:TX64Shift;
                        Destination:TX64Reg);
var Group:Byte; ModRM:Byte;
begin
  { G6.261: обидві межі 0..7 до складання ModRM. }
  if (Ord(Destination)<0) or (Ord(Destination)>7) then
    raise EX64CodeError.Create('недопустимий host регістр r32');
  Group:=ShiftGroup(Operation);
  ModRM:=$C0 or (Group shl 3) or Byte(Ord(Destination));
  AppendShift(Code,#$D3+AnsiChar(ModRM));
end;
end.
