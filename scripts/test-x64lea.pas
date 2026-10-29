{ Механічний тест host LEA: байти проти незалежного GNU as,
  реальні виконувані ELF64 та двійкова D1 відповідь із pinned T5M.
  Не є тестом нової семантики SENS. 
  Питання: 1) Чому oracle тут GNU as, а не мова SENS?
  2) Навіщо перевірка ELF геометрії?
  3) Чому D1 отримано з EncodeT5M, а не з константи?
  4) Як виявити неатомарне переповнення?
  5) Чому LEA не є доведенням готового compiler? }
program TestX64Lea;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64lea,wsm.t5m,wsm.elfgeometry;
type TDisps=array[0..2] of SizeInt;
const DispValues:TDisps=(-128,0,127);
      Scales:array[0..3] of SizeInt=(1,2,4,8);
var Dir:String; Code:TX64Code;
    AsmText:TStringList; AllBytes:RawByteString; D,B,I:TX64Reg;
    ScaleIndex,DispIndex,MatrixCount,NegativeCount,Bit:Integer;
    Image,Physical:RawByteString; Geometry:TELFGeometry;

procedure Check(Condition:Boolean;const Message:String);
begin
  if not Condition then raise Exception.Create(Message);
end;

function RegisterName(Reg:TX64Reg):String;
begin
  case Reg of
    xrAX:Result:='rax'; xrCX:Result:='rcx'; xrDX:Result:='rdx';
    xrBX:Result:='rbx'; xrSP:Result:='rsp'; xrBP:Result:='rbp';
    xrSI:Result:='rsi'; xrDI:Result:='rdi';
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

