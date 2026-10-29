{ G6.107: локальні відносні CALL/RET + збережений кадр RBP.
  Вхід: каталог артефактів. Вихід: два дійсні ELF64, два точні
  packed T5M D1, машинна матриця для незалежного GNU as.
  Кодер не обчислює предикатів або SENS результатів на Pascal.

  Питання: 1) Як відрізнити signed displacement від D12 числа?
  2) Чому фізична адреса після CALL не дорівнює адресі opcode?
  3) Що перевіряє незалежний GNU as, а що виконання ELF?
  4) Чому стекове вирівнювання залежить від обох CALL?
  5) Чому D1:0 і D1:1 генеруються через pinned T5M кодек? }
program TestX64Call;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64stack,wsm.x64call,
     wsm.t5m,wsm.elfgeometry;

var Code:TX64Code;Dir:String;GoldenBytes,Machine,Image,Physical:RawByteString;
    F,Back,FirstTarget,SecondTarget,I,Bit,Negative:SizeInt;
    Geometry:TELFGeometry;

procedure Need(Yes:Boolean;const Why:String);
begin
  if not Yes then raise Exception.Create('X64-ВИКЛИК-ПРОВАЛ: '+Why);
end;

procedure SaveBytes(const Path:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then Stream.WriteBuffer(Data[1],Length(Data));
  finally
    Stream.Free;
  end;
end;

procedure Golden;
var Source:TStringList;
begin
  X64Reset(Code);
  X64EmitLocalCall(Code,F);
  Need(F=1,'0-based CALL disp32 починається з байта 1');
  X64MovImm32(Code,xrAX,7);
  FirstTarget:=Length(Code.Bytes);
  X64Return(Code);
  SecondTarget:=Length(Code.Bytes);
  X64Return(Code);
  X64EmitLocalCall(Code,Back);
  Need(Back=13,'0-based CALL назад має disp32=13');
  X64PatchLocalCall(Code,F,FirstTarget);
  X64PatchLocalCall(Code,Back,SecondTarget);
  GoldenBytes:=X64Image(Code);
  Need(GoldenBytes=
    #$E8#$05#0#0#0+#$B8#$07#0#0#0+#$C3#$C3+
    #$E8#$FA#$FF#$FF#$FF,
    'незалежні golden CALL forward +5 / backward -6');
  Source:=TStringList.Create;
  try
    Source.Add('.intel_syntax noprefix');
    Source.Add('.text');
    Source.Add('.global _start');
    Source.Add('_start:');
    Source.Add('  call .Lfirst');
    Source.Add('  mov eax, 7');
    Source.Add('.Lfirst:');
    Source.Add('  ret');
    Source.Add('.Lsecond:');
    Source.Add('  ret');
    Source.Add('  call .Lsecond');
    Source.SaveToFile(Dir+'/call-matrix.s');
  finally
    Source.Free;
  end;
  SaveBytes(Dir+'/call-matrix.fpc.bin',GoldenBytes);
end;

{ Кожна невдала підстановка тестується на старому непорожньому коді.
  Спроба не може частково замінити байти або залишити відірвану адресу.
  Відновлення після негативу має дати правильну інструкцію. }
procedure RefusePatch(Kind:SizeInt);
var Old:RawByteString;Raised:Boolean;Fix,Target:SizeInt;
begin
  X64Reset(Code);
  X64EmitLocalCall(Code,Fix);
  X64MovImm32(Code,xrAX,7);
  X64Return(Code);
  Target:=Length(Code.Bytes)-1;
  case Kind of
    6:Code.Bytes[Fix]:=#$90;
    7:Code.Bytes[Fix+1]:=#$01;
    9:X64PatchLocalCall(Code,Fix,Target);
    11:Code.Bytes:=StringOfChar(AnsiChar($90),257);
  end;
  Old:=X64Image(Code);
  Raised:=False;
  try
    case Kind of
      1:X64PatchLocalCall(Code,-1,Target);
      2:X64PatchLocalCall(Code,0,Target);
      3:X64PatchLocalCall(Code,Fix,-1);
      4:X64PatchLocalCall(Code,Fix,Length(Code.Bytes));
      5:X64PatchLocalCall(Code,Fix,Length(Code.Bytes)+1);
      6,7,9,11:X64PatchLocalCall(Code,Fix,Target);
      8:X64PatchLocalCall(Code,Fix,Fix+4);
      10:X64PatchLocalCall(Code,Fix+1,Target);
    end;
  except on E:EX64CodeError do Raised:=True end;
  Need(Raised,'відсутня відмова патчера '+IntToStr(Kind));
  Need(Code.Bytes=Old,'патчер пошкодив буфер '+IntToStr(Kind));
  Inc(Negative);
  X64Reset(Code);
  X64EmitLocalCall(Code,Fix);
  X64MovImm32(Code,xrAX,7);
  Target:=Length(Code.Bytes);
  X64Return(Code);
  X64PatchLocalCall(Code,Fix,Target);
  Need(X64Image(Code)=#$E8#$05#0#0#0+#$B8#$07#0#0#0+#$C3,
       'не відновлено правильний CALL після негативу');
end;

procedure RejectAppend(Kind:SizeInt);
var Old:RawByteString;Raised:Boolean;Fix:SizeInt;
begin
  X64Reset(Code);
  if Kind=12 then
    Code.Bytes:=StringOfChar(AnsiChar($90),252)
  else
    Code.Bytes:=StringOfChar(AnsiChar($90),256);
  Old:=X64Image(Code);
  Raised:=False;
  try
    if Kind=12 then
      X64EmitLocalCall(Code,Fix)
    else
      X64Return(Code);
  except on E:EX64CodeError do Raised:=True end;
  Need(Raised,'не відхилено квоту '+IntToStr(Kind));
  Need(Code.Bytes=Old,'неатомарне переповнення '+IntToStr(Kind));
  Inc(Negative);
end;

procedure PutLE(var Data:RawByteString;Offset:SizeInt;Value:QWord;Count:SizeInt);
var J:SizeInt;
begin
  Need((Offset>=0) and (Count>=1) and (Count<=8) and
       (Offset<=Length(Data)-Count),'ELF поле за межею');
  for J:=0 to Count-1 do begin
    Data[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function PhysicalD1(Value:SizeInt):RawByteString;
var Words:TExactWords;
begin
  Need((Value=0) or (Value=1),'недопустиме D1 тестове значення');
  SetLength(Words,1);
  Words[0]:=AnsiChar(Ord('0')+Value);
  Result:=EncodeT5M(Words);
  Need(Length(Result)=1,'D1 фізичне слово не має одного T5M байта');
end;

{ ДВА вкладені машинні CALL:
  entry→F1 (push rbp)→F2 (мовно-нейтральне повернення фізичного байта)
  →F1 (pop rbp,ret)→entry (запис одного T5M байта у stdout).
  RSP при entry кратний 16, F1 після CALL має RSP mod16=8,
  PUSH RBP відновлює mod16=0 перед другим CALL, F2 має mod16=8.
  Жодного обчислення семантики на Pascal — тільки pinned codec.
  Результат — owned ELF64 PIE, stack frame зберігається на CPU. }
procedure BuildNestedELF(Value:SizeInt);
var OuterFix,InnerFix,OuterAt,InnerAt,K,LengthImage:SizeInt;
begin
  Physical:=PhysicalD1(Value);
  X64Reset(Code);
  X64EmitLocalCall(Code,OuterFix);
  X64StackSubtract(Code,16);
  X64StoreRspQword(Code,xrAX,0);
  X64MovImm32(Code,xrAX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovRSIRsp(Code);
  X64MovImm32(Code,xrDX,1);
  X64Syscall(Code);
  X64StackAdd(Code,16);
  X64MovImm32(Code,xrAX,60);
  X64XorEDI(Code);
  X64Syscall(Code);

  OuterAt:=Length(Code.Bytes);
  X64StackPush(Code,xrBP);
  X64EmitLocalCall(Code,InnerFix);
  X64StackPop(Code,xrBP);
  X64Return(Code);

  InnerAt:=Length(Code.Bytes);
  X64MovImm32(Code,xrAX,Ord(Physical[1]));
  X64Return(Code);

  X64PatchLocalCall(Code,OuterFix,OuterAt);
  X64PatchLocalCall(Code,InnerFix,InnerAt);
  Machine:=X64Image(Code);
  LengthImage:=120+Length(Machine);
  Need(Length(Machine)<=256,'машинний код перевищив квоту');
  SetLength(Image,LengthImage);
  FillChar(Image[1],Length(Image),0);
  PutLE(Image,0,$464C457F,4);
  PutLE(Image,4,2,1);PutLE(Image,5,1,1);PutLE(Image,6,1,1);
  PutLE(Image,16,3,2);PutLE(Image,18,62,2);PutLE(Image,20,1,4);
  PutLE(Image,24,120,8);PutLE(Image,32,64,8);
  PutLE(Image,52,64,2);PutLE(Image,54,56,2);PutLE(Image,56,1,2);
  PutLE(Image,64,1,4);PutLE(Image,68,5,4);
  PutLE(Image,96,LengthImage,8);
  PutLE(Image,104,LengthImage,8);PutLE(Image,112,$1000,8);
  for K:=1 to Length(Machine) do Image[120+K]:=Machine[K];
  VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=LengthImage),'невалідний PIE ELF64');
  SaveBytes(Dir+'/call-'+IntToStr(Value)+'.elf',Image);
  SaveBytes(Dir+'/call-'+IntToStr(Value)+'.expected.sens',Physical);
end;

procedure PrintSummary;
var Bytes:RawByteString;OutputBytes:THandleStream;
begin
  { Явні UTF-8 байти: FPC WriteLn під C.UTF-8 може втратити кирилицю
    через системний OEM/console conversion навіть після codepage utf8.
    OS-handle позичений, THandleStream звільняється нами. }
  Bytes:=RawByteString(UTF8Encode(UnicodeString(
    'X64-ЛОКАЛЬНІ-ВИКЛИКИ-ГОТОВО')))+
    ' golden=2 GNU-as=1 negative='+IntToStr(Negative)+
    ' nested-calls=2 elf=2 energy=NOT-MEASURED'+#10;
  OutputBytes:=THandleStream.Create(TextRec(Output).Handle);
  try OutputBytes.WriteBuffer(Bytes[1],Length(Bytes));
  finally OutputBytes.Free end;
end;

begin
  Need(ParamCount=1,'потрібен каталог артефактів');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'немає каталогу артефактів');
  Negative:=0;
  Golden;
  for I:=1 to 11 do RefusePatch(I);
  RejectAppend(12);
  RejectAppend(13);
  for Bit:=0 to 1 do BuildNestedELF(Bit);
  PrintSummary;
end.
