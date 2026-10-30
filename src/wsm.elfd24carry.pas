{ G6.252 — вузький AOT для двох фізичних D24 у Linux ELF64.
  Мовне право на додавання не виводимо з host opcode: перевірка фізичних
  D24 і очікуваної ширини належить pinned механізму wsm.numericadd.
  Кодер лише переносить 16-bit carry через ADD→ADC (32-bit CF).
  Вхід: дві позичені canonical T5M-атомні строки та managed пам'ять.
  Вихід: власні ELF64 PIE-байти з реальним обчисленням і T5M stdout;
  Result публікуємо лише після повної перевірки.
  1) Чому lower16 треба зсунути на 16 перед ADD?
  2) Чому між ADD та ADC не можна змінювати прапор CF?
  3) Чому ширина D48 — явна відмова, а не обрізання?
  4) Чому таблиці T5M походять з чинного EncodeT5M?
  5) Чому успішний ELF не доводить загальну SENS-викличність? }
unit wsm.elfd24carry;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED24CarryELFError=class(Exception);
function BuildD24CarryAddELF(const LeftPhysical,RightPhysical:RawByteString):
  RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.numericadd,wsm.x64code,
  wsm.x64alu,wsm.x64carry,wsm.x64shift,wsm.x64pie,wsm.elfgeometry;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED24CarryELFError.Create(Why);
end;

{ Exact D24 фізичні біти, не Unicode число; повертаємо тільки host
  unsigned 24-bit container для mov imm32. Поза цим API домен не вгадуємо. }
function Unsigned24(const Bits:RawByteString):LongWord;
var I:Integer;
begin
  Need(Length(Bits)=24,'очікується точний D24');
  Result:=0;
  for I:=1 to 24 do begin
    Need(Bits[I] in ['0','1'],'небінарний біт D24');
    Result:=(Result shl 1) or LongWord(Ord(Bits[I])-Ord('0'));
  end;
end;

{ Число Value — лише host індекс 5/4-бітового T5M lookup.
  Двійковий текст віддаємо вже існуючому фізичному EncodeT5M. }
function PackedChunk(Width,Value:Integer):AnsiChar;
var Bits,Raw:RawByteString;Words:TExactWords;I:Integer;
begin
  Need((Width in [4,5]) and (Value>=0) and (Value<(1 shl Width)),
    'T5M lookup поза фізичними межами');
  SetLength(Bits,Width);
  for I:=1 to Width do
    if (Value and (1 shl (Width-I)))<>0 then Bits[I]:='1'
    else Bits[I]:='0';
  SetLength(Words,1);
  Words[0]:=Bits;
  Raw:=EncodeT5M(Words);
  Need(Length(Raw)=1,'фізичне T5M слово W4/W5 має бути одним байтом');
  Result:=Raw[1];
end;

function BuildD24CarryAddELF(const LeftPhysical,RightPhysical:RawByteString):
  RawByteString;
var L,R,V:TExplicitNumeric;
    Expected,Table5,Table4,Machine:RawByteString;
    A,B:LongWord;I,At:Integer;
    Code:TX64Code;
    Fix:array[0..4] of SizeInt;
    TableStart:SizeInt;
    Geometry:TELFGeometry;
