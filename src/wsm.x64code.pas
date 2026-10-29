{ G6.91 — обмежений байтовий кодер host x86-64 для native backend.
  ЛИШЕ машинні інструкції, не SENS закони, не Dn registry.
  Параметричні регістри/зміщення та 256-байтна квота з відмовою.
  Кожен шаблон перевірений незалежним золотим тестом машинних байтів.
  Власність: TCodeX64 зберігає managed RawByteString; виняток не
  публікує ELF. Навіщо відрізняти host opcode від точного Dn ключа?
  Як перевірити x86-64 без вигаданих бенчмарків і джоулів? }
unit wsm.x64code;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  EX64CodeError=class(Exception);
  TX64Reg=(xrAX,xrCX,xrDX,xrBX,xrSP,xrBP,xrSI,xrDI);
  TX64Code=record
    Bytes:RawByteString;
  end;
procedure X64Reset(out Code:TX64Code);
procedure X64MovImm32(var Code:TX64Code;Reg:TX64Reg;Value:LongWord);
procedure X64SubRsp8(var Code:TX64Code;Amount:SizeInt);
procedure X64StoreRspQword(var Code:TX64Code;Reg:TX64Reg;Disp:SizeInt);
procedure X64LeaRSIRsp(var Code:TX64Code);
procedure X64LoadRDXRSI(var Code:TX64Code;Disp:SizeInt);
procedure X64ImulEDX8(var Code:TX64Code;Immediate:LongInt);
procedure X64AddEDX8(var Code:TX64Code;Immediate:LongInt);
procedure X64StoreRspDL(var Code:TX64Code);
procedure X64Syscall(var Code:TX64Code);
procedure X64XorEDI(var Code:TX64Code);
function X64Image(const Code:TX64Code):RawByteString;
implementation
const MaxCodeBytes=256;

procedure Demand(Good:Boolean;const Why:String);
begin
  if not Good then raise EX64CodeError.Create(Why);
end;

procedure Emit(var Code:TX64Code;const S:RawByteString);
begin
  Demand((Length(S)>0) and (Length(S)<=MaxCodeBytes) and
         (Length(Code.Bytes)<=MaxCodeBytes-Length(S)),
         'Машинний код перевищує host-квоту або порожній');
  Code.Bytes:=Code.Bytes+S;
end;

procedure X64Reset(out Code:TX64Code);
begin
  Code.Bytes:='';
end;

procedure X64MovImm32(var Code:TX64Code;Reg:TX64Reg;Value:LongWord);
begin
  { B8+r, imm32 little endian; r32 запис обнуляє верхні 32 біти r64. }
  Emit(Code,AnsiChar($B8+Ord(Reg))+
    AnsiChar(Byte(Value))+
    AnsiChar(Byte(Value shr 8))+
    AnsiChar(Byte(Value shr 16))+
    AnsiChar(Byte(Value shr 24)));
end;

procedure X64SubRsp8(var Code:TX64Code;Amount:SizeInt);
begin
  Demand((Amount>=0) and (Amount<=127),'sub rsp: imm8 поза межею');
  Emit(Code,#$48#$83#$EC+AnsiChar(Byte(Amount)));
end;

procedure X64StoreRspQword(var Code:TX64Code;Reg:TX64Reg;Disp:SizeInt);
begin
  { 48 89 /r, ModRM r/m=100 + SIB 24: база RSP.
    Для [rsp] немає зміщення; для [rsp+disp8] mod=01.
    Дозволено тільки невід'ємні 0..127 — адреса локального кадру,
    а не довільна чи позамежна пам'ять. }
  Demand((Disp>=0) and (Disp<=127),'зміщення QWord поза стеком');
  if Disp=0 then
    Emit(Code,#$48#$89+AnsiChar((Ord(Reg) shl 3) or $04)+#$24)
  else
    Emit(Code,#$48#$89+AnsiChar($40 or (Ord(Reg) shl 3) or $04)+
      #$24+AnsiChar(Byte(Disp)));
end;

procedure X64LeaRSIRsp(var Code:TX64Code);
begin
  Emit(Code,#$48#$8D#$34#$24);
end;

procedure X64LoadRDXRSI(var Code:TX64Code;Disp:SizeInt);
begin
  Demand((Disp>=0) and (Disp<=127),'зміщення читання rsi поза кадром');
  Emit(Code,#$48#$8B#$56+AnsiChar(Byte(Disp)));
end;

procedure X64ImulEDX8(var Code:TX64Code;Immediate:LongInt);
begin
  Demand((Immediate>=-128) and (Immediate<=127),
         'imul edx: immediate не вміщується в signed 8');
  Emit(Code,#$6B#$D2+AnsiChar(Byte(Immediate)));
end;

procedure X64AddEDX8(var Code:TX64Code;Immediate:LongInt);
begin
  Demand((Immediate>=-128) and (Immediate<=127),
         'add edx: immediate не вміщується в signed 8');
  Emit(Code,#$83#$C2+AnsiChar(Byte(Immediate)));
end;

procedure X64StoreRspDL(var Code:TX64Code);
begin
  Emit(Code,#$88#$14#$24);
end;

procedure X64Syscall(var Code:TX64Code);
begin
  Emit(Code,#$0F#$05);
end;

procedure X64XorEDI(var Code:TX64Code);
begin
  Emit(Code,#$31#$FF);
end;

function X64Image(const Code:TX64Code):RawByteString;
begin
  Result:=Code.Bytes;
end;
end.
