{ G6.133 — машинний POPCNT, НЕ SENS закон.
  TX64Code.Bytes: керований RawByteString викликача, зберігає байти.
  Вхід Width=32/64 та апаратні номери регістрів 0..15.
  Вихід: F3 REX? 0F B8 ModRM; нічого не виділяється поза managed рядком.
  У разі відмови старий буфер залишається незмінним, квота 256 байтів.
  POPCNT на нулі визначений: результат 0; CPU мусить мати POPCNT.
  Питання: 1) Чому F3 стоїть перед REX?
  2) Як REX.R і REX.B кодують незалежні номери регістрів?
  3) Чому 64-бітна ширина потребує REX.W?
  4) Чому машинний opcode не означає нової Dn функції?
  5) Чому квоту перевіряють до конкатенації? }
unit wsm.x64popcnt;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64PopCount(var Code:TX64Code; Width,Destination,Source:Integer);
implementation
const MaxMachineBytes=256;
procedure X64PopCount(var Code:TX64Code; Width,Destination,Source:Integer);
var REX,ModRM:Byte; Encoded:RawByteString;
begin
  if (Width<>32) and (Width<>64) then
    raise EX64CodeError.Create('POPCNT: лише host r32 або r64');
  if (Destination<0) or (Destination>15) or
     (Source<0) or (Source>15) then
    raise EX64CodeError.Create('POPCNT: регістр поза 0..15');
  REX:=$40;
  if Width=64 then REX:=REX or $08;
  if Destination>=8 then REX:=REX or $04;
  if Source>=8 then REX:=REX or $01;
  ModRM:=$C0 or ((Destination and 7) shl 3) or (Source and 7);
  Encoded:=#$F3;
  if REX<>$40 then Encoded:=Encoded+AnsiChar(REX);
  Encoded:=Encoded+#$0F#$B8+AnsiChar(ModRM);
  if Length(Code.Bytes)>MaxMachineBytes-Length(Encoded) then
    raise EX64CodeError.Create('POPCNT: перевищено квоту 256 байтів');
  Code.Bytes:=Code.Bytes+Encoded;
end;
end.
