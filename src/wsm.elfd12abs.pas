{ G6.88 — машинний x86-64 CDQ/XOR/SUB для модуля для одного exact D12 з D24-просуванням.
  Ширину допускає лише чинний MultiplyNumericPhysical і pinned Contract 12.0.
  Тут немає нового SENS закону, opcode чи текстового dispatch.
  Відсутня constant-fold підміна: x86 CDQ/XOR/SUB обчислює значення у runtime. }
unit wsm.elfd12abs;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12AbsELFError=class(Exception);
function BuildD12AbsELF(const InputPhysical:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.numericmul,wsm.elfgeometry;

const ELFHeaderBytes=120;
type TIntArray=array of SizeInt;
     TRawArray=array of RawByteString;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ED12AbsELFError.Create(Why) end;

function Immediate12(const Bits:RawByteString):LongInt;
var I,V:LongInt;
begin
  Need(Length(Bits)=12,'операнд має бути точним D12');
  V:=0;
  for I:=1 to 12 do begin
    Need(Bits[I] in ['0','1'],'пошкоджений двійковий D12');
    V:=V*2+Ord(Bits[I])-Ord('0');
  end;
  if Bits[1]='1' then Result:=V-4096 else Result:=V;
end;

function T5MTableByte(Width,Chunk,Index:SizeInt):AnsiChar;
var Bits,Encoded:RawByteString; Words:TExactWords;
    Start,Count,J:SizeInt;
begin
  Start:=Chunk*5;
  Count:=Width-Start;
  if Count>5 then Count:=5;
  Need((Width in [12,24]) and (Count>0) and (Index<(1 shl Count)),
    'неприпустима фізична T5M таблиця');
  Bits:=StringOfChar('0',Width);
  for J:=0 to Count-1 do
    if (Index and (1 shl (Count-J-1)))<>0 then Bits[Start+J+1]:='1';
  SetLength(Words,1); Words[0]:=Bits;
  Encoded:=EncodeT5M(Words);
  Need(Length(Encoded)=(Width+5) div 5,'неочікувана довжина канонічного T5M');
  Result:=Encoded[Chunk+1];
end;

function BuildD12AbsELF(const InputPhysical:RawByteString):RawByteString;
var Input,Answer:TExplicitNumeric; Expected,MinusOne:RawByteString;
    Width,Chunks,I,J,N,Shift,Mask,CodeBytes,TableStart,OutBytes:SizeInt;
    A:LongInt; Code,Image:RawByteString; Tables:TRawArray;
    LeaPos:TIntArray; TableOffsets:TIntArray; Geometry:TELFGeometry;

  procedure Emit(const S:RawByteString);
  begin Code:=Code+S; Need(Length(Code)<4096,'завеликий ELF машинний код') end;

  procedure Emit32(V:LongWord);
  var K:SizeInt;
  begin for K:=0 to 3 do begin Emit(AnsiChar(V and $FF)); V:=V shr 8 end end;

  procedure Patch32(var S:RawByteString;Pos0:SizeInt;V:LongWord);
  var K:SizeInt;
  begin
    Need((Pos0>=0) and (Pos0+4<=Length(S)),'неприпустима адреса RIP-відносного поля');
    for K:=0 to 3 do begin S[Pos0+K+1]:=AnsiChar(V and $FF); V:=V shr 8 end;
  end;

  procedure Put(Off:SizeInt;V:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Need((Off>=0) and (Count>0) and (Count<=8) and (Off+Count<=Length(Image)),
      'ELF поле поза образом');
    for K:=0 to Count-1 do begin Image[Off+K+1]:=AnsiChar(Byte(V and $FF)); V:=V shr 8 end;
  end;

begin
  Result:='';
  { Перш ніж емітувати код, числова операція відповідна гілка (-1) * D12 повинна
    пройти тільки чинний pinned числовий механізм. Вхід не мутуємо.
    Результат owned; ширина точна D12 або, для -2048, D24.
    Питання: чому MUL є gate? Чому overflow не обрізаємо?
    Чому D7/англійський рядок не є числовим dispatch? }
  Input:=ReadNumericPhysical(InputPhysical,12);
  MinusOne:=EncodeNumericDecimal('-1',12);
  if Input.ExactBits[1]='1' then
    Expected:=MultiplyNumericPhysical(MinusOne,InputPhysical,12)
  else Expected:=InputPhysical;
  try
    Answer:=ReadNumericPhysical(Expected,12);
    Width:=12;
  except
    on ENumericPlaneError do begin
      Answer:=ReadNumericPhysical(Expected,24);
      Width:=24;
    end;
  end;
  Need((Answer.DomainWidth=Width) and (Length(Answer.ExactBits)=Width),
    'порушено точну ширину результату модуля D12/D24');
  A:=Immediate12(Input.ExactBits);
  OutBytes:=(Width+5) div 5;
  Chunks:=OutBytes;
  SetLength(Tables,Chunks); SetLength(LeaPos,Chunks); SetLength(TableOffsets,Chunks);
  Code:='';
  Emit(#$B8); Emit32(LongWord(A));                { mov eax, signed D12 }
  Emit(#$99#$31#$D0#$29#$D0);                                { CDQ; XOR EAX,EDX; SUB EAX,EDX: справжній машинний модуль }
  Emit(#$48#$83#$EC#$08);                         { private stack output buffer }
  for I:=0 to Chunks-1 do begin
    N:=Width-I*5; if N>5 then N:=5;
    Shift:=Width-(I*5+N); Mask:=(1 shl N)-1;
    Emit(#$89#$C1);                               { mov ecx,eax }
    if Shift>0 then begin Emit(#$C1#$E9); Emit(AnsiChar(Shift)) end;
    Emit(#$83#$E1); Emit(AnsiChar(Mask));         { and ecx,bit mask }
    LeaPos[I]:=Length(Code);
    Emit(#$48#$8D#$35#0#0#0#0);                   { lea rsi,[rip+chunk table] }
    Emit(#$8A#$14#$0E);                           { mov dl,[rsi+rcx] }
    if I=0 then Emit(#$88#$14#$24)
    else begin Emit(#$88#$54#$24); Emit(AnsiChar(I)) end;
  end;
  Emit(#$B8#$01#0#0#0); Emit(#$BF#$01#0#0#0);     { write(1,rsp,n) }
  Emit(#$48#$89#$E6); Emit(#$BA); Emit32(OutBytes); Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0); Emit(#$31#$FF#$0F#$05);   { exit(0) }
  CodeBytes:=Length(Code);
  TableStart:=CodeBytes;
  for I:=0 to Chunks-1 do begin
    N:=Width-I*5; if N>5 then N:=5;
    SetLength(Tables[I],1 shl N);
    for J:=0 to Length(Tables[I])-1 do Tables[I][J+1]:=T5MTableByte(Width,I,J);
    TableOffsets[I]:=TableStart;
    Inc(TableStart,Length(Tables[I]));
  end;
  for I:=0 to Chunks-1 do
    Patch32(Code,LeaPos[I]+3,LongWord(ELFHeaderBytes+TableOffsets[I]-
      (ELFHeaderBytes+LeaPos[I]+7)));

  SetLength(Image,ELFHeaderBytes+TableStart);
  FillChar(Image[1],Length(Image),0);
  Put(0,$464C457F,4); Put(4,2,1); Put(5,1,1); Put(6,1,1);
  Put(16,3,2); Put(18,62,2); Put(20,1,4);
  Put(24,ELFHeaderBytes,8); Put(32,64,8);
  Put(52,64,2); Put(54,56,2); Put(56,1,2);
  Put(64,1,4); Put(68,5,4);
  Put(80,0,8); Put(88,0,8);
  Put(96,Length(Image),8); Put(104,Length(Image),8); Put(112,$1000,8);
  for I:=1 to CodeBytes do Image[ELFHeaderBytes+I]:=Code[I];
  TableStart:=CodeBytes;
  for I:=0 to Chunks-1 do begin
    for J:=1 to Length(Tables[I]) do Image[ELFHeaderBytes+TableStart+J]:=Tables[I][J];
    Inc(TableStart,Length(Tables[I]));
  end;
  VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Image)),
    'не підтверджено ELF64 PIE геометрію');
  Result:=Image;
end;
end.
