{ G6.97. Два конкретні native D6-компілятори: 110100 «не-більше?» і
  110110 «не-менше?». Закони тільки pinned SENS 12/D6; це НЕ реєстр
  законів та НЕ загальний SENS compiler. Перші backend уже виконують
  фізичні D12 admission і повертають перевірений ELF64 з T5M D1.
  Замінюємо рівно один машинний SETcc після суворого proof шаблону;
  жодна відповідь не обчислюється у Pascal. }
unit wsm.elfd6mezhy;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED6MezhyELFError=class(Exception);
function BuildD6NotGreaterELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
function BuildD6NotLessELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.elfd12greater,wsm.elfd12less,wsm.elfgeometry;
const HeaderBytes=120;

procedure Need(Valid:Boolean;const Why:String);
begin
  if not Valid then raise ED6MezhyELFError.Create(Why);
end;

{ Image — власні FPC managed bytes, які копіюються за copy-on-write.
  Offset — 1-based позиція ЛИШЕ машинного opcode, не D6 адреса.
  before/after — host x86-64 SETcc, не opcode мови SENS.
  Кандидат публікується лише після двох перевірок ELF-геометрії.
  1) Чому байт SETcc не є словом SENS?
  2) Яка перевірка не допускає патч невідомої версії backend?
  3) Чому не можна замінити D1 на Pascal Boolean?
  4) Хто володіє пам'яттю Image та її результатом? }
procedure PatchOneSetCC(var Image:RawByteString;OpcodeOffset:SizeInt;
                        const Original,Replacement,ExpectedPrefix:RawByteString);
var G:TELFGeometry;
begin
  Need(Length(Image)>=HeaderBytes+32,'надто короткий машинний ELF');
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Image)),'непідтверджений ELF64 PIE');
  Need(Copy(Image,HeaderBytes+1,Length(ExpectedPrefix))=ExpectedPrefix,
    'змінився машинний пролог джерельного backend');
  Need((Length(Original)=3) and (Length(Replacement)=3) and
       (OpcodeOffset>=HeaderBytes+1) and
       (OpcodeOffset+2<=Length(Image)),'поза межами x86 opcode');
  Need(Copy(Image,OpcodeOffset,3)=Original,
    'не знайдено точний машинний SETcc шаблон');
  Need(Copy(Image,OpcodeOffset+3,3)=#$0F#$B6#$C0,
    'порушено суміжний MOVZX після машинного порівняння');
  Image[OpcodeOffset+1]:=Replacement[2]; { 0F, opcode, C0 }
  Need(Copy(Image,OpcodeOffset,3)=Replacement,'машинний патч не атомарний');
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.FileBytes=Length(Image)),
    'пошкоджено ELF після заміни SETcc');
end;

{ Left/Right: borrowed canonical packed W12 .sens, ідентичність
  підтверджує наявний ReadNumericPhysical усередині original backend.
  Result: owned ET_DYN bytes, під час запуску x86 SETLE обирає D1.
  1) Чому SETLE є запереченням signed SETG, включно з рівністю?
  2) Де перевіряється точність D12 та канонічний T5M?
  3) Чому native ELF не містить заздалегідь обчисленої відповіді? }
function BuildD6NotGreaterELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
begin
  Result:=BuildD12GreaterELF(LeftPhysical,RightPhysical);
  { mov eax,A; mov ecx,B; cmp eax,ecx; setg al; movzx eax,al }
  PatchOneSetCC(Result,133,#$0F#$9F#$C0,#$0F#$9E#$C0,
                #$B8);
end;

{ Аналогічно signed SETGE заперечує SETL. Рівні D12 дають D1:1.
  1) Чому беззнакове SETAE тут було б неправильним?
  2) Який саме фізичний діапазон W12 приймає джерельний backend?
  3) Чому зміна фіксованого шаблону обов'язково має падати? }
function BuildD6NotLessELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
begin
  Result:=BuildD12LessELF(LeftPhysical,RightPhysical);
  { mov eax,A; cmp eax,B; setl al; movzx eax,al }
  PatchOneSetCC(Result,131,#$0F#$9C#$C0,#$0F#$9D#$C0,
                #$B8);
end;
end.
