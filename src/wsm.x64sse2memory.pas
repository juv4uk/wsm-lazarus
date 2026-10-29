{ G6.115 — host ISA SSE2 MOVDQU, не семантика SENS.
  Вхід: TX64Code — власний буфер байтів викликачa, XMM 0..15,
  base GPR 0..15 (RAX,RCX,RDX,RBX,RSP,RBP,RSI,RDI,R8..R15),
  знакове 32-бітне displacement і напрям load/store.
  Вихід: F3 [REX] 0F 6F/7F ModRM [SIB] [disp8/disp32].
  Буфер FPC managed; помилка до однієї атомарної конкатенації.
  Питання: 1) Чому для RSP/R12 потрібен SIB?
  2) Чому RBP/R13 з disp=0 має mod=01?
  3) Який біт REX.B розширює базовий регістр?
  4) Чому F3 перед REX?
  5) Чому це не викличність жодної Dn координати? }
unit wsm.x64sse2memory;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type
  TX64SSE2MemoryOperation=(smLoad,smStore);
procedure X64SSE2Memory(var Code:TX64Code;Operation:TX64SSE2MemoryOperation;
                        XMM,Base:Integer;Displacement:LongInt);
implementation
const MaxHostBytes=256;
procedure X64SSE2Memory(var Code:TX64Code;Operation:TX64SSE2MemoryOperation;
                        XMM,Base:Integer;Displacement:LongInt);
var OpCode,ModRM,SIB,Mode,BaseLow,REX:Byte;
    Instruction:RawByteString;I:Integer;Bits:LongWord;
begin
  if (XMM<0) or (XMM>15) or (Base<0) or (Base>15) then
    raise EX64CodeError.Create('SSE2-ПАМ: фізичний host регістр поза 0..15');
  case Operation of
    smLoad:OpCode:=$6F;
    smStore:OpCode:=$7F;
  else
    raise EX64CodeError.Create('SSE2-ПАМ: невідома ISA-операція');
  end;
  BaseLow:=Byte(Base and 7);
  { mod=00 rm=101 означає RIP+disp32 (а не RBP/R13).
    Отже RBP/R13 при нульовому зміщенні вимагає disp8=0. }
  if (Displacement=0) and (BaseLow<>5) then Mode:=0
  else if (Displacement>=-128) and (Displacement<=127) then Mode:=1
  else Mode:=2;
  REX:=$40 or ((XMM shr 3) shl 2) or (Base shr 3);
  Instruction:=#$F3;
  if REX<>$40 then Instruction:=Instruction+AnsiChar(REX);
  ModRM:=Byte((Mode shl 6) or ((XMM and 7) shl 3) or BaseLow);
  Instruction:=Instruction+#$0F+AnsiChar(OpCode)+AnsiChar(ModRM);
  if BaseLow=4 then begin
    { scale=00 index=100 («немає індексу») base=100 (RSP/R12). }
    SIB:=$24;
    Instruction:=Instruction+AnsiChar(SIB);
  end;
  if Mode=1 then Instruction:=Instruction+AnsiChar(Byte(Displacement and $FF))
  else if Mode=2 then begin
    Bits:=LongWord(Displacement);
    for I:=0 to 3 do begin
      Instruction:=Instruction+AnsiChar(Byte(Bits and $FF));
      Bits:=Bits shr 8;
    end;
  end;
  if (Length(Code.Bytes)>MaxHostBytes) or
     (Length(Instruction)>MaxHostBytes-Length(Code.Bytes)) then
    raise EX64CodeError.Create('SSE2-ПАМ: перевищено фізичну квоту 256 байтів');
  Code.Bytes:=Code.Bytes+Instruction;
end;
end.
