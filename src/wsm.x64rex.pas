{ G6: незалежний host-кодер x86-64 REX.W/R/B для регістрів RAX..R15.
  Вхід: TX64Code (managed RawByteString), machine регістри, QWord або
  регістрова host-операція. Вихід: 3/10 виконуваних байтів.
  Кодер не приймає Dn, проєкції чи текст функцій SENS: мовне зв'язування
  відбувається ДО виклику machine emitter.
  Lifetime: буфер належить caller; всі перевірки до єдиної конкатенації;
  невдала операція зберігає байти без змін.
  Запитання: 1) Що відрізняє REX.R від REX.B?
  2) Чому для MOVABS потрібно рівно 8 байтів immediate?
  3) Чому адреса Dn не є host-регістром?
  4) Де перевіряється атомарність при 256-байтній квоті?
  5) Чому golden x86 байти не доводять SENS-семантики? }
unit wsm.x64rex;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type
  TX64WideReg=(wrAX,wrCX,wrDX,wrBX,wrSP,wrBP,wrSI,wrDI,
               wrR8,wrR9,wrR10,wrR11,wrR12,wrR13,wrR14,wrR15);
  TX64RexOperation=(roMove,roAdd,roXor);
procedure X64RexMovAbs(var Code:TX64Code; Reg:TX64WideReg; Value:QWord);
procedure X64RexReg64(var Code:TX64Code; Operation:TX64RexOperation;
                      Destination,Source:TX64WideReg);
implementation
const MaxHostBytes=256;
procedure CommitBytes(var Code:TX64Code;const Instruction:RawByteString);
begin
  if (Length(Instruction)=0) or
     (Length(Instruction)>MaxHostBytes) or
     (Length(Code.Bytes)>MaxHostBytes-Length(Instruction)) then
    raise EX64CodeError.Create('REX: перевищено квоту host-машини');
  Code.Bytes:=Code.Bytes+Instruction;
end;

procedure DemandReg(Reg:TX64WideReg);
begin
  if (Ord(Reg)<0) or (Ord(Reg)>15) then
    raise EX64CodeError.Create('REX: недопустимий host-регістр');
end;

procedure X64RexMovAbs(var Code:TX64Code;Reg:TX64WideReg;Value:QWord);
var Instruction:RawByteString; I:Integer;
begin
  DemandReg(Reg);
  { REX.W=1, REX.B містить старший біт machine-регістра.
    B8+low3, 64-bit little-endian immediate без втрати провідних нулів. }
  Instruction:=AnsiChar($48 or (Ord(Reg) shr 3))+
               AnsiChar($B8 or (Ord(Reg) and 7));
  for I:=0 to 7 do begin
    Instruction:=Instruction+AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
  CommitBytes(Code,Instruction);
end;

procedure X64RexReg64(var Code:TX64Code;Operation:TX64RexOperation;
                      Destination,Source:TX64WideReg);
var Prefix,OpCode,ModRM:Byte; Instruction:RawByteString;
begin
  DemandReg(Destination);
  DemandReg(Source);
  case Operation of
    roMove:OpCode:=$89; { MOV r/m64,r64 }
    roAdd:OpCode:=$01;  { ADD r/m64,r64 }
    roXor:OpCode:=$31;  { XOR r/m64,r64 }
  else
    raise EX64CodeError.Create('REX: невідома host-операція');
  end;
  { ModRM register addressing: mod=11, reg=source, r/m=destination.
    REX.R піднімає source до R8..R15, REX.B піднімає destination. }
  Prefix:=$48 or ((Ord(Source) shr 3) shl 2) or (Ord(Destination) shr 3);
  ModRM:=$C0 or ((Ord(Source) and 7) shl 3) or (Ord(Destination) and 7);
  Instruction:=AnsiChar(Prefix)+AnsiChar(OpCode)+AnsiChar(ModRM);
  CommitBytes(Code,Instruction);
end;
end.
