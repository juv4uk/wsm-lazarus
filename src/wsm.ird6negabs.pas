{ G6.181 — фізичне вкладення pinned D6:010011(D6:010010(D12))
  через точний WideIR у єдиний реальний Linux x86-64 ELF64 PIE.
  Не додає SENS закону: обидві координати лише з pinned Contract 12.0.
  Машина рахує NEG, CDQ, XOR, SUB; не готову Pascal відповідь. }
unit wsm.ird6negabs;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRNegAbs=class(Exception);
function BuildIRNegAbsELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12abs,wsm.elfgeometry;
const HeaderBytes=120;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRNegAbs.Create(Why) end;

{ IR — borrowed, без виділення додаткових мовних сутностей.
  Структура дерева: [root, D6:abs, inner-list, D6:neg, W12].
  Точні бітові координати та позиції уже звірені pinned binder.
  1) Чому однакова ширина D6 не робить голови тотожними?
  2) Чому wkList внутрішнього виразу є необхідним?
  3) Чому D12 atom ще повинен пройти numeric admission?
  4) Чому заборонені додаткові вкладені вузли? }
procedure CheckNested(const IR:TWideIR;const S:TWideIRGuardStats);
var N:TWideIRNode; I:SizeInt;
begin
  Need((S.Roots=1) and (S.Nodes=5) and
       (S.PhysicalLeaves=3) and (S.OpaqueLeaves=1) and
       (Length(IR.Nodes)=5) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0),'потрібна одна вкладена D6 форма');
  N:=IR.Nodes[0];
  Need((N.Kind=wkList) and N.OwnWord and
       (N.ParentIndex=-1) and (N.RootIndex=0) and
       (N.ChildIndex=0) and (N.Depth=0),'хибний D2 корінь');
  for I:=1 to 4 do begin
    N:=IR.Nodes[I];
    Need(N.OwnWord and (N.RootIndex=0),'втрата фізичного слова');
    if I in [1,3] then begin
      Need((N.Kind=wkAtom) and N.HasPinnedKey and
           (N.Width=6) and (Length(N.Bits)=6) and
           SameKey(N.NarrowKey,ExactKey(N.Bits)),
           'нератифікована голова D6');
      if I=1 then
        Need(N.Bits='010011','зовнішня голова не D6 модуль')
      else
        Need(N.Bits='010010','внутрішня голова не D6 змінити-знак');
    end;
  end;
  Need((IR.Nodes[1].ParentIndex=0) and
       (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1),
       'хибна зовнішня голова');
  Need((IR.Nodes[2].Kind=wkList) and
       (IR.Nodes[2].Width=0) and
       (IR.Nodes[2].ParentIndex=0) and
       (IR.Nodes[2].ChildIndex=1) and (IR.Nodes[2].Depth=1),
       'відсутній внутрішній D2 список');
  Need((IR.Nodes[3].ParentIndex=2) and
       (IR.Nodes[3].ChildIndex=0) and (IR.Nodes[3].Depth=2),
       'хибна внутрішня голова');
  N:=IR.Nodes[4];
  Need((N.Kind=wkAtom) and (N.Width=12) and
       (Length(N.Bits)=12) and (not N.HasPinnedKey) and
       (N.NarrowKey.Width=0) and
       (N.ParentIndex=2) and (N.ChildIndex=1) and
       (N.Depth=2),'потрібен лише один opaque D12 атом');
end;

{ Image — owned managed raw ELF, offset0 — host zero-based LE64.
  Змінюємо лише довжини єдиного RX PT_LOAD, а не мовні біти.
  1) Чому p_filesz і p_memsz однакові?
  2) Чому ELF entry=120 залишається незмінним?
  3) Чому перед записом потрібна перевірка меж? }
procedure Write64(var Image:RawByteString;Offset0:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset0>=0) and (Offset0+8<=Length(Image)),
       'поле ELF поза фізичним образом');
  UniqueString(Image);
  for I:=0 to 7 do begin
    Image[Offset0+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ ProgramPhysical: borrowed canonical T5M D2 source з зовнішнім та
  внутрішнім pinned D6; AuthorityRoot: borrowed pinned SENS directory.
  Result: owned ELF64 PIE. Наявний BuildD12AbsELF проходить numeric
  допуск і визначає D12/D24 довжину через вже наявний numeric plane.
  Допускаємо також -2048: внутрішній NEG дає +2048 (D24), зовнішній
  модуль лишає точне D24. Результат обчислюється тільки x86.
  Вставляємо саме 2 байти NEG після MOV EAX,imm32 перед CDQ.
  LEA RIP-relative інструкції та T5M таблиці ЗМІЩУЮТЬСЯ ОБИДВА на 2,
  тому їхня відносна відстань НЕ змінюється.
  1) Чому машинний NEG вставлено перед CDQ, а не перед MOV?
  2) Чому відмова має відбутися до створення ELF?
  3) Хто зберігає точний домен D24 при -2048?
  4) Чому два байти не змінюють RIP displacement?
  5) Хто керує часом життя IR/Decoded/Image? }
function BuildIRNegAbsELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Decoded,One:TExactWords;Numeric:TExplicitNumeric;
    InputPhysical,Base:RawByteString;G:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
       'джерело фізичної програми порожнє або завелике');
  DecodeT5M(ProgramPhysical,Decoded);
  Need(EncodeT5M(Decoded)=ProgramPhysical,
       'джерело не є канонічним фізичним T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  CheckNested(IR,Stats);
  SetLength(One,1);One[0]:=IR.Nodes[4].Bits;
  InputPhysical:=EncodeT5M(One);
  Numeric:=ReadNumericPhysical(InputPhysical,12);
  Need((Numeric.DomainWidth=12) and
       (Numeric.ExactBits=IR.Nodes[4].Bits),
       'не підтверджено signed D12 numeric admission');

  Base:=BuildD12AbsELF(InputPhysical);
  VerifySENSELF64(Base,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Base)) and (G.MachineBytes>0),
       'чинний machine ABS donor не підтверджено');
  Need((Length(Base)>HeaderBytes+12) and
       (Byte(Base[HeaderBytes+1])=$B8) and
       (Copy(Base,HeaderBytes+6,5)=#$99#$31#$D0#$29#$D0),
       'немає точного MOV/CDQ/XOR/SUB машинного прологу');

  { Вставка F7 D8 після MOV EAX imm32: жоден машинний
    арифметичний результат не вираховується Pascal. }
  Result:=Copy(Base,1,HeaderBytes+5)+#$F7#$D8+
          Copy(Base,HeaderBytes+6,Length(Base)-HeaderBytes-5);
  Need(Length(Result)=Length(Base)+2,
       'втрачено фізичні машинні байти після вставки NEG');
  Write64(Result,96,Length(Result));
  Write64(Result,104,Length(Result));
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)) and
       (G.MachineBytes>0) and
       (Copy(Result,HeaderBytes+6,7)=#$F7#$D8#$99#$31#$D0#$29#$D0),
       'вкладений машинний ELF64 PIE не пройшов admission');
end;
end.
