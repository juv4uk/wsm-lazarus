{ FPC oracle host REX: 832 незалежних байтових вектори проти GNU as.
  Два machine ELF повертають один canonical T5M W1 байт, одержаний
  через чинний wsm.t5m. Тут немає Pascal-виконання законів SENS.
  Типи: enum TX64WideReg лише для host x86, QWord immediate 64 біти.
  Ownership: TStrings/файли/RawByteString звільняються до завершення.
  Запитання: 1) Чому GNU as є незалежним oracle машинних байтів?
  2) Чому джерело T5M не можна замінити магічним literal?
  3) Як перевіряємо, що ELF реально виконує R8/R9?
  4) Чому signed immediate тут не є SENS D12?
  5) Який negative тест доводить, що Code.Bytes не змінився? }
program TestX64Rex;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64rex,wsm.t5m,wsm.elfgeometry;
const ImmediateValues:array[0..3] of QWord=
  (0,1,$0123456789ABCDEF,High(QWord));
var OutputDir:String; C:TX64Code; Source,Target:TX64WideReg;
    Op:TX64RexOperation; VI,Count,NegativeCount,B:Integer;
    Assembly:TStringList; Combined,Physical,Image:RawByteString;
    Geometry:TELFGeometry;
procedure Guard(Valid:Boolean;const Description:String);
begin
  if not Valid then raise Exception.Create('REX-ПРОВАЛ: '+Description);
end;
function RegName(R:TX64WideReg):String;
begin
  case R of
    wrAX:Result:='rax'; wrCX:Result:='rcx'; wrDX:Result:='rdx';
    wrBX:Result:='rbx'; wrSP:Result:='rsp'; wrBP:Result:='rbp';
    wrSI:Result:='rsi'; wrDI:Result:='rdi'; wrR8:Result:='r8';
    wrR9:Result:='r9'; wrR10:Result:='r10'; wrR11:Result:='r11';
    wrR12:Result:='r12'; wrR13:Result:='r13'; wrR14:Result:='r14';
    wrR15:Result:='r15';
  end;
end;
function OperationName(O:TX64RexOperation):String;
begin
  case O of
    roMove:Result:='mov'; roAdd:Result:='add'; roXor:Result:='xor';
  end;
