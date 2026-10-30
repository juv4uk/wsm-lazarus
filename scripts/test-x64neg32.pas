{ G6.257 — справжній host NEG r32, незалежний GNU-as та 3 фізичні ELF64.
  Code.Bytes, PatchedRIP — керовані поля, власник тестовий виклик.
  Вхід трьох ELF: константа host r32 і очікуване host r32; через
  NEG/CMP/SETE отримуємо біт, а його фізичний W1 формує pinned T5M.
  Жодна координата D12+, D7 чи функція SENS цим не визначається.
  Питання: 1) Чому NEG(1) = FFFFFFFF лише в host r32?
  2) Чому перевірка 3 ELF потрібна понад незалежні opcode GNU as?
  3) Чому очікувані W1 беруться з EncodeT5M, а не ASCII '0'/'1'?
  4) Як повний sys_write виявляє закритий fd1 і /dev/full?
  5) Як відмови гарантують недоторканість Bytes та PatchedRIP? }
program test_x64neg32;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.x64neg32,
     wsm.x64pie,wsm.elfgeometry,wsm.t5m;
const RegName:array[0..7] of String=
  ('eax','ecx','edx','ebx','esp','ebp','esi','edi');
var
  TargetDir:String;
  PhysicalZero,PhysicalOne:RawByteString;
  BaseByte,Delta:LongInt;
  NegativeCount,ELFCount:LongInt;

procedure Need(Good:Boolean;const Reason:String);
begin
  if not Good then raise Exception.Create('NEG32-ПОМИЛКА: '+Reason);
end;

