{ G6.250 — обмежена host-інструкція x86-64 SHRD r32,r32,imm8.
  Вхід: запозичений TX64Code, реєстри 0..7 та зсув 1..31.
  Вихід: дописані 4 байти 0F AC /r ib; Code.Bytes залишається
  власністю caller, Code.PatchedRIP не змінюється.
  Відмова відбувається до конкатенації: не псує попередній код.
  Це НЕ мовний закон SENS, не операція D12+ та не D7-проєкція.
  1) Чому ModRM.reg — джерело, а ModRM.r/m — призначення?
  2) Навіщо заборонено зсуви 0 та 32 і більше?
  3) Чому квота 256 байтів належить host, а не SENS?
  4) Хто володіє згенерованими байтами після помилки? }
unit wsm.x64shrd;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64SHRD32(var Code:TX64Code;Destination,Source:TX64Reg;
                    Count:Integer);
implementation
const MaxMachineBytes=256;
procedure X64SHRD32(var Code:TX64Code;Destination,Source:TX64Reg;
                    Count:Integer);
var Instruction:RawByteString;ModRM:Byte;
begin
  if (Ord(Destination)>7) or (Ord(Source)>7) then
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
