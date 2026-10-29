{ G6.111 — виключно host x86-64 SSE2, не закони мови SENS.
  Тип TX64Code: керований RawByteString, власник — викликач.
  Dst/Src: індекси фізичних XMM0..XMM15, НЕ доменні слова.
  Вихід: 4 або 5 виконуваних машинних байтів у Code.Bytes.
  Atomicity: усі перевірки та повний Instruction до одного Commit.
  Питання: 1) Чим відрізняється REX.R від REX.B?
  2) Чому legacy 66 стоїть перед REX?
  3) Чому D7-проєкція не є SIMD-регістром?
  4) Як працює перевірка квоти перед записом?
  5) Чому GNU as доводить ISA, але не семантику SENS? }
unit wsm.x64sse2;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type
  TX64SSE2Operation=(soXor,soAnd,soOr,soAddQ);
procedure X64SSE2RegReg(var Code:TX64Code;Operation:TX64SSE2Operation;
                         Destination,Source:Integer);
implementation
const MaxHostBytes=256;
procedure X64SSE2RegReg(var Code:TX64Code;Operation:TX64SSE2Operation;
                         Destination,Source:Integer);
var OpCode,REX,ModRM:Byte; Instruction:RawByteString;
begin
  if (Destination<0) or (Destination>15) or
     (Source<0) or (Source>15) then
    raise EX64CodeError.Create('SSE2: XMM поза фізичними 0..15');
  case Operation of
    soXor:OpCode:=$EF;  { PXOR xmm,xmm }
    soAnd:OpCode:=$DB;  { PAND xmm,xmm }
    soOr:OpCode:=$EB;   { POR xmm,xmm }
    soAddQ:OpCode:=$D4; { PADDQ xmm,xmm }
  else
    raise EX64CodeError.Create('SSE2: невідома host ISA операція');
  end;
  { 66 — legacy mandatory SSE2 prefix; наступний опційний REX
    REX.R розширює reg=destination, REX.B розширює r/m=source.
    Без REX для XMM0..7; mod=11 гарантує тільки регістри. }
  REX:=$40 or ((Destination shr 3) shl 2) or (Source shr 3);
  ModRM:=$C0 or ((Destination and 7) shl 3) or (Source and 7);
  Instruction:=#$66;
  if REX<>$40 then Instruction:=Instruction+AnsiChar(REX);
  Instruction:=Instruction+#$0F+AnsiChar(OpCode)+AnsiChar(ModRM);
  if (Length(Code.Bytes)>MaxHostBytes) or
     (Length(Instruction)>MaxHostBytes-Length(Code.Bytes)) then
    raise EX64CodeError.Create('SSE2: перевищено 256 machine bytes');
  Code.Bytes:=Code.Bytes+Instruction;
end;
end.