function ExactWords(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(TargetDir+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure ExpectFailure(var Code:TX64Code;Reg:TX64Reg;const LabelText:String);
var BeforeBytes,BeforeRIP:RawByteString;Thrown:Boolean;
begin
  BeforeBytes:=Copy(Code.Bytes,1,Length(Code.Bytes));
  BeforeRIP:=Copy(Code.PatchedRIP,1,Length(Code.PatchedRIP));
  Thrown:=False;
  try X64Neg32(Code,Reg);
  except on E:EX64CodeError do begin
    Thrown:=True;
    Need(E.Message<>'',LabelText+': немає діагностики');
  end end;
  Need(Thrown and (Code.Bytes=BeforeBytes) and
       (Code.PatchedRIP=BeforeRIP),LabelText+': часткова зміна коду');
  Inc(NegativeCount);
end;

procedure CheckMachineMatrix;
var C:TX64Code;I:LongInt;All:RawByteString;Invalid:TX64Reg;
    OutputFile:TextFile;
begin
  All:='';
  for I:=0 to 7 do begin
    X64Reset(C);
    X64Neg32(C,TX64Reg(I));
    Need((Length(C.Bytes)=2) and (C.PatchedRIP=''),
         'не два байти NEG: '+IntToStr(I));
    All:=All+C.Bytes;
  end;
  Need(Length(All)=16,'матриця 8 NEG має 16 байтів');
  Save('matrix.bin',All);
  AssignFile(OutputFile,TargetDir+'/matrix.s');
  Rewrite(OutputFile);
  try
    WriteLn(OutputFile,'.intel_syntax noprefix');
    WriteLn(OutputFile,'.text');
    for I:=0 to 7 do WriteLn(OutputFile,'  neg ',RegName[I]);
  finally CloseFile(OutputFile) end;

  X64Reset(C);
  X64Neg32(C,xrAX);
  Need(C.Bytes=#$F7#$D8,'golden NEG EAX');
  X64Reset(C);
  X64Neg32(C,xrDI);
  Need(C.Bytes=#$F7#$DF,'golden NEG EDI');

  NegativeCount:=0;
  X64Reset(C);C.Bytes:='KEEP';C.PatchedRIP:=#$2A;
  {$R-}
  Invalid:=TX64Reg(8);
  {$R+}
  ExpectFailure(C,Invalid,'регістр 8');
  {$R-}
  Invalid:=TX64Reg(255);
  {$R+}
  ExpectFailure(C,Invalid,'регістр 255');
  X64Reset(C);
  C.Bytes:=RawByteString(StringOfChar('Q',255));
  C.PatchedRIP:=#$33;
  ExpectFailure(C,xrAX,'квота 255+2');
  X64Reset(C);
  C.Bytes:=RawByteString(StringOfChar('Q',256));
  C.PatchedRIP:=#$44;
  ExpectFailure(C,xrAX,'квота 256+2');
  Need(NegativeCount=4,'очікували 4 негативи');

  X64Reset(C);
  C.Bytes:=RawByteString(StringOfChar('Q',254));
  C.PatchedRIP:=#$55;
  X64Neg32(C,xrBX);
  Need((Length(C.Bytes)=256) and (C.PatchedRIP=#$55),
       'припустима межа 254+2');
  X64Reset(C);
  X64Neg32(C,xrAX);
  Need((C.Bytes=#$F7#$D8) and (C.PatchedRIP=''),
       'відновлення після всіх відмов');
end;

procedure CheckRealELF(const Name:String;Input,ExpectedNeg:LongWord;
                       ExpectEqual:Boolean);
var Code:TX64Code;Image,Expected:RawByteString;Geometry:TELFGeometry;
begin
  if ExpectEqual then Expected:=PhysicalOne else Expected:=PhysicalZero;
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Input);
  X64Neg32(Code,xrAX);
  X64MovImm32(Code,xrCX,ExpectedNeg);
  X64ALU32(Code,xaCmp,xrAX,xrCX);
  X64SetEAL(Code);
  X64MovzxEAXAL(Code);
  X64MovImm32(Code,xrDX,0);
  X64ALU32(Code,xaOr,xrDX,xrAX);
  X64ImulEDX8(Code,Delta);
  X64AddEDX8(Code,BaseByte);
  X64SubRsp8(Code,8);
  X64StoreRspDL(Code);
  X64LeaRSIRsp(Code);
  X64MovImm32(Code,xrDX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovImm32(Code,xrAX,1);
  X64Syscall(Code);
  { Повний одно-байтовий запис stdout; Linux write без повтору для W1. }
  X64MovImm32(Code,xrCX,1);
  X64ALU32(Code,xaCmp,xrAX,xrCX);
  X64SetEAL(Code);
  X64MovzxEAXAL(Code);
  X64MovImm32(Code,xrDI,1);
  X64ALU32(Code,xaSub,xrDI,xrAX);
  X64MovImm32(Code,xrAX,60);
  X64Syscall(Code);
  Image:=BuildX64PIE(Code);
  VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.MachineBytes=Length(Code.Bytes)) and
       (Copy(Image,121,Length(Code.Bytes))=Code.Bytes),
       'не збережено фізичні байти ELF64');
  Save(Name+'.elf',Image);
  Save(Name+'.expected.sens',Expected);
  Inc(ELFCount);
end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'NEG32: потрібен приватний каталог');Halt(64);
  end;
  TargetDir:=ParamStr(1);
  Need(DirectoryExists(TargetDir),'не існує каталог');
  PhysicalZero:=EncodeT5M(ExactWords(['0']));
  PhysicalOne:=EncodeT5M(ExactWords(['1']));
  Need((Length(PhysicalZero)=1) and (Length(PhysicalOne)=1),
       'точне W1 має один фізичний байт');
  BaseByte:=Byte(PhysicalZero[1]);
  Delta:=LongInt(Byte(PhysicalOne[1]))-BaseByte;
  Need((BaseByte>=-128) and (BaseByte<=127) and
       (Delta>=-128) and (Delta<=127) and (Delta<>0),
       'фізичний T5M W1 не можна передати через host imm8');
  CheckMachineMatrix;
  ELFCount:=0;
  CheckRealELF('zero',0,0,True);
  CheckRealELF('minus-one',1,$FFFFFFFF,True);
  CheckRealELF('mismatch',1,0,False);
  Need((ELFCount=3) and (NegativeCount=4),'неповна матриця доказів');
  WriteLn('G6.257-X64NEG32-PASS matrix=8 golden=2 negative=4 recovery=1 elf=3');
end.
