{ G6.250 — host x86-64 ADC/SBB r/m32,r32 для майбутнього native lowering.
  Вхід: managed TX64Code і два регістри x86-64 0..7, прапор CF формується
  попередньою машинною інструкцією. Вихід: рівно два machine bytes.
  Код не приймає SENS координат, не тлумачить D12+, не призначає закону.
  TX64Code належить викликачу; відмова не змінює Bytes/PatchedRIP.
  Питання: 1) Чому CF встановлює попередня інструкція?
  2) Як 11 /r відрізняється від 13 /r? 3) Чому регістри 0..7?
  4) Хто перевіряє машинне виконання? 5) Чому це ще не D24 арифметика? }
unit wsm.x64carry;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type TX64Carry=(xcAdc,xcSbb);
procedure X64Carry32(var Code:TX64Code; Operation:TX64Carry;
  Destination,Source:TX64Reg);
implementation
const MaxMachineBytes=256;
procedure X64Carry32(var Code:TX64Code; Operation:TX64Carry;
  Destination,Source:TX64Reg);
var Opcode,ModRM:Byte;
    Candidate:RawByteString;
begin
  if (Ord(Destination)<0) or (Ord(Destination)>7) or
     (Ord(Source)<0) or (Ord(Source)>7) then
    raise EX64CodeError.Create('ADC/SBB: недопустимий host регістр 0..7');
  case Operation of
    xcAdc:Opcode:=$11; { ADC r/m32, r32: додає вхідний CPU CF }
    xcSbb:Opcode:=$19; { SBB r/m32, r32: віднімає вхідний CPU CF }
  else
    raise EX64CodeError.Create('ADC/SBB: невідома host операція');
  end;
  ModRM:=$C0 or (Ord(Source) shl 3) or Ord(Destination);
  if Length(Code.Bytes)>MaxMachineBytes-2 then
    raise EX64CodeError.Create('ADC/SBB: перевищена квота 256 байтів');
  Candidate:=Code.Bytes+AnsiChar(Opcode)+AnsiChar(ModRM);
  Code.Bytes:=Candidate;
end;
end.
