{ G6.256: точний host механізм signextend 12→32 для майбутнього WideIR.
  Вхід: позичений TX64Code і регістр із 12 молодшими бітами, верхні
  біти за контрактом caller знехтувані тільки після перевірки фізичного
  D12 окремим ReadNumericPhysical. Результат: owned Code.Bytes:
  SHL reg,4; MOVSX reg32,reg16; SAR reg,4 (9 машинних байтів).
  Жодного закону D12, семантичного dispatch чи алокації SENS-об'єктів.
  Питання: 1) Чому MOVSX сам по собі не працює для знака біта 11?
  2) Чому SAR, а не SHR? 3) Хто перевіряє exact D12 до виклику?
  4) Чому весь кандидат публікується атомарно? 5) Де межа квоти 256? }
unit wsm.x64d12sign;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
procedure X64SignExtendD12(var Code:TX64Code;Reg:TX64Reg);
implementation
uses wsm.x64shift,wsm.x64movsx;
const MaxMachineBytes=256;
procedure X64SignExtendD12(var Code:TX64Code;Reg:TX64Reg);
var Candidate:TX64Code;
begin
  if (Ord(Reg)<0) or (Ord(Reg)>7) then
    raise EX64CodeError.Create('D12-sign: недійсний host регістр');
  if Length(Code.Bytes)>MaxMachineBytes-9 then
    raise EX64CodeError.Create('D12-sign: квота 256 машинних байтів');
  Candidate:=Code;
  X64ShiftImm32(Candidate,xsShl,Reg,4);
  X64MovSX16to32(Candidate,Reg,Reg);
  X64ShiftImm32(Candidate,xsSar,Reg,4);
  if Length(Candidate.Bytes)<>Length(Code.Bytes)+9 then
    raise EX64CodeError.Create('D12-sign: невірна довжина lowering');
  Code:=Candidate;
end;
end.