procedure CheckGolden;
begin
  X64Reset(Code);
  X64LeaIndexed(Code,xrDX,xrAX,xrCX,4,-8);
  Check(X64Image(Code)=#$48#$8D#$54#$88#$F8,'golden LEA indexed disp8');
  X64Reset(Code);
  X64LeaIndexed(Code,xrAX,xrBP,xrCX,1,0);
  Check(X64Image(Code)=#$48#$8D#$44#$0D#$00,'golden RBP forced disp8');
  X64Reset(Code);
  X64LeaIndexed(Code,xrDI,xrSP,xrDI,8,127);
  Check(X64Image(Code)=#$48#$8D#$7C#$FC#$7F,'golden RSP base SIB');
  X64Reset(Code);
  X64LeaIndexed(Code,xrAX,xrAX,xrAX,1,0);
  Check(X64Image(Code)=#$48#$8D#$04#$00,'golden zero displacement');
end;

procedure Reject(Dest,Base,Index:TX64Reg;Scale,Disp:SizeInt);
var Previous:RawByteString; Failed:Boolean;
begin
  X64Reset(Code);
  Code.Bytes:=#$AA#$BB#$CC;
  Previous:=Code.Bytes;
  Failed:=False;
  try
    X64LeaIndexed(Code,Dest,Base,Index,Scale,Disp);
  except
    on E:EX64CodeError do Failed:=True;
  end;
  Check(Failed,'очікували відмову для host LEA');
  Check(Code.Bytes=Previous,'відмова пошкодила машинний буфер');
  Inc(NegativeCount);
end;

procedure CheckNegative;
var Previous:RawByteString; Failed:Boolean; InvalidReg:Byte;
begin
  NegativeCount:=0;
  Reject(xrAX,xrAX,xrSP,1,0);
  Reject(xrAX,xrAX,xrCX,0,0);
  Reject(xrAX,xrAX,xrCX,3,0);
  Reject(xrAX,xrAX,xrCX,16,0);
  Reject(xrAX,xrAX,xrCX,1,-129);
  Reject(xrAX,xrAX,xrCX,1,128);
  InvalidReg:=8;
  Reject(TX64Reg(InvalidReg),xrAX,xrCX,1,0);
  Reject(xrAX,TX64Reg(InvalidReg),xrCX,1,0);
  Reject(xrAX,xrAX,TX64Reg(InvalidReg),1,0);
  X64Reset(Code);
  Code.Bytes:=StringOfChar(AnsiChar($90),253);
  Previous:=Code.Bytes; Failed:=False;
  try
    X64LeaIndexed(Code,xrAX,xrAX,xrCX,1,0);
  except
    on E:EX64CodeError do Failed:=True;
  end;
  Check(Failed and (Code.Bytes=Previous),'quota failure must be atomic');
  Inc(NegativeCount);
  X64Reset(Code);
  X64LeaIndexed(Code,xrDX,xrAX,xrCX,4,-8);
  Check(X64Image(Code)=#$48#$8D#$54#$88#$F8,'відновлення після відмови');
end;

procedure BuildAssemblerMatrix;
var Statement:String; Disp:SizeInt;
begin
  AsmText:=TStringList.Create;
  try
    AsmText.Add('.intel_syntax noprefix');
    AsmText.Add('.text');
    AsmText.Add('.global _start');
    AsmText.Add('_start:');
    AllBytes:=''; MatrixCount:=0;
    for D:=Low(TX64Reg) to High(TX64Reg) do
      for B:=Low(TX64Reg) to High(TX64Reg) do
        for I:=Low(TX64Reg) to High(TX64Reg) do begin
          if I=xrSP then Continue;
          for ScaleIndex:=Low(Scales) to High(Scales) do
            for DispIndex:=Low(DispValues) to High(DispValues) do begin
              Disp:=DispValues[DispIndex];
              X64Reset(Code);
              X64LeaIndexed(Code,D,B,I,Scales[ScaleIndex],Disp);
              AllBytes:=AllBytes+X64Image(Code);
              Statement:='  lea '+RegisterName(D)+', ['+RegisterName(B)+
                  '+'+RegisterName(I)+'*'+IntToStr(Scales[ScaleIndex]);
              if Disp>=0 then Statement:=Statement+'+'+IntToStr(Disp)
              else Statement:=Statement+IntToStr(Disp);
              Statement:=Statement+']';
              AsmText.Add(Statement);
              Inc(MatrixCount);
            end;
        end;
    Check(MatrixCount=5376,'неповна матриця LEA/SIB');
    AsmText.SaveToFile(Dir+'/matrix.s');
    SaveBinary(Dir+'/matrix.fpc.bin',AllBytes);
  finally
    AsmText.Free;
  end;
end;

procedure PutLE(var Data:RawByteString;Offset:SizeInt;Value:QWord;Count:SizeInt);
var K:SizeInt;
begin
  Check((Offset>=0) and (Offset+Count<=Length(Data)) and
    (Count>=1) and (Count<=8),'ELF поле за межею');
  for K:=0 to Count-1 do begin
    Data[Offset+K+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function PhysicalD1(Value:AnsiChar):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1);
  Words[0]:=Value;
  Result:=EncodeT5M(Words);
  Check(Length(Result)=1,'D1 фізичний T5M не є одним байтом');
end;

procedure BuildELF(Value:Integer);
var Writer:TX64Code; Machine:RawByteString; K:SizeInt;
begin
  Physical:=PhysicalD1(AnsiChar(Ord('0')+Value));
  X64Reset(Writer);
  X64MovImm32(Writer,xrAX,Ord(Physical[1]));
  X64MovImm32(Writer,xrCX,2);
  { LEA реально утворює байт D1: RAX + RCX*4 - 8 = RAX. }
  X64LeaIndexed(Writer,xrDX,xrAX,xrCX,4,-8);
  X64SubRsp8(Writer,8);
  X64StoreRspDL(Writer);
  X64MovImm32(Writer,xrAX,1);
  X64MovImm32(Writer,xrDI,1);
  X64MovRSIRsp(Writer);
  X64MovImm32(Writer,xrDX,1);
  X64Syscall(Writer);
  X64MovImm32(Writer,xrAX,60);
  X64XorEDI(Writer);
  X64Syscall(Writer);
  Machine:=X64Image(Writer);
  SetLength(Image,120+Length(Machine));
  FillChar(Image[1],Length(Image),0);
  PutLE(Image,0,$464C457F,4); PutLE(Image,4,2,1);
  PutLE(Image,5,1,1); PutLE(Image,6,1,1);
  PutLE(Image,16,3,2); PutLE(Image,18,62,2); PutLE(Image,20,1,4);
  PutLE(Image,24,120,8); PutLE(Image,32,64,8);
  PutLE(Image,52,64,2); PutLE(Image,54,56,2); PutLE(Image,56,1,2);
  PutLE(Image,64,1,4); PutLE(Image,68,5,4);
  PutLE(Image,96,Length(Image),8);
  PutLE(Image,104,Length(Image),8); PutLE(Image,112,$1000,8);
  for K:=1 to Length(Machine) do Image[120+K]:=Machine[K];
  VerifySENSELF64(Image,Geometry);
  Check((Geometry.Kind=3) and (Geometry.Entry=120) and
    (Geometry.FileBytes=Length(Image)),'неправильний PIE ELF');
  SaveBinary(Dir+'/lea-'+IntToStr(Value)+'.elf',Image);
  SaveBinary(Dir+'/lea-'+IntToStr(Value)+'.expected.sens',Physical);
end;

begin
  Check(ParamCount=1,'виклик: test-x64lea <тимчасовий каталог>');
  Dir:=ParamStr(1);
  Check(DirectoryExists(Dir),'немає тимчасового каталогу');
  CheckGolden;
  CheckNegative;
  BuildAssemblerMatrix;
  for Bit:=0 to 1 do BuildELF(Bit);
  WriteLn('X64-LEA-ГОТОВО matrix=',MatrixCount,' golden=4 negative=',
          NegativeCount,' recovery=1 elf=2 energy=NOT-MEASURED');
end.
