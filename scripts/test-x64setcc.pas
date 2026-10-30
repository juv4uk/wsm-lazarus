{ G6.247 — справжні ELF64 для host CMP/SETcc без власного SENS закону.
  Фізичний результат W1 походить лише з pinned T5M-кодека.
  Чотири cc (E/NE/L/GE) × чотири пари машинних бітів = 16 ELF.
  Вхідні 0/1 — host тестові операнди, не SENS-члени D12.
  Питання: 1) Де закінчується CPU умова і починається мовний закон?
  2) Чому MOVZX потрібен після SETcc AL?
  3) Хто володіє побудованим ELF до запису?
  4) Чому write=0/-errno не можна вважати успіхом?
  5) Чому expected .sens будуємо незалежно від машинного stdout? }
program test_x64setcc;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.x64setcc,
     wsm.x64pie,wsm.t5m,wsm.elfgeometry;

var C:TX64Code; Root:String; A,B,CC,ResultBit:Integer;
    Good,Bad,Native:Integer; Old,Image:RawByteString;
    ZeroByte,OneByte:AnsiChar; Geometry:TELFGeometry; Physical:RawByteString;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('X64-SETCC-ПРОВАЛ: '+Why);
end;

function PhysicalBit(Value:Integer):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1);
  if Value=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Check(Length(Result)=1,'фізичне W1 мусить мати один байт');
end;

procedure WriteBytes(const Path:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

procedure Golden(Condition:Integer;Register:TX64Reg;
                 const Expected:RawByteString);
begin
  X64Reset(C);
  X64SetCondition8(C,Condition,Register);
  Check(X64Image(C)=Expected,'точні opcode/ModRM SETcc');
  Inc(Good);
end;

procedure Refused(const Why:String;Condition:Integer;Register:TX64Reg);
var Raised:Boolean;
begin
  Old:=X64Image(C);
  Raised:=False;
  try X64SetCondition8(C,Condition,Register)
  except on E:EX64CodeError do Raised:=True end;
  Check(Raised and (X64Image(C)=Old),'неатомарна відмова: '+Why);
  Inc(Bad);
end;

function ExpectedPredicate(Condition,Left,Right:Integer):Integer;
begin
  case Condition of
    4:Result:=Ord(Left=Right);  { ZF: E }
    5:Result:=Ord(Left<>Right); { !ZF: NE }
    12:Result:=Ord(Left<Right); { signed SF != OF: L }
    13:Result:=Ord(Left>=Right);{ signed SF == OF: GE }
  else
    raise Exception.Create('Недопустимий тестовий host condition');
  end;
end;

function BuildMachine(Condition,Left,Right:Integer):RawByteString;
var Code:TX64Code;
begin
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Left);
  X64MovImm32(Code,xrCX,Right);
  X64ALU32(Code,xaCmp,xrAX,xrCX);
  X64SetCondition8(Code,Condition,xrAX);
  X64MovzxEAXAL(Code);
  { EAX тепер 0/1, перетворити на фізичний T5M W1 байт. }
  X64MovImm32(Code,xrDX,0);
  X64ALU32(Code,xaAdd,xrDX,xrAX);
  X64ImulEDX8(Code,Ord(OneByte)-Ord(ZeroByte));
  X64AddEDX8(Code,Ord(ZeroByte));
  X64SubRsp8(Code,8);
  X64StoreRspQword(Code,xrDX,0);
  X64MovImm32(Code,xrAX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovRSIRsp(Code);
  X64MovImm32(Code,xrDX,1);
  X64Syscall(Code);
  { Linux write повертає 1 на успіх, інше значення — exit(1).
    Не публікуємо удаваний успіх при EBADF, ENOSPC або short write. }
  X64MovImm32(Code,xrCX,1);
  X64ALU32(Code,xaCmp,xrAX,xrCX);
  X64MovImm32(Code,xrAX,0);
  X64SetCondition8(Code,5,xrAX);
  X64MovzxEAXAL(Code);
  X64MovImm32(Code,xrDI,0);
  X64ALU32(Code,xaAdd,xrDI,xrAX);
  X64MovImm32(Code,xrAX,60);
  X64Syscall(Code);
  Result:=BuildX64PIE(Code);
  VerifySENSELF64(Result,Geometry);
  Check((Geometry.Kind=3) and (Geometry.Entry=120) and
    (Geometry.MachineBytes=Length(Code.Bytes)),'неперевірений ELF64 PIE');
end;

var Prefix:String;
begin
  Check(ParamCount=1,'потрібен каталог фізичних ELF');
  Root:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Root),'відсутній каталог ELF');
  Good:=0;Bad:=0;Native:=0;
  Physical:=PhysicalBit(0);ZeroByte:=Physical[1];
  Physical:=PhysicalBit(1);OneByte:=Physical[1];
  Check((Byte(ZeroByte)=$50) and (Byte(OneByte)=$A1),
    'pinned фізичний T5M W1 не збігається');

  Golden(4,xrAX,#$0F#$94#$C0);
  Golden(5,xrCX,#$0F#$95#$C1);
  Golden(12,xrDX,#$0F#$9C#$C2);
  Golden(13,xrBX,#$0F#$9D#$C3);

  X64Reset(C);C.Bytes:=#$90;
  Refused('відʼємна умова',-1,xrAX);
  Refused('умова понад 15',16,xrAX);
  Refused('SP без REX',4,xrSP);
  Refused('SI без REX',4,xrSI);
  X64Reset(C);C.Bytes:=StringOfChar(#$90,254);
  Refused('понад квоту 256',4,xrAX);
  X64Reset(C);
  X64SetCondition8(C,4,xrAX);
  Check(X64Image(C)=#$0F#$94#$C0,'відновлення після негативів');

  for CC:=0 to 3 do
    for A:=0 to 1 do
      for B:=0 to 1 do begin
        case CC of
          0:ResultBit:=4;
          1:ResultBit:=5;
          2:ResultBit:=12;
        else ResultBit:=13;
        end;
        Prefix:=Root+'cc'+IntToStr(ResultBit)+'-'+IntToStr(A)+'-'+IntToStr(B);
        Image:=BuildMachine(ResultBit,A,B);
        WriteBytes(Prefix+'.elf',Image);
        WriteBytes(Prefix+'.expected.sens',
                   PhysicalBit(ExpectedPredicate(ResultBit,A,B)));
        Inc(Native);
      end;
  Check((Good=4) and (Bad=5) and (Native=16),'лічильники тестів');
  Writeln('X64-SETCC-ПЕРЕВІРЕНО golden=4 negative=5 recovery=1 elf=16');
end.
