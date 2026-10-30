{ G6.85 — механізм компіляції двох ратифікованих D6 предикатів:
  D6:010000 парне? / D6:010001 непарне? над одним exact D12.
  Pinned SENS Contract 12 є єдиним семантичним авторитетом.
  Машинні TEST/SETE/SETNE не є новими законами мови. }
unit wsm.elfd6parnist;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type
  ED6ParnistError = class(Exception);
{ Physical: borrowed raw canonical packed T5M D12; IsOdd: host напрямок
  між ДВОМА вже ratified координатами D6, не текстове визначення функції.
  Result — новий managed RawByteString ELF64 ET_DYN, зі справжнім x86.
  Немає побічних ефектів, потоків, глобального стану або власних ресурсів. }
function BuildD6ParnistELF(const Physical:RawByteString;
  IsOdd:Boolean):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.elfgeometry;
const
  HeaderBytes=120;

procedure Need(Ok:Boolean;const Why:RawByteString);
begin
  if not Ok then raise ED6ParnistError.Create(Why);
end;

{ Вхід — точні 12 бітів з уже підтвердженого D12 admission.
  Повертає 32-бітове знакове механічне immediate, збережено bit0.
  Жоден host integer не є канонічним SENS значенням.
  1) Навіщо перевіряти усі 12 бітів?
  2) Чому старший біт D12 знаковий?
  3) Чому D1:1 не допускається як числовий операнд? }
function Immediate12(const Bits:RawByteString):LongInt;
var I,V:LongInt;
begin
  Need(Length(Bits)=12,'потрібна точна ширина D12');
  V:=0;
  for I:=1 to 12 do begin
    Need(Bits[I] in ['0','1'],'пошкоджений двійковий D12');
    V:=V*2+Ord(Bits[I])-Ord('0');
  end;
  if Bits[1]='1' then Result:=V-4096 else Result:=V;
end;

{ Один canonical D1 T5M byte для кожної ратифікованої відповіді.
  Ці host-байти дає лише вже існуючий wsm.t5m, не власний encoder.
  1) Чому два байти — лише lookup, а не новий SENS-регістр?
  2) Чому D3:000 не може бути значенням предиката?
  3) Хто звільняє Words/Encoded? }
function D1Byte(Bit:AnsiChar):AnsiChar;
var Words:TExactWords; Encoded:RawByteString;
begin
  Need(Bit in ['0','1'],'невірний D1');
  SetLength(Words,1);Words[0]:=Bit;
  Encoded:=EncodeT5M(Words);
  Need(Length(Encoded)=1,'D1 T5M має один фізичний байт');
  Result:=Encoded[1];
end;

{ Результат: ELF64 PIE зі справжньою оцінкою парності у процесорі.
  TEST rax,1 читає лише молодший біт; SETE/SETNE відповідають
  двом різним pinned D6 координатам, вибраним explicit host mode.
  MOVZX робить внутрішній індекс 0 або 1; canonical D1 output
  пакується винятково таблицею з EncodeT5M. Precomputed output немає.
  Власність: результат FPC-managed, стек буферу належить ОС, RWX нема.
  1) Як довести, що machine TEST виконується, а не host precompute?
  2) Чому знакові від'ємні цілі мають ту саму bit0 парність?
  3) Як не змішати координату D6 з числовим D12?
  4) Чому RIP-rel relocation має перевірку межі?
  5) Чому ELF geometry перевіряється до публікації? }
function BuildD6ParnistELF(const Physical:RawByteString;
  IsOdd:Boolean):RawByteString;
var Number:TExplicitNumeric; Value:LongInt;
    Code,Table:RawByteString;
    LeaAt,CodeBytes,I:SizeInt;
    Geometry:TELFGeometry;
  procedure Emit(const B:RawByteString);
  begin
    Code:=Code+B;
    Need(Length(Code)<4096,'машинний код поза host-лімітом');
  end;
  procedure Emit32(V:LongWord);
  var K:SizeInt;
  begin
    for K:=0 to 3 do begin Emit(AnsiChar(V and $FF));V:=V shr 8 end;
  end;
  procedure Patch32(var B:RawByteString;At:SizeInt;V:LongWord);
  var K:SizeInt;
  begin
    Need((At>=0) and (At+4<=Length(B)),'RIP relocation поза кодом');
    for K:=0 to 3 do begin
      B[At+K+1]:=AnsiChar(V and $FF);
      V:=V shr 8;
    end;
  end;
  procedure Put(At:SizeInt;V:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Need((At>=0) and (Count>0) and (Count<=8) and
      (At+Count<=Length(Result)),'ELF поле поза образом');
    for K:=0 to Count-1 do begin
      Result[At+K+1]:=AnsiChar(V and $FF);
      V:=V shr 8;
    end;
  end;
begin
  Result:='';
  Number:=ReadNumericPhysical(Physical,12);
  Need(Number.DomainWidth=12,'не підтверджено явний D12');
  Value:=Immediate12(Number.ExactBits);
  Table:=D1Byte('0')+D1Byte('1');
  Need(Length(Table)=2,'неповна фізична D1 таблиця');
  Code:='';
  Emit(#$B8);Emit32(LongWord(Value)); { mov eax,signed D12 immediate }
  Emit(#$48#$F7#$C0#$01#0#0#0); { test rax,0x1: REX.W F7 /0 imm32, pinned ISA }
  if IsOdd then Emit(#$0F#$95#$C0) { setne al }
  else Emit(#$0F#$94#$C0);         { sete al }
  Emit(#$0F#$B6#$C0);              { movzx eax,al — byte→0/1 }
  LeaAt:=Length(Code);
  Emit(#$48#$8D#$35#0#0#0#0);      { lea rsi,[rip+D1 table] }
  Emit(#$8A#$14#$06);              { mov dl,[rsi+rax] }
  Emit(#$48#$83#$EC#$08);          { sub rsp,8 — stack buffer }
  Emit(#$88#$14#$24);              { mov [rsp],dl }
  Emit(#$B8#$01#0#0#0);            { sys_write(fd=1,buf=rsp,n=1) }
  Emit(#$BF#$01#0#0#0);
  Emit(#$48#$89#$E6);
  Emit(#$BA#$01#0#0#0);
  Emit(#$0F#$05);
  Emit(#$B8#$3C#0#0#0);            { sys_exit(0) }
  Emit(#$31#$FF#$0F#$05);
  CodeBytes:=Length(Code);
  Patch32(Code,LeaAt+3,LongWord(CodeBytes-(LeaAt+7)));
  SetLength(Result,HeaderBytes+CodeBytes+Length(Table));
  FillChar(Result[1],Length(Result),0);
  Put(0,$464C457F,4); Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Length(Result),8);Put(104,Length(Result),8);Put(112,$1000,8);
  for I:=1 to CodeBytes do Result[HeaderBytes+I]:=Code[I];
  for I:=1 to Length(Table) do Result[HeaderBytes+CodeBytes+I]:=Table[I];
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and
    (Geometry.FileBytes=Length(Result)) and
    (Geometry.Entry=HeaderBytes),'непідтверджений ELF64 PIE');
end;
end.
