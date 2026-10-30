{ G6.257 — лише host x86-64 NEG r/m32 (F7 /3) для нативного backend.
  Вхід: позичений TX64Code (керовані Bytes/PatchedRIP) та фізичний
  індекс регістра 0..7; це не SENS домен, D12 число або D7-проєкція.
  Вихід: рівно 2 host машинні байти F7 D8..DF; buffer належить caller,
  власних об'єктів і довгоживучих ресурсів не створюється.
  При помилці регістра або квоти обидва поля Code незмінні.
  Питання: 1) Чому /3 міститься в ModRM.reg?
  2) Чому машинний NEG ще не визначає закон чисел D12+?
  3) Чому квоту перевірено до додавання байтів?
  4) Як зберігаються PatchedRIP та lifetime позиченого TX64Code?
  5) Що незалежно перевіряє GNU as, а що лише виконаний ELF? }
unit wsm.x64neg32;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses wsm.x64code;
procedure X64Neg32(var Code:TX64Code;Reg:TX64Reg);

implementation
uses SysUtils;
const MaxHostBytes=256;

procedure X64Neg32(var Code:TX64Code;Reg:TX64Reg);
var Index:LongInt;
    Instruction:RawByteString;
begin
  Index:=Ord(Reg);
  if (Index<0) or (Index>7) then
    raise EX64CodeError.Create('NEG32: host регістр поза 0..7');
  Instruction:=#$F7+AnsiChar($D8 or Index);
  if Length(Code.Bytes)>MaxHostBytes-Length(Instruction) then
    raise EX64CodeError.Create('NEG32: перевищена host квота 256 байтів');
  Code.Bytes:=Code.Bytes+Instruction;
end;
end.
