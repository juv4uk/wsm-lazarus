{ G6.101 — нативна вузька D6:010101 операція НСД для двох додатних D12.
  Закони: тільки pinned SENS 12.0 / lib/domains/d6.lisp.
  Два canonical T5M атоми перевіряє вже існуючий ReadNumericPhysical.
  x86-64 DIV виконує алгоритм Евкліда ПІД ЧАС запуску ELF, а не в FPC.
  Вихід: один точний фізичний D12 через спільні EncodeT5M таблиці.
  Це host-емітер для одного профілю; не D6 dispatch і не загальний compiler. }
unit wsm.elfd12nsd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12NsdELFError=class(Exception);
function BuildD12NsdELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.elfgeometry;

const HeaderBytes=120;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12NsdELFError.Create(Why);
end;

{ Exact — borrowed 12 двійкових символів. Result — signed 32-bit
  host-операнд для mov/add; жодного десяткового проміжного SENS.
  1) Чому знак розширюємо? 2) Чому 12, не 16 бітів?
  3) Чим це відрізняється від Unicode-числа? 4) Де перевірено D12? }
function Immediate12(const Exact:RawByteString):LongInt;
var I,Unsigned:LongInt;
begin
  Need(Length(Exact)=12,'операнд має бути точним D12');
  Unsigned:=0;
  for I:=1 to 12 do begin
    Need(Exact[I] in ['0','1'],'пошкоджений двійковий D12');
    Unsigned:=Unsigned*2+Ord(Exact[I])-Ord('0');
  end;
  if Exact[1]='1' then Result:=Unsigned-4096 else Result:=Unsigned;
end;

{ Mechanical T5M lookup тільки з раніше перевіреного EncodeT5M:
  5 тритів→1 byte, два останні біти з канонічним padding до 5.
  Це host binary-format table, ніколи opcode/доменний реєстр.
  1) Чому жоден індекс не є D7 кодом? 2) Чому кінець має padding?
  3) Чому байт не є семантичною ідентичністю числа? }
function LookupWord(I,W:SizeInt):AnsiChar;
var Bits,Encoded:RawByteString; Words:TExactWords; J:SizeInt;
begin
  Need((W=5) or (W=2),'невірна T5M lookup ширина');
  Need((I>=0) and (I<(1 shl W)),'індекс T5M поза бюджетом');
  SetLength(Bits,W);
  for J:=1 to W do
    if (I and (1 shl (W-J)))<>0 then Bits[J]:='1' else Bits[J]:='0';
  SetLength(Words,1);Words[0]:=Bits;
  Encoded:=EncodeT5M(Words);
  Need(Length(Encoded)=1,'одне фізичне W2/W5 має один байт');
  Result:=Encoded[1];
end;

{ Входи borrowed canonical packed T5M D12; Result — owned managed ELF64.
  A/B — тимчасові host immediates (1..2047), НЕ нова мова чисел.
  Машинний цикл: EDX=0; DIV ECX; (EAX,ECX)=(ECX,EDX).
  Перевірка ECX=0 перед діленням робить кінець циклу безпечним.
  Математичний результат НЕ обчислюється у FPC до породження ELF.
  1) Чому signed D12 допускаємо лише позитивний піднабір?
  2) Де ратифіковано D6:010101? 3) Чому результат W12, а не D7?
  4) Чому не можна зробити DIV при ECX=0?
  5) Хто звільняє керовані Code/Result і тимчасову пам'ять ELF? }
