{ G6.102 — машинний стек x86-64, незалежний GNU as і два реальні ELF.
  Це перевірка backend-механіки, а не нова семантика SENS.
  Питання: 1) Що доводить GNU as? 2) Навіщо атомарні негативи?
  3) Хто володіє Image? 4) Чим physical D1 відрізняється від host byte?
  5) Чому успішний ELF не доводить загальний compiler? }
program TestX64Stack;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.x64code, wsm.x64stack, wsm.t5m,
     wsm.elfgeometry;

const Amounts:array[0..4] of SizeInt=(8,16,120,128,4096);
      Offsets:array[0..2] of SizeInt=(0,8,120);
var OutDir:String; Code:TX64Code; TextAsm:TStringList;
    AllBytes,Image,Physical:RawByteString;
    R:TX64Reg; I,Bit,MatrixCount,NegativeCount:Integer;
    Geometry:TELFGeometry;

procedure Check(Good:Boolean;const Why:String);
begin
  if not Good then raise Exception.Create('стек: '+Why);
end;

function RegName(Reg:TX64Reg):String;
begin
  case Reg of
    xrAX:Result:='rax';xrCX:Result:='rcx';xrDX:Result:='rdx';
    xrBX:Result:='rbx';xrSP:Result:='rsp';xrBP:Result:='rbp';
    xrSI:Result:='rsi';xrDI:Result:='rdi';
  end;
end;

