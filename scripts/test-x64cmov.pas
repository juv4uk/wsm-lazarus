{ G6.113 — FPC механічний доказ: усі 1024 host CMOVcc
  кодування, 4 негативи й чотири реально виконувані ELF64.
  Усі 1024 байтові послідовності окремо звіряє GNU as/objcopy.
  Фізичний T5M D1 результат створює чинний wsm.t5m.
  Вхід: приватний каталог; вихід: еталон .s/.bin і чотири
  ELF64 та відповідні packed .sens, не SENS semantic authority.
  Запитання: 1) Навіщо потрібен незалежний GNU as?
  2) Як відрізнити порівняння FLAGS від SENS COND?
  3) Чому до компіляції довільного SENS ще далеко?
  4) Чому реальне виконання ELF перевіряємо через cmp? }
program test_x64cmov;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.x64cmov,
     wsm.t5m,wsm.elfgeometry;
const
  Mnemonics:array[0..15] of String=
    ('o','no','b','ae','e','ne','be','a',
     's','ns','p','np','l','ge','le','g');
  RegNames:array[0..7] of String=
    ('eax','ecx','edx','ebx','esp','ebp','esi','edi');
var
  C:TX64Code;
  Directory:String;
  Lines:TStringList;
  Count,NegativeCount,Cond,D,S,A,B,I:Integer;
  Bytes,Before,ZeroByte,OneByte,Expected,ELF:RawByteString;
  Answers:TExactWords;
  Geometry:TELFGeometry;
  Failed:Boolean;
procedure Need(Good:Boolean;const Why:String);
begin
  if not Good then raise Exception.Create('X64-CMOV-ПРОВАЛ: '+Why);
end;
procedure Save(const Path:String;const Value:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Value)>0 then F.WriteBuffer(Value[1],Length(Value))
  finally F.Free end;
end;
procedure PutLE(var Buffer:RawByteString; Offset:SizeInt;
                Value:QWord; Count:SizeInt);
var J:SizeInt;
begin
  for J:=0 to Count-1 do begin
    Buffer[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function MakeELF64(const Machine:RawByteString):RawByteString;
const Header=120; Base:QWord=$400000;
var J,N:SizeInt;
begin
  N:=Header+Length(Machine);
  SetLength(Result,N);
  for J:=1 to N do Result[J]:=#0;
  PutLE(Result,0,$464C457F,4);
  PutLE(Result,4,2,1); PutLE(Result,5,1,1); PutLE(Result,6,1,1);
  PutLE(Result,16,2,2); PutLE(Result,18,62,2); PutLE(Result,20,1,4);
  PutLE(Result,24,Base+Header,8); PutLE(Result,32,64,8);
  PutLE(Result,52,64,2); PutLE(Result,54,56,2); PutLE(Result,56,1,2);
  PutLE(Result,64,1,4); PutLE(Result,68,5,4);
  PutLE(Result,80,Base,8); PutLE(Result,88,Base,8);
  PutLE(Result,96,N,8); PutLE(Result,104,N,8);
  PutLE(Result,112,$1000,8);
  for J:=1 to Length(Machine) do Result[Header+J]:=Machine[J];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.MachineBytes=Length(Machine)) and
       (Geometry.Kind=2),'ELF64 геометрія');
end;
procedure Reject(const Reason:String; WasRejected:Boolean);
begin
  Need(WasRejected,'не відхилено '+Reason);
  Need(X64Image(C)=Before,'зіпсовано старі байти: '+Reason);
  Inc(NegativeCount);
