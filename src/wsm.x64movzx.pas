{ G6.258 — беззнакове розширення host x86-64 MOVZX r32,r16.
  Це будівельний механізм для майбутнього D12+ lowering, а НЕ закон SENS.
  Вхід: позичений TX64Code та точні host-регістри 0..7, вихід:
  три байти 0F B7 /r у керованому Code.Bytes; Code.PatchedRIP без змін.
  Помилка реєстру або квоти відбувається ДО єдиного дописування.
  Питання: 1) Чому 0F B7 працює без prefix 66 для r32/r16?
  2) Чому ModRM.reg — це ціль r32, а ModRM.r/m — джерело r16?
  3) Чому беззнакове розширення CPU не визначає закон SENS D12+?
  4) Хто володіє керованим Code.Bytes після повернення?
  5) Чому відмова не має чіпати RIP fixups? }
unit wsm.x64movzx;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64MovZX16to32(var Code:TX64Code;Destination,Source:TX64Reg);
implementation
const MaxMachineBytes=256;
procedure X64MovZX16to32(var Code:TX64Code;Destination,Source:TX64Reg);
var Machine:RawByteString;
begin
  if (Ord(Destination)<0) or (Ord(Destination)>7) or
     (Ord(Source)<0) or (Ord(Source)>7) then
    raise EX64CodeError.Create('MOVZX: потрібні host-регістри 0..7');
  if Length(Code.Bytes)>MaxMachineBytes-3 then
    raise EX64CodeError.Create('MOVZX: перевищено квоту машинних 256 байтів');
  Machine:=#$0F#$B7+AnsiChar($C0 or (Ord(Destination) shl 3) or Ord(Source));
  Code.Bytes:=Code.Bytes+Machine;
end;
end.
