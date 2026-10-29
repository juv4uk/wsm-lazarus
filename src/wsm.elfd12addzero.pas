{ G6.85 — фізична композиція D5:01010 та D5:01000 у одному ELF64.
  Ніякого нового SENS-резидента: це вузький механізм pinned профілю
  Intel x86-64, не host-evaluator. Точний D1:0/1 — тільки T5M.
  Контракт: external/sens@1f1bf676... D5, numeric D12, CPU profile.
  Питання: чому тут немає локального закону нуля?
  Чому проміжний результат не можна неявно звузити з D24?
  Чому D1 істина не є Pascal boolean?
  Чому підстановка байтів до першої RIP-адресації не змінює displacement?
  Чому для готового ELF виконуємо незалежний структурний guard? }
unit wsm.elfd12addzero;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EAddZeroELFError=class(Exception);
function BuildD12AddZeroELF(const APhysical,BPhysical:RawByteString):RawByteString;
implementation
uses wsm.numericadd,wsm.elfd12add,wsm.elfd12zero,wsm.elfgeometry;

const HeaderBytes=120;
      InitialMovBytes=5;
      AddInstructionBytes=5;

procedure Need(OK:Boolean;const MessageText:String);
begin
  if not OK then raise EAddZeroELFError.Create(MessageText);
end;

{ Image — власні фізичні ELF-байти, Offset — host little endian ELF64
  p_filesz/p_memsz. Вхід і вихід НЕ мовні слова SENS.
  1) Що означає borrowed image для цієї процедури?
  2) Чому два поля довжини ELF змінюються одночасно?
  3) Чому заборонено писати поза фізичними байтами? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
    'поле машинного ELF виходить за межі');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ APhysical/BPhysical borrowed canonical T5M D12, Result owned ELF64 PIE.
  Чинний ADD-emitter допускає D12 і генерує MOV EAX,imm; ADD EAX,imm.
  Чинний ZERO-emitter допускає суму і генерує MOV EAX,sum; TEST EAX,EAX;
  SETE AL; MOVZX EAX,AL; D1 lookup + Linux write(1,buf,1).
  Замінюємо лише початковий MOV у ZERO-програмі 10-байтовим MOV+ADD,
  отриманим безпосередньо з перевіреного ADD-emitter. Компонування до
  першого RIP-relative LEA пересуває LEA і таблицю на однакові 5 байтів.
  Вихід D1 обчислює процесор; у ELF немає literal "істина/хиба".
  1) Де перевіряється відмова D12→D24 проміжного значення?
  2) Чому не можна з'єднати два ELF заголовки?
  3) Чому не підставляємо готовий D1, відомий host-компілятору?
  4) Як перевірка префікса захищає від зміни попередніх emitter-ів?
  5) Яке джерело байтів D1 lookup — не Pascal boolean? }
function BuildD12AddZeroELF(const APhysical,BPhysical:RawByteString):RawByteString;
var Addition,ZeroImage,Intermediate:RawByteString;
    AddGeometry,ZeroGeometry,FinalGeometry:TELFGeometry;
    OldLength:SizeInt;
begin
  Result:='';
  Addition:=BuildD12AddELF(APhysical,BPhysical);
  Intermediate:=AddNumericPhysical(APhysical,BPhysical,12);
  ZeroImage:=BuildD12ZeroELF(Intermediate);
  VerifySENSELF64(Addition,AddGeometry);
  VerifySENSELF64(ZeroImage,ZeroGeometry);
  Need((AddGeometry.Kind=3) and (ZeroGeometry.Kind=3) and
    (AddGeometry.Entry=HeaderBytes) and
    (ZeroGeometry.Entry=HeaderBytes),
    'потрібні два допущені ELF64 PIE x86-64');
  Need((Length(Addition)>=HeaderBytes+10) and
    (Length(ZeroImage)>=HeaderBytes+10),
    'неповний машинний prefix');
  Need((Addition[HeaderBytes+1]=#$B8) and
    (Addition[HeaderBytes+6]=#$05) and
    (ZeroImage[HeaderBytes+1]=#$B8) and
    (ZeroImage[HeaderBytes+6]=#$85) and
    (ZeroImage[HeaderBytes+7]=#$C0) and
    (ZeroImage[HeaderBytes+8]=#$0F) and
    (ZeroImage[HeaderBytes+9]=#$94) and
    (ZeroImage[HeaderBytes+10]=#$C0),
    'машинний префікс вже злитих emitter-ів не збігається з профілем');
  OldLength:=Length(ZeroImage);
  Need(OldLength<1024*1024-AddInstructionBytes,'перевищена квота ELF');
  Result:=Copy(ZeroImage,1,HeaderBytes)+
    Copy(Addition,HeaderBytes+1,InitialMovBytes+AddInstructionBytes)+
    Copy(ZeroImage,HeaderBytes+InitialMovBytes+1,
         Length(ZeroImage)-HeaderBytes-InitialMovBytes);
  Need(Length(Result)=OldLength+AddInstructionBytes,
    'втрачено ELF-байти при композиції');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and
    (FinalGeometry.Entry=HeaderBytes) and
    (FinalGeometry.FileBytes=Length(Result)),
    'підсумковий ELF64 не пройшов перевірку геометрії');
end;
end.
