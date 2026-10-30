{ G6.134 — лише host native-механізм фізичного D12 + BSF/BSR.
  Вхід: borrowed RawByteString canonical T5M для рівно одного D12;
  вихід: owned RawByteString готового x86-64 PIE ELF (не .sens).
  Числовий домен обирає caller явно; знак не змінює фізичні 12 бітів.
  CPU зчитує саме ці 12 бітів як беззнакову host-бітову маску.
  TEST/JZ перед BSF/BSR захищає undefined destination на нулі.
  Нуль -> exit(2) і порожній stdout. Ненуль -> host index mod 2,
  результат CPU серіалізується у pinned фізичне D1/W1 T5M.
  НІЯКОГО мовного Dn-закону чи прихованого dispatch тут немає.
  Lifetime: TX64Code, Numeric та RawByteString managed; жодного файлу
  не публікуємо при помилці. Енергію не вимірюємо.
  Питання: 1) Чому D12 передається фізично й із явною шириною?
  2) Навіщо TEST/JZ саме ДО BSF/BSR?
  3) Чому host parity індексу — не нова SENS-функція?
  4) Де відбувається фізичне кодування виходу?
  5) Що гарантує цілісність ELF перед публікацією? }
unit wsm.elfbitscansafe;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64bitscan;
type
  EELFBitScanSafeError=class(Exception);
function BuildGuardedD12BitScanELF(
  const Physical:RawByteString;Operation:TX64BitScan):RawByteString;
implementation
uses wsm.x64code,wsm.x64stack,wsm.x64branch,wsm.x64alu,wsm.numericplane,
     wsm.t5m,wsm.x64pie;

procedure Need(Condition:Boolean;const Reason:String);
begin if not Condition then raise EELFBitScanSafeError.Create(Reason) end;

{ Фізичні біти: 12 цифр MSB->LSB, жодного sign extension;
  LongWord є лише тимчасовим host-регістром, НЕ ідентичністю D12.
  Питання: чому -1 D12 тут є маскою 0FFF, а не FFFFFFFF?
  Чому відхиляємо ширину, а не обрізаємо біти? }
function Mask12(const Bits:RawByteString):LongWord;
var I:SizeInt;
begin
  Need(Length(Bits)=12,'очікується точна ширина D12');
  Result:=0;
  for I:=1 to 12 do begin
    Need(Bits[I] in ['0','1'],'невірний фізичний біт');
    Result:=(Result shl 1) or LongWord(Ord(Bits[I])-Ord('0'));
  end;
end;

{ Вхідний T5M borrowed; результат — managed ELF bytes, owned caller.
  Внутрішній TX64Code володіє машинним кодом. Успіх — рівно один
  перевірений ET_DYN PIE ELF; відмова — exception, файл не створений.
  Питання: чому zero trap виходить 2 без stdout? Де patch rel32?
  Хто перераховує byte-exact T5M W1 таблицю? }
function BuildGuardedD12BitScanELF(
  const Physical:RawByteString;Operation:TX64BitScan):RawByteString;
var
  Numeric:TExplicitNumeric;
  Code:TX64Code;
  Words:TExactWords;
  ZeroByte,OneByte:AnsiChar;
  ZeroDisp,TrapOffset:SizeInt;
  Mask:LongWord;
  Machine:RawByteString;
begin
  Result:='';
  Numeric:=ReadNumericPhysical(Physical,12);
  Mask:=Mask12(Numeric.ExactBits);
  SetLength(Words,1);
  Words[0]:='0'; Machine:=EncodeT5M(Words);
  Need(Length(Machine)=1,'фізичний D1:0 повинен мати один байт');
  ZeroByte:=Machine[1];
  Words[0]:='1'; Machine:=EncodeT5M(Words);
  Need(Length(Machine)=1,'фізичний D1:1 повинен мати один байт');
  OneByte:=Machine[1];
  Need((Ord(ZeroByte)=$50) and (Ord(OneByte)=$A1),
       'pinned T5M W1 змінився');
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Mask);
  X64TestEAX(Code);
  X64EmitBranch(Code,xbZero,ZeroDisp);
  X64BitScan32(Code,Operation,xrCX,xrAX);
  X64MovImm32(Code,xrAX,1);
  X64ALU32(Code,xaAnd,xrCX,xrAX);
  X64MovImm32(Code,xrDX,0);
  X64ALU32(Code,xaAdd,xrDX,xrCX);
  X64ImulEDX8(Code,Ord(OneByte)-Ord(ZeroByte));
  X64AddEDX8(Code,Ord(ZeroByte));
  X64StackSubtract(Code,8);
  X64StackStore(Code,xrDX,0);
  X64MovImm32(Code,xrAX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovRSIRsp(Code);
  X64MovImm32(Code,xrDX,1);
  X64Syscall(Code);
  { G6.232: після Linux sys_write RAX — кількість записаних байтів або
    -errno, EDX — точна очікувана довжина фізичного D1 (1).
    CMP/SETE/MOVZX перетворюють рівність у host 0/1; подвоєння
    і 2 - 2*успіх гарантує exit(0) ЛИШЕ за повного write,
    а при -EBADF/-ENOSPC/короткому write — host exit(2).
    Це НЕ мовний D1-біт і не новий закон BSF/BSR.
    Пам'ять: змінюється лише owned TX64Code, додаткового heap немає.
    1) Чому порівнюємо EAX саме з EDX після syscall?
    2) Навіщо MOVZX перед подвоєнням?
    3) Як 2-2*success відрізняє stdout failure від D1:0?
    4) Чому нульовий D12 обходить цей епілог через JZ? }
  X64ALU32(Code,xaCmp,xrAX,xrDX);
  X64SetEAL(Code);
  X64MovzxEAXAL(Code);
  X64ALU32(Code,xaAdd,xrAX,xrAX);
  X64MovImm32(Code,xrDI,2);
  X64ALU32(Code,xaSub,xrDI,xrAX);
  X64MovImm32(Code,xrAX,60);
  X64Syscall(Code);
  TrapOffset:=Length(Code.Bytes);
  X64MovImm32(Code,xrAX,60);
  X64MovImm32(Code,xrDI,2);
  X64Syscall(Code);
  X64PatchBranch(Code,xbZero,ZeroDisp,TrapOffset);
  { G6.258: усі CPU інструкції, нульова пастка та T5M уже готові.
    Єдиний спільний BuildX64PIE формує/перевіряє ELF64 без дубля
    локального заголовка. Code — managed власність цієї функції;
    повернутий managed Result належить caller. Немає нових законів D12.
    1) Чому не переписуємо TEST/JZ/BSF/BSR?
    2) Чому ELF64 header не визначає мовного D12?
    3) Хто перевіряє 256-байтову квоту?
    4) Де повертається owned ELF?
    5) Чому треба зберігати аварійні stdout тести? }
  Result:=BuildX64PIE(Code);
end;
end.
