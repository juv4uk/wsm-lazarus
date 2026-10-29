{ G6.92 — незалежні машинні golden/негативи та реальні ELF64.
  Фізичні W1 лише свідки T5M, а XOR є host CPU тестом, не SENS
  оператором. Після створення ELF має запрацювати справжній Linux
  x86-64 kernel; машинний вихід звіряє зовнішній shell test. }
program test_x64alu;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.t5m,wsm.elfgeometry;
var C:TX64Code; A,B:Integer; Failed:Boolean; Z:Byte;
    Old,Image,Folder:RawByteString; Good,Bad:Integer;
    Zero,One:AnsiChar; Words:TExactWords; G:TELFGeometry;

procedure Check(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('X64-ALU-ПРОВАЛ: '+Why);
end;

function T5MBit(Bit:Integer):AnsiChar;
var Bytes:RawByteString;
begin
  SetLength(Words,1);
  if Bit=0 then Words[0]:='0' else Words[0]:='1';
  Bytes:=EncodeT5M(Words);
  Check(Length(Bytes)=1,'W1 має бути рівно один T5M байт');
  Result:=Bytes[1];
end;

procedure Golden(Op:TX64ALU;Dst,Src:TX64Reg;
                 const Expected:RawByteString);
begin
  X64Reset(C);
  X64ALU32(C,Op,Dst,Src);
  Check(X64Image(C)=Expected,'точні opcode/ModRM');
  Inc(Good);
end;

procedure PutWord(var Target:RawByteString;Offset,Count:SizeInt;V:QWord);
var K:SizeInt;
begin
  Check((Offset>=0) and (Count>0) and (Count<=8) and
        (Offset<=Length(Target)-Count),'ELF поле виходить за образ');
  for K:=0 to Count-1 do begin
    Target[Offset+K+1]:=AnsiChar(Byte(V and $FF));
    V:=V shr 8;
  end;
end;

function BuildXorELF(Left,Right:Byte):RawByteString;
var Code:TX64Code; Machine:RawByteString; K:SizeInt;
begin
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Left);
  X64MovImm32(Code,xrCX,Right);
  X64ALU32(Code,xaXor,xrAX,xrCX);
  X64MovImm32(Code,xrDX,Ord(Zero));
  X64ALU32(Code,xaAdd,xrDX,xrAX);
  X64SubRsp8(Code,8);
  X64StoreRspQword(Code,xrDX,0);
  X64MovImm32(Code,xrAX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovRSIRsp(Code);
  X64MovImm32(Code,xrDX,1);
  X64Syscall(Code);
  X64MovImm32(Code,xrAX,60);
  X64XorEDI(Code);
  X64Syscall(Code);
  Machine:=X64Image(Code);
  Check(Length(Machine)<256,'машинний код за межами квоти');
  SetLength(Result,120+Length(Machine));
  FillChar(Result[1],Length(Result),0);
  PutWord(Result,0,4,$464C457F);
  PutWord(Result,4,1,2);PutWord(Result,5,1,1);PutWord(Result,6,1,1);
  PutWord(Result,16,2,3);PutWord(Result,18,2,62);PutWord(Result,20,4,1);
  PutWord(Result,24,8,120);PutWord(Result,32,8,64);
  PutWord(Result,52,2,64);PutWord(Result,54,2,56);PutWord(Result,56,2,1);
  PutWord(Result,64,4,1);PutWord(Result,68,4,5);
  PutWord(Result,96,8,Length(Result));PutWord(Result,104,8,Length(Result));
  PutWord(Result,112,8,$1000);
  for K:=1 to Length(Machine) do Result[120+K]:=Machine[K];
  VerifySENSELF64(Result,G);
  Check((G.Kind=3) and (G.FileBytes=Length(Result)),
        'некоректний власний PIE ELF64');
end;

procedure WriteBytes(const Path:String;const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then
      Check(S.Write(Data[1],Length(Data))=Length(Data),'неповний запис');
  finally S.Free end;
end;

procedure Negative(const Why:String);
begin
  Check(Failed,'не відхилено '+Why);
  Check(X64Image(C)=Old,'пошкоджено код після відмови '+Why);
  Inc(Bad);
end;

begin
  Check(ParamCount=1,'потрібна приватна тека вихідних ELF');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Folder),'немає тимчасової теки');
  Good:=0;Bad:=0;
  Zero:=T5MBit(0);One:=T5MBit(1);
  Check((Ord(Zero)=$50) and (Ord(One)=$51),
        'несподіване фізичне T5M W1 у pinned codec');

  Golden(xaAdd,xrAX,xrCX,#$01#$C8);
  Golden(xaSub,xrAX,xrCX,#$29#$C8);
  Golden(xaXor,xrAX,xrCX,#$31#$C8);
  Golden(xaAnd,xrAX,xrCX,#$21#$C8);
  Golden(xaCmp,xrAX,xrCX,#$39#$C8);
  Golden(xaImul,xrAX,xrCX,#$0F#$AF#$C1);
  Golden(xaAdd,xrDI,xrBX,#$01#$DF);
  Golden(xaImul,xrDI,xrBX,#$0F#$AF#$FB);

  X64Reset(C);C.Bytes:=StringOfChar(#$90,254);
  X64ALU32(C,xaAdd,xrAX,xrCX);
  Check(Length(C.Bytes)=256,'рівна квоті довжина');
  Old:=X64Image(C);Failed:=False;
  try X64ALU32(C,xaAdd,xrAX,xrCX)
  except on E:Exception do Failed:=True end;
  Negative('перевищення квоти');
  X64Reset(C);C.Bytes:=#$90;Old:=X64Image(C);
  Z:=255;Failed:=False;
  try X64ALU32(C,TX64ALU(Z),xrAX,xrCX)
  except on E:Exception do Failed:=True end;
  Negative('невідомий opcode');
  Z:=8;Failed:=False;
  try X64ALU32(C,xaAdd,TX64Reg(Z),xrCX)
  except on E:Exception do Failed:=True end;
  Negative('невідомий регістр');
  X64Reset(C);
  X64ALU32(C,xaXor,xrDX,xrAX);
  Check(X64Image(C)=#$31#$C2,'відновлення після відмов');
  for A:=0 to 1 do for B:=0 to 1 do begin
    Image:=BuildXorELF(A,B);
    WriteBytes(Folder+'xor-'+IntToStr(A)+'-'+IntToStr(B)+'.elf',Image);
    WriteBytes(Folder+'xor-'+IntToStr(A)+'-'+IntToStr(B)+'.expected.sens',
               AnsiChar(Ord(Zero)+(A xor B)));
  end;
  Check((Good=8) and (Bad=3),'лічильники golden/negative');
  WriteLn('X64-ALU-ГОТОВО golden=8 negative=3 recovery=1 elf=4');
end.