begin
  Result:='';
  L:=ReadNumericPhysical(LeftPhysical,24);
  R:=ReadNumericPhysical(RightPhysical,24);
  Expected:=AddNumericPhysical(LeftPhysical,RightPhysical,24);
  { D24+D24 → D48 переповнення тут ЗАБОРОНЕНО до emission:
    новий backend підтримує лише точний D24, не вводячи D48 law. }
  Need(Length(Expected)=5,'очікуваний T5M D24 має п’ять байтів');
  try
    V:=ReadNumericPhysical(Expected,24);
  except
    on E:Exception do
      raise ED24CarryELFError.Create('D24→D48 не підтримано: '+E.Message);
  end;
  Need(Length(V.ExactBits)=24,'отримано не D24 результат');
  A:=Unsigned24(L.ExactBits);
  B:=Unsigned24(R.ExactBits);
  X64Reset(Code);
  { Обидва low16 у верхніх половинах r32: CF з ADD точно відповідає
    переходу через біт 16. Верхні 8 біт підсумовує тільки ADC.
    Stack/CPU живуть до syscall exit, Code — managed FPC caller. }
  X64MovImm32(Code,xrAX,(A and $FFFF) shl 16);
  X64MovImm32(Code,xrCX,(B and $FFFF) shl 16);
  X64MovImm32(Code,xrDX,A shr 16);
  X64MovImm32(Code,xrBX,B shr 16);
  X64ALU32(Code,xaAdd,xrAX,xrCX);
  X64Carry32(Code,xcAdc,xrDX,xrBX);
  X64ShiftImm32(Code,xsShr,xrAX,16);
  X64ShiftImm32(Code,xsShl,xrDX,16);
  X64ALU32(Code,xaOr,xrAX,xrDX);

  { EAX тепер містить справжній 24-bit machine результат.
    Послідовні 5/5/5/5/4 біти беруться з нього, а НЕ з Expected.
    Таблиці — лише T5M transport, виконуваний розрахунок не fold-иться. }
  X64SubRsp8(Code,8);
  for I:=0 to 4 do begin
    Code.Bytes:=Code.Bytes+#$89#$C1; { mov ecx,eax, без змін EAX }
    if I<4 then begin
      Code.Bytes:=Code.Bytes+#$C1#$E9+
        AnsiChar(Byte(19-5*I)); { shr ecx,19/14/9/4 }
      Code.Bytes:=Code.Bytes+#$83#$E1#$1F; { and ecx,31 }
    end else
      Code.Bytes:=Code.Bytes+#$83#$E1#$0F; { and ecx,15 }
    X64LeaRSIRip(Code,Fix[I]);
    Code.Bytes:=Code.Bytes+#$8A#$14#$0E;  { mov dl,[rsi+rcx] }
    if I=0 then Code.Bytes:=Code.Bytes+#$88#$14#$24
    else Code.Bytes:=Code.Bytes+#$88#$54#$24+AnsiChar(I);
  end;
  X64MovImm32(Code,xrAX,1);
  X64MovImm32(Code,xrDI,1);
  X64MovRSIRsp(Code);
  X64MovImm32(Code,xrDX,5);
  X64Syscall(Code);
  Code.Bytes:=Code.Bytes+#$48#$83#$F8#$05; { cmp rax,5 }
  Code.Bytes:=Code.Bytes+#$75#$09;           { jne exit(2) }
  X64MovImm32(Code,xrAX,60);
  X64XorEDI(Code);
  X64Syscall(Code);
  X64MovImm32(Code,xrAX,60);
  X64MovImm32(Code,xrDI,2);
  X64Syscall(Code);

  Table5:='';Table4:='';
  for I:=0 to 31 do Table5:=Table5+PackedChunk(5,I);
  for I:=0 to 15 do Table4:=Table4+PackedChunk(4,I);
  Need((Length(Table5)=32) and (Length(Table4)=16),
    'неповні canonical T5M transport таблиці');
  TableStart:=Length(Code.Bytes);
  Need((TableStart+48<=256) and (TableStart>0),
    'машинне тіло з таблицями перевищує 256 байтів');
  Code.Bytes:=Code.Bytes+Table5+Table4;
  for I:=0 to 3 do X64PatchRIP32(Code,Fix[I],TableStart);
  X64PatchRIP32(Code,Fix[4],TableStart+32);
  Machine:=X64Image(Code);
  Result:=BuildX64PIE(Code);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.MachineBytes=Length(Machine)) and
       (Copy(Result,121,Length(Machine))=Machine),
       'ELF64 PIE не зберіг точні machine bytes');
end;
end.
