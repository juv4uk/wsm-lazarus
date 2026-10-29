{ G6.97 — машинні golden, негативи, GNU reference і справжні ELF.
  Фізичний D1/T5M тут лише транспорт вихідного біта CPU; не
  тлумачити SHL/SAR/ROL як мовні закони SENS. }
program test_x64shift;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64shift,wsm.x64alu,
     wsm.t5m,wsm.elfgeometry;
const
  Ops:array[0..4] of TX64Shift=(xsShl,xsShr,xsSar,xsRol,xsRor);
  Counts:array[0..2] of Byte=(3,7,31);
  Values:array[0..4] of LongWord=(1,3,$80000000,$80000000,1);
  RunCounts:array[0..4] of Byte=(2,1,31,1,1);
  ExpectedBits:array[0..4] of Byte=(0,1,1,1,0);
var
  C:TX64Code;
  O,R,K,M,Good,Bad:Integer;
  Failed:Boolean;
  Old,Path,Data,Image:RawByteString;
  Zero,One:AnsiChar;
  Words:TExactWords;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('X64-ЗСУВ-ПРОВАЛ: '+Why);
end;

procedure WriteBytes(const FileName:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(FileName,fmCreate);
  try
    if Length(Bytes)>0 then
      Check(Stream.Write(Bytes[1],Length(Bytes))=Length(Bytes),
            'неповний файловий запис');
  finally Stream.Free end;
end;

procedure Golden(Op:TX64Shift;Reg:TX64Reg;Count:Integer;
                 const Reference:RawByteString);
begin
  X64Reset(C);
  if Count<0 then X64ShiftCL32(C,Op,Reg)
  else X64ShiftImm32(C,Op,Reg,Count);
  Check(X64Image(C)=Reference,'точна host opcode/ModRM golden');
  Inc(Good);
end;

procedure Negative(const Why:String);
begin
  Check(Failed,'не відхилено '+Why);
  Check(X64Image(C)=Old,'пошкоджено байти після відмови '+Why);
  Inc(Bad);
end;

function BitT5M(Bit:Byte):RawByteString;
begin
  SetLength(Words,1);
  if Bit=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Check(Length(Result)=1,'D1 W1 має фізично один байт');
end;

procedure PutLE(var Target:RawByteString;Offset,Count:SizeInt;V:QWord);
var J:SizeInt;
begin
  Check((Offset>=0) and (Count>0) and (Count<=8) and
        (Offset<=Length(Target)-Count),'ELF поле поза образом');
  for J:=0 to Count-1 do begin
    Target[Offset+J+1]:=AnsiChar(Byte(V and $FF));
    V:=V shr 8;
  end;
end;

function BuildMachineELF(Op:TX64Shift;Value:LongWord;
                         Count:Byte;UseCL:Boolean):RawByteString;
var Code:TX64Code; Machine:RawByteString; G:TELFGeometry; J:SizeInt;
begin
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Value);
  if UseCL then begin
    X64MovImm32(Code,xrCX,Count);
    X64ShiftCL32(Code,Op,xrAX);
  end else X64ShiftImm32(Code,Op,xrAX,Count);
  X64MovImm32(Code,xrCX,1);
  X64ALU32(Code,xaAnd,xrAX,xrCX);
  { Host bit0 -> фізичний W1: використовуємо саме pinned EncodeT5M.
    Немає компіляції мовної операції SENS або готового результату. }
  X64MovImm32(Code,xrDX,0);
  X64ALU32(Code,xaAdd,xrDX,xrAX);
  X64ImulEDX8(Code,Ord(One)-Ord(Zero));
  X64AddEDX8(Code,Ord(Zero));
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
  Check((Length(Machine)>0) and (Length(Machine)<=256),'host-квота');
  SetLength(Result,120+Length(Machine));
  FillChar(Result[1],Length(Result),0);
  PutLE(Result,0,4,$464C457F);
  PutLE(Result,4,1,2); PutLE(Result,5,1,1); PutLE(Result,6,1,1);
  PutLE(Result,16,2,3); PutLE(Result,18,2,62); PutLE(Result,20,4,1);
  PutLE(Result,24,8,120); PutLE(Result,32,8,64);
  PutLE(Result,52,2,64); PutLE(Result,54,2,56);
  PutLE(Result,56,2,1);
  PutLE(Result,64,4,1); PutLE(Result,68,4,5);
  PutLE(Result,96,8,Length(Result));
  PutLE(Result,104,8,Length(Result)); PutLE(Result,112,8,$1000);
  for J:=1 to Length(Machine) do Result[120+J]:=Machine[J];
  VerifySENSELF64(Result,G);
  Check((G.Kind=3) and (G.MachineBytes=Length(Machine)),
        'непридатний x86-64 ET_DYN PIE');
