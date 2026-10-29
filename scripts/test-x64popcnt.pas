{ G6.133 — host x86-64 POPCNT r32/r64: GNU as oracle та ELF/T5M.
  Жодне машинне POPCNT саме по собі не визначає закон SENS або Dn.
  TX64Code, TExactWords та ELF — керовані буфери поточного виклику.
  Питання: 1) Навіщо 512 незалежних асемблерних форм?
  2) Чому 0 — законний вхід POPCNT, але не визначений для BSF?
  3) Як фізичний D1 байт відрізняється від ASCII 0 або 1?
  4) Чому застосовуємо CPU-feature gate до реального ELF? }
program test_x64popcnt;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.x64popcnt,
     wsm.t5m,wsm.elfgeometry;
const
  R32:array[0..15] of String=
    ('eax','ecx','edx','ebx','esp','ebp','esi','edi',
     'r8d','r9d','r10d','r11d','r12d','r13d','r14d','r15d');
  R64:array[0..15] of String=
    ('rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi',
     'r8','r9','r10','r11','r12','r13','r14','r15');
var C:TX64Code; Words:TExactWords; Path,Data,Before,Machine:RawByteString;
    Zero,One:AnsiChar; W,D,S,Count,NegativeCount:Integer;
    Failed:Boolean; AssemblyFile:TextFile;

procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('POPCNT-ПРОВАЛ: '+Why);
end;

procedure WriteBytes(const Name:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Name,fmCreate);
  try
    if Length(Bytes)>0 then
      Check(Stream.Write(Bytes[1],Length(Bytes))=Length(Bytes),
        'неповний запис '+Name);
  finally Stream.Free end;
end;

function BitT5M(Bit:Byte):RawByteString;
begin
  SetLength(Words,1);
  if Bit=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Check(Length(Result)=1,'D1 має рівно один фізичний T5M байт');
end;

