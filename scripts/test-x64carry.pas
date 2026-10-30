{ G6.250 — 128 незалежних GNU as координат host ADC/SBB і 4 ELF64.
  Програма пише golden .s/.bin та native PIE з точним фізичним T5M W1.
  Це перевірка CPU/host assembler, а не семантичний оракул SENS.
  Machine/Expected — owned managed byte strings, тимчасові файли
  належать shell-викликачу; файли закриваються у finally.
  Питання: 1) Чому перевіряємо 8x8 регістрів для кожної операції?
  2) Чому GNU as незалежніший від власного ModRM алгоритму?
  3) Що доводить запуск ELF64, чого не доводить байтова матриця?
  4) Чому ADC/SBB використовують прапор попередньої ADD/SUB?
  5) Чому W1 фізично не є мовною операцією? }
program test_x64carry;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.x64carry,
  wsm.x64pie,wsm.t5m,wsm.elfgeometry;
const
  RegNames:array[0..7] of String=
    ('eax','ecx','edx','ebx','esp','ebp','esi','edi');
var C:TX64Code;
    Folder:String;
    Golden:RawByteString;
    Lines:TStringList;
    I,J,Mode,Count,Negatives,Executables:Integer;
    Op:TX64Carry;
    Expected,Picture,Machine,Before,BeforeRIP:RawByteString;
    Words:TExactWords;
    Geometry:TELFGeometry;
    Rejected:Boolean;

