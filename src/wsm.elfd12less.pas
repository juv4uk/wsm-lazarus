{ G6.75: два окремі фізичні signed D12 атоми → x86-64 CMP/SETL
  → точний T5M D1. Закон «менше?» — лише pinned SENS D5:11010.
  Це механізм нативної компіляції вузького host-профілю, не новий
  мовний opcode, не беззнаковий u64 machine-effect та не general compiler. }
unit wsm.elfd12less;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12LessELFError=class(Exception);
function BuildD12LessELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;

implementation
uses wsm.t5m,wsm.numericplane,wsm.elfgeometry;
const ELFHeaderBytes=120;

procedure Need(Condition:Boolean;const Why:String);
begin if not Condition then raise ED12LessELFError.Create(Why) end;

{ Позичені exact W12 signed бітові слова після ReadNumericPhysical.
  LongInt є host представленням для x86 EAX, НЕ SENS-domain identity.
  Від'ємний операнд розширюється знаком, а не втрачає провідні біти.
  1) Чому потрібно усі 12 бітів? 2) Хто відповідає за домен?
  3) Чому це не SENS беззнаковий u64 effect? }
function SignedImmediate12(const Bits:RawByteString):LongInt;
var I,V:LongInt;
begin
  Need(Length(Bits)=12,'неприпустима фізична ширина D12');
  V:=0;
  for I:=1 to 12 do begin
    Need(Bits[I] in ['0','1'],'нефізичні двійкові біти D12');
    V:=V*2+Ord(Bits[I])-48;
  end;
  if Bits[1]='1' then Result:=V-4096 else Result:=V;
end;

{ Два канонічні фізичні D1 байти отримуються ЛИШЕ з чинного
  EncodeT5M, не з вигаданого локального T5M-алфавіту.
  Борг FPC: Words/Encoded — managed owner, звільняє caller.
  1) Чому один біт ≠ один ASCII-байт '1'?
  2) Чому D7 текст сюди не може потрапити?
  3) Хто визначає закон D1? }
function EncodeD1Byte(const Bit:RawByteString):AnsiChar;
var Words:TExactWords;Encoded:RawByteString;
begin
  Need((Bit='0') or (Bit='1'),'недопущений D1-біт');
  SetLength(Words,1); Words[0]:=Bit;
  Encoded:=EncodeT5M(Words);
  Need(Length(Encoded)=1,'очікувано один packed D1 байт');
  Result:=Encoded[1];
end;

{ Left/Right — borrowed canonical T5M D12, не математичні імена.
  Image: owned ELF64 ET_DYN. Машинний код під час КОЖНОГО запуску:
  MOV eax,A; CMP eax,B; SETL al; MOVZX eax,al → D1 lookup →
  write(1,packed D1,1); exit(0). Це runtime computation, не
  precomputed результат FPC. Точний signed admission робить
  ReadNumericPhysical перед будь-яким формуванням ELF.
  1) Де саме виконується CMP? 2) Чому SETL signed?
  3) Як таблиця D1 адресується RIP-relative?
  4) Хто перевіряє ELF64 до публікації?
  5) Чому це не compiled arbitrary SENS expression? }
function BuildD12LessELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var L,R:TExplicitNumeric;A,B:LongInt;
    Code,Image:RawByteString;CodeBytes,LeaAt,I:SizeInt;
    Geometry:TELFGeometry;

  procedure Emit(const Bytes:RawByteString);
  begin
    Code:=Code+Bytes;
    Need(Length(Code)<4096,'перевищено межу машинного коду');
  end;

  procedure Emit32(Value:LongWord);
  var J:SizeInt;
  begin
    for J:=0 to 3 do begin Emit(AnsiChar(Value and $FF));Value:=Value shr 8 end;
  end;

  procedure Patch32(Pos0:SizeInt;Value:LongWord);
  var J:SizeInt;
  begin
    Need((Pos0>=0) and (Pos0+4<=Length(Code)),'адреса RIP displacement поза кодом');
    for J:=0 to 3 do begin
      Code[Pos0+J+1]:=AnsiChar(Value and $FF);
      Value:=Value shr 8;
    end;
  end;

  procedure Put(Offset:SizeInt;Value:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    Need((Offset>=0) and (Count>=1) and (Count<=8) and
      (Offset+Count<=Length(Image)),'поле ELF поза файлом');
    for J:=0 to Count-1 do begin
      Image[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';
  L:=ReadNumericPhysical(LeftPhysical,12);
  R:=ReadNumericPhysical(RightPhysical,12);
  A:=SignedImmediate12(L.ExactBits);
  B:=SignedImmediate12(R.ExactBits);

  Code:='';
  Emit(#$B8);Emit32(LongWord(A));              { MOV eax, signextend D12 }
  Emit(#$3D);Emit32(LongWord(B));              { CMP eax, signextend D12 }
  Emit(#$0F#$9C#$C0);                         { SETL al, signed comparison }
  Emit(#$0F#$B6#$C0);                         { MOVZX eax,al -> exact D1 bit }
  Emit(#$48#$83#$EC#$08);                    { SUB rsp,8: private byte }
  LeaAt:=Length(Code);
  Emit(#$48#$8D#$35#0#0#0#0);                { LEA rsi,[rip+table D1] }
  Emit(#$8A#$14#$06);                         { MOV dl,[rsi+rax] }
  Emit(#$88#$14#$24);                         { MOV [rsp],dl }
  Emit(#$B8#$01#0#0#0);                      { write syscall }
  Emit(#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6);
  Emit(#$BA#$01#0#0#0);
  Emit(#$0F#$05);
  { G6.214: Linux повертає у RAX кількість фактично записаних
    фізичних D1 T5M байтів. Один байт = успіх; -EBADF/-ENOSPC
    або короткий/нульовий запис НЕ є опублікованою відповіддю.
    Host exit code 2 не є SENS-значенням і не змінює D5 закон.
    Чому CMP перевіряє RAX, а не результат signed SETL? }
  Emit(#$48#$83#$F8#$01);                   { cmp rax,1: exact D1 T5M }
  Emit(#$75#$09);                           { jne +9 до exit(2) }
  Emit(#$B8#$3C#0#0#0);                     { exit(0) syscall }
  Emit(#$31#$FF#$0F#$05);
  Emit(#$B8#$3C#0#0#0);                     { exit(2) host failure }
  Emit(#$BF#$02#0#0#0);
  Emit(#$0F#$05);
  CodeBytes:=Length(Code);
  Patch32(LeaAt+3,LongWord(CodeBytes-(LeaAt+7)));

  SetLength(Image,ELFHeaderBytes+CodeBytes+2);
  FillChar(Image[1],Length(Image),0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,ELFHeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Length(Image),8);Put(104,Length(Image),8);Put(112,$1000,8);
  for I:=1 to CodeBytes do Image[ELFHeaderBytes+I]:=Code[I];
  Image[ELFHeaderBytes+CodeBytes+1]:=EncodeD1Byte('0');
  Image[ELFHeaderBytes+CodeBytes+2]:=EncodeD1Byte('1');
  VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Image)),
    'відхилено ELF64 ET_DYN геометрію');
  Result:=Image;
end;
end.
