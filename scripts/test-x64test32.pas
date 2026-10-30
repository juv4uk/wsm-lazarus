{ G6.254 — окремий перевірений host TEST r32,r32.
  Спільний TX64Code — owned managed байти; ELF і очікувані .sens
  зберігаються лише в тимчасовому каталозі CI. Жодного D7 dispatch.
  1) Чому 64 машинні opcode перевіряє зовнішній GNU as?
  2) Як відрізнити ZF x86 від законів SENS?
  3) Чому T5M expected створює pinned codec, а не таблиця тесту?
  4) Як вихід із кодом 1 виявляє неповний stdout write?
  5) Хто володіє ELF-байтами після BuildX64PIE? }
program test_x64test32;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.x64code,wsm.x64alu,wsm.x64test32,
     wsm.x64pie,wsm.elfgeometry,wsm.t5m;
var Positive,Negative:LongInt;
    TargetDir:String;
    PhysicalZero,PhysicalOne:RawByteString;
    BaseByte,Delta:LongInt;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('TEST32-ПОМИЛКА: '+Why);
end;

function Words(const A:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(TargetDir+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure ExpectError(var Code:TX64Code;Dest,Source:TX64Reg;
                      const Why:String);
var OldBytes,OldRIP:RawByteString;Caught:Boolean;
begin
  OldBytes:=Copy(Code.Bytes,1,Length(Code.Bytes));
  OldRIP:=Copy(Code.PatchedRIP,1,Length(Code.PatchedRIP));
  Caught:=False;
  try X64Test32(Code,Dest,Source);
  except on E:EX64CodeError do begin
    Caught:=True;
    Check(E.Message<>'',Why+': порожня діагностика');
  end end;
  Check(Caught and (Code.Bytes=OldBytes) and
        (Code.PatchedRIP=OldRIP),
        Why+': відмова змінила машинні байти або RIP');
  Inc(Negative);
end;

procedure MatrixAndNegatives;
var Code:TX64Code;D,S:Integer;Invalid:TX64Reg;
begin
  X64Reset(Code);
  for D:=0 to 7 do
    for S:=0 to 7 do
      X64Test32(Code,TX64Reg(D),TX64Reg(S));
  Check((Length(Code.Bytes)=128) and (Code.PatchedRIP=''),
        'матриця не містить рівно 64 host TEST');
  Save('matrix.bin',Code.Bytes);

  X64Reset(Code);
  Code.Bytes:=RawByteString(StringOfChar('N',254));
  Code.PatchedRIP:=#$17;
  X64Test32(Code,xrAX,xrBX);
  Check((Length(Code.Bytes)=256) and
        (Code.PatchedRIP=#$17),'квота 256 повинна допускати 254+2');
  ExpectError(Code,xrAX,xrCX,'заповнена квота 256');

  X64Reset(Code);
  Code.Bytes:=RawByteString(StringOfChar('N',255));
  Code.PatchedRIP:=#$22;
  ExpectError(Code,xrAX,xrCX,'квота 255+2');

  X64Reset(Code);
  Code.Bytes:='бережи';
  Code.PatchedRIP:=#$07;
  {$R-}
  Invalid:=TX64Reg(8);
  {$R+}
  ExpectError(Code,Invalid,xrAX,'недійсний регістр призначення');
  ExpectError(Code,xrAX,Invalid,'недійсний регістр джерела');

  X64Reset(Code);
  X64Test32(Code,xrAX,xrAX);
  Check((Code.Bytes=#$85#$C0) and (Code.PatchedRIP=''),
        'відновлення після негативів або opcode TEST EAX,EAX');
end;

procedure WriteRealELF(ZeroFlagInput:Boolean);
var Code:TX64Code;Image,Expected:RawByteString;
    Geo:TELFGeometry;HostValue:LongWord;LabelText:String;
begin
  if ZeroFlagInput then begin
    HostValue:=0; Expected:=PhysicalOne; LabelText:='nulyovyi';
  end else begin
    HostValue:=1; Expected:=PhysicalZero; LabelText:='nenulyovyi';
  end;
  X64Reset(Code);
  X64MovImm32(Code,xrAX,HostValue);
  X64MovImm32(Code,xrCX,HostValue);
  X64Test32(Code,xrAX,xrCX);
  X64SetEAL(Code);
  X64MovzxEAXAL(Code);
  X64MovImm32(Code,xrDX,0);
  X64ALU32(Code,xaOr,xrDX,xrAX);
  X64ImulEDX8(Code,Delta);
  X64AddEDX8(Code,BaseByte);
  X64SubRsp8(Code,8);
  X64StoreRspDL(Code);
  X64LeaRSIRsp(Code);
  X64MovImm32(Code,xrDX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovImm32(Code,xrAX,1);
  X64Syscall(Code);
  { Перевірити фізичне число реально записаних байтів.
    Помилка closed stdout або /dev/full завершується exit=1. }
  X64MovImm32(Code,xrCX,1);
  X64ALU32(Code,xaCmp,xrAX,xrCX);
  X64SetEAL(Code);
  X64MovzxEAXAL(Code);
  X64MovImm32(Code,xrDI,1);
  X64ALU32(Code,xaSub,xrDI,xrAX);
  X64MovImm32(Code,xrAX,60);
  X64Syscall(Code);
  Image:=BuildX64PIE(Code);
  VerifySENSELF64(Image,Geo);
  Check((Geo.Kind=3) and (Geo.Entry=120) and
        (Geo.MachineBytes=Length(Code.Bytes)) and
        (Copy(Image,121,Length(Code.Bytes))=Code.Bytes),
        'PIE не містить точні машинні байти');
  Save(LabelText+'.elf',Image);
  Save(LabelText+'.expected.sens',Expected);
  Inc(Positive);
end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Потрібен тимчасовий каталог');Halt(64);
  end;
  TargetDir:=ParamStr(1);
  Check(DirectoryExists(TargetDir),'відсутній каталог');
  Positive:=0;Negative:=0;
  PhysicalZero:=EncodeT5M(Words(['0']));
  PhysicalOne:=EncodeT5M(Words(['1']));
  Check((Length(PhysicalZero)=1) and (Length(PhysicalOne)=1),
        'очікували один фізичний T5M байт на W1');
  BaseByte:=Byte(PhysicalZero[1]);
  Delta:=LongInt(Byte(PhysicalOne[1]))-BaseByte;
  Check((BaseByte>=-128) and (BaseByte<=127) and
        (Delta>=-128) and (Delta<=127) and (Delta<>0),
        'фізичний W1 не вміщується у host imm8');
  MatrixAndNegatives;
  WriteRealELF(True);
  WriteRealELF(False);
  Check((Positive=2) and (Negative=4),'хибні лічильники тесту');
  WriteLn('G6.254-X64TEST32-PASS matrix=64 golden=2 negative=4 recovery=1');
end.
