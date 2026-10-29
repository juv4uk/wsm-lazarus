{ G6.80: один нативний ELF64 із двома вже перевіреними машинними
  діями ADD→IMUL для трьох фізичних D12-атомів.
  Не створює нового SENS резидента, правила арифметики чи D7 dispatch:
  це тільки вузька host-композиція двох злитих native emitter-ів.
  SENS авторитет: pinned Contract12, D5(01010,10110) і числові домени.
  Питання: чому тут немає нового SENS opcode?
  Чому проміжна сума обов'язково W12?
  Чому переміщення code+tables на 5 байтів не ламає RIP?
  Чому реальний результат не можна замінити готовим T5M literal?
  Хто володіє двома вихідними ELF і фізичними буферами? }
unit wsm.elfd12addmul;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12AddMulError=class(Exception);
function BuildD12AddMulELF(const FirstPhysical,SecondPhysical,
  ThirdPhysical:RawByteString):RawByteString;
implementation
uses wsm.numericadd,wsm.elfd12add,wsm.elfd12mul,wsm.elfgeometry;

const HeaderBytes=120;
      MovBytes=5;
      AddBytes=5;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12AddMulError.Create(Why);
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
  AddELF starts with MOV EAX,imm32; ADD EAX,imm32 (10 exact bytes).
  MulELF starts with MOV EAX,imm32; IMUL EAX,EAX,imm32.
  We replace MulELF's first MOV with AddELF's MOV+ADD: thus all later
  instructions AND every RIP-relative table move together by +5 bytes.
  No new ISA instruction encoder, no extra numeric law, no interpreter.
  Kernel sys_write emits one physical T5M atom from the machine result.
  Insertion is before the first RIP-relative LEA and uses no jumps.
  Expected proof comes from the EXISTING D12 admission routines.
  1) Why not concatenate two whole ELF files?
  2) Why does the first MOV of MulELF have to be removed?
  3) Why is a 5-byte displacement-free prefix safe for RIP tables?
  4) What rejects add overflow before publication?
  5) Why does byte-exact output require executing the resulting ELF? }
function BuildD12AddMulELF(const FirstPhysical,SecondPhysical,
  ThirdPhysical:RawByteString):RawByteString;
var Addition,Multiplication,Intermediate:RawByteString;
    AddGeometry,MulGeometry,FinalGeometry:TELFGeometry;
    OldLength:SizeInt;
begin
  Result:='';
  { Numeric law and exact explicit D12 belong to existing emitters. }
  Addition:=BuildD12AddELF(FirstPhysical,SecondPhysical);
  Intermediate:=AddNumericPhysical(FirstPhysical,SecondPhysical,12);
  Multiplication:=BuildD12MulELF(Intermediate,ThirdPhysical);
  VerifySENSELF64(Addition,AddGeometry);
  VerifySENSELF64(Multiplication,MulGeometry);
  Need((AddGeometry.Kind=3) and (MulGeometry.Kind=3) and
    (AddGeometry.Entry=HeaderBytes) and
    (MulGeometry.Entry=HeaderBytes),
    'композиція вимагає два перевірені x86-64 PIE профілі');
  Need((Length(Addition)>=HeaderBytes+MovBytes+AddBytes) and
    (Length(Multiplication)>=HeaderBytes+MovBytes+6),
    'занадто короткий машинний код');
  Need((Addition[HeaderBytes+1]=#$B8) and
    (Addition[HeaderBytes+6]=#$05) and
    (Multiplication[HeaderBytes+1]=#$B8) and
    (Multiplication[HeaderBytes+6]=#$69) and
    (Multiplication[HeaderBytes+7]=#$C0),
    'несподіваний код префікса злитого D12 emitter');
  OldLength:=Length(Multiplication);
  Need(OldLength<1024*1024-AddBytes,'ELF перевищує квоту');
  { Header із злитого множника; 10 байтів обчислення суми із злитого
    додавача; увесь перевірений IMUL+T5M writer+RIP tables із множника. }
  Result:=Copy(Multiplication,1,HeaderBytes)+
    Copy(Addition,HeaderBytes+1,MovBytes+AddBytes)+
    Copy(Multiplication,HeaderBytes+MovBytes+1,
      Length(Multiplication)-HeaderBytes-MovBytes);
  Need(Length(Result)=OldLength+AddBytes,'втрата фізичних ELF байтів');
  PutLE64(Result,96,Length(Result)); { PT_LOAD p_filesz }
  PutLE64(Result,104,Length(Result));{ PT_LOAD p_memsz  }
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and
    (FinalGeometry.Entry=HeaderBytes) and
    (FinalGeometry.FileBytes=Length(Result)),
    'невдалий допуск злитого машинного ELF64');
end;
end.
