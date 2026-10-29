{ G6 BSF/BSR: exact host bytes, machine ELF і pinned D1/T5M transport.
  Це не власні SENS функції; machine positives використовують ненульовий
  вхід, бо BSF/BSR на нулі мають невизначений destination.
  TX64Code і TExactWords — managed, ELF-бінарник належить caller.
  Питання: 1) Навіщо GNU as як незалежний byte oracle?
  2) Чому stdout порівнюється як packed T5M, не ASCII?
  3) Який негатив охороняє незмінність машинних байтів?
  4) Чому ELF з BSF ще не доводить Dn-компіляцію? }
program test_x64bitscan;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64bitscan,wsm.x64alu,
     wsm.t5m,wsm.elfgeometry;
const
  RegisterNames:array[0..7] of String=
    ('eax','ecx','edx','ebx','esp','ebp','esi','edi');
  InstructionNames:array[0..1] of String=('bsf','bsr');
var
  C:TX64Code; Words:TExactWords; Before,Data,Path,Machine:RawByteString;
  Zero,One:AnsiChar; Op,D,S,Good,Bad:Integer; Failed:Boolean;
  AssemblyFile:TextFile;

procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('BSF-BSR-ПРОВАЛ: '+Why);
end;

procedure WriteBytes(const FileName:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(FileName,fmCreate);
  try
    if Length(Bytes)>0 then
      Check(Stream.Write(Bytes[1],Length(Bytes))=Length(Bytes),
            'неповний запис '+FileName);
  finally Stream.Free end;
end;

function BitT5M(Bit:Byte):RawByteString;
begin
  SetLength(Words,1);
  if Bit=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Check(Length(Result)=1,'D1 W1 має один фізичний байт');
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

function MakeELF(Operation:TX64BitScan;Value:LongWord):RawByteString;
var Code:TX64Code; Body:RawByteString; Geo:TELFGeometry; J:SizeInt;
begin
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Value);
  X64BitScan32(Code,Operation,xrCX,xrAX); { ECX = index, Value <> 0 }
  X64MovImm32(Code,xrAX,1);
  X64ALU32(Code,xaAnd,xrCX,xrAX);        { physical output bit index&1 }
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
  Check((Length(Body)>0) and (Length(Body)<=256),'машинна квота');
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
        'невалідний ET_DYN x86-64 PIE');
end;

procedure Negative(const Why:String);
begin
  Check(Failed,'не відхилено '+Why);
  Check(X64Image(C)=Before,'мутація коду після відмови '+Why);
  Inc(Bad);
end;

begin
  Check(ParamCount=1,'потрібна приватна тека');
  Path:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Path),'немає тимчасової теки');
  Data:=BitT5M(0);Zero:=Data[1];
  Data:=BitT5M(1);One:=Data[1];
  Check((Ord(Zero)=$50) and (Ord(One)=$A1),
        'pinned canonical T5M W1 змінився');
  Good:=0;Bad:=0;
  X64Reset(C);
  X64BitScan32(C,xbFirstSet,xrAX,xrBX);
  Check(X64Image(C)=#$0F#$BC#$C3,'BSF eax,ebx golden');
  Inc(Good);
  X64Reset(C);
  X64BitScan32(C,xbLastSet,xrDX,xrCX);
  Check(X64Image(C)=#$0F#$BD#$D1,'BSR edx,ecx golden');
  Inc(Good);

  X64Reset(C);C.Bytes:=#$90;Before:=X64Image(C);Failed:=False;
  try X64BitScan32(C,xbFirstSet,TX64Reg(8),xrAX)
  except on E:EX64CodeError do Failed:=True end;
  Negative('destination');
  Failed:=False;
  try X64BitScan32(C,xbLastSet,xrAX,TX64Reg(8))
  except on E:EX64CodeError do Failed:=True end;
  Negative('source');
  Failed:=False;
  try X64BitScan32(C,TX64BitScan(255),xrAX,xrBX)
  except on E:EX64CodeError do Failed:=True end;
  Negative('opcode');

  C.Bytes:=StringOfChar(#$90,254);Before:=X64Image(C);Failed:=False;
  try X64BitScan32(C,xbFirstSet,xrAX,xrBX)
  except on E:EX64CodeError do Failed:=True end;
  Negative('квота 254+3');
  C.Bytes:=StringOfChar(#$90,253);
  X64BitScan32(C,xbFirstSet,xrAX,xrBX);
  Check(Length(X64Image(C))=256,'граничний буфер 253+3');
  X64Reset(C);
  X64BitScan32(C,xbLastSet,xrAX,xrAX);
  Check(X64Image(C)=#$0F#$BD#$C0,'відновлення після відмов');

  AssignFile(AssemblyFile,Path+'matrix.s');Rewrite(AssemblyFile);
  try
    WriteLn(AssemblyFile,'.intel_syntax noprefix');
    WriteLn(AssemblyFile,'.text');
    Data:='';
    for Op:=0 to 1 do
      for D:=0 to 7 do
        for S:=0 to 7 do begin
          X64Reset(C);
          if Op=0 then
            X64BitScan32(C,xbFirstSet,TX64Reg(D),TX64Reg(S))
          else
            X64BitScan32(C,xbLastSet,TX64Reg(D),TX64Reg(S));
          Data:=Data+X64Image(C);
          WriteLn(AssemblyFile,InstructionNames[Op]+' '+
            RegisterNames[D]+', '+RegisterNames[S]);
        end;
    Check(Length(Data)=128*3,'128 машинних інструкцій');
    WriteBytes(Path+'matrix.fpc.bin',Data);
  finally CloseFile(AssemblyFile) end;

  { Зіставлення з pinned фізичними W1 виконує зовнішній bash cmp,
    а тут очікування зібране незалежним EncodeT5M, без ASCII. }
  Machine:=MakeELF(xbFirstSet,$08); { BSF(8) = 3 → bit1 }
  WriteBytes(Path+'first.elf',Machine);
  WriteBytes(Path+'first.sens',BitT5M(1));
  Machine:=MakeELF(xbLastSet,$10); { BSR(16) = 4 → bit0 }
  WriteBytes(Path+'last.elf',Machine);
  WriteBytes(Path+'last.sens',BitT5M(0));
  Check((Good=2) and (Bad=4),'лічильники');
  WriteLn('BSF-BSR-ГОТОВО golden=2 negative=4 quota=256 recovery=1 gnu=128 elf=2');
end.