procedure PutLE(var Buffer:RawByteString;Offset,Count:SizeInt;Value:QWord);
var J:SizeInt;
begin
  Check((Offset>=0) and (Count>0) and (Count<=8) and
        (Offset<=Length(Buffer)-Count),'ELF поле поза межами');
  for J:=0 to Count-1 do begin
    Buffer[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function MakeELF(Width:Integer;Value:QWord):RawByteString;
var Code:TX64Code;Body:RawByteString;Geo:TELFGeometry;J:SizeInt;
    Tmp:QWord;
begin
  X64Reset(Code);
  if Width=32 then
    X64MovImm32(Code,xrAX,LongWord(Value))
  else begin
    Check(Width=64,'неприпустима фізична ширина тесту');
    Code.Bytes:=#$48#$B8; { movabs rax, imm64: приватна host fixture }
    Tmp:=Value;
    for J:=0 to 7 do begin
      Code.Bytes:=Code.Bytes+AnsiChar(Byte(Tmp and $FF));
      Tmp:=Tmp shr 8;
    end;
  end;
  X64PopCount(Code,Width,1,0); { ECX/RCX = POPCNT(EAX/RAX) }
  X64MovImm32(Code,xrAX,1);
  X64ALU32(Code,xaAnd,xrCX,xrAX); { біт парності рахунку }
  X64MovImm32(Code,xrDX,0);
  X64ALU32(Code,xaAdd,xrDX,xrCX);
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
  Body:=X64Image(Code);
  Check((Length(Body)>0) and (Length(Body)<=256),
    'машинний код поза квотою');
  SetLength(Result,120+Length(Body));
  FillChar(Result[1],Length(Result),0);
  PutLE(Result,0,4,$464C457F);
  PutLE(Result,4,1,2);PutLE(Result,5,1,1);PutLE(Result,6,1,1);
  PutLE(Result,16,2,3);PutLE(Result,18,2,62);PutLE(Result,20,4,1);
  PutLE(Result,24,8,120);PutLE(Result,32,8,64);
  PutLE(Result,52,2,64);PutLE(Result,54,2,56);PutLE(Result,56,2,1);
  PutLE(Result,64,4,1);PutLE(Result,68,4,5);
  PutLE(Result,96,8,Length(Result));
  PutLE(Result,104,8,Length(Result));PutLE(Result,112,8,$1000);
  for J:=1 to Length(Body) do Result[120+J]:=Body[J];
  VerifySENSELF64(Result,Geo);
  Check((Geo.Kind=3) and (Geo.MachineBytes=Length(Body)),
    'невалідний ELF64 PIE');
end;

procedure Rejected(const Why:String);
begin
  Check(Failed,'не відхилено '+Why);
  Check(X64Image(C)=Before,'часткова мутація '+Why);
  Inc(NegativeCount);
end;

begin
  Check(ParamCount=1,'потрібна приватна тека');
  Path:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Path),'відсутня тека');
  Data:=BitT5M(0);Zero:=Data[1];
  Data:=BitT5M(1);One:=Data[1];
  Check((Ord(Zero)=$50) and (Ord(One)=$A1),
    'потрібна канонічна T5M D1 фізика');
  Count:=0;NegativeCount:=0;
  X64Reset(C);
  X64PopCount(C,32,0,3);
  Check(X64Image(C)=#$F3#$0F#$B8#$C3,'golden popcnt eax,ebx');
  Inc(Count);
  X64Reset(C);
  X64PopCount(C,32,8,9);
  Check(X64Image(C)=#$F3#$45#$0F#$B8#$C1,'golden popcnt r8d,r9d');
  Inc(Count);
  X64Reset(C);
  X64PopCount(C,64,15,8);
  Check(X64Image(C)=#$F3#$4D#$0F#$B8#$F8,'golden popcnt r15,r8');
  Inc(Count);

  X64Reset(C);C.Bytes:=#$90;Before:=X64Image(C);Failed:=False;
  try X64PopCount(C,16,0,1)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('ширина 16');
  Failed:=False;
  try X64PopCount(C,32,-1,1)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('destination -1');
  Failed:=False;
  try X64PopCount(C,64,0,16)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('source 16');
  Failed:=False;
  try X64PopCount(C,64,16,0)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('destination 16');

  C.Bytes:=StringOfChar(#$90,253);Before:=X64Image(C);Failed:=False;
  try X64PopCount(C,32,0,1) { +4 >256 }
  except on E:EX64CodeError do Failed:=True end;
  Rejected('квота 253+4');
  C.Bytes:=StringOfChar(#$90,252);
  X64PopCount(C,32,0,1);
  Check(Length(X64Image(C))=256,'край 252+4');
  C.Bytes:=StringOfChar(#$90,252);Before:=X64Image(C);Failed:=False;
  try X64PopCount(C,64,8,9) { +5 >256 }
  except on E:EX64CodeError do Failed:=True end;
  Rejected('квота 252+5');
  C.Bytes:=StringOfChar(#$90,251);
  X64PopCount(C,64,8,9);
  Check(Length(X64Image(C))=256,'край 251+5');
  X64Reset(C);
  X64PopCount(C,32,0,0);
  Check(X64Image(C)=#$F3#$0F#$B8#$C0,'відновлення після негативів');

  AssignFile(AssemblyFile,Path+'matrix.s');Rewrite(AssemblyFile);
  try
    WriteLn(AssemblyFile,'.intel_syntax noprefix');
    WriteLn(AssemblyFile,'.text');
    Data:='';
    for W:=0 to 1 do
      for D:=0 to 15 do
        for S:=0 to 15 do begin
          X64Reset(C);
          if W=0 then begin
            X64PopCount(C,32,D,S);
            WriteLn(AssemblyFile,'popcnt ',R32[D],', ',R32[S]);
          end else begin
            X64PopCount(C,64,D,S);
            WriteLn(AssemblyFile,'popcnt ',R64[D],', ',R64[S]);
          end;
          Data:=Data+X64Image(C);
        end;
    Check(Length(Data)>=512*4,'занадто коротка машинна матриця');
    WriteBytes(Path+'matrix.fpc.bin',Data);
  finally CloseFile(AssemblyFile) end;

  Machine:=MakeELF(32,0); { POPCNT(0)=0, визначений ISA результат }
  WriteBytes(Path+'zero.elf',Machine);
  WriteBytes(Path+'zero.sens',BitT5M(0));
  Machine:=MakeELF(32,$B0); { POPCNT(0xB0)=3 -> D1:1 }
  WriteBytes(Path+'three.elf',Machine);
  WriteBytes(Path+'three.sens',BitT5M(1));
  Machine:=MakeELF(64,(QWord(1) shl 63) or QWord($A0)); { high bit+2 =3 }
  WriteBytes(Path+'high.elf',Machine);
  WriteBytes(Path+'high.sens',BitT5M(1));
  Check((Count=3) and (NegativeCount=6),'лічильники');
  WriteLn('POPCNT-ГОТОВО golden=3 negative=6 gnu=512 elf=3');
end.
