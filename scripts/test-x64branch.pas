{ G6.97 — FPC перевірка host x86-64 переходів:
  golden машинні байти, відмови без побічних дій, два реальні ELF.
  Очікувані фізичні D1 байти обчислює тільки pinned-compatible
  wsm.t5m, НЕ локальний список опкодів/мовних законів.
  Вхід: один каталог виходу; вихід: 2 ELF + 2 packed .sens.
  Керовані RawByteString живуть у процедурі; файли віддаються тесту.

  Питання: 1) Чому golden незалежний від Linux ELF?
  2) Чому тут немає мовної семантики D3 COND?
  3) Чому негатив має залишати старий буфер без змін?
  4) Чому запуск потрібен поряд із дизасемблюванням? }
program test_x64branch;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.x64code,wsm.x64branch,wsm.t5m,wsm.elfgeometry;
var C:TX64Code; F,EndFix,ZeroTarget,PublishTarget,I,Negatives:SizeInt;
    Before,Actual,Expected,ELF:RawByteString; Failed:Boolean;
    Answers:TExactWords; Dir:String; Geometry:TELFGeometry;
procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('X64-ПЕРЕХІД-ПРОВАЛ: '+Why);
end;
procedure Save(const Path:String;const Bytes:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free end;
end;
procedure PutLE(var Buffer:RawByteString;Offset:SizeInt;
  Value:QWord;Count:SizeInt);
var J:SizeInt;
begin
  for J:=0 to Count-1 do begin
    Buffer[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function MakeELF64(const Machine:RawByteString):RawByteString;
const Header=120; Base:QWord=$400000;
var J,Size:SizeInt;
begin
  Size:=Header+Length(Machine);
  SetLength(Result,Size);
  for J:=1 to Size do Result[J]:=#0;
  PutLE(Result,0,$464C457F,4);
  PutLE(Result,4,2,1);PutLE(Result,5,1,1);PutLE(Result,6,1,1);
  PutLE(Result,16,2,2);PutLE(Result,18,62,2);PutLE(Result,20,1,4);
  PutLE(Result,24,Base+Header,8);PutLE(Result,32,64,8);
  PutLE(Result,52,64,2);PutLE(Result,54,56,2);PutLE(Result,56,1,2);
  PutLE(Result,64,1,4);PutLE(Result,68,5,4);
  PutLE(Result,80,Base,8);PutLE(Result,88,Base,8);
  PutLE(Result,96,Size,8);PutLE(Result,104,Size,8);
  PutLE(Result,112,$1000,8);
  for J:=1 to Length(Machine) do Result[Header+J]:=Machine[J];
  VerifySENSELF64(Result,Geometry);
  Check((Geometry.MachineBytes=Length(Machine)) and (Geometry.Kind=2),
    'згенерована ELF64 геометрія');
end;
procedure Rejected(const LabelText:String;DidFail:Boolean);
begin
  Check(DidFail,'не відхилено '+LabelText);
  Check(X64Image(C)=Before,'змінено код після відмови '+LabelText);
  Inc(Negatives);
end;
procedure BuildBranchProgram(Value:Byte;ZeroByte,OneByte:Byte);
begin
  X64Reset(C);
  X64MovImm32(C,xrAX,Value);
  X64TestEAX(C);
  X64EmitBranch(C,xbZero,F);
  X64MovImm32(C,xrDX,OneByte);
  X64EmitBranch(C,xbJump,EndFix);
  ZeroTarget:=Length(C.Bytes);
  X64MovImm32(C,xrDX,ZeroByte);
  PublishTarget:=Length(C.Bytes);
  X64SubRsp8(C,16);
  X64StoreRspQword(C,xrDX,0);
  X64MovImm32(C,xrAX,1);  { Linux write }
  X64MovImm32(C,xrDI,1);
  X64MovRSIRsp(C);
  X64MovImm32(C,xrDX,1);
  X64Syscall(C);
  X64MovImm32(C,xrAX,60); { Linux exit }
  X64XorEDI(C);
  X64Syscall(C);
  X64PatchBranch(C,xbZero,F,ZeroTarget);
  X64PatchBranch(C,xbJump,EndFix,PublishTarget);
end;
begin
  Check(ParamCount=1,'потрібен каталог артефактів');
  Dir:=ParamStr(1);
  Check(DirectoryExists(Dir),'немає каталогу артефактів');
  Negatives:=0;
  X64Reset(C);
  X64EmitBranch(C,xbZero,F);
  Check(F=2,'0-based JZ fixup');
  X64MovImm32(C,xrAX,7);
  X64XorEDI(C);
  X64PatchBranch(C,xbZero,F,11);
  Actual:=X64Image(C);
  Expected:=#$0F#$84#$05#0#0#0+#$B8#$07#0#0#0+#$31#$FF;
  Check(Actual=Expected,'незалежний JZ rel32 +5 golden');
  X64Reset(C);
  X64MovImm32(C,xrAX,7);
  X64EmitBranch(C,xbJump,F);
  Check(F=6,'0-based JMP fixup');
  X64PatchBranch(C,xbJump,F,0);
  Check(X64Image(C)=#$B8#$07#0#0#0+#$E9#$F6#$FF#$FF#$FF,
    'незалежний JMP rel32 -10 golden');
  { Всі негативи перевіряють незмінність навіть після пізньої помилки. }
  X64Reset(C);
  X64EmitBranch(C,xbJump,F);
  X64MovImm32(C,xrAX,42);
  Before:=X64Image(C);
  Failed:=False;
  try X64PatchBranch(C,xbZero,F,0)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('тип opcode',Failed);
  Failed:=False;
  try X64PatchBranch(C,xbJump,-1,0)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('негативний fixup',Failed);
  Failed:=False;
  try X64PatchBranch(C,xbJump,F,-1)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('негативна ціль',Failed);
  Failed:=False;
  try X64PatchBranch(C,xbJump,F,Length(C.Bytes))
  except on E:EX64CodeError do Failed:=True end;
  Rejected('ціль після кінця коду',Failed);
  Failed:=False;
  try X64PatchBranch(C,xbJump,F,F+4)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('нульовий rel32',Failed);
  Failed:=False;
  try X64PatchBranch(C,xbJump,4,0)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('хибна адреса opcode',Failed);
  { Успішний patch і повторна спроба підстановки. }
  X64PatchBranch(C,xbJump,F,0);
  Before:=X64Image(C);
  Failed:=False;
  try X64PatchBranch(C,xbJump,F,0)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('подвійна підстановка',Failed);
  X64Reset(C);
  for I:=1 to 51 do X64MovImm32(C,xrAX,0);
  Check(Length(C.Bytes)=255,'початкова host-квота');
  Before:=X64Image(C);
  Failed:=False; F:=999;
  try X64EmitBranch(C,xbZero,F)
  except on E:EX64CodeError do Failed:=True end;
  Rejected('квота 256',Failed);
  Check(F=-1,'відмова не залишила хибний fixup');
  { Відновлення після негативів: дві реально відмінні машинні гілки. }
  SetLength(Answers,1);
  Answers[0]:='0'; Expected:=EncodeT5M(Answers);
  Check(Length(Expected)=1,'один канонічний D1 T5M байт');
  Save(Dir+'/branch-0.expected.sens',Expected);
  Answers[0]:='1'; Actual:=EncodeT5M(Answers);
  Check((Length(Actual)=1) and (Actual<>Expected),
    'дві різні фізичні D1 відповіді');
  Save(Dir+'/branch-1.expected.sens',Actual);
  for I:=0 to 1 do begin
    BuildBranchProgram(Byte(I),Byte(Ord(Expected[1])),Byte(Ord(Actual[1])));
    ELF:=MakeELF64(X64Image(C));
    Save(Dir+'/branch-'+IntToStr(I)+'.elf',ELF);
  end;
  Check(Negatives=8,'точна кількість відхилень');
  WriteLn('X64-ПЕРЕХОДИ-ГАРАЗД golden=2 negative=8 recovery=1 elf=2');
end.
