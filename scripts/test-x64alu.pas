{ G6.92 — незалежні машинні golden/негативи та реальні ELF64.
  Фізичні W1 лише свідки T5M, а XOR є host CPU тестом, не SENS
  оператором. Після створення ELF має запрацювати справжній Linux
  x86-64 kernel; машинний вихід звіряє зовнішній shell test. }
program test_x64alu;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.t5m,wsm.elfgeometry,
  wsm.x64pie;
var C:TX64Code; A,B:Integer; Failed:Boolean; Z:Byte;
    Old,Image,Folder:RawByteString; Good,Bad,PieBad:Integer;
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


function BuildBitELF(Left,Right:Byte;Operation:TX64ALU):RawByteString;
var Code:TX64Code; Machine,Picture:RawByteString; G:TELFGeometry;
begin
  X64Reset(Code);
  X64MovImm32(Code,xrAX,Left);
  X64MovImm32(Code,xrCX,Right);
  Check(Operation in [xaXor,xaOr,xaXchg],'ELF тест допускає лише host XOR/OR/XCHG');
  X64ALU32(Code,Operation,xrAX,xrCX);
  { W1 T5M: 0 + four trit-2 paddings = $50;
    1 + four trit-2 paddings = $A1. Delta=$51 (81), не байт $51. }
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
  Check(Length(Machine)<256,'машинний код за межами квоти');
  { Спільний перевірений ELF64 PIE замість дубльованого ручного
    заповнення заголовка. Code/Bytes — borrowed managed RawByteString,
    Picture — власний ELF64 ET_DYN з точним машинним тілом та геометрією.
    1) Чому цей test не повинен мати власний ELF header writer?
    2) Чому BuildX64PIE не змінює TX64Code?
    3) Чому ISA golden і фактичний Linux stdout — різні докази?
    4) Чому T5M W1 залишається фізичним, а не host-операцією? }
  Picture:=BuildX64PIE(Code);
  Check(X64Image(Code)=Machine,'PIE змінив позичений TX64Code');
  Check((Length(Picture)=120+Length(Machine)) and
        (Copy(Picture,121,Length(Machine))=Machine),
        'PIE змінив точне машинне тіло');
  VerifySENSELF64(Picture,G);
  Check((G.Kind=3) and (G.Entry=120) and
        (G.MachineBytes=Length(Machine)) and
        (G.FileBytes=Length(Picture)),
        'спільна PIE-геометрія некоректна');
  Result:=Picture;
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
  Good:=0;Bad:=0;PieBad:=0;
  Zero:=T5MBit(0);One:=T5MBit(1);
  Check((Ord(Zero)=$50) and (Ord(One)=$A1),
        'несподіване фізичне T5M W1 у pinned codec');

  Golden(xaAdd,xrAX,xrCX,#$01#$C8);
  Golden(xaSub,xrAX,xrCX,#$29#$C8);
  Golden(xaXor,xrAX,xrCX,#$31#$C8);
  Golden(xaAnd,xrAX,xrCX,#$21#$C8);
  Golden(xaOr,xrAX,xrCX,#$09#$C8);
  Golden(xaCmp,xrAX,xrCX,#$39#$C8);
  Golden(xaImul,xrAX,xrCX,#$0F#$AF#$C1);
  Golden(xaAdd,xrDI,xrBX,#$01#$DF);
  Golden(xaImul,xrDI,xrBX,#$0F#$AF#$FB);
  Golden(xaOr,xrDI,xrBX,#$09#$DF);
  Golden(xaXchg,xrAX,xrCX,#$87#$C8);
  Golden(xaXchg,xrDI,xrBX,#$87#$DF);

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
    Image:=BuildBitELF(A,B,xaXor);
    WriteBytes(Folder+'xor-'+IntToStr(A)+'-'+IntToStr(B)+'.elf',Image);
    WriteBytes(Folder+'xor-'+IntToStr(A)+'-'+IntToStr(B)+'.expected.sens',
               T5MBit(A xor B));
    { Host OR має окрему фізичну матрицю 0/1. Це НЕ мовний
      D1 «або»: T5MBit лише перевіряє точний фізичний байт, а
      виконання доводить Linux x86-64 CPU. Кожен образ — managed
      RawByteString, записаний в приватну тимчасову теку caller-а.
      Питання: 1) Хто обирає мовний закон? 2) Чому OR і XOR різні?
      3) Чому не достатньо лише golden 09 C8?
      4) Де перевіряється фактичний ELF stdout? }
    Image:=BuildBitELF(A,B,xaOr);
    WriteBytes(Folder+'or-'+IntToStr(A)+'-'+IntToStr(B)+'.elf',Image);
    WriteBytes(Folder+'or-'+IntToStr(A)+'-'+IntToStr(B)+'.expected.sens',
               T5MBit(A or B));
    { Host XCHG переставляє два регістри: після обміну EAX=колишній ECX.
      Тільки W1-вхід 0/1 і фізичний T5M stdout; D1-законів тут немає.
      Managed ELF-образ живе до WriteBytes; тимчасову теку звільняє
      shell-тест. Питання: 1) Чому очікуємо B, а не A?
      2) Чим відрізняються golden і реальне виконання ELF?
      3) Хто знищує тимчасові артефакти?
      4) Чому T5M не вважається текстовою проєкцією?
    }
    Image:=BuildBitELF(A,B,xaXchg);
    WriteBytes(Folder+'xchg-'+IntToStr(A)+'-'+IntToStr(B)+'.elf',Image);
    WriteBytes(Folder+'xchg-'+IntToStr(A)+'-'+IntToStr(B)+'.expected.sens',
               T5MBit(B));
  end;
  { Ті самі строгі host-квоти загального PIE будівника.
    Спроби порожніх/257 байтів не змінюють borrowed Code і не
    видають часткового ELF. Позитив після відмов доводить recovery.
    Ці байти не є законами SENS і не потребують D7/D12 admission.
    1) Чому 257 — host-квота, а не D12?
    2) Чому перевіряємо точний клас EX64PIEError?
    3) Чому після відмови важливо порівняти оригінальні байти?
    4) Чому тест відновлення не замінює семантичний oracle? }
  X64Reset(C);Old:=X64Image(C);Failed:=False;
  try Image:=BuildX64PIE(C)
  except on E:EX64PIEError do Failed:=True end;
  Check(Failed and (X64Image(C)=Old),
        'PIE не відхилив порожнє тіло або змінив вхід');
  Inc(PieBad);
  X64Reset(C);C.Bytes:=StringOfChar(#$90,257);
  Old:=X64Image(C);Failed:=False;
  try Image:=BuildX64PIE(C)
  except on E:EX64PIEError do Failed:=True end;
  Check(Failed and (X64Image(C)=Old),
        'PIE не відхилив 257 байтів або змінив вхід');
  Inc(PieBad);
  X64Reset(C);X64MovImm32(C,xrAX,60);X64Syscall(C);
  Old:=X64Image(C);Image:=BuildX64PIE(C);
  Check((X64Image(C)=Old) and
        (Length(Image)=120+Length(Old)) and
        (Copy(Image,121,Length(Old))=Old),
        'PIE recovery пошкодив машинний вміст');
  Check(PieBad=2,'лічильник PIE negative');
  WriteLn('X64-PIE-SHARED-PASS negative=2 recovery=1 borrowed=unchanged');
  Check((Good=12) and (Bad=3),'лічильники golden/negative');
  WriteLn('X64-ALU-ГОТОВО golden=12 negative=3 recovery=1 elf=12');
end.
