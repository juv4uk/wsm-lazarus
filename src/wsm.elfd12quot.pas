{ G6.78 — звужений pinned машинний fast-path D5:10111 «частка».
  Два окремі canonical D12 атоми, рівні, додатні, ненульові.
  ELF64 PIE реально виконує CQO + IDIV RCX, а не друкує
  наперед задану відповідь. Це НЕ загальна реалізація ділення
  чи копія закону D5; викличність дає тільки pinned SENS.
  Історичний x86-64 mccarthy-eval — інженерний донор, не authority. }
unit wsm.elfd12quot;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12QuotELFError=class(Exception);
function BuildD12QuotELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.elfgeometry;

const HeaderBytes=120;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12QuotELFError.Create(Why);
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

{ Параметри — borrowed canonical T5M атоми D12, повертається
  owned RawByteString із справжнім ET_DYN ELF64. Два managed
  TExplicitNumeric зберігають exact 12-bit значення. На рівних
  додатних ненульових RAX/RCX machine обчислює CQO/IDIV,
  залишає 12 молодших бітів у EAX і кодує три байти T5M
  тільки за згенерованими з wsm.t5m таблицями. Linux сам
  звільняє stack 16-byte buffer після exit; FPC звільняє Image.
  1) Чому рівність і знак — ДО emission? 2) Чому CQO потрібен?
  3) Хто перевіряє bytes фізичного D12? 4) Чому це не D5 evaluator?
  5) Чому відповідь обчислюється лише при запуску ELF? }
function BuildD12QuotELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var L,R:TExplicitNumeric; Code,Table5,Table2:RawByteString;
    Geometry:TELFGeometry; A,B,FirstLea,SecondLea,I,CodeBytes:SizeInt;

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
  { Точний pinned machine profile допускає лише рівні додатні
    операнди; цей gate не визначає новий закон ділення. }
  Need((L.ExactBits=R.ExactBits) and (A>0) and (B>0),
    'машинний CQO/IDIV допускає лише рівні додатні D12 числа');
  Table5:='';Table2:='';
  for I:=0 to 31 do Table5:=Table5+LookupWord(I,5);
  for I:=0 to 3 do Table2:=Table2+LookupWord(I,2);
  Need((Length(Table5)=32) and (Length(Table2)=4),
    'неповна таблиця T5M');
  { Операнди перевірено ReadNumericPhysical; відповідь формується
    машинним IDIV лише при ЗАПУСКУ, а не під час компіляції. }
  Need((Length(L.ExactBits)=12) and (Length(R.ExactBits)=12),
    'втрата точних D12 операндів');

  Code:='';
  Add(#$48#$C7#$C0); Add32(LongWord(A));  { mov rax, imm32 (signextended) }
  Add(#$48#$99);                         { CQO signextend RAX into RDX:RAX }
  Add(#$48#$C7#$C1); Add32(LongWord(B));  { mov rcx, imm32 (positive divisor) }
  Add(#$48#$F7#$F9);                     { IDIV rcx — реальна частка в RAX }
  Add(#$25#$FF#$0F#$00#$00);           { output: низькі рівно 12 біт D12 }
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
  Add(#$0F#$05);
  Add(#$B8#$3C#0#0#0);              { exit(0) }
  Add(#$31#$FF#$0F#$05);
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
