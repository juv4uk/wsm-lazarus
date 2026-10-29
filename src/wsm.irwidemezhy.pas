{ G6.144 — повна canonical binary D2/T5M форма D6:110100/110110
  над двома signed D12 -> pinned WideIR -> раніше перевірений
  machine CMP/SETLE або CMP/SETGE -> фізичний D1 T5M.
  Єдиний закон — external/sens Contract 12.0 та lib/domains/d6.lisp.
  Pascal не обчислює предикат і не створює реєстру мовних законів. }
unit wsm.irwidemezhy;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideMezhyError=class(Exception);
function BuildIRWideMezhyELF(
 const PhysicalProgram,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd6mezhy,wsm.elfgeometry;

procedure Need(OK:Boolean;const Message:String);
begin if not OK then raise EIRWideMezhyError.Create(Message) end;

{ Input IR: FPC-owned managed WideIR від незалежного pinned binder.
  Results L/R: borrowed фізичні W12 leaves, НЕ Pascal Boolean.
  Перевірка exact domain width, key, parent/child index — механічний gate.
  1) Чому D6:110100 відрізняється від D5:11010 за шириною?
  2) Чому непідтверджений HasPinnedKey не є мовною функцією?
  3) Чому W12 аргумент лишається opaque до числового допуску?
  4) Що заважає підміні кореневого D2 списку ще одним коренем?
  5) Як IR зберігає провідні нулі D12? }
procedure VerifyMezhyForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var H,N:TWideIRNode;I:SizeInt;
begin
  Need((Stats.Roots=1) and (Stats.Nodes=4) and
    (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
    (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Length(IR.Nodes)=4),'потрібна одна плоска D2 форма D6 з двома D12');
  N:=IR.Nodes[0];
  Need((N.Kind=wkList) and N.OwnWord and
    (N.ParentIndex=-1) and (N.RootIndex=0) and
    (N.ChildIndex=0) and (N.Depth=0),
    'корінь не є цілісним D2 списком');
  H:=IR.Nodes[1];
  Need((H.Kind=wkAtom) and H.OwnWord and H.HasPinnedKey and
    (H.Width=6) and (Length(H.Bits)=6) and
    ((H.Bits='110100') or (H.Bits='110110')) and
    SameKey(H.NarrowKey,ExactKey(H.Bits)) and
    (H.ParentIndex=0) and (H.RootIndex=0) and
    (H.ChildIndex=0) and (H.Depth=1),
    'допускаємо лише pinned D6:110100 або D6:110110');
  for I:=2 to 3 do begin
    N:=IR.Nodes[I];
    Need((N.Kind=wkAtom) and N.OwnWord and
      (N.Width=12) and (Length(N.Bits)=12) and
      (not N.HasPinnedKey) and (N.NarrowKey.Width=0) and
      (N.ParentIndex=0) and (N.RootIndex=0) and
      (N.ChildIndex=I-1) and (N.Depth=1),
      'операнди мають бути точними opaque D12 атомами');
  end;
end;

{ Node — borrowed exact W12 signed бітовий рисунок після pinned D6.
  Result — owned packed T5M байти ОДНОГО фізичного numeric atom.
  Host-рядки автоматично керовані FPC; числовий закон повторно
  допускається лише чинним ReadNumericPhysical, не власною таблицею.
  1) Чому друга перевірка numeric domain тут обов'язкова?
  2) Чому 3 байти не визначають число без W12 та pinned контексту?
  3) Хто звільняє тимчасовий TExactWords?
  4) Де відхиляється D24 як неявний D12?
  5) Чому саме бітовий рисунок, а не десятковий рядок? }
function AdmitNumeric(const N:TWideIRNode):RawByteString;
var W:TExactWords;Value:TExplicitNumeric;
begin
  SetLength(W,1);W[0]:=N.Bits;
  Result:=EncodeT5M(W);
  Value:=ReadNumericPhysical(Result,12);
  Need((Value.DomainWidth=12) and (Value.ExactBits=N.Bits),
       'numeric D12 admission не зберіг біти');
end;

{ PhysicalProgram — borrowed canonical packed full D2 source.
  AuthorityRoot — borrowed pinned repository directory.
  Result — owned machine ELF64 ET_DYN image; caller publishes atomically.
  Рівно дві machine profile координати обираються тільки після pinned
  exact-key admission; SETLE/SETGE обчислює CPU у виконаному ELF.
  1) Чому text .lisp тут не підмінює фізичне джерело?
  2) Чому VerifyWideIRStructure не доказ семантичної викличності?
  3) Де реальне signed CMP/SETcc, а де тільки host routing?
  4) Чому T5M round-trip до IR, і ELF geometry після backend?
  5) Чому x86 вихідний D1 не є Pascal Boolean? }
function BuildIRWideMezhyELF(
 const PhysicalProgram,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;Left,Right:RawByteString;G:TELFGeometry;
begin
  Result:='';
  Need((Length(PhysicalProgram)>0) and (Length(PhysicalProgram)<=65536),
    'недопустима квота фізичної .sens програми');
  DecodeT5M(PhysicalProgram,Words);
  Need(EncodeT5M(Words)=PhysicalProgram,
    'пошкоджено canonical T5M round-trip');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(PhysicalProgram,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyMezhyForm(IR,Stats);
  Left:=AdmitNumeric(IR.Nodes[2]);
  Right:=AdmitNumeric(IR.Nodes[3]);
  if SameKey(IR.Nodes[1].NarrowKey,ExactKey('110100')) then
    Result:=BuildD6NotGreaterELF(Left,Right)
  else
    Result:=BuildD6NotLessELF(Left,Right);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
    (G.FileBytes=Length(Result)),
    'machine ELF64 PIE із pinned D6 не підтверджений');
end;
end.
