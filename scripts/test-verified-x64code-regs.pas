{ G6.247 — справжня checked FPC перевірка меж machine register API.
  Це лише host x86-64, НЕ новий закон SENS і не textual dispatch.
  Типи: TX64Reg — host enum, недійсні числа допускаються лише як
  контрольовано зіпсовані тестові значення; TX64Code — managed bytes,
  власником є тест. ELF64 і T5M — власні RawByteString; файли — тимчасові.
  Питання: 1) Чому Ord(Reg) не є SENS-доменом?
  2) Як перевірити незмінність буфера після помилки?
  3) Чому незалежний GNU as кращий за повтор формули?
  4) Чому D1/W1 пишеться фізичним T5M байтом?
  5) Що саме доводить виконання вузького ELF64? }
program test_verified_x64code_regs;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64pie,wsm.t5m;
const
  Names32:array[0..7] of String=
    ('eax','ecx','edx','ebx','esp','ebp','esi','edi');
  Names64:array[0..7] of String=
    ('rax','rcx','rdx','rbx','rsp','rbp','rsi','rdi');
  Invalid:array[0..2] of LongInt=(-1,8,255);
var
  C:TX64Code;
  I,J,Mode,Bad:Integer;
  Snapshot,BeforeFixup,Image,Physical:RawByteString;
  TextAsm:TStringList;
  W:TExactWords;
  Dir:String;
  Failed:Boolean;

procedure Check(Good:Boolean;const Reason:String);
begin
  if not Good then raise Exception.Create('X64-РЕГІСТРИ-ПРОВАЛ: '+Reason);
end;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Name,fmCreate);
  try
    if Length(Data)>0 then
      Check(F.Write(Data[1],Length(Data))=Length(Data),
        'неповний фізичний запис');
  finally F.Free end;
end;

{ Вимкнення host range check обмежено ЛИШЕ виготовленням ворожої
  координати; production emitter збирається з -Cr і зобов'язаний
  підняти саме EX64CodeError, а не згенерувати неправильний opcode. }
{$R-}
function ForgedRegister(Number:LongInt):TX64Reg;
begin
  Result:=TX64Reg(Number);
end;
{$R+}

procedure DemandAtomicReject(const Reason:String);
begin
  Check(Failed,'відсутня власна відмова '+Reason);
  Check((C.Bytes=Snapshot) and (C.PatchedRIP=BeforeFixup),
        'частково пошкоджено машинний стан '+Reason);
  Inc(Bad);
end;

procedure NegativeRegisters;
var R:TX64Reg;
begin
  Bad:=0;
  for I:=0 to High(Invalid) do
    for Mode:=0 to 1 do begin
      R:=ForgedRegister(Invalid[I]);
      X64Reset(C);
      C.Bytes:=#$90;
      C.PatchedRIP:=#$03;
      Snapshot:=C.Bytes; BeforeFixup:=C.PatchedRIP;
      Failed:=False;
      try
        if Mode=0 then X64MovImm32(C,R,$11223344)
        else X64StoreRspQword(C,R,8);
      except on E:EX64CodeError do Failed:=True end;
      DemandAtomicReject('регістр='+IntToStr(Invalid[I])+
                         ' emitter='+IntToStr(Mode));
    end;

  for Mode:=0 to 1 do begin
    X64Reset(C);
    C.Bytes:=StringOfChar(#$90,253);
    C.PatchedRIP:=#$07;
    Snapshot:=C.Bytes; BeforeFixup:=C.PatchedRIP;
    Failed:=False;
    try
      if Mode=0 then X64MovImm32(C,xrAX,1)
      else X64StoreRspQword(C,xrAX,8);
    except on E:EX64CodeError do Failed:=True end;
    DemandAtomicReject('квота='+IntToStr(Mode));
  end;
  Check(Bad=8,'очікувані вісім відмов');
end;

procedure Matrix;
begin
  X64Reset(C);
  TextAsm:=TStringList.Create;
  try
    TextAsm.Add('.text');
    TextAsm.Add('.globl _start');
    TextAsm.Add('_start:');
    for J:=0 to 7 do begin
      X64MovImm32(C,TX64Reg(J),$11223344);
      X64StoreRspQword(C,TX64Reg(J),0);
      X64StoreRspQword(C,TX64Reg(J),8);
      TextAsm.Add('movl $0x11223344, %'+Names32[J]);
      TextAsm.Add('movq %'+Names64[J]+', (%rsp)');
      TextAsm.Add('movq %'+Names64[J]+', 8(%rsp)');
    end;
    Check(Length(C.Bytes)=112,'матриця 24 інструкцій');
    TextAsm.SaveToFile(Dir+'matrix.s');
    Save(Dir+'matrix.fpc.bin',X64Image(C));
  finally TextAsm.Free end;
end;

procedure BuildELF(Bit:Integer);
begin
  SetLength(W,1);
  if Bit=0 then W[0]:='0' else W[0]:='1';
  Physical:=EncodeT5M(W);
  Check((Length(Physical)=1) and
    (((Bit=0) and (Ord(Physical[1])=$50)) or
     ((Bit=1) and (Ord(Physical[1])=$A1))),
    'втрачено фізичний pinned W1 T5M');
  X64Reset(C);
  X64MovImm32(C,xrDX,Ord(Physical[1]));
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
  Check((Length(Image)>120) and
    (Copy(Image,121,Length(C.Bytes))=C.Bytes),
    'машинний ELF64 змінює код');
  Save(Dir+'bit-'+IntToStr(Bit)+'.elf',Image);
  Save(Dir+'bit-'+IntToStr(Bit)+'.sens',Physical);
end;

begin
  Check(ParamCount=1,'потрібна приватна тимчасова тека');
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Dir),'відсутня тимчасова тека');
  NegativeRegisters;
  Matrix;
  X64Reset(C);
  X64MovImm32(C,xrAX,$11223344);
  X64StoreRspQword(C,xrAX,8);
  Check(X64Image(C)=#$B8#$44#$33#$22#$11#$48#$89#$44#$24#$08,
    'позитивний golden і відновлення');
  for I:=0 to 1 do BuildELF(I);
  WriteLn('G6.247-X64CODE-REGS-PASS matrix=24 negatives=8',
    ' recovery=1 elf=2 oracle=NOT-RUN energy=NOT-MEASURED');
end.
