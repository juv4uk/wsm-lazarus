{ G6.126 — чинний backend розширено до 1..3 повних D3:110 гілок.
  EBP утримує прапорець уже вибраної відповіді; ESI — поточний D1
  тест, EDI — одноразовий eligibility біт, EBX — pinned T5M байт.
  3× подвійний вкладений D3:101 вкладається у 256 байтів коду.
  Усі типи — host r32; буфер належить локальному TX64Code, а ELF
  стає Result лише після повного LowerPinnedIRCond та geometry guard.
  1) Чому OR EBP,ESI стоїть ПІСЛЯ CMOVE?
  2) Чому для непідтриманих побічних ефектів це було б неправильно?
  3) Чому 4 гілки треба відхиляти, а не мовчки обрізати?
  4) Де зберігається exact D3:000 при всіх хибних тестах? }
{ G6.116 — одна повна фізична D3:110 → verified ExactIR → x86-64
  CMP/SETE/CMOVNE/CMOVE → ELF64 PIE → pinned T5M.
  Семантичний допуск/закон: ТІЛЬКИ LowerPinnedIRCond із pinned SENS.
  Підмножина: рівно ОДНА двопольова гілка, її тест/вираз —
  exact D1:0/1 або D3:101 з двома exact D1. Операнди чисті,
  тому спекулятивне обчислення обох не має побічного ефекту.
  Вхід: borrowed packed фізичний RawByteString і pinned root.
  Вихід: owned RawByteString ELF64 PIE; жоден образ не публікується
  до повного admission і перевірки геометрії. Локальний TX64Code
  володіє тимчасовими байтами, живе лише протягом виклику.
  CPU-регістри, CMOV opcode та signed displacement НЕ є Dn законами.
  D3:000 завжди залишається окремим від D1:0.

  Питання:
  1) Чому не можна переплутати D3:000 та D1:0?
  2) Хто допускає точну викличність D3:110/D3:101?
  3) Чому CMP/CMOV не запроваджує новий SENS закон?
  4) Чому спекулятивний вираз безпечний ЛИШЕ в цьому профілі?
  5) Навіщо окремо виконувати ELF та незалежний SENS oracle? }
unit wsm.ircondcmov;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRCondCMovError=class(Exception);
function BuildPinnedIRCondCMovELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.ircond,wsm.x64code,wsm.x64stack,wsm.x64alu,wsm.x64cmov,wsm.t5m,
     wsm.x64pie;
const MaxCodeBytes=256;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRCondCMovError.Create(Why);
end;
procedure Emit(var C:TX64Code;const Bytes:RawByteString);
begin
  Need((Length(Bytes)>0) and (Length(C.Bytes)<=MaxCodeBytes-Length(Bytes)),
       'Переповнено host-квоту машинного коду 256 байтів');
  C.Bytes:=C.Bytes+Bytes;
end;
procedure EmitValue(var C:TX64Code;const V:TIRCondValue);
begin
  Need((V.Kind<=1) and (V.LeftBit<=1) and (V.RightBit<=1),
       'Пошкоджено вже допущене D1/EQ значення');
  X64MovImm32(C,xrAX,V.LeftBit);
  if V.Kind=1 then begin
    X64MovImm32(C,xrCX,V.RightBit);
    X64ALU32(C,xaCmp,xrAX,xrCX);
    X64SetEAL(C);
    X64MovzxEAXAL(C);
  end;
end;
function BuildPinnedIRCondCMovELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Lowered:TLoweredIRCond;
  C:TX64Code;
  Words:TExactWords;
  ZeroByte,OneByte,EmptyByte:RawByteString;
  I:SizeInt;
