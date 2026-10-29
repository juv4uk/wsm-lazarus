{ G6.139 — цілісна фізична D2/T5M програма
  (D5:10111 D12 D12) -> pinned WideIR -> ВЖЕ перевірений CQO/IDIV ELF64.
  Єдиний мовний закон — external/sens, Contract 12.0; немає
  ні Pascal-ділення, ні dispatch за D7/українською/англійською назвою.
  Машинний профіль свідомо лишається вузьким: однакові ненульові
  додатні D12 операнди, все інше — відмова чинного backend.
  Вхід: borrowed packed T5M і шлях authority; вихід: owned ELF PIE.
  1) Чому W12 без D5 контексту не число?
  2) Чому голова перевіряється за шириною і бітами?
  3) Чому допуск обох D12 робимо після pinned structural guard?
  4) Хто звільняє managed IR і ELF?
  5) Чому немає семантики частки у цьому адаптері? }
unit wsm.irwidequot;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideQuotError=class(Exception);
function BuildIRWideQuotELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12quot,wsm.elfgeometry;

procedure Require(Allowed:Boolean;const Why:String);
begin
  if not Allowed then raise EIRWideQuotError.Create(Why);
end;

{ IR — borrowed і незмінний. Лише ДВА opaque W12; всі
  координати, фізичні позиції та parent/child узяті з pinned WideIR.
  Result відсутній: процедура або приймає форму, або відмовляє.
  1) Навіщо OwnWord? 2) Чому дитячі індекси точні?
  3) Чому неможна допускати іншу п'ятибітну голову? }
procedure CheckQuotForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var N:TWideIRNode;I:SizeInt;
begin
  Require((Stats.Roots=1) and (Stats.Nodes=4) and
    (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
    (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Length(IR.Nodes)=4),
    'потрібна одна фізична форма D5:10111 з двома D12');
  N:=IR.Nodes[0];
  Require((N.Kind=wkList) and N.OwnWord and
    (N.ParentIndex=-1) and (N.RootIndex=0) and
    (N.ChildIndex=0) and (N.Depth=0),
    'корінь не є канонічним D2 списком');
  N:=IR.Nodes[1];
  Require((N.Kind=wkAtom) and N.OwnWord and N.HasPinnedKey and
    (N.Width=5) and (N.Bits='10111') and
    SameKey(N.NarrowKey,ExactKey('10111')) and
    (N.ParentIndex=0) and (N.RootIndex=0) and
    (N.ChildIndex=0) and (N.Depth=1),
    'голова не є ратифікованою pinned D5:10111');
  for I:=2 to 3 do begin
    N:=IR.Nodes[I];
    Require((N.Kind=wkAtom) and N.OwnWord and
      (N.Width=12) and (Length(N.Bits)=12) and
      (not N.HasPinnedKey) and (N.NarrowKey.Width=0) and
      (N.ParentIndex=0) and (N.RootIndex=0) and
      (N.ChildIndex=I-1) and (N.Depth=1),
      'аргумент не є фізичним opaque W12');
  end;
end;

{ ProgramPhysical — borrowed packed bytes з усією D2 формою;
  AuthorityRoot — borrowed шлях до pinned таблиць.
  Return — owned ELF64 PIE. Жодної семантичної арифметики в Pascal;
  старий BuildD12QuotELF повністю перевіряє обмеження машинного
  профілю та лише під час ВИКОНАННЯ машинного IDIV рахує результат.
  1) Чому потрібен T5M round-trip до роботи з IR?
  2) Чим opaque 12 бітів відрізняються від D12 з допуском?
  3) Як перевіряється незмінність leading zeros?
  4) Що станеться для нерівних чисел?
  5) Чому цей вузький профіль не є загальним компілятором D5? }
function BuildIRWideQuotELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words,Decoded:TExactWords;
    LeftPhysical,RightPhysical:RawByteString;
    L,R:TExplicitNumeric;G:TELFGeometry;
begin
  Result:='';
  Require((Length(ProgramPhysical)>0) and
    (Length(ProgramPhysical)<=65536),
    'порожня або завелика фізична програма');
  DecodeT5M(ProgramPhysical,Decoded);
  Require(EncodeT5M(Decoded)=ProgramPhysical,
    'джерело не є канонічним фізичним T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  CheckQuotForm(IR,Stats);
  SetLength(Words,1);
  Words[0]:=IR.Nodes[2].Bits;
  LeftPhysical:=EncodeT5M(Words);
  L:=ReadNumericPhysical(LeftPhysical,12);
  Words[0]:=IR.Nodes[3].Bits;
  RightPhysical:=EncodeT5M(Words);
  R:=ReadNumericPhysical(RightPhysical,12);
  Require((L.DomainWidth=12) and (R.DomainWidth=12) and
    (L.ExactBits=IR.Nodes[2].Bits) and
    (R.ExactBits=IR.Nodes[3].Bits),
    'втрачено exact D12 під час фізичного допуску');
  Result:=BuildD12QuotELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Result,G);
  Require((G.Kind=3) and (G.Entry=120) and
    (G.FileBytes=Length(Result)),
    'неправильна геометрія x86-64 PIE');
end;
end.