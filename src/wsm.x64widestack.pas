{ G6.241 — host-only x86-64 REX.W+REX.R stack storage for R8..R15.
  No SENS domain law or text projection is interpreted in this unit.
  Input: borrowed TX64Code (managed RawByteString), machine register,
  aligned host byte offset 0,8,..120. Output: appended x86-64 instruction.
  The frame and QWord lifetime are caller-owned; no implicit allocation.
  On any rejection Code.Bytes and Code.PatchedRIP stay untouched.
  1) Why must REX.R be set for R8..R15 as the ModRM.reg field?
  2) Why does RSP addressing require the SIB byte $24?
  3) Why are +7 and +121 invalid spill displacements?
  4) Which component allocates/resets the 16-byte-aligned frame?
  5) Why does executing host MOV prove no new SENS law? }
unit wsm.x64widestack;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code,wsm.x64rex;

procedure X64WideStackStore(var Code:TX64Code;Reg:TX64WideReg;Offset:SizeInt);
procedure X64WideStackLoad(var Code:TX64Code;Reg:TX64WideReg;Offset:SizeInt);

implementation
const MaxHostCodeBytes=256;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EX64CodeError.Create(Why);
end;

{ One full instruction is composed BEFORE publication, never byte-by-byte.
  REX.W=1, REX.R=1, REX.B=0: $4C; ModRM.reg=R8..R15 low 3 bits.
  ModRM.r/m=100 + SIB.base=RSP; disp8 is unsigned 0..120.
  A borrowed Code retains all previous bytes if quota/args reject. }
procedure Transfer(var Code:TX64Code;Reg:TX64WideReg;
                   Offset:SizeInt;Store:Boolean);
var Part:RawByteString;Opcode,ModRM:Byte;
begin
  Need((Ord(Reg)>=Ord(wrR8)) and (Ord(Reg)<=Ord(wrR15)),
       'широкий стек: підтримано тільки R8..R15');
  Need((Offset>=0) and (Offset<=120) and (Offset mod 8=0),
       'широкий стек: потрібен вирівняний qword offset 0..120');
  if Store then Opcode:=$89 else Opcode:=$8B;
  ModRM:=((Ord(Reg) and 7) shl 3) or 4;
  if Offset=0 then
    Part:=#$4C+AnsiChar(Opcode)+AnsiChar(ModRM)+#$24
  else
    Part:=#$4C+AnsiChar(Opcode)+AnsiChar($40 or ModRM)+
          #$24+AnsiChar(Byte(Offset));
  Need((Length(Code.Bytes)<=MaxHostCodeBytes-Length(Part)),
       'широкий стек: квота TX64Code 256 байтів');
  Code.Bytes:=Code.Bytes+Part;
end;

procedure X64WideStackStore(var Code:TX64Code;Reg:TX64WideReg;Offset:SizeInt);
begin Transfer(Code,Reg,Offset,True) end;

procedure X64WideStackLoad(var Code:TX64Code;Reg:TX64WideReg;Offset:SizeInt);
begin Transfer(Code,Reg,Offset,False) end;

end.
