{ G6.113 — host-кодер x86-64 CMOVcc r32,r32 для verified lowering.
  Вхід: 0..15 x86 condition nibble, два апаратні r32 TX64Reg,
  керований TX64Code.Bytes (RawByteString, до 256 байтів).
  Вихід: рівно три машинні байти 0F 40+cc ModRM.
  Lifetime: байтами володіє TX64Code викликача, алокація лише
  при успішному дописуванні, за відмови Code.Bytes незмінний.
  Це механізм процесора, НЕ SENS-координата/закон/dispatch.
  Запитання: 1) Чому ModRM.reg — destination?
  2) Хто встановлює CPU FLAGS перед CMOV?
  3) Чому стан прапорців не є SENS-законом?
  4) Як збережено старий код при некоректному cc?
  5) Чому тут немає SIMD або x64 extended-register REX? }
unit wsm.x64cmov;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64CMov32(var Code:TX64Code; Condition:Integer;
                    Destination,Source:TX64Reg);
implementation
const MaxMachineBytes=256;
procedure X64CMov32(var Code:TX64Code; Condition:Integer;
                    Destination,Source:TX64Reg);
var Bytes:RawByteString; Encoded:Byte;
begin
  if (Condition<0) or (Condition>15) then
    raise EX64CodeError.Create('CMOV: недопустима host умова 0..15');
  { G6.261: тільки host номер 0..7, перевірка до ModRM. }
  if (Ord(Destination)<0) or (Ord(Destination)>7) or
     (Ord(Source)<0) or (Ord(Source)>7) then
    raise EX64CodeError.Create('CMOV: недопустимий host регістр');
  if Length(Code.Bytes)>MaxMachineBytes-3 then
    raise EX64CodeError.Create('CMOV: переповнення host-квоти 256 байтів');
  Encoded:=$C0 or (Ord(Destination) shl 3) or Ord(Source);
  Bytes:=#$0F+AnsiChar($40+Condition)+AnsiChar(Encoded);
  Code.Bytes:=Code.Bytes+Bytes;
end;
end.