procedure SaveBinary(const Path:String;const Data:RawByteString);
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
begin
  X64Reset(Code);
  X64StackPush(Code,xrBP);
  Check(X64Image(Code)=#$55,'PUSH RBP');
  X64Reset(Code);
  X64StackPop(Code,xrDI);
  Check(X64Image(Code)=#$5F,'POP RDI');
  X64Reset(Code);
  X64StackSubtract(Code,120);
  Check(X64Image(Code)=#$48#$83#$EC#$78,'SUB RSP,120');
  X64Reset(Code);
  X64StackAdd(Code,128);
  Check(X64Image(Code)=#$48#$81#$C4#$80#0#0#0,'ADD RSP,128');
  X64Reset(Code);
  X64StackLoad(Code,xrDX,120);
  Check(X64Image(Code)=#$48#$8B#$54#$24#$78,'MOV RDX,[RSP+120]');
  X64Reset(Code);
  X64StackStore(Code,xrDX,120);
  Check(X64Image(Code)=#$48#$89#$54#$24#$78,'MOV [RSP+120],RDX');
end;

{ Різні відмови перевіряються на НЕПОРОЖНЬОМУ попередньому стані.
  Усі операції мають exception-safety strong guarantee.
  Питання: 1) Де треба робити quota-check?
  2) Чому негатив не може лишати частково записану інструкцію?
  3) Чим відрізняється RSP як адреса та RSP як ціль MOV? }
procedure Refuse(Kind:Integer);
var Before:RawByteString; Failed:Boolean;
begin
  X64Reset(Code);
  Code.Bytes:=#$90#$90;
  if ((Kind>=13) and (Kind<=15)) or (Kind=20) then
    Code.Bytes:=StringOfChar(AnsiChar($90),256);
  Before:=Code.Bytes;
  Failed:=False;
  try
    case Kind of
      1:X64StackPush(Code,xrSP);
      2:X64StackPop(Code,xrSP);
      3:X64StackSubtract(Code,0);
      4:X64StackSubtract(Code,7);
      5:X64StackSubtract(Code,-8);
      6:X64StackSubtract(Code,4097);
      7:X64StackAdd(Code,0);
      8:X64StackAdd(Code,15);
      9:X64StackLoad(Code,xrAX,-8);
      10:X64StackLoad(Code,xrAX,7);
      11:X64StackLoad(Code,xrAX,128);
      12:X64StackLoad(Code,xrSP,0);
      13:X64StackPush(Code,xrAX);
      14:X64StackSubtract(Code,4096);
      15:X64StackLoad(Code,xrDX,0);
      16:X64StackStore(Code,xrSP,0);
      17:X64StackStore(Code,xrAX,-8);
      18:X64StackStore(Code,xrAX,7);
      19:X64StackStore(Code,xrAX,128);
      20:X64StackStore(Code,xrAX,0);
      else raise Exception.Create('невідомий тест');
    end;
  except on E:EX64CodeError do Failed:=True end;
  Check(Failed,'негатив не відхилено '+IntToStr(Kind));
  Check(Code.Bytes=Before,'негатив пошкодив буфер '+IntToStr(Kind));
  Inc(NegativeCount);
  X64Reset(Code);
  X64StackPush(Code,xrAX);
  Check(X64Image(Code)=#$50,'немає відновлення після негативу');
end;

procedure MatrixStep(const Assembler:String);
begin
  AllBytes:=AllBytes+X64Image(Code);
  TextAsm.Add('  '+Assembler);
  Inc(MatrixCount);
end;

procedure BuildMatrix;
var Position:SizeInt; Statement:String;
begin
  TextAsm:=TStringList.Create;
  try
    TextAsm.Add('.intel_syntax noprefix');
    TextAsm.Add('.text');
    TextAsm.Add('.global _start');
    TextAsm.Add('_start:');
    AllBytes:='';
    MatrixCount:=0;
    for R:=Low(TX64Reg) to High(TX64Reg) do begin
      if R=xrSP then Continue;
      X64Reset(Code);
      X64StackPush(Code,R);
      MatrixStep('push '+RegName(R));
      X64Reset(Code);
      X64StackPop(Code,R);
      MatrixStep('pop '+RegName(R));
    end;
    for I:=Low(Amounts) to High(Amounts) do begin
      X64Reset(Code);
      X64StackSubtract(Code,Amounts[I]);
      MatrixStep('sub rsp, '+IntToStr(Amounts[I]));
      X64Reset(Code);
      X64StackAdd(Code,Amounts[I]);
      MatrixStep('add rsp, '+IntToStr(Amounts[I]));
    end;
    for R:=Low(TX64Reg) to High(TX64Reg) do begin
      if R=xrSP then Continue;
      for I:=Low(Offsets) to High(Offsets) do begin
        Position:=Offsets[I];
        X64Reset(Code);
        X64StackLoad(Code,R,Position);
        if Position=0 then Statement:='mov '+RegName(R)+', QWORD PTR [rsp]'
        else Statement:='mov '+RegName(R)+', QWORD PTR [rsp+'+
                        IntToStr(Position)+']';
        MatrixStep(Statement);
        X64Reset(Code);
        X64StackStore(Code,R,Position);
        if Position=0 then Statement:='mov QWORD PTR [rsp],'+RegName(R)
        else Statement:='mov QWORD PTR [rsp+'+
                        IntToStr(Position)+'],'+RegName(R);
        MatrixStep(Statement);
      end;
    end;
    Check(MatrixCount=66,'неповна незалежна матриця');
    TextAsm.SaveToFile(OutDir+'/matrix.s');
    SaveBinary(OutDir+'/matrix.fpc.bin',AllBytes);
  finally
    TextAsm.Free;
  end;
end;

procedure PutLE(var Data:RawByteString;Offset:SizeInt;Value:QWord;Count:SizeInt);
var K:SizeInt;
begin
  Check((Offset>=0) and (Count>=1) and (Count<=8) and
        (Offset<=Length(Data)-Count),'ELF поле за межею');
  for K:=0 to Count-1 do begin
    Data[Offset+K+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function D1Physical(Value:Integer):RawByteString;
var Words:TExactWords;
begin
  Check((Value=0) or (Value=1),'не фізичний D1');
  SetLength(Words,1);
  Words[0]:=AnsiChar(Ord('0')+Value);
  Result:=EncodeT5M(Words);
  Check(Length(Result)=1,'D1 T5M не вмістився в один байт');
end;

{ Виконуваний PIE: D1 отриманий ТІЛЬКИ через наявний T5M кодек.
  Той самий фізичний байт зберігається/відновлюється стековими
  MOV/PUSH/POP; Linux sys_write віддає точно один байт у stdout.
  Результат — owned ELF image, незалежний від compiler/law dispatch.
  Питання: 1) Чому машинний результат не precomputed лише у stdout?
  2) Де перевірено ELF geometry? 3) Чому стек вирівнюємо окремо?
  4) Чому RDX після збереження можна використовувати для sys_write? }
procedure BuildELF(Value:Integer);
var Machine:RawByteString; K:SizeInt;
begin
  Physical:=D1Physical(Value);
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Ord(Physical[1]));
  X64StackPush(Code,xrAX);
  X64MovImm32(Code,xrAX,0);
  X64StackPop(Code,xrDX);
  X64StackSubtract(Code,16);
  X64StackStore(Code,xrDX,0);
  X64StackLoad(Code,xrDX,0);
  X64StoreRspDL(Code);
  X64MovImm32(Code,xrAX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovRSIRsp(Code);
  X64MovImm32(Code,xrDX,1);
  X64Syscall(Code);
  X64StackAdd(Code,16);
  X64MovImm32(Code,xrAX,60);
  X64XorEDI(Code);
  X64Syscall(Code);
  Machine:=X64Image(Code);
  SetLength(Image,120+Length(Machine));
  FillChar(Image[1],Length(Image),0);
  PutLE(Image,0,$464C457F,4);PutLE(Image,4,2,1);
  PutLE(Image,5,1,1);PutLE(Image,6,1,1);
  PutLE(Image,16,3,2);PutLE(Image,18,62,2);PutLE(Image,20,1,4);
  PutLE(Image,24,120,8);PutLE(Image,32,64,8);
  PutLE(Image,52,64,2);PutLE(Image,54,56,2);PutLE(Image,56,1,2);
  PutLE(Image,64,1,4);PutLE(Image,68,5,4);
  PutLE(Image,96,Length(Image),8);PutLE(Image,104,Length(Image),8);
  PutLE(Image,112,$1000,8);
  for K:=1 to Length(Machine) do Image[120+K]:=Machine[K];
  VerifySENSELF64(Image,Geometry);
  Check((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Image)),'неправильний PIE ELF');
  SaveBinary(OutDir+'/stack-'+IntToStr(Value)+'.elf',Image);
  SaveBinary(OutDir+'/stack-'+IntToStr(Value)+'.expected.sens',Physical);
