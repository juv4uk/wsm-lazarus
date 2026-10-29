{ G6 — незалежна матриця 32 кодів BSWAP і два виконувані ELF64.
  Вхід: приватний тимчасовий каталог; FPC створює reference.s,
  emitted.bin, case-32/64.elf і очікувані 8-байтові файли.
  GNU as/objcopy звіряється зовнішнім shell-скриптом, а не Pascal.
  Буфери RawByteString локальні, файлові потоки закриваються у finally.
  Жоден байт stdout не є SENS-значенням: це тест host ISA.
  Питання: 1) Чим незалежний GNU as від власного encoder?
  2) Чому для R8 потрібен префікс 49 при W=64?
  3) Що доводить вивід ELF64, чого не доводить disassembly?
  4) Чому R32 операція обнуляє старші 32 біти?
  5) Чому ці тести не означають загальну компіляцію SENS? }
program test_x64bswap;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64bswap,wsm.elfgeometry;
const
  Reg32:array[0..15] of String=
    ('eax','ecx','edx','ebx','esp','ebp','esi','edi',
     'r8d','r9d','r10d','r11d','r12d','r13d','r14d','r15d');
  Reg64:array[0..15] of String=
    ('rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi',
     'r8','r9','r10','r11','r12','r13','r14','r15');
var
  C:TX64Code;
  Directory:String;
  Lines:TStringList;
  Count,NegativeCount,R,I,Width:Integer;
  AllBytes,One,Before,Executable:RawByteString;
  Geometry:TELFGeometry;
  WasRejected:Boolean;
procedure Need(Good:Boolean;const Why:String);
begin
  if not Good then raise Exception.Create('X64-BSWAP-ПРОВАЛ: '+Why);
end;
procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally
    F.Free;
  end;
end;
procedure PutLE(var Data:RawByteString;Offset:SizeInt;
                Value:QWord;CountBytes:SizeInt);
var J:SizeInt;
begin
  for J:=0 to CountBytes-1 do begin
    Data[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function MakeELF64(const Machine:RawByteString):RawByteString;
const HeaderSize=120; Base:QWord=$400000;
var J,Size:SizeInt;
begin
  Size:=HeaderSize+Length(Machine);
  SetLength(Result,Size);
  for J:=1 to Size do Result[J]:=#0;
  PutLE(Result,0,$464C457F,4);
  PutLE(Result,4,2,1); PutLE(Result,5,1,1); PutLE(Result,6,1,1);
  PutLE(Result,16,2,2); PutLE(Result,18,62,2); PutLE(Result,20,1,4);
  PutLE(Result,24,Base+HeaderSize,8); PutLE(Result,32,64,8);
  PutLE(Result,52,64,2); PutLE(Result,54,56,2); PutLE(Result,56,1,2);
  PutLE(Result,64,1,4); PutLE(Result,68,5,4);
  PutLE(Result,80,Base,8); PutLE(Result,88,Base,8);
  PutLE(Result,96,Size,8); PutLE(Result,104,Size,8);
  PutLE(Result,112,$1000,8);
  for J:=1 to Length(Machine) do
    Result[HeaderSize+J]:=Machine[J];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=2) and (Geometry.MachineBytes=Length(Machine)),
       'структурна ELF64 геометрія');
end;
procedure MatrixTests;
begin
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');
    Count:=0;
    AllBytes:='';
    for I:=0 to 1 do begin
      if I=0 then Width:=32 else Width:=64;
      for R:=0 to 15 do begin
        X64Reset(C);
        X64BSwap(C,R,Width);
        One:=X64Image(C);
        Need(Length(One)=2+Ord((Width=64) or (R>=8)),
             'довжина '+IntToStr(Width)+'/'+IntToStr(R));
        AllBytes:=AllBytes+One;
        if Width=32 then Lines.Add('  bswap '+Reg32[R])
        else Lines.Add('  bswap '+Reg64[R]);
        Inc(Count);
      end;
    end;
    Need((Count=32) and (Length(AllBytes)=88),
         '32 варіанти, 88 машинних байтів');
    Lines.SaveToFile(Directory+'/bswap-reference.s');
    Save(Directory+'/bswap-fpc.bin',AllBytes);
  finally
    Lines.Free;
  end;