begin
  Result:='';
  try
    { Жодного дублювання parser/binder/ratified law. }
    LowerPinnedIRCond(Physical,AuthorityRoot,Lowered);
    Need((Lowered.Count>=1) and (Lowered.Count<=3),
         'CMOV-зріз допускає лише 1..3 двопольові D3-гілки');
    SetLength(Words,1);
    Words[0]:='0'; ZeroByte:=EncodeT5M(Words);
    Words[0]:='1'; OneByte:=EncodeT5M(Words);
    Words[0]:='000'; EmptyByte:=EncodeT5M(Words);
    Need((Length(ZeroByte)=1) and (Length(OneByte)=1) and
         (Length(EmptyByte)=1) and (ZeroByte<>OneByte) and
         (ZeroByte<>EmptyByte) and (OneByte<>EmptyByte),
         'Неоднозначні канонічні D1/D3 фізичні результати');
    X64Reset(C);
    { EBX — вибраний фізичний T5M байт, спочатку exact D3:000.
      EBP — чи вибрана попередня істинна гілка (0 або 1).
      Усі допущені D1/EQ піддерева чисті; лише для них допустима
      спекулятивна машинна оцінка тестів і виразів без Jcc. }
    X64MovImm32(C,xrBX,Ord(EmptyByte[1]));
    X64MovImm32(C,xrBP,0);
    for I:=0 to Lowered.Count-1 do begin
      EmitValue(C,Lowered.Clauses[I].TestValue);
      Emit(C,#$89#$C6); { mov esi,eax: фізичний D1 біт тесту }
      EmitValue(C,Lowered.Clauses[I].ExpressionValue);
      X64MovImm32(C,xrCX,Ord(ZeroByte[1]));
      X64MovImm32(C,xrDX,Ord(OneByte[1]));
      X64TestEAX(C);
      X64CMov32(C,5,xrCX,xrDX); { CMOVNE ECX,EDX: T5M виразу }
      { eligibility = test AND (1 XOR already_selected).
        EDI — тимчасовий host прапорець; не SENS координата. }
      Emit(C,#$89#$EF);       { mov edi,ebp }
      Emit(C,#$83#$F7#$01);   { xor edi,1 }
      Emit(C,#$21#$F7);       { and edi,esi }
      Emit(C,#$83#$FF#$01);   { cmp edi,1 }
      X64CMov32(C,4,xrBX,xrCX); { CMOVE EBX,ECX, перша істинна }
      Emit(C,#$09#$F5);       { or ebp,esi: selected OR test }
    end;
    X64StackSubtract(C,8);
    Emit(C,#$88#$1C#$24); { MOV BYTE PTR [RSP], BL }
    X64MovImm32(C,xrAX,1); { write(stdout, rsp, 1) }
    X64MovImm32(C,xrDI,1);
    X64MovRSIRsp(C);
    { G6.236 — push imm8; pop rdx задає Linux write count=1 за
      3 байти замість 5-байтового mov edx,1. PUSH/POP змінює RSP
      тільки тимчасово; RSI досі вказує на фізичний T5M-байт.
      Економимо 2 байти для перевірки syscall в 256-byte code budget.
      1) Чому після POP RDX дорівнює рівно 1?
      2) Чому стек до write не змінився?
      3) Чому це host ABI, а не D12 числова операція? }
    Emit(C,#$6A#$01#$5A); { push 1; pop rdx }
    X64Syscall(C);
    { G6.236 — тільки Linux host ABI, не SENS D1/D3 закон.
      sys_write(1,rsp,EDX=1) повертає EAX=1 лише після повного
      фізичного T5M байта. -EBADF, -ENOSPC, 0 та short write
      дають host exit(1), не хибний успіх виконання.
      EDI перед syscall дорівнює 1; syscall змінює RCX/R11,
      але зберігає EDX і RDI. SETNE DIL встановлює exit code 0/1.
      TX64Code.Bytes — owned тимчасовий managed buffer до MakePIE.
      1) Чому CMP EAX,EDX звіряє host кількість, а не D1?
      2) Чому REX 40 потрібен для 8-бітного регістра DIL?
      3) Чому PUSH 60/POP RAX обнуляє sign-extended syscall errno?
      4) Чому RDI тут є лише кодом виходу Linux, не SENS?
      5) Хто перевіряє точну pinned фізичну програму до епілогу? }
    Emit(C,#$39#$D0#$40#$0F#$95#$C7#$6A#$3C#$58#$0F#$05);
    { G6.253: єдиний перевірений конструктор ELF64 PIE отримує позичений
      TX64Code. Він не змінює машинних байтів/попереднього IR, будує owned
      ET_DYN образ і перевіряє точну геометрію до повернення Result.
      Lifetime C локальний, Result належить викликачу; законів SENS немає.
      1) Чому конструктор не виконує semantic admission?
      2) Чому 120-байтовий ELF header не дублюємо в цій одиниці?
      3) Що доводять 26 фізичних ELF і 16 негативів?
      4) Чому не можна послаблювати stdout host-error перевірки? }
    Result:=BuildX64PIE(C);
  except
    on E:Exception do begin
      Result:='';
      raise EIRCondCMovError.Create('D3-CMOV-ВІДМОВА: '+E.Message);
    end;
  end;
end;
end.
