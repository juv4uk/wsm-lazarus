{ G6.170 — фізичний pinned D5 SUB→IMUL в одному справжньому ELF64.
  Вхід: 3 borrowed canonical packed D12 T5M; результат: owned ELF64 PIE.
  Чинний wsm.numericsub перевіряє проміжний D12, wsm.elfd12sub
  постачає машинний SUB, wsm.elfd12mul постачає машинний IMUL та
  кінцевий T5M writer. Компонування не є новим SENS законом.
  1) Чому проміжний результат має вміщатися в exact D12?
  2) Чому фінальний добуток допускає D24?
  3) Чому перевірка opcode SUB потрібна перед з'єднанням префіксів?
  4) Чому зміщення RIP-таблиць залишається правильним після вставки?
  5) Хто володіє ELF-буфером і звільняє його після повернення? }
unit wsm.elfd12submul;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12SubMulError=class(Exception);
function BuildD12SubMulELF(const FirstPhysical,SecondPhysical,
  ThirdPhysical:RawByteString):RawByteString;
implementation
uses wsm.numericsub,wsm.elfd12sub,wsm.elfd12mul,wsm.elfgeometry;

const HeaderBytes=120;
      MovBytes=5;
      SubBytes=5;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12SubMulError.Create(Why);
end;

{ Borrowed готовий ELF64 образ, owned змінений Result;
  host little-endian p_filesz/p_memsz (offsets 96/104) — не домени SENS.
  1) Навіщо змінювати обидві ELF-розмірності?
  2) Чому відмовляємося від довільного сегмента?
  3) Чи можна використовувати цей код для іншого ISA без перевірки? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
    'поле ELF поза образом');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Two preexisting verified emitters supply ALL executable instructions:
  SubELF starts with MOV EAX,imm32; SUB EAX,imm32 (10 exact bytes).
  MulELF starts with MOV EAX,imm32; IMUL EAX,EAX,imm32.
  We replace MulELF's first MOV with SubELF's MOV+SUB: thus all later
  instructions AND every RIP-relative table move together by +5 bytes.
  Немає нового ISA-кодера чи закону: це тільки композиція перевірених префіксів.
  Kernel sys_write emits one physical T5M atom from the machine result.
  Insertion is before the first RIP-relative LEA and uses no jumps.
  Expected proof comes from the EXISTING D12 admission routines.
  1) Why not concatenate two whole ELF files?
  2) Why does the first MOV of MulELF have to be removed?
  3) Why is a 5-byte displacement-free prefix safe for RIP tables?
  4) What rejects sub overflow before publication?
  5) Why does byte-exact output require executing the resulting ELF? }
function BuildD12SubMulELF(const FirstPhysical,SecondPhysical,
  ThirdPhysical:RawByteString):RawByteString;
var Difference,Multiplication,Intermediate:RawByteString;
    SubGeometry,MulGeometry,FinalGeometry:TELFGeometry;
    OldLength:SizeInt;
begin
  Result:='';
  { Numeric law and exact explicit D12 belong to existing emitters. }
  Difference:=BuildD12SubELF(FirstPhysical,SecondPhysical);
  Intermediate:=SubtractNumericPhysical(FirstPhysical,SecondPhysical,12);
  Multiplication:=BuildD12MulELF(Intermediate,ThirdPhysical);
  VerifySENSELF64(Difference,SubGeometry);
  VerifySENSELF64(Multiplication,MulGeometry);
  Need((SubGeometry.Kind=3) and (MulGeometry.Kind=3) and
    (SubGeometry.Entry=HeaderBytes) and
    (MulGeometry.Entry=HeaderBytes),
    'композиція вимагає два перевірені x86-64 PIE профілі');
  Need((Length(Difference)>=HeaderBytes+MovBytes+SubBytes) and
    (Length(Multiplication)>=HeaderBytes+MovBytes+6),
    'занадто короткий машинний код');
  Need((Difference[HeaderBytes+1]=#$B8) and
    (Difference[HeaderBytes+6]=#$2D) and
    (Multiplication[HeaderBytes+1]=#$B8) and
    (Multiplication[HeaderBytes+6]=#$69) and
    (Multiplication[HeaderBytes+7]=#$C0),
    'несподіваний код префікса злитого D12 emitter');
  OldLength:=Length(Multiplication);
  Need(OldLength<1024*1024-SubBytes,'ELF перевищує квоту');
  { Header із злитого множника; 10 байтів обчислення різниці із злитого
    віднімача; увесь перевірений IMUL+T5M writer+RIP tables із множника. }
  Result:=Copy(Multiplication,1,HeaderBytes)+
    Copy(Difference,HeaderBytes+1,MovBytes+SubBytes)+
    Copy(Multiplication,HeaderBytes+MovBytes+1,
      Length(Multiplication)-HeaderBytes-MovBytes);
  Need(Length(Result)=OldLength+SubBytes,'втрата фізичних ELF байтів');
  PutLE64(Result,96,Length(Result)); { PT_LOAD p_filesz }
  PutLE64(Result,104,Length(Result));{ PT_LOAD p_memsz  }
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and
    (FinalGeometry.Entry=HeaderBytes) and
    (FinalGeometry.FileBytes=Length(Result)),
    'невдалий допуск злитого машинного ELF64');
end;
end.