procedure Check(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('X64-CARRY-ПОМИЛКА: '+Why);
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free; end;
end;

function PhysicalBit(Bit:Integer):RawByteString;
begin
  Check((Bit=0) or (Bit=1),'потрібний фізичний W1');
  SetLength(Words,1);
  if Bit=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Check((Length(Result)=1) and
        (((Bit=0) and (Byte(Result[1])=$50)) or
         ((Bit=1) and (Byte(Result[1])=$A1))),
        'точний фізичний W1 T5M');
end;

procedure Matrix;
var One:RawByteString;
begin
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');
    Golden:='';Count:=0;
    for Mode:=0 to 1 do
      for I:=0 to 7 do for J:=0 to 7 do begin
        if Mode=0 then Op:=xcAdc else Op:=xcSbb;
        X64Reset(C);
        X64Carry32(C,Op,TX64Reg(I),TX64Reg(J));
        One:=X64Image(C);
        Check(Length(One)=2,'довжина host ADC/SBB');
        Golden:=Golden+One;
        if Mode=0 then
          Lines.Add('  adc '+RegNames[I]+', '+RegNames[J])
        else
          Lines.Add('  sbb '+RegNames[I]+', '+RegNames[J]);
        Inc(Count);
      end;
    Check((Count=128) and (Length(Golden)=256),
          'математична квота незалежного еталона');
    Lines.SaveToFile(Folder+'/carry-reference.s');
    Save('carry-fpc.bin',Golden);
  finally Lines.Free; end;
end;

procedure Reject(OperationCode,DestCode,SourceCode:Integer;const Why:String);
var Operation:TX64Carry;D,S:TX64Reg;
begin
  Before:=X64Image(C);
  BeforeRIP:=C.PatchedRIP;
  Rejected:=False;
  try
    Operation:=TX64Carry(OperationCode);
    D:=TX64Reg(DestCode);
    S:=TX64Reg(SourceCode);
    X64Carry32(C,Operation,D,S);
  except on E:Exception do Rejected:=True end;
  Check(Rejected,'не відхилено: '+Why);
  Check((X64Image(C)=Before) and (C.PatchedRIP=BeforeRIP),
        'зіпсовано machine buffer: '+Why);
  Inc(Negatives);
end;

procedure NegativeTests;
begin
  Negatives:=0;
  X64Reset(C);
  C.Bytes:=#$90;C.PatchedRIP:='x';
  Reject(Ord(xcAdc),8,Ord(xrAX),'destination=8');
  Reject(Ord(xcSbb),Ord(xrAX),8,'source=8');
  Reject(255,Ord(xrAX),Ord(xrCX),'unknown operation');
  C.Bytes:=StringOfChar(#$90,255);
  Reject(Ord(xcAdc),Ord(xrAX),Ord(xrCX),'255+2 перевищення');
  C.Bytes:=StringOfChar(#$90,257);
  Reject(Ord(xcSbb),Ord(xrAX),Ord(xrCX),'пошкоджений буфер 257');
  C.Bytes:=StringOfChar(#$90,254);
  X64Carry32(C,xcAdc,xrDX,xrCX);
  Check(Length(C.Bytes)=256,'не прийнято точну квоту 256');
  Reject(Ord(xcSbb),Ord(xrDX),Ord(xrCX),'повна квота');
  X64Reset(C);
  X64Carry32(C,xcSbb,xrAX,xrCX);
  Check(X64Image(C)=#$19#$C8,'відновлення після негативів');
  Check(Negatives=6,'лічильник негативів');
end;

procedure MachineCase(Kind:TX64Carry;HasFlag:Boolean);
var Name:String; ResultBit:Integer;
begin
  X64Reset(C);
  if Kind=xcAdc then begin
    X64MovImm32(C,xrAX,$FFFFFFFF);
    X64MovImm32(C,xrCX,Ord(HasFlag));
    X64MovImm32(C,xrDX,0);
    X64MovImm32(C,xrBX,0);
    X64ALU32(C,xaAdd,xrAX,xrCX);
    X64Carry32(C,xcAdc,xrDX,xrBX);
    Name:='adc';ResultBit:=Ord(HasFlag);
  end else begin
    X64MovImm32(C,xrAX,0);
    X64MovImm32(C,xrCX,Ord(HasFlag));
    X64MovImm32(C,xrDX,1);
    X64MovImm32(C,xrBX,0);
    X64ALU32(C,xaSub,xrAX,xrCX);
    X64Carry32(C,xcSbb,xrDX,xrBX);
    Name:='sbb';ResultBit:=Ord(not HasFlag);
  end;
  { Host 0/1 перетворюємо в байт T5M лише після ADC/SBB;
    множення/додавання тут НЕ є семантичним SENS lowering. }
  X64ImulEDX8(C,81);
  X64AddEDX8(C,80);
  X64SubRsp8(C,8);
  X64StoreRspQword(C,xrDX,0);
  X64MovImm32(C,xrAX,1);  { Linux write(fd=1,&byte,1) }
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60); { Linux exit(0) }
  X64XorEDI(C);
  X64Syscall(C);
  Machine:=X64Image(C);
  Check(Length(Machine)<=256,'машина перевищує host квоту');
  Picture:=BuildX64PIE(C);
  Check(X64Image(C)=Machine,'PIE змінив позичений machine буфер');
  VerifySENSELF64(Picture,Geometry);
  Check((Geometry.Kind=3) and (Geometry.MachineBytes=Length(Machine)) and
        (Geometry.Entry=120) and (Copy(Picture,121,Length(Machine))=Machine),
        'втрачено machine bytes у PIE');
  if HasFlag then Name:=Name+'-1' else Name:=Name+'-0';
  Save(Name+'.elf',Picture);
  Expected:=PhysicalBit(ResultBit);
  Save(Name+'.expected.sens',Expected);
  Inc(Executables);
end;

begin
  Check(ParamCount=1,'потрібен приватний каталог');
  Folder:=ParamStr(1);
  Check(DirectoryExists(Folder),'каталог не існує');
  Executables:=0;
  Matrix;
  NegativeTests;
  MachineCase(xcAdc,False);
  MachineCase(xcAdc,True);
  MachineCase(xcSbb,False);
  MachineCase(xcSbb,True);
  Check(Executables=4,'кількість фізичних ELF');
  WriteLn('X64-CARRY-ГОТОВО golden=128 negative=',Negatives,
    ' elf64=',Executables,' t5m=',Executables,' energy=NOT-MEASURED');
end.