end;
procedure Reject(RegNumber,TargetWidth:Integer;const Why:String);
begin
  Before:=X64Image(C);
  WasRejected:=False;
  try
    X64BSwap(C,RegNumber,TargetWidth);
  except
    on E:EX64CodeError do WasRejected:=True;
  end;
  Need(WasRejected,'негатив не відхилено: '+Why);
  Need(X64Image(C)=Before,'змінено буфер: '+Why);
  Inc(NegativeCount);
end;
procedure NegativeTests;
begin
  NegativeCount:=0;
  X64Reset(C);
  X64MovImm32(C,xrAX,$12345678);
  Reject(-1,32,'регістр -1');
  Reject(16,64,'регістр 16');
  Reject(0,16,'16-бітний BSWAP');
  Reject(8,128,'128-бітний BSWAP');
  C.Bytes:=StringOfChar('z',255);
  Reject(0,32,'255+2');
  C.Bytes:=StringOfChar('z',254);
  Reject(0,64,'254+3');
  C.Bytes:=StringOfChar('z',256);
  Reject(8,32,'256+3');
  C.Bytes:=StringOfChar('z',257);
  Reject(0,32,'пошкоджений буфер 257');
  Need(NegativeCount=8,'кількість негативів');
  C.Bytes:=StringOfChar('z',254);
  X64BSwap(C,0,32);
  Need(Length(C.Bytes)=256,'дозволена точна квота');
  Reject(0,32,'заповнена квота');
  Need(NegativeCount=9,'дев\x27ять негативів');
  X64Reset(C);
  X64BSwap(C,8,64);
  Need(X64Image(C)=#$49#$0F#$C8,'відновлення після відмов');
end;
procedure ExecutableTest(TargetWidth:Integer);
var Name:String;
begin
  X64Reset(C);
  if TargetWidth=32 then begin
    { MOV EAX,imm32; BSWAP EAX => 0x44332211, RAX верх = нуль. }
    X64MovImm32(C,xrAX,$11223344);
    X64BSwap(C,0,32);
    Name:='32';
    Save(Directory+'/case-32.expected.bin',#$11#$22#$33#$44#0#0#0#0);
  end else begin
    { Test harness: MOV R8, imm64; host BSWAP R8; MOV RAX,R8.
      Власний encoder відповідає тільки за середні BSWAP bytes. }
    C.Bytes:=#$49#$B8#$88#$77#$66#$55#$44#$33#$22#$11;
    X64BSwap(C,8,64);
    C.Bytes:=C.Bytes+#$4C#$89#$C0;
    Name:='64';
    Save(Directory+'/case-64.expected.bin',#$11#$22#$33#$44#$55#$66#$77#$88);
  end;
  X64SubRsp8(C,16);
  X64StoreRspQword(C,xrAX,0);
  X64MovImm32(C,xrAX,1); { Linux write(1,rsp,8) }
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,8);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60); { Linux exit(0) }
  X64XorEDI(C);
  X64Syscall(C);
  Executable:=MakeELF64(X64Image(C));
  Save(Directory+'/case-'+Name+'.elf',Executable);
end;
begin
  Need(ParamCount=1,'потрібен приватний каталог');
  Directory:=ParamStr(1);
  Need(DirectoryExists(Directory),'каталогу не існує');
  MatrixTests;
  NegativeTests;
  ExecutableTest(32);
  ExecutableTest(64);
  WriteLn('X64-BSWAP-OK cases=',Count,' negative=',NegativeCount,
          ' elf=2 energy=NOT-MEASURED');
end.