end;
procedure MatrixTests;
begin
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');
    Count:=0;
    Bytes:='';
    for Cond:=0 to 15 do
      for D:=0 to 7 do
        for S:=0 to 7 do begin
          X64Reset(C);
          X64CMov32(C,Cond,TX64Reg(D),TX64Reg(S));
          Need(Length(X64Image(C))=3,'CMOV має займати 3 байти');
          Need(X64Image(C)=(#$0F+
            AnsiChar($40+Cond)+AnsiChar($C0 or (D shl 3) or S)),
            'CMOV golden ModRM '+IntToStr(Cond)+'/'+
            IntToStr(D)+'/'+IntToStr(S));
          Bytes:=Bytes+X64Image(C);
          Lines.Add('  cmov'+Mnemonics[Cond]+' '+
                    RegNames[D]+', '+RegNames[S]);
          Inc(Count);
        end;
    Need((Count=1024) and (Length(Bytes)=3072),
         '16 умов × 8 × 8 матриця');
    Lines.SaveToFile(Directory+'/cmov-reference.s');
    Save(Directory+'/cmov-fpc.bin',Bytes);
  finally Lines.Free end;
end;
procedure NegativeTests;
begin
  NegativeCount:=0;
  X64Reset(C);
  X64MovImm32(C,xrAX,17);
  Before:=X64Image(C);
  Failed:=False;
  try X64CMov32(C,-1,xrAX,xrCX)
  except on E:EX64CodeError do Failed:=True end;
  Reject('умова -1',Failed);
  Failed:=False;
  try X64CMov32(C,16,xrAX,xrCX)
  except on E:EX64CodeError do Failed:=True end;
  Reject('умова 16',Failed);
  X64Reset(C);
  for I:=1 to 51 do X64MovImm32(C,xrAX,0);
  Need(Length(C.Bytes)=255,'host quota setup');
  Before:=X64Image(C);
  Failed:=False;
  try X64CMov32(C,4,xrAX,xrCX)
  except on E:EX64CodeError do Failed:=True end;
  Reject('квота 255 + 3',Failed);
  X64Reset(C);
  C.Bytes:=StringOfChar('x',257);
  Before:=X64Image(C);
  Failed:=False;
  try X64CMov32(C,4,xrAX,xrCX)
  except on E:EX64CodeError do Failed:=True end;
  Reject('пошкоджений oversized buffer',Failed);
  Need(NegativeCount=4,'кількість відмов');
end;
procedure ExecutableTests;
var Suffix:String;
begin
  SetLength(Answers,1);
  Answers[0]:='0'; ZeroByte:=EncodeT5M(Answers);
  Answers[0]:='1'; OneByte:=EncodeT5M(Answers);
  Need((Length(ZeroByte)=1) and (Length(OneByte)=1) and
       (ZeroByte<>OneByte),'два різні фізичні D1 T5M');
  for A:=0 to 1 do
    for B:=0 to 1 do begin
      Suffix:=IntToStr(A)+IntToStr(B);
      X64Reset(C);
      X64MovImm32(C,xrAX,A);
      X64MovImm32(C,xrCX,B);
      X64MovImm32(C,xrDX,Ord(ZeroByte[1]));
      X64MovImm32(C,xrBX,Ord(OneByte[1]));
      X64ALU32(C,xaCmp,xrAX,xrCX);
      X64CMov32(C,4,xrDX,xrBX); { CMOVE після CMP }
      X64SubRsp8(C,16);
      X64StoreRspDL(C);
      X64MovImm32(C,xrAX,1); { Linux write(fd=1, rsp, 1) }
      X64MovImm32(C,xrDI,1);
      X64MovRSIRsp(C);
      X64MovImm32(C,xrDX,1);
      X64Syscall(C);
      X64MovImm32(C,xrAX,60); { Linux exit(0) }
      X64XorEDI(C);
      X64Syscall(C);
      ELF:=MakeELF64(X64Image(C));
      Save(Directory+'/case-'+Suffix+'.elf',ELF);
      if A=B then Expected:=OneByte else Expected:=ZeroByte;
      Save(Directory+'/case-'+Suffix+'.expected.sens',Expected);
    end;
end;
begin
  Need(ParamCount=1,'потрібен приватний каталог');
  Directory:=ParamStr(1);
  Need(DirectoryExists(Directory),'каталогу не існує');
  MatrixTests;
  NegativeTests;
  ExecutableTests;
  WriteLn('X64-CMOV-OK cases=',Count,' negative=',NegativeCount,
          ' elf=4 energy=NOT-MEASURED');
end.
