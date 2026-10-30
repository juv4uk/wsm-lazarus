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
     wsm.x64stack,wsm.t5m,wsm.elfgeometry,wsm.elfwriteguard,
     wsm.x64pie;
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
{ G6.244: перевірений ELF64 контейнер приймає ТІЛЬКИ machine bytes,
  а не ширини Dn або назви з D7. Створюється один власний RawByteString.
  Перевіряємо короткий/максимальний машинний код і відмову >256 байтів.
  Питання: 1) Чому 1 byte RET є допустимим ELF, але не доказом SENS?
  2) Чому вхідний TX64Code не змінюється при overflow?
  3) Де саме виклик VerifySENSELF64 відсікає зламану геометрію?
  4) Чому два фактичні T5M ELF нижче потрібні понад структурний тест? }
procedure VerifyPIEBounds;
var Candidate,Original,OriginalRIP:RawByteString;
    G:TELFGeometry;Failed:Boolean;Len,K:LongInt;
begin
  X64Reset(C);Failed:=False;
  try Candidate:=BuildX64PIE(C)
  except on E:EX64PIEError do Failed:=True end;
  Need(Failed and (Length(C.Bytes)=0),'PIE accepted empty machine');
  for K:=1 to 2 do begin
    if K=1 then Len:=257 else Len:=1024;
    X64Reset(C);SetLength(C.Bytes,Len);
    FillChar(C.Bytes[1],Len,$90);
    C.PatchedRIP:='X';
    Original:=C.Bytes;OriginalRIP:=C.PatchedRIP;
    Failed:=False;
    try Candidate:=BuildX64PIE(C)
    except on E:EX64PIEError do Failed:=True end;
    Need(Failed and (C.Bytes=Original) and
         (C.PatchedRIP=OriginalRIP),
         'PIE quota invalidated borrowed machine bytes');
  end;
  X64Reset(C);C.Bytes:=#$C3;
  Original:=C.Bytes;
  Candidate:=BuildX64PIE(C);
  VerifySENSELF64(Candidate,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Candidate)) and
       (G.MachineBytes=1) and (Length(Candidate)=121) and
       (Candidate[121]=#$C3) and (C.Bytes=Original),
       'one byte PIE geometry / machine roundtrip');
  X64Reset(C);SetLength(C.Bytes,256);
  FillChar(C.Bytes[1],256,$90);
  C.PatchedRIP:='P';
  Original:=C.Bytes;OriginalRIP:=C.PatchedRIP;
  Candidate:=BuildX64PIE(C);
  VerifySENSELF64(Candidate,G);
  Need((G.Kind=3) and (G.MachineBytes=256) and
       (Length(Candidate)=376) and
       (Copy(Candidate,121,256)=Original) and
       (C.Bytes=Original) and (C.PatchedRIP=OriginalRIP),
       '256 byte PIE lost exact machine bytes');
  WriteLn('G6.244-X64PIE-OK positive=2 negative=3 code-bytes=1,256');
end;

procedure MakeELF(Bit:LongInt);
var Expected,Machine,Image:RawByteString;
    G:TELFGeometry;RawValue:QWord;
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
  { Спільний host builder зберігає всі байти від перевіреного
    R8 STORE/LOAD до машинного sys_write; pinned T5M не зачіпаємо. }
  Image:=BuildX64PIE(C);
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.FileBytes=Length(Image)) and
       (G.MachineBytes=Length(Machine)) and
       (Copy(Image,HeaderBytes+1,Length(Machine))=Machine),
       'shared PIE did not preserve native machine code');
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
  VerifyPIEBounds;
  for B:=0 to 1 do MakeELF(B);
  WriteLn('G6.241-WIDESTACK-OK matrix=256 negative=16 elf=2');
end.