end;
procedure SaveBytes(const Path:String;const Bytes:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then
      Guard(S.Write(Bytes[1],Length(Bytes))=Length(Bytes),
            'неповний запис у тимчасовий файл');
  finally
    S.Free;
  end;
end;
procedure GoldenCheck;
begin
  X64Reset(C);
  X64RexMovAbs(C,wrR8,$0123456789ABCDEF);
  Guard(X64Image(C)=#$49#$B8#$EF#$CD#$AB#$89#$67#$45#$23#$01,
        'MOVABS R8 exact immediate');
  X64Reset(C);X64RexReg64(C,roMove,wrDX,wrR8);
  Guard(X64Image(C)=#$4C#$89#$C2,'MOV RDX,R8');
  X64Reset(C);X64RexReg64(C,roAdd,wrR8,wrR9);
  Guard(X64Image(C)=#$4D#$01#$C8,'ADD R8,R9');
  X64Reset(C);X64RexReg64(C,roXor,wrR15,wrR15);
  Guard(X64Image(C)=#$4D#$31#$FF,'XOR R15,R15');
end;
procedure RejectReg(Operation:TX64RexOperation;Dest,Src:TX64WideReg);
var Old:RawByteString; Failed:Boolean;
begin
  X64Reset(C);C.Bytes:=#$90#$90;
  Old:=X64Image(C);Failed:=False;
  try
    X64RexReg64(C,Operation,Dest,Src);
  except on E:Exception do Failed:=True end;
  Guard(Failed and (C.Bytes=Old),'негатив регістра/операції неатомарний');
  Inc(NegativeCount);
end;
procedure RejectAbs(Reg:TX64WideReg);
var Old:RawByteString; Failed:Boolean;
begin
  X64Reset(C);C.Bytes:=#$90#$90;
  Old:=X64Image(C);Failed:=False;
  try X64RexMovAbs(C,Reg,0)
  except on E:Exception do Failed:=True end;
  Guard(Failed and (C.Bytes=Old),'негатив MOVABS неатомарний');
  Inc(NegativeCount);
end;
procedure NegativeChecks;
var InvalidReg:Byte;InvalidOp:Byte; Old:RawByteString;Failed:Boolean;
begin
  NegativeCount:=0;
  InvalidReg:=16;InvalidOp:=3;
  RejectReg(roMove,TX64WideReg(InvalidReg),wrAX);
  RejectReg(roAdd,wrAX,TX64WideReg(InvalidReg));
  RejectReg(roXor,TX64WideReg(InvalidReg),wrR15);
  RejectReg(TX64RexOperation(InvalidOp),wrAX,wrCX);
  RejectAbs(TX64WideReg(InvalidReg));
  X64Reset(C);C.Bytes:=StringOfChar(#$90,254);
  Old:=C.Bytes;Failed:=False;
  try X64RexReg64(C,roMove,wrAX,wrR8)
  except on E:EX64CodeError do Failed:=True end;
  Guard(Failed and (C.Bytes=Old),'quota reg+3 failed atomicity');
  Inc(NegativeCount);
  X64Reset(C);C.Bytes:=StringOfChar(#$90,247);
  Old:=C.Bytes;Failed:=False;
  try X64RexMovAbs(C,wrR15,1)
  except on E:EX64CodeError do Failed:=True end;
  Guard(Failed and (C.Bytes=Old),'quota movabs+10 failed atomicity');
  Inc(NegativeCount);
  X64Reset(C);C.Bytes:=StringOfChar(#$90,253);
  X64RexReg64(C,roMove,wrR15,wrR8);
  Guard(Length(C.Bytes)=256,'точна квота 256');
  Inc(NegativeCount);
  X64Reset(C);C.Bytes:=StringOfChar(#$90,246);
  X64RexMovAbs(C,wrR15,1);
  Guard(Length(C.Bytes)=256,'точна MOVABS квота 256');
  Inc(NegativeCount);
  X64Reset(C);
  X64RexReg64(C,roAdd,wrR15,wrR8);
  Guard(C.Bytes=#$4D#$01#$C7,'recovery після негативів');
end;
procedure AssembleMatrix;
var TextLine:String;
begin
  Assembly:=TStringList.Create;
  try
    Assembly.Add('.intel_syntax noprefix');
    Assembly.Add('.text');
    Assembly.Add('.global _start');
    Assembly.Add('_start:');
    Combined:='';Count:=0;
    for Op:=Low(TX64RexOperation) to High(TX64RexOperation) do
      for Target:=Low(TX64WideReg) to High(TX64WideReg) do
        for Source:=Low(TX64WideReg) to High(TX64WideReg) do begin
          X64Reset(C);X64RexReg64(C,Op,Target,Source);
          Combined:=Combined+X64Image(C);
          TextLine:='  '+OperationName(Op)+' '+RegName(Target)+','+RegName(Source);
          Assembly.Add(TextLine);
          Inc(Count);
        end;
    for Target:=Low(TX64WideReg) to High(TX64WideReg) do
      for VI:=Low(ImmediateValues) to High(ImmediateValues) do begin
        X64Reset(C);X64RexMovAbs(C,Target,ImmediateValues[VI]);
        Combined:=Combined+X64Image(C);
        Assembly.Add('  movabs '+RegName(Target)+',0x'+
                     IntToHex(ImmediateValues[VI],16));
        Inc(Count);
      end;
    Guard(Count=832,'неповна матриця 832 машинних інструкцій');
    Guard(Length(Combined)=2944,'неочікувана довжина machine matrix');
    Assembly.SaveToFile(OutputDir+'/matrix.s');
    SaveBytes(OutputDir+'/matrix.fpc.bin',Combined);
  finally
    Assembly.Free;
  end;
end;
procedure PutLE(var Bytes:RawByteString;Offset:SizeInt;Value:QWord;LengthBytes:SizeInt);
var J:SizeInt;
begin
  Guard((Offset>=0) and (LengthBytes>=1) and (LengthBytes<=8) and
      (Offset<=Length(Bytes)-LengthBytes),'ELF поле за межами');
  for J:=0 to LengthBytes-1 do begin
    Bytes[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function PhysicalBit(Value:Integer):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1);
  if Value=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Guard(Length(Result)=1,'W1 має один фізичний T5M byte');
end;
procedure MachineELF(Value:Integer);
var Writer:TX64Code; Raw:RawByteString;J:SizeInt;
begin
  Physical:=PhysicalBit(Value);
  X64Reset(Writer);
  X64RexMovAbs(Writer,wrR8,Ord(Physical[1]));
  X64RexMovAbs(Writer,wrR9,1);
  X64RexReg64(Writer,roXor,wrR9,wrR9);
  X64RexReg64(Writer,roAdd,wrR8,wrR9);
  X64RexReg64(Writer,roMove,wrDX,wrR8);
  X64SubRsp8(Writer,8);
  X64StoreRspQword(Writer,xrDX,0);
  X64MovImm32(Writer,xrAX,1);
  X64MovImm32(Writer,xrDI,1);
  X64MovRSIRsp(Writer);
  X64MovImm32(Writer,xrDX,1);
  X64Syscall(Writer);
  X64MovImm32(Writer,xrAX,60);
  X64XorEDI(Writer);
  X64Syscall(Writer);
  Raw:=X64Image(Writer);
  SetLength(Image,120+Length(Raw));
  FillChar(Image[1],Length(Image),0);
  PutLE(Image,0,$464C457F,4);PutLE(Image,4,2,1);
  PutLE(Image,5,1,1);PutLE(Image,6,1,1);
  PutLE(Image,16,3,2);PutLE(Image,18,62,2);PutLE(Image,20,1,4);
  PutLE(Image,24,120,8);PutLE(Image,32,64,8);
  PutLE(Image,52,64,2);PutLE(Image,54,56,2);PutLE(Image,56,1,2);
  PutLE(Image,64,1,4);PutLE(Image,68,5,4);
  PutLE(Image,96,Length(Image),8);PutLE(Image,104,Length(Image),8);
  PutLE(Image,112,$1000,8);
  for J:=1 to Length(Raw) do Image[120+J]:=Raw[J];
  VerifySENSELF64(Image,Geometry);
  Guard((Geometry.Kind=3) and (Geometry.Entry=120) and
        (Geometry.FileBytes=Length(Image)),'ELF64 PIE геометрія');
  SaveBytes(OutputDir+'/rex-'+IntToStr(Value)+'.elf',Image);
  SaveBytes(OutputDir+'/rex-'+IntToStr(Value)+'.expected.sens',Physical);
end;
begin
  Guard(ParamCount=1,'потрібна тимчасова тека');
  OutputDir:=ParamStr(1);
  Guard(DirectoryExists(OutputDir),'немає тимчасової теки');
  GoldenCheck;
  NegativeChecks;
  AssembleMatrix;
  for B:=0 to 1 do MachineELF(B);
  WriteLn('X64-REX-OK matrix=',Count,' golden=4 negative=',NegativeCount,
          ' recovery=1 elf=2 energy=NOT-MEASURED');
end.
