{ G6.63 — нативний x86-64 D12-додавач: машинний ADD, не константна відповідь.
  Точна числова семантика належить pinned SENS, її FPC-механізм —
  wsm.numericadd. Тут тільки механічне 12-bit lowering і T5M write.
  D12→D24 overflow навмисно НЕ підтримується: відмова до ELF. }
unit wsm.elfd12add;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12ELFError=class(Exception);
function BuildD12AddELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.numericadd,wsm.elfgeometry;

const HeaderBytes=120;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12ELFError.Create(Why);
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

{ Входи — два власні канонічні T5M атоми D12.
  Вихід — ELF64 ET_DYN: обчислює EAX=signextend(L)+signextend(R),
  відкидає лише зайві 20 host-бітів (не D12 overflow — його відхилено
  за pinned AddNumericPhysical ПЕРЕД emission), за таблицями складає
  3 байти T5M на стеку і виконує sys_write(1,buf,3), exit(0).
  Таблиці кодека походять виключно з wsm.t5m. Код завжди executable
  й не містить готових байтів суми як literal.
  1) Де перевіряється переповнення? 2) Чому дані на стеку?
  3) Як RIP-relative таблиці не залежать від ASLR? 4) Як
  доводимо, що справжній ELF арифметично рахує? 5) Хто звільняє Image? }
function BuildD12AddELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var L,R,Answer:TExplicitNumeric; Expected,Code,Table5,Table2:RawByteString;
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
  Expected:=AddNumericPhysical(LeftPhysical,RightPhysical,12);
  try
    Answer:=ReadNumericPhysical(Expected,12);
  except on E:Exception do
    raise ED12ELFError.Create('D12→D24 потребує іншого backend: '+E.Message)
  end;

  A:=Immediate12(L.ExactBits);
  B:=Immediate12(R.ExactBits);
  Table5:='';Table2:='';
  for I:=0 to 31 do Table5:=Table5+LookupWord(I,5);
  for I:=0 to 3 do Table2:=Table2+LookupWord(I,2);
  Need((Length(Table5)=32) and (Length(Table2)=4),
    'неповна таблиця T5M');
  { Повторна перевірка механічного T5M результату до ELF. }
  I:=0;
  while I<Length(Answer.ExactBits) do Inc(I);
  Need(I=12,'сума втратила точну ширину');

  Code:='';
  Add(#$B8); Add32(LongWord(A));      { mov eax, signextended L }
  Add(#$05); Add32(LongWord(B));      { add eax, signextended R }
  Add(#$25#$FF#$0F#$00#$00);        { and eax, 0x0fff }
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
  Add(#$0F#$05);                     { справжній write(1,rsp,3), RAX=кількість/error }
  { G6.210: відмова на неповному host stdout, навіть коли D12 ADD
    було правильно обчислено у машинному EAX. Це лише Linux status,
    не D1, не D5 закон і не нова перевірка pinned чисел.
    1) Чому cmp RAX,3, а не перевірка арифметичного результату?
    2) Чому навіть 1 чи 2 фізичні байти не доводять T5M?
    3) Чому short JNE пропускає рівно дев'ять байтів exit(0)?
    4) Чому новий ELF не змінює успішні T5M байти? }
  Add(#$48#$83#$F8#$03);             { cmp rax,3 }
  Add(#$75#$09);                     { jne +9, пропустити успішний exit }
  Add(#$B8#$3C#0#0#0);               { exit(0) лише після повного write }
  Add(#$31#$FF#$0F#$05);
  Add(#$B8#$3C#0#0#0);               { exit(2) для -errno / short write }
  Add(#$BF#$02#0#0#0);
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