end;

{ stdout — позичений POSIX handle, а звіт — owned UTF-8 байти.
  WriteLn у FPC 3.2.2 може транскодувати кирилицю в знаки питання
  навіть за LC_ALL=C.UTF-8; перевіряємо саме фізичний UTF-8.
  Питання: 1) Чому байти краще за codepage-dependent WriteLn?
  2) Хто звільняє THandleStream? 3) Чим звіт відрізняється від D1? }
procedure Report;
var Data:RawByteString; Stream:THandleStream;
begin
  Data:=RawByteString(UTF8Encode(UnicodeString('X64-СТЕК-ГОТОВО matrix=')))+
        RawByteString(IntToStr(MatrixCount))+
        ' golden=5 negative='+RawByteString(IntToStr(NegativeCount))+
        ' recovery=15 elf=2 energy=NOT-MEASURED'+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try
    Stream.WriteBuffer(Data[1],Length(Data));
  finally
    Stream.Free;
  end;
end;

begin
  Check(ParamCount=1,'виклик: test-x64stack <тимчасовий каталог>');
  OutDir:=ParamStr(1);
  Check(DirectoryExists(OutDir),'немає тимчасового каталогу');
  Golden;
  NegativeCount:=0;
  for I:=1 to 20 do Refuse(I);
  BuildMatrix;
  for Bit:=0 to 1 do BuildELF(Bit);
  Report;
end.