function BuildD12NsdELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var L,R:TExplicitNumeric; Code,Table5,Table2:RawByteString;
    Geometry:TELFGeometry; A,B,FirstLea,SecondLea,I,CodeBytes,LoopPos,JzPos,JmpPos,ExitPos:SizeInt;

  procedure Add(const Bytes:RawByteString);
  begin
    Code:=Code+Bytes;
    Need(Length(Code)<4096,'неприпустима довжина машинного коду');
  end;

  procedure Add32(V:LongWord);
  var K:SizeInt;
  begin
    for K:=0 to 3 do begin Add(AnsiChar(V and $FF));V:=V shr 8 end;
  end;

  procedure Patch32(var Target:RawByteString;Pos0:SizeInt;V:LongWord);
  var K:SizeInt;
  begin
    Need((Pos0>=0) and (Pos0<=Length(Target)-4),'неприпустимий RIP relocation');
    for K:=0 to 3 do begin
      Target[Pos0+K+1]:=AnsiChar(V and $FF);
      V:=V shr 8;
    end;
  end;

  procedure Put(Off:SizeInt;V:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Need((Off>=0) and (Count>0) and (Count<=8) and
      (Off<=Length(Result)-Count),'ELF поле поза довжиною');
    for K:=0 to Count-1 do begin
      Result[Off+K+1]:=AnsiChar(Byte(V and $FF));
      V:=V shr 8;
    end;
  end;

begin
  Result:='';
  { Єдине джерело числової механіки — наявні pinned module gates. }
  L:=ReadNumericPhysical(LeftPhysical,12);
  R:=ReadNumericPhysical(RightPhysical,12);
  A:=Immediate12(L.ExactBits);
  B:=Immediate12(R.ExactBits);
  { Це свідомий позитивний піднабір D12 signed; 0 і мінус — fail closed. }
  Need((A>0) and (A<=2047) and (B>0) and (B<=2047),
    'нативний НСД допускає лише додатні D12 1..2047');
  Table5:='';Table2:='';
  for I:=0 to 31 do Table5:=Table5+LookupWord(I,5);
  for I:=0 to 3 do Table2:=Table2+LookupWord(I,2);
  Need((Length(Table5)=32) and (Length(Table2)=4),
    'неповна таблиця T5M');
  { FPC перевіряє лише фізичний допуск і межі; НСД рахує машинний цикл. }
  Need((Length(L.ExactBits)=12) and (Length(R.ExactBits)=12),
    'втрата точних D12 операндів');

  Code:='';
  Add(#$B8); Add32(LongWord(A));       { MOV EAX, immediate D12 }
  Add(#$B9); Add32(LongWord(B));       { MOV ECX, immediate D12 }
  LoopPos:=Length(Code);
  Add(#$85#$C9);                      { TEST ECX,ECX }
  JzPos:=Length(Code);
  Add(#$0F#$84); Add32(0);             { JZ до готового НСД }
  Add(#$31#$D2);                      { XOR EDX,EDX — нуль старших бітів }
  Add(#$F7#$F1);                      { DIV ECX — остача EDX }
  Add(#$89#$C8);                      { MOV EAX,ECX }
  Add(#$89#$D1);                      { MOV ECX,EDX }
  JmpPos:=Length(Code);
  Add(#$E9); Add32(0);                 { JMP назад до TEST }
  ExitPos:=Length(Code);
  Patch32(Code,JzPos+2,LongWord(LongInt(ExitPos-(JzPos+6))));
  Patch32(Code,JmpPos+1,LongWord(LongInt(LoopPos-(JmpPos+5))));
  Add(#$25#$FF#$0F#$00#$00);         { маска рівно D12 вихідних бітів }
  Add(#$48#$83#$EC#$10);            { sub rsp,16; private 3-byte buffer }
  Add(#$89#$C1#$C1#$E9#$07#$83#$E1#$1F);
  FirstLea:=Length(Code);
  Add(#$48#$8D#$35#0#0#0#0);        { lea rsi,[rip+table5] }
  Add(#$8A#$14#$0E#$88#$14#$24);   { table5[(eax>>7)&31] -> rsp[0] }
  Add(#$89#$C1#$C1#$E9#$02#$83#$E1#$1F);
  Add(#$8A#$14#$0E#$88#$54#$24#$01); { table5[(eax>>2)&31] -> rsp[1] }
  Add(#$89#$C1#$83#$E1#$03);
  SecondLea:=Length(Code);
  Add(#$48#$8D#$3D#0#0#0#0);        { lea rdi,[rip+table2] }
  Add(#$8A#$14#$0F#$88#$54#$24#$02); { table2[eax&3] -> rsp[2] }
  Add(#$B8#$01#0#0#0);              { write(1,rsp,3) }
  Add(#$BF#$01#0#0#0);
  Add(#$48#$89#$E6);
  Add(#$BA#$03#0#0#0);
  Add(#$0F#$05);                       { sys_write(1,rsp,3) }
  { G6.219: Linux повертає у RAX ФАКТИЧНУ довжину запису.
    Лише рівно три packed T5M байти означають завершену відповідь.
    RDI перед syscall був 1; Linux x86-64 syscall змінює RCX/R11/RAX,
    але не RDI. SETNE записує молодший DIL = 0 або 1, SHL → host 0/2.
    Другий syscall завжди exit; ми не додаємо третього системного виклику.
    Це перевірка host stdout, НЕ новий D6 закон або локальний evaluator.
    1) Чому саме три байти? 2) Чому перевіряємо RAX після syscall?
    3) Що зберігає старші 24 біти EDI нульовими?
    4) Чому exit(2) не є SENS значенням?
    5) Чому відсутній додатковий write/буфер? }
  Add(#$48#$83#$F8#$03);             { cmp rax,3 }
  Add(#$40#$0F#$95#$C7);             { setne dil: RDI був 1 }
  Add(#$D1#$E7);                     { shl edi,1: 0 або 2 }
  Add(#$B8#$3C#0#0#0);                { Linux sys_exit(EDI) }
  Add(#$0F#$05);
  CodeBytes:=Length(Code);
  Patch32(Code,FirstLea+3,LongWord(CodeBytes-(FirstLea+7)));
  Patch32(Code,SecondLea+3,LongWord(CodeBytes+32-(SecondLea+7)));

  SetLength(Result,HeaderBytes+CodeBytes+36);
  FillChar(Result[1],Length(Result),0);
  { PIE ELF64, одна RX PT_LOAD, адреси тільки RIP-relative.
    RW-стек надає Linux; executable сегмент ніколи не стає writable. }
  Put(0,$464C457F,4);
  Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Length(Result),8);Put(104,Length(Result),8);Put(112,$1000,8);
  for I:=1 to CodeBytes do Result[HeaderBytes+I]:=Code[I];
  for I:=1 to 32 do Result[HeaderBytes+CodeBytes+I]:=Table5[I];
  for I:=1 to 4 do Result[HeaderBytes+CodeBytes+32+I]:=Table2[I];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)),
    'непідтверджена геометрія нативного ELF64');
end;
end.
