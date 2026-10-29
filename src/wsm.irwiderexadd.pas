{ G6.103 — canonical binary .sens D5 додати: pinned WideIR -> R8/R9.
  Цей адаптер НЕ містить законів D5/D12, не читає назв проєкцій і
  НЕ визначає бібліотечних функцій. Повний admission та перевірене
  складання фізичного D12 виконує BuildIRWideAddRegisterELF.
  Механічно замінюємо тільки машинний пролог: R8/R9 рахують
  64-bit, MOV RAX,R8 віддає молодші 32 біти попередньому verified
  AND EAX,0xfff та T5M writer. Неприпустимий D12 overflow
  відхиляється ДО входу в цей host adapter.
  Вхід: borrowed RawByteString packed binary T5M + шлях pinned SENS.
  Вихід: власний managed RawByteString ELF64 ET_DYN; під час винятку
  Result лишається порожнім. Локальні TX64Code/bytes звільняє FPC.
  1) Чому REX-reg не може бути номером функції D5?
  2) Як mod 4096 лишається точним після MOV RAX,R8?
  3) Де заборонено D12→D24 overflow?
  4) Чому rel32 у хвості можна перенести без зміни?
  5) Який guard не дає змінити чужий machine prefix? }
unit wsm.irwiderexadd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideRexAddError=class(Exception);
function BuildIRWideRexAddELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwideaddreg,wsm.elfgeometry,wsm.x64code,wsm.x64rex;
const
  HeaderBytes=120;
  PreviousBytes=12;
  CurrentBytes=26;

procedure Need(Condition:Boolean;const Why:String);
begin
  if not Condition then
    raise EIRWideRexAddError.Create(Why);
end;

function ReadLE32(const Buffer:RawByteString;Offset:SizeInt):LongWord;
var J:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Buffer)-4),
       'невірне зміщення machine immediate');
  Result:=0;
  for J:=3 downto 0 do
    Result:=(Result shl 8) or LongWord(Byte(Buffer[Offset+J+1]));
end;

procedure WriteLE64(var Buffer:RawByteString;Offset:SizeInt;Value:QWord);
var J:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Buffer)-8),
       'неправильне фізичне ELF64 поле');
  for J:=0 to 7 do begin
    Buffer[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function BuildIRWideRexAddELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Original,Candidate,Prologue:RawByteString;
    Machine:TX64Code;Geometry:TELFGeometry;
    LeftImm,RightImm:LongWord;
begin
  Result:='';
  { ЄДИНИЙ pinned exact-domain + numeric admission; хвіст походить
    із вже доведеного register ALU emitter та його T5M таблиць. }
  Original:=BuildIRWideAddRegisterELF(ProgramPhysical,AuthorityRoot);
  VerifySENSELF64(Original,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=Length(Original)) and
       (Length(Original)>HeaderBytes+PreviousBytes+36),
       'попередній ELF64 вийшов із перевіреного профілю');
  Need((Original[HeaderBytes+1]=#$B8) and
       (Original[HeaderBytes+6]=#$B9) and
       (Original[HeaderBytes+11]=#$01) and
       (Original[HeaderBytes+12]=#$C8) and
       (Original[HeaderBytes+13]=#$25),
       'змінився verified D12 ADD пролог: не переписувати');
  LeftImm:=ReadLE32(Original,HeaderBytes+1);
  RightImm:=ReadLE32(Original,HeaderBytes+6);
  X64Reset(Machine);
  { Zero extend encoded signed D12 machine immediate. Низькі 32 біти
    арифметичної суми однакові; вже перевірений AND EAX,4095
    добирає саме 12 бітів. Це host lowering, не закон SENS. }
  X64RexMovAbs(Machine,wrR8,QWord(LeftImm));
  X64RexMovAbs(Machine,wrR9,QWord(RightImm));
  X64RexReg64(Machine,roAdd,wrR8,wrR9);
  X64RexReg64(Machine,roMove,wrAX,wrR8);
  Prologue:=X64Image(Machine);
  Need((Length(Prologue)=CurrentBytes) and
       (Copy(Prologue,21,3)=#$4D#$01#$C8) and
       (Copy(Prologue,24,3)=#$4C#$89#$C0),
       'машинний REX-пролог не відповідає контракту emitter');
  { Після 12-байтного прологу продовжуємо тим самим AND EAX та
    RIP-relative таблицями. Хвіст разом із усіма target addresses
    зсувається на +14, отже rel32 displacement не змінюється. }
  Candidate:=Copy(Original,1,HeaderBytes)+Prologue+
             Copy(Original,HeaderBytes+PreviousBytes+1,
                  Length(Original)-HeaderBytes-PreviousBytes);
  Need(Length(Candidate)=Length(Original)+CurrentBytes-PreviousBytes,
       'неправильний розмір ELF64 після REX lowering');
  WriteLE64(Candidate,96,QWord(Length(Candidate)));
  WriteLE64(Candidate,104,QWord(Length(Candidate)));
  VerifySENSELF64(Candidate,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=Length(Candidate)),
       'REX-ELF64 не пройшов структурну перевірку');
  Result:=Candidate;
end;
end.
