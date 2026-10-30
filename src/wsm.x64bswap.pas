{ G6 — самостійний host-кодер x86-64 BSWAP для native lowering.
  Вхід: TX64Code (керований RawByteString викликача), RegNumber — апаратний
  індекс 0..15 (RAX..R15), Width — рівно 32 або 64 біти.
  Вихід: два або три машинні байти REX?/0F/C8+reg; повернення через
  буфер викликача, окремих власних pointer/heap-об'єктів немає.
  За будь-якої відмови буфер не змінюється; квота — 256 байтів.
  Це host ISA, НЕ D1–D10/число D12+, НЕ SENS law або текстовий dispatch.
  Питання: 1) Чому REX.B потрібен для R8–R15?
  2) Чому 64-бітний BSWAP завжди має REX.W?
  3) Чому x86 opcode не є SENS-доменним ідентифікатором?
  4) Як зберігається старий буфер у разі переповнення?
  5) Чому побайтова звірка з GNU as незалежніша за власну формулу? }
unit wsm.x64bswap;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.x64code;
procedure X64BSwap(var Code:TX64Code; RegNumber,Width:Integer);
implementation
const MaxMachineBytes=256;
procedure X64BSwap(var Code:TX64Code; RegNumber,Width:Integer);
var Encoded:RawByteString;
begin
  if (RegNumber<0) or (RegNumber>15) then
    raise EX64CodeError.Create('BSWAP: апаратний регістр поза 0..15');
  if (Width<>32) and (Width<>64) then
    raise EX64CodeError.Create('BSWAP: підтримано лише 32/64 біти');
  Encoded:='';
  if Width=64 then
    Encoded:=AnsiChar($48 or (RegNumber shr 3))
  else if RegNumber>=8 then
    Encoded:=#$41;
  Encoded:=Encoded+#$0F+AnsiChar($C8 or (RegNumber and 7));
  if Length(Code.Bytes)>MaxMachineBytes-Length(Encoded) then
    raise EX64CodeError.Create('BSWAP: перевищена квота 256 байтів');
  Code.Bytes:=Code.Bytes+Encoded;
end;
end.
