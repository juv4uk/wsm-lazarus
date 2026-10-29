{ G6.78 — нативний машинний x86-64 D5:11011 «більше?» над двома D12.
  Вузький host-профіль, НЕ синтаксичний компілятор довільної D5-форми.
  Єдиний закон: pinned Contract 12 / lib/domains/d5.lisp;
  ISA доказ: pinned machine/profile/current-domain-x86-64.lisp.
  Вхід: два canonical packed T5M D12, вихід ELF64 ET_DYN, який
  ВИКОНУЄ cmp eax,ecx / setg al / movzx eax,al → D1 T5M stdout.
  Немає FPC попереднього обчислення відповіді чи локальних законів. }
unit wsm.elfd12greater;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12GreaterELFError=class(Exception);
function BuildD12GreaterELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.numericplane,wsm.t5m,wsm.elfgeometry;
const HeaderBytes=120;

procedure Need(Condition:Boolean;const Reason:String);
begin if not Condition then raise ED12GreaterELFError.Create(Reason) end;

{ Bits: borrowed W12 signed two's-complement; LongInt лише host immediate,
  не числове джерело закону. Значення не використовуємо для predicate:
  його з фактичних інструкцій визначить створений ELF. }
function NativeImmediate12(const Bits:RawByteString):LongInt;
var I,N:LongInt;
begin
  Need(Length(Bits)=12,'не точний D12');
  N:=0;
  for I:=1 to 12 do begin
    Need(Bits[I] in ['0','1'],'не двійкове D12');
    N:=2*N+Ord(Bits[I])-Ord('0');
  end;
  if Bits[1]='1' then Result:=N-4096 else Result:=N;
end;

{ Власні локальні FPC-managed T5M bytes містять два КОДИ D1:0/1,
  не результат конкретного порівняння. Machine вибирає індекс.
  Розміри/ELF metadata — host, не D12 чи SENS значення. }
function BuildD12GreaterELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var
  L,R:TExplicitNumeric;
  A,B:LongInt;
  W:TExactWords;
  NoBytes,YesBytes,Code,Table:RawByteString;
  StartLea,Disp,I,Total:SizeInt;
  G:TELFGeometry;

  procedure Add(const Data:RawByteString);
  begin
    Need(Length(Data)+Length(Code)<4096,'надто великий машинний код');
    Code:=Code+Data;
  end;

  procedure AddLE32(Value:LongWord);
  var J:SizeInt;
  begin
    for J:=0 to 3 do begin
      Add(AnsiChar(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

  procedure Patch32(Pos0:SizeInt;Value:LongWord);
  var J:SizeInt;
  begin
    Need((Pos0>=0) and (Pos0<=Length(Code)-4),'неправильний RIP displacement');
    for J:=0 to 3 do begin
      Code[Pos0+J+1]:=AnsiChar(Value and $FF);
      Value:=Value shr 8;
    end;
  end;

  procedure Put(Off:SizeInt;Value:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    Need((Off>=0) and (Count>=1) and (Count<=8) and
      (Off<=Length(Result)-Count),'ELF header поза межами');
    for J:=0 to Count-1 do begin
      Result[Off+J+1]:=AnsiChar(Value and $FF);
      Value:=Value shr 8;
    end;
  end;
begin
  Result:='';
  { Єдиний канонічний допуск — існуючий механізм exact D12. }
  L:=ReadNumericPhysical(LeftPhysical,12);
  R:=ReadNumericPhysical(RightPhysical,12);
  A:=NativeImmediate12(L.ExactBits);
  B:=NativeImmediate12(R.ExactBits);
  SetLength(W,1);
  W[0]:='0';NoBytes:=EncodeT5M(W);
  W[0]:='1';YesBytes:=EncodeT5M(W);
  Need((Length(NoBytes)=1) and (Length(YesBytes)=1) and
    (NoBytes<>YesBytes),'немає двох незалежних канонічних D1 байтів');
  Table:=NoBytes+YesBytes;
  { Машинний код не знає слова «більше?». Він приймає ЛИШЕ
    попередньо допущені signed D12 immediate; setg читає OF/SF/ZF.
    Два останні байти — T5M таблиця, взята з діючого codec.
    Ніякої host-оцінки A>B у цьому unit не здійснюємо. }
  Code:='';
  Add(#$B8);AddLE32(LongWord(A));   { mov eax, signed lhs }
  Add(#$B9);AddLE32(LongWord(B));   { mov ecx, signed rhs }
  Add(#$39#$C8);                   { cmp eax,ecx }
  Add(#$0F#$9F#$C0);               { setg al (signed) }
  Add(#$0F#$B6#$C0);               { movzx eax,al }
  StartLea:=Length(Code);
  Add(#$48#$8D#$35#0#0#0#0);       { lea rsi,[rip+table] }
  Add(#$0F#$B6#$04#$06);           { movzx eax,byte [rsi+rax] }
  Add(#$48#$83#$EC#$10);           { sub rsp,16 }
  Add(#$88#$04#$24);               { mov [rsp],al }
  Add(#$B8#$01#0#0#0);             { sys_write(1, stack, 1) }
  Add(#$BF#$01#0#0#0);
  Add(#$48#$89#$E6);
  Add(#$BA#$01#0#0#0);
  Add(#$0F#$05);
  Add(#$B8#$3C#0#0#0);             { sys_exit(0) }
  Add(#$31#$FF);
  Add(#$0F#$05);
  Disp:=Length(Code)-(StartLea+7);
  Need((Disp>=0) and (Disp<=High(LongInt)),'відносний T5M покажчик за межею');
  Patch32(StartLea+3,LongWord(Disp));
  Total:=HeaderBytes+Length(Code)+Length(Table);
  Need((Total>HeaderBytes) and (Total<4096),'машинний образ поза budget');
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
  for I:=1 to Length(Code) do Result[HeaderBytes+I]:=Code[I];
  Result[HeaderBytes+Length(Code)+1]:=Table[1];
  Result[HeaderBytes+Length(Code)+2]:=Table[2];
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.FileBytes=Length(Result)) and
    (G.MachineBytes=Length(Code)+Length(Table)),
    'машинний x86-64 ET_DYN не пройшов перевірку');
end;
{ Питання: 1) Чому setg, а не seta для знакового D12?
  2) Чому D1 кодек містить два байти, а не Pascal Boolean?
  3) Хто перевіряє точний W12 і канонічність T5M перед machine code?
  4) Чому RIP displacement не залежать від ASLR?
  5) Хто володіє managed Code/Result і чи є у ньому heap? }
end.
