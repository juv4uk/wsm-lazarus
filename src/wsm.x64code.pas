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
procedure X64MovRSIRsp(var Code:TX64Code);
procedure X64LoadRDXRSI(var Code:TX64Code;Disp:SizeInt);
procedure X64ImulEDX8(var Code:TX64Code;Immediate:LongInt);
procedure X64AddEDX8(var Code:TX64Code;Immediate:LongInt);
procedure X64StoreRspDL(var Code:TX64Code);
procedure X64Syscall(var Code:TX64Code);
procedure X64TestEAX(var Code:TX64Code);
procedure X64SetEAL(var Code:TX64Code);
procedure X64MovzxEAXAL(var Code:TX64Code);
procedure X64LeaRSIRip(var Code:TX64Code;out FixupPos:SizeInt);
procedure X64LoadDLRSIRAX(var Code:TX64Code);
procedure X64PatchRIP32(var Code:TX64Code;FixupPos,TargetOffset:SizeInt);
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
    AnsiChar(Byte(Value and $FF))+
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

procedure X64MovRSIRsp(var Code:TX64Code);
begin
  { 48 89 E6: MOV RSI,RSP, не 48 8D 34 24 (LEA RSI,[RSP]).
    Обидва обчислюють ту саму адресу, але байти і розмір різні. }
  Emit(Code,#$48#$89#$E6);
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
  Emit(Code,#$6B#$D2+AnsiChar(Byte(Immediate and $FF)));
end;

procedure X64AddEDX8(var Code:TX64Code;Immediate:LongInt);
begin
  Demand((Immediate>=-128) and (Immediate<=127),
         'add edx: immediate не вміщується в signed 8');
  Emit(Code,#$83#$C2+AnsiChar(Byte(Immediate and $FF)));
end;

procedure X64StoreRspDL(var Code:TX64Code);
begin
  Emit(Code,#$88#$14#$24);
end;

procedure X64Syscall(var Code:TX64Code);
begin
  Emit(Code,#$0F#$05);
end;

{ Нові G6.95 host-механізми; pinned D5:01000 перевіряє caller.
  TEST/SETE/MOVZX — лише x86-64, а не власний закон про нуль. }
procedure X64TestEAX(var Code:TX64Code);
begin
  Emit(Code,#$85#$C0);
end;

procedure X64SetEAL(var Code:TX64Code);
begin
  Emit(Code,#$0F#$94#$C0);
end;

procedure X64MovzxEAXAL(var Code:TX64Code);
begin
  Emit(Code,#$0F#$B6#$C0);
end;

{ RIP-relative fixup указує на ПЕРШИЙ з чотирьох байтів disp32.
  Виклик не публікує ELF: підстановка відбувається лише після
  побудови повної машини й перевірки геометрії. }
procedure X64LeaRSIRip(var Code:TX64Code;out FixupPos:SizeInt);
begin
  FixupPos:=Length(Code.Bytes)+3;
  Emit(Code,#$48#$8D#$35#0#0#0#0);
end;

procedure X64LoadDLRSIRAX(var Code:TX64Code);
begin
  Emit(Code,#$8A#$14#$06);
end;

procedure X64PatchRIP32(var Code:TX64Code;FixupPos,TargetOffset:SizeInt);
var Distance:Int64; Encoded:QWord; Candidate:RawByteString; I:SizeInt;
begin
  Demand((FixupPos>=3) and (FixupPos<=Length(Code.Bytes)-4) and
         (Copy(Code.Bytes,FixupPos-2,3)=#$48#$8D#$35),
         'RIP fixup не вказує на LEA RSI,[RIP+disp32]');
  Demand((TargetOffset>=0) and (TargetOffset<=MaxCodeBytes),
         'RIP ціль поза host-квотою');
  Demand(Copy(Code.Bytes,FixupPos+1,4)=#0#0#0#0,
         'RIP fixup уже застосовано або непорожній');
  Distance:=Int64(TargetOffset)-Int64(FixupPos+4);
  Demand((Distance>=Low(LongInt)) and (Distance<=High(LongInt)),
         'RIP signed disp32 поза діапазоном');
  Encoded:=QWord(Distance) and $FFFFFFFF;
  Candidate:=Copy(Code.Bytes,1,Length(Code.Bytes));
  for I:=0 to 3 do begin
    Candidate[FixupPos+I+1]:=AnsiChar(Byte(Encoded and $FF));
    Encoded:=Encoded shr 8;
  end;
  Code.Bytes:=Candidate;
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
