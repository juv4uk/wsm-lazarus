{ G6.241 — R8..R15 stack STORE/LOAD: GNU as matrix + real ELF64.
  Only host mechanics. Physical D1 byte is encoded by the existing
  canonical T5M codec, never inferred from a text projection.
  1) Why is GNU as an independent byte oracle for x86-64?
  2) Who owns [rsp] between SUB and ADD?
  3) Why is a completed sys_write required for successful native output?
  4) Why is this not a complete SENS compiler? }
program test_x64widestack;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64widestack,wsm.x64code,wsm.x64rex,
     wsm.x64stack,wsm.t5m,wsm.elfgeometry,wsm.elfwriteguard;
const HeaderBytes=120;
var Dir:String; C:TX64Code; Lines:TStringList;
    Pos,Neg,I,J,B:LongInt;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('ШИРОКИЙ-СТЕК-ПОМИЛКА: '+Why) end;
procedure Save(const Filename:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Filename,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
function RegName(N:LongInt):String;
begin Result:='r'+IntToStr(N) end;
function MemName(D:LongInt):String;
begin
  if D=0 then Result:='[rsp]'
  else Result:='[rsp+'+IntToStr(D)+']';
end;
procedure Matrix;
var P,Combined:RawByteString;R:TX64WideReg;
begin
  Combined:='';Pos:=0;
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');Lines.Add('.global _start');Lines.Add('_start:');
    for I:=8 to 15 do begin
      R:=TX64WideReg(I);
      for J:=0 to 15 do begin
        X64Reset(C);
        X64WideStackStore(C,R,J*8);
        P:=X64Image(C);
        Need((Length(P)=4+Ord(J<>0)) and
             (Byte(P[1])=$4C) and (Byte(P[2])=$89),
             'MOV STORE bytes');
        Combined:=Combined+P;Inc(Pos);
        Lines.Add(' mov QWORD PTR '+MemName(J*8)+','+RegName(I));
        X64Reset(C);
        X64WideStackLoad(C,R,J*8);
        P:=X64Image(C);
        Need((Length(P)=4+Ord(J<>0)) and
             (Byte(P[1])=$4C) and (Byte(P[2])=$8B),
             'MOV LOAD bytes');
        Combined:=Combined+P;Inc(Pos);
        Lines.Add(' mov '+RegName(I)+',QWORD PTR '+MemName(J*8));
      end;
    end;
    Need(Pos=256,'missing matrix entries');
    Lines.SaveToFile(Dir+'/wide-matrix.s');
    Save('wide-matrix.fpc.bin',Combined);
  finally Lines.Free end;
end;

procedure Reject(Reg:TX64WideReg;Offset:SizeInt;Store:Boolean);
var Old,OldFix:RawByteString; Failed:Boolean;
begin
  X64Reset(C);
  C.Bytes:='ABCD';C.PatchedRIP:='P';
  Old:=C.Bytes;OldFix:=C.PatchedRIP;
  Failed:=False;
  try
    if Store then X64WideStackStore(C,Reg,Offset)
    else X64WideStackLoad(C,Reg,Offset)
  except on E:EX64CodeError do Failed:=True end;
  Need(Failed and (C.Bytes=Old) and (C.PatchedRIP=OldFix),
       'invalid wide stack instruction changed code');
  Inc(Neg);
end;
procedure RejectQuota(Store:Boolean);
var Old,OldFix:RawByteString;Failed:Boolean;
begin
  X64Reset(C);SetLength(C.Bytes,253);
  C.PatchedRIP:='R';Old:=C.Bytes;OldFix:=C.PatchedRIP;
  Failed:=False;
  try
    if Store then X64WideStackStore(C,wrR8,0)
    else X64WideStackLoad(C,wrR8,0)
  except on E:EX64CodeError do Failed:=True end;
  Need(Failed and (C.Bytes=Old) and (C.PatchedRIP=OldFix),
       'quota was not atomic');
  Inc(Neg);
end;
procedure Negatives;
var Store:Boolean;N:LongInt;
begin
  Neg:=0;
  for N:=0 to 1 do begin
    Store:=N=0;
    Reject(wrAX,0,Store);
    Reject(wrDI,0,Store);
    Reject(wrSP,0,Store);
    Reject(wrR8,-8,Store);
    Reject(wrR8,7,Store);
    Reject(wrR8,121,Store);
    Reject(wrR15,128,Store);
    RejectQuota(Store);
  end;
  Need(Neg=16,'negative matrix incomplete');
  X64Reset(C);
  X64WideStackStore(C,wrR15,120);
  X64WideStackLoad(C,wrR8,0);
  Need(Length(C.Bytes)=9,'failed to recover after errors');
end;
function PhysicalD1(Value:LongInt):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);
  if Value=0 then W[0]:='0' else W[0]:='1';
  Result:=EncodeT5M(W);
  Need(Length(Result)=1,'canonical D1 is not one packed T5M byte');
