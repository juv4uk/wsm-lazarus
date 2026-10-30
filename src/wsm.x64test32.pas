{ G6.254 — host-only TEST r/m32,r32 (85 /r), прапорці x86-64.
  Вхід: позичений TX64Code та два host регістри 0..7.
  Вихід: рівно два машинні байти у managed Bytes; PatchedRIP незмінний.
  При помилці регістра/квоти обидва поля Code лишаються незмінними.
  Цей unit не знає SENS, D7, D12+, Core1/Core4 або мовних законів.
  1) Чому TEST встановлює ZF, але не переписує операнди?
  2) Чому біти Source у ModRM.reg, а Destination у ModRM.r/m?
  3) Чому квота є host policy, а не доменом SENS?
  4) Як перевірено атомарність відмови і фізичні opcode? }
unit wsm.x64test32;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses wsm.x64code;
procedure X64Test32(var Code:TX64Code;Destination,Source:TX64Reg);
implementation
uses SysUtils;
const MaxHostBytes=256;
procedure X64Test32(var Code:TX64Code;Destination,Source:TX64Reg);
var D,S:LongInt;
    Candidate:RawByteString;
begin
  D:=Ord(Destination);
  S:=Ord(Source);
  if (D<0) or (D>7) or (S<0) or (S>7) then
    raise EX64CodeError.Create('TEST32: регістр поза host 0..7');
  if Length(Code.Bytes)>MaxHostBytes-2 then
    raise EX64CodeError.Create('TEST32: квота host machine code 256');
  Candidate:=#$85+AnsiChar($C0 or (S shl 3) or D);
  Code.Bytes:=Code.Bytes+Candidate;
end;
end.
