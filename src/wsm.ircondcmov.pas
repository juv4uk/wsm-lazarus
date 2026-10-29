{ G6.116 — одна повна фізична D3:110 → verified ExactIR → x86-64
  CMP/SETE/CMOVNE/CMOVE → ELF64 PIE → pinned T5M.
  Семантичний допуск/закон: ТІЛЬКИ LowerPinnedIRCond із pinned SENS.
  Підмножина: рівно ОДНА двопольова гілка, її тест/вираз —
  exact D1:0/1 або D3:101 з двома exact D1. Операнди чисті,
  тому спекулятивне обчислення обох не має побічного ефекту.
  Вхід: borrowed packed фізичний RawByteString і pinned root.
  Вихід: owned RawByteString ELF64 PIE; жоден образ не публікується
  до повного admission і перевірки геометрії. Локальний TX64Code
  володіє тимчасовими байтами, живе лише протягом виклику.
  CPU-регістри, CMOV opcode та signed displacement НЕ є Dn законами.
  D3:000 завжди залишається окремим від D1:0.

  Питання:
  1) Чому не можна переплутати D3:000 та D1:0?
  2) Хто допускає точну викличність D3:110/D3:101?
  3) Чому CMP/CMOV не запроваджує новий SENS закон?
  4) Чому спекулятивний вираз безпечний ЛИШЕ в цьому профілі?
  5) Навіщо окремо виконувати ELF та незалежний SENS oracle? }
unit wsm.ircondcmov;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRCondCMovError=class(Exception);
function BuildPinnedIRCondCMovELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.ircond,wsm.x64code,wsm.x64alu,wsm.x64cmov,wsm.t5m,
     wsm.elfgeometry;
const HeaderBytes=120;
      MaxCodeBytes=256;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRCondCMovError.Create(Why);
end;
procedure Emit(var C:TX64Code;const Bytes:RawByteString);
begin
  Need((Length(Bytes)>0) and (Length(C.Bytes)<=MaxCodeBytes-Length(Bytes)),
       'Переповнено host-квоту машинного коду 256 байтів');
  C.Bytes:=C.Bytes+Bytes;
end;
procedure EmitValue(var C:TX64Code;const V:TIRCondValue);
begin
  Need((V.Kind<=1) and (V.LeftBit<=1) and (V.RightBit<=1),
       'Пошкоджено вже допущене D1/EQ значення');
  X64MovImm32(C,xrAX,V.LeftBit);
  if V.Kind=1 then begin
    X64MovImm32(C,xrCX,V.RightBit);
    X64ALU32(C,xaCmp,xrAX,xrCX);
    X64SetEAL(C);
    X64MovzxEAXAL(C);
  end;
end;
procedure PutLE(var Image:RawByteString;Offset:SizeInt;
                Value:QWord;Count:SizeInt);
var J:SizeInt;
begin
  Need((Offset>=0) and (Count>=1) and (Count<=8) and
       (Offset<=Length(Image)-Count),'Поле ELF поза фізичним образом');
  for J:=0 to Count-1 do begin
    Image[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;
function MakePIE(const C:TX64Code):RawByteString;
var Size,J:SizeInt; Geometry:TELFGeometry;
begin
  Need((Length(C.Bytes)>0) and (Length(C.Bytes)<=MaxCodeBytes),
       'Непридатна довжина нативного коду');
  Size:=HeaderBytes+Length(C.Bytes);
  SetLength(Result,Size);
  FillChar(Result[1],Size,0);
  PutLE(Result,0,$464C457F,4);
  PutLE(Result,4,2,1);PutLE(Result,5,1,1);PutLE(Result,6,1,1);
  PutLE(Result,16,3,2);PutLE(Result,18,62,2);PutLE(Result,20,1,4);
  PutLE(Result,24,HeaderBytes,8);PutLE(Result,32,64,8);
  PutLE(Result,52,64,2);PutLE(Result,54,56,2);PutLE(Result,56,1,2);
  PutLE(Result,64,1,4);PutLE(Result,68,5,4);
  PutLE(Result,80,0,8);PutLE(Result,88,0,8);
  PutLE(Result,96,Size,8);PutLE(Result,104,Size,8);
  PutLE(Result,112,$1000,8);
  for J:=1 to Length(C.Bytes) do Result[HeaderBytes+J]:=C.Bytes[J];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and
       (Geometry.MachineBytes=Length(C.Bytes)) and
       (Geometry.FileBytes=Size),'PIE геометрія не підтверджена');
end;
function BuildPinnedIRCondCMovELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Lowered:TLoweredIRCond;
  C:TX64Code;
  Words:TExactWords;
  ZeroByte,OneByte,EmptyByte:RawByteString;
begin
  Result:='';
  try
    { Жодного дублювання parser/binder/ratified law. }
    LowerPinnedIRCond(Physical,AuthorityRoot,Lowered);
    Need(Lowered.Count=1,'CMOV-зріз допускає рівно одну двопольову D3-гілку');
    SetLength(Words,1);
    Words[0]:='0'; ZeroByte:=EncodeT5M(Words);
    Words[0]:='1'; OneByte:=EncodeT5M(Words);
    Words[0]:='000'; EmptyByte:=EncodeT5M(Words);
    Need((Length(ZeroByte)=1) and (Length(OneByte)=1) and
         (Length(EmptyByte)=1) and (ZeroByte<>OneByte) and
         (ZeroByte<>EmptyByte) and (OneByte<>EmptyByte),
         'Неоднозначні канонічні D1/D3 фізичні результати');
    X64Reset(C);
    { Обчислити тест на CPU, зберегти D1-біт у EBP. }
    EmitValue(C,Lowered.Clauses[0].TestValue);
    Emit(C,#$89#$C5); { MOV EBP,EAX; не змінює FLAGS }
    { Точний вираз обчислюється на CPU: дозволено лише pure D1/EQ. }
    EmitValue(C,Lowered.Clauses[0].ExpressionValue);
    { Спочатку вибрати T5M D1:0 або D1:1 за результатом виразу. }
    X64MovImm32(C,xrBX,Ord(EmptyByte[1])); { default D3:000 }
    X64MovImm32(C,xrCX,Ord(ZeroByte[1]));
    X64MovImm32(C,xrDX,Ord(OneByte[1]));
    X64TestEAX(C);
    X64CMov32(C,5,xrCX,xrDX); { CMOVNE ECX,EDX: D1 expression }
    { Лише D1:1 тесту дозволяє заміну структурної D3:000. }
    Emit(C,#$83#$FD#$01);   { CMP EBP,exact D1:1 }
    X64CMov32(C,4,xrBX,xrCX); { CMOVE EBX,ECX }
    X64SubRsp8(C,8);
    Emit(C,#$88#$1C#$24); { MOV BYTE PTR [RSP], BL }
    X64MovImm32(C,xrAX,1); { write(stdout, rsp, 1) }
    X64MovImm32(C,xrDI,1);
    X64MovRSIRsp(C);
    X64MovImm32(C,xrDX,1);
    X64Syscall(C);
    X64MovImm32(C,xrAX,60); { exit(0) }
    X64XorEDI(C);
    X64Syscall(C);
    Result:=MakePIE(C);
  except
    on E:Exception do begin
      Result:='';
      raise EIRCondCMovError.Create('D3-CMOV-ВІДМОВА: '+E.Message);
    end;
  end;
end;
end.