end;
procedure PutLE(var S:RawByteString;At:SizeInt;Value:QWord;Count:LongInt);
var K:LongInt;
begin
  Need((At>=0) and (Count>0) and (Count<=8) and
       (At<=Length(S)-Count),'ELF field bounds');
  for K:=0 to Count-1 do begin
    S[At+K+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
procedure MakeELF(Bit:LongInt);
var Expected,Machine,Image:RawByteString;
    G:TELFGeometry;K:LongInt;RawValue:QWord;
begin
  Expected:=PhysicalD1(Bit);
  RawValue:=QWord(Byte(Expected[1]));
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');Lines.Add('.global _start');Lines.Add('_start:');
    X64Reset(C);
    X64StackSubtract(C,16);Lines.Add(' sub rsp,16');
    X64RexMovAbs(C,wrR8,RawValue);
    Lines.Add(' movabs r8,0x'+IntToHex(RawValue,16));
    X64WideStackStore(C,wrR8,0);Lines.Add(' mov QWORD PTR [rsp],r8');
    X64RexMovAbs(C,wrR8,0);Lines.Add(' movabs r8,0');
    X64WideStackLoad(C,wrR8,0);Lines.Add(' mov r8,QWORD PTR [rsp]');
    X64RexReg64(C,roMove,wrAX,wrR8);Lines.Add(' mov rax,r8');
    X64StackAdd(C,16);Lines.Add(' add rsp,16');
    X64SubRsp8(C,8);Lines.Add(' sub rsp,8');
    X64StoreRspQword(C,xrAX,0);Lines.Add(' mov QWORD PTR [rsp],rax');
    X64MovImm32(C,xrAX,1);Lines.Add(' mov eax,1');
    X64MovImm32(C,xrDI,1);Lines.Add(' mov edi,1');
    X64MovRSIRsp(C);Lines.Add(' mov rsi,rsp');
    X64MovImm32(C,xrDX,1);Lines.Add(' mov edx,1');
    X64Syscall(C);Lines.Add(' syscall');
    X64MovImm32(C,xrAX,60);Lines.Add(' mov eax,60');
    X64XorEDI(C);Lines.Add(' xor edi,edi');
    X64Syscall(C);Lines.Add(' syscall');
    Machine:=X64Image(C);
    Need((Length(Machine)>50) and (Length(Machine)<256),
         'machine code length outside bounds');
    Lines.SaveToFile(Dir+'/wide-'+IntToStr(Bit)+'.s');
    Save('wide-'+IntToStr(Bit)+'.fpc.bin',Machine);
  finally Lines.Free end;
  SetLength(Image,HeaderBytes+Length(Machine));
  FillChar(Image[1],Length(Image),0);
  PutLE(Image,0,$464C457F,4);
  PutLE(Image,4,2,1);PutLE(Image,5,1,1);PutLE(Image,6,1,1);
  PutLE(Image,16,3,2);PutLE(Image,18,62,2);PutLE(Image,20,1,4);
  PutLE(Image,24,120,8);PutLE(Image,32,64,8);
  PutLE(Image,52,64,2);PutLE(Image,54,56,2);PutLE(Image,56,1,2);
  PutLE(Image,64,1,4);PutLE(Image,68,5,4);
  PutLE(Image,96,Length(Image),8);PutLE(Image,104,Length(Image),8);
  PutLE(Image,112,$1000,8);
  for K:=1 to Length(Machine) do Image[HeaderBytes+K]:=Machine[K];
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.FileBytes=Length(Image)),'invalid PIE geometry');
  Image:=RequireCompleteNativeWrite(Image);
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.FileBytes=Length(Image)) and
       (Length(Image)=HeaderBytes+Length(Machine)+11),
       'invalid checked-write ELF');
  Save('wide-'+IntToStr(Bit)+'.elf',Image);
  Save('wide-'+IntToStr(Bit)+'.expected.sens',Expected);
end;
begin
  Need(ParamCount=1,'private test directory required');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'test directory absent');
  Matrix;
  Negatives;
  for B:=0 to 1 do MakeELF(B);
  WriteLn('G6.241-WIDESTACK-OK matrix=256 negative=16 elf=2');
end.
