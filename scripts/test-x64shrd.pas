{ G6.251 — фізичний машинний свідок SHRD, а не інтерпретатор SENS.
  64 opcode/ModRM перевіряються окремим GNU as. Чотири ELF64 реально
  виконують SHRD і пишуть канонічний W1 T5M з чинного pinned кодека.
  Числа для CPU-тесту є host-стимулами, не D12+ законами.
  Запитання: 1) Який порядок ModRM для SHRD?
  2) Чому SHR 31 повертає саме молодший біт Source?
  3) Хто володіє managed TX64Code, TExactWords і ELF?
  4) Чому чотири W1-відповіді не доводять довільне SENS виконання? }
program test_x64shrd;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64shrd,wsm.x64alu,
     wsm.x64pie,wsm.elfgeometry,wsm.elfwriteguard,wsm.t5m,
     wsm.x64shift;
const
  Names:array[0..7] of String=
    ('eax','ecx','edx','ebx','esp','ebp','esi','edi');
var
  C:TX64Code;
  Dir:String;
  Good,Neg:LongInt;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('SHRD-ПРОВАЛ: '+Why);
end;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+Name,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure Golden(Destination,Source:TX64Reg;Count:Integer;
                 const Expected:RawByteString);
begin
  X64Reset(C);
  X64SHRD32(C,Destination,Source,Count);
  Need(X64Image(C)=Expected,'неправильний точний ModRM або imm8');
  Inc(Good);
end;

procedure Matrix;
var
  I,J,Shift:Integer;
  Bytes:RawByteString;
  Lines:TStringList;
begin
  Bytes:='';
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');
    Lines.Add('.global _start');
    Lines.Add('_start:');
    for I:=0 to 7 do for J:=0 to 7 do begin
      Shift:=1+((I*8+J) mod 31);
      X64Reset(C);
      X64SHRD32(C,TX64Reg(I),TX64Reg(J),Shift);
      Need(Length(C.Bytes)=4,'довжина машинного SHRD не 4 байти');
      Bytes:=Bytes+X64Image(C);
      Lines.Add(' shrd '+Names[I]+','+Names[J]+','+IntToStr(Shift));
    end;
    Need(Length(Bytes)=256,'неповна 64-командна матриця');
    Lines.SaveToFile(Dir+'shrd-matrix.s');
    Save('shrd-matrix.fpc.bin',Bytes);
  finally Lines.Free end;
end;

procedure Reject(Destination,Source:TX64Reg;Count:Integer;
                 Quota:Boolean);
var
  Previous,PreviousRIP:RawByteString;
  Failed:Boolean;
begin
  X64Reset(C);
  if Quota then begin
    SetLength(C.Bytes,253);
    FillChar(C.Bytes[1],253,$90);
  end else C.Bytes:=#$90;
  C.PatchedRIP:='S';
  Previous:=C.Bytes;PreviousRIP:=C.PatchedRIP;
  Failed:=False;
  try
    X64SHRD32(C,Destination,Source,Count);
  except on E:EX64CodeError do Failed:=True end;
  Need(Failed and (C.Bytes=Previous) and
       (C.PatchedRIP=PreviousRIP),
       'некоректний SHRD пошкодив попередній машинний код');
  Inc(Neg);
end;

procedure Negatives;
var BadReg:Byte;
begin
  Neg:=0;
  Reject(xrAX,xrCX,0,False);
  Reject(xrAX,xrCX,-1,False);
  Reject(xrAX,xrCX,32,False);
  Reject(xrAX,xrCX,256,False);
  BadReg:=8;
  Reject(TX64Reg(BadReg),xrCX,1,False);
  BadReg:=255;
  Reject(xrAX,TX64Reg(BadReg),1,False);
  Reject(xrAX,xrCX,1,True);
  Need(Neg=7,'не всі негативи виконано');
  X64Reset(C);
  X64SHRD32(C,xrAX,xrCX,1);
  Need(X64Image(C)=#$0F#$AC#$C8#$01,
       'відновлення після fail-closed відмов');
end;

function PhysicalW1(Bit:Integer):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1);
  if Bit=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Need(Length(Result)=1,'W1 не вмістився в один T5M байт');
end;

procedure BuildMachine(A,B:Integer);
var
  Expect,Image,Zero,One:RawByteString;
  G:TELFGeometry;
  Filename:String;
begin
  X64Reset(C);
  { Два host-стимули A,B у межах 0..1: SHRD(A,B,1) вставляє
    молодший біт B у старший біт результату EAX. Повертаємо його
    host-зсувом SHR EAX,31; це НЕ D12 числовий закон і не D1 dispatch.
    Фізичний W1 формується тільки канонічним pinned T5M кодеком. }
  X64MovImm32(C,xrAX,LongWord(A));
  X64MovImm32(C,xrCX,LongWord(B));
  X64SHRD32(C,xrAX,xrCX,1);
  X64ShiftImm32(C,xsShr,xrAX,31);
  X64MovImm32(C,xrDX,0);
  X64ALU32(C,xaAdd,xrDX,xrAX);
  Zero:=PhysicalW1(0);
  One:=PhysicalW1(1);
  Expect:=PhysicalW1(B);
  Need((Ord(Zero[1])=$50) and (Ord(One[1])=$A1),
       'змінився pinned W1 T5M кодек');
  X64ImulEDX8(C,Ord(One[1])-Ord(Zero[1]));
  X64AddEDX8(C,Ord(Zero[1]));
  X64SubRsp8(C,8);
  X64StoreRspQword(C,xrDX,0);
  X64MovImm32(C,xrAX,1);
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60);
  X64XorEDI(C);
  X64Syscall(C);
  Image:=BuildX64PIE(C);
  Image:=RequireCompleteNativeWrite(Image);
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.FileBytes=Length(Image)) and
       (G.Entry=120),'некоректна ELF64 PIE геометрія');
  Filename:='shrd-'+IntToStr(A)+'-'+IntToStr(B);
  Save(Filename+'.elf',Image);
  Save(Filename+'.expected.sens',Expect);
end;

var A,B:Integer;
begin
  Need(ParamCount=1,'очікується приватний каталог результатів');
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  Need(DirectoryExists(Dir),'каталог результатів відсутній');
  Good:=0;
  Golden(xrAX,xrCX,1,#$0F#$AC#$C8#$01);
  Golden(xrCX,xrAX,31,#$0F#$AC#$C1#$1F);
  Golden(xrSP,xrSP,1,#$0F#$AC#$E4#$01);
  Golden(xrDI,xrSI,31,#$0F#$AC#$F7#$1F);
  Need(Good=4,'не всі позитиви перевірено');
  Matrix;
  Negatives;
  for A:=0 to 1 do for B:=0 to 1 do BuildMachine(A,B);
  WriteLn('G6.251-SHRD-PASS matrix=64 golden=4 negative=7 elf=4 recovery=1');
end.