end;

begin
  Check(ParamCount=1,'потрібна приватна тека');
  Path:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Path),'тимчасову теку не створено');
  Data:=BitT5M(0); Zero:=Data[1];
  Data:=BitT5M(1); One:=Data[1];
  Check((Ord(Zero)=$50) and (Ord(One)=$A1),
        'несподівана canonical T5M таблиця W1');
  Good:=0;Bad:=0;

  Golden(xsShl,xrAX,3,#$C1#$E0#$03);
  Golden(xsShr,xrBX,7,#$C1#$EB#$07);
  Golden(xsSar,xrDX,31,#$C1#$FA#$1F);
  Golden(xsRol,xrDI,3,#$C1#$C7#$03);
  Golden(xsRor,xrCX,7,#$C1#$C9#$07);
  Golden(xsShl,xrAX,-1,#$D3#$E0);
  Golden(xsSar,xrBX,-1,#$D3#$FB);
  Golden(xsRor,xrDI,-1,#$D3#$CF);

  X64Reset(C);C.Bytes:=#$90;
  Old:=X64Image(C);Failed:=False;
  try X64ShiftImm32(C,xsShl,xrAX,32)
  except on E:Exception do Failed:=True end;
  Negative('imm32 замість imm5');
  Failed:=False;
  try X64ShiftImm32(C,xsShl,TX64Reg(8),3)
  except on E:Exception do Failed:=True end;
  Negative('невідомий r32');
  Failed:=False;
  try X64ShiftCL32(C,TX64Shift(255),xrAX)
  except on E:Exception do Failed:=True end;
  Negative('невідомий shift opcode');

  C.Bytes:=StringOfChar(#$90,254);
  Old:=X64Image(C);Failed:=False;
  try X64ShiftImm32(C,xsSar,xrDX,31)
  except on E:Exception do Failed:=True end;
  Negative('квота imm8');
  C.Bytes:=StringOfChar(#$90,255);
  Old:=X64Image(C);Failed:=False;
  try X64ShiftCL32(C,xsSar,xrDX)
  except on E:Exception do Failed:=True end;
  Negative('квота CL');
  X64Reset(C);
  X64ShiftImm32(C,xsRol,xrAX,3);
  Check(X64Image(C)=#$C1#$C0#$03,'відновлення після відмов');

  { GNU as/objcopy є незалежним oracle лише машинного КОДУ x86-64. }
  for O:=0 to 4 do
    for R:=0 to 7 do begin
      for K:=0 to 2 do begin
        X64Reset(C);
        X64ShiftImm32(C,Ops[O],TX64Reg(R),Counts[K]);
        Data:=X64Image(C);
        Check(Length(Data)=3,'immediate x86 bytes');
        WriteBytes(Path+'imm-'+IntToStr(O)+'-'+IntToStr(R)+'-'+
                   IntToStr(Counts[K])+'.bin',Data);
      end;
      X64Reset(C);
      X64ShiftCL32(C,Ops[O],TX64Reg(R));
      Data:=X64Image(C);
      Check(Length(Data)=2,'CL x86 bytes');
      WriteBytes(Path+'cl-'+IntToStr(O)+'-'+IntToStr(R)+'.bin',Data);
    end;

  for O:=0 to 4 do for M:=0 to 1 do begin
    Image:=BuildMachineELF(Ops[O],Values[O],RunCounts[O],M=1);
    WriteBytes(Path+'elf-'+IntToStr(O)+'-'+IntToStr(M)+'.elf',Image);
    WriteBytes(Path+'elf-'+IntToStr(O)+'-'+IntToStr(M)+'.sens',
               BitT5M(ExpectedBits[O]));
  end;
  Check((Good=8) and (Bad=5),'лічильники golden і негативів');
  WriteLn('X64-ЗСУВ-ГОТОВО golden=8 negative=5 recovery=1 as=160 elf=10');
end.
