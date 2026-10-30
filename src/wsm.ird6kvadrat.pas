{ G6.128 — лише фізичний D6:010111, показник exact D24:2.
  Закон піднесення до степеня вже визначено у pinned Core4; цей
  механізм понижує квадрат до РАНІШЕ ПЕРЕВІРЕНОГО D5 множення.
  Немає ні Pascal-рекурсії Core4, ні локального реєстру законів.
  Вхід borrowed T5M, вихід owned ELF64 ET_DYN, ніякої .lisp підміни.
  1) Чому D24 показник не можна замінити D12:2?
  2) Хто звіряє точну D6 голову з pinned таблицею?
  3) Чому тут немає нового машинного IMUL кодера?
  4) Де відхиляються невідомі показники?
  5) Хто відповідає за D12/D24 ширину результату? }
unit wsm.ird6kvadrat;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRD6KvadratError=class(Exception);
function BuildIRD6KvadratELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12mul,wsm.elfgeometry;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRD6KvadratError.Create(Why);
end;

{ Borrowed read-only IR; identity = exact width + bits + pinned key.
  Статистика доводить один D2 список з трьома фізичними листками:
  D6:010111 та два opaque числові слова D12/D24 відповідно.
  Ніяка назва з людської проєкції не використовується як dispatch. }
procedure CheckShape(const IR:TWideIR;const Stats:TWideIRGuardStats);
var Head,Base,Power:TWideIRNode;
begin
  Need((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Nodes)=4) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0),'потрібна одна фізична форма D6(D12,D24)');
  Need((IR.Nodes[0].Kind=wkList) and
       (IR.Nodes[0].ParentIndex=-1) and
       (IR.Nodes[0].RootIndex=0) and
       (IR.Nodes[0].ChildIndex=0) and
       (IR.Nodes[0].Depth=0),'фізичний D2 корінь неправильний');
  Head:=IR.Nodes[1];Base:=IR.Nodes[2];Power:=IR.Nodes[3];
  Need((Head.Kind=wkAtom) and Head.OwnWord and Head.HasPinnedKey and
       (Head.Width=6) and (Head.Bits='010111') and
       SameKey(Head.NarrowKey,ExactKey('010111')) and
       (Head.ParentIndex=0) and (Head.RootIndex=0) and
       (Head.ChildIndex=0) and (Head.Depth=1),
       'не ратифікована pinned D6:010111 голова');
  Need((Base.Kind=wkAtom) and Base.OwnWord and
       (Base.Width=12) and (Length(Base.Bits)=12) and
       (not Base.HasPinnedKey) and (Base.NarrowKey.Width=0) and
       (Base.ParentIndex=0) and (Base.RootIndex=0) and
       (Base.ChildIndex=1) and (Base.Depth=1),
       'основа не є одним opaque exact D12');
  Need((Power.Kind=wkAtom) and Power.OwnWord and
       (Power.Width=24) and (Length(Power.Bits)=24) and
       (not Power.HasPinnedKey) and (Power.NarrowKey.Width=0) and
       (Power.ParentIndex=0) and (Power.RootIndex=0) and
       (Power.ChildIndex=2) and (Power.Depth=1),
       'показник не є одним opaque exact D24');
end;

{ Result — власний фізичний ELF64 image. Система допускає ТІЛЬКИ
  точний D24:2; D6 загалом не називаємо скомпільованим.
  Повторний numeric admission дає D12-ідентичність лише після
  правильного pinned WideIR, а не з самої довжини W12.
  Ратифіковану Core4 рекурсію не переносимо до Pascal:
  expt(основа,2) -> наявний verified IMUL(основа,основа). }
function BuildIRD6KvadratELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words,OneWord:TExactWords;BasePhysical,PowerPhysical:RawByteString;
    Base,Power,Two:TExplicitNumeric;G:TELFGeometry;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
       'порожній або завеликий фізичний .sens');
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,'неканонічні T5M байти');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  CheckShape(IR,Stats);
  SetLength(OneWord,1);
  OneWord[0]:=IR.Nodes[2].Bits;
  BasePhysical:=EncodeT5M(OneWord);
  Base:=ReadNumericPhysical(BasePhysical,12);
  Need((Base.DomainWidth=12) and (Base.ExactBits=IR.Nodes[2].Bits),
       'не допущено точну основу D12');
  OneWord[0]:=IR.Nodes[3].Bits;
  PowerPhysical:=EncodeT5M(OneWord);
  Power:=ReadNumericPhysical(PowerPhysical,24);
  Two:=ReadNumericPhysical(EncodeNumericDecimal('2',24),24);
  Need((Power.DomainWidth=24) and (Power.ExactBits=IR.Nodes[3].Bits) and
       (Power.ExactBits=Two.ExactBits),
       'вузький машинний профіль підтримує ТІЛЬКИ exact D24:2');
  Result:=BuildD12MulELF(BasePhysical,BasePhysical);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Result)),
       'verified native IMUL не повернув коректний ELF64 PIE');
end;
end.
