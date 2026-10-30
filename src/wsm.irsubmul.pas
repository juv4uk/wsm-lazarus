{ G6.170: одна вкладена фізична D5 програма → verified WideIR → ELF64.
  Pinned SENS Contract 12.0: D5:10110 (помножити) над D5:01011
  (відняти), точні D12 атоми. Назви — виключно коментарі, не dispatch.
  Усе машинне SUB+IMUL запозичує вже доведений wsm.elfd12submul.
  Це НЕ універсальний compiler, не нова D5 функція й не evaluator. }
unit wsm.irsubmul;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRSubMulError=class(Exception);
function BuildPhysicalNestedSubMulELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12submul,wsm.elfgeometry;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRSubMulError.Create(Why) end;

{ Позичений вузол WideIR залишається opaque W12 аж до перевірки
  ReadNumericPhysical із ЯВНИМ доменом D12 у ратифікованій D5 формі.
  Результат — owned standalone canonical T5M одного exact D12 слова;
  повторне пакування не змінює біти чи провідні нулі.
  Питання: чому 12-бітна ширина сама не є мовним законом?
  Чому немає неявного D24→D12? Хто володіє байтами Result?
  Чому ні D1, ні D7 не допускаються як операнди? }
function AdmitD12(const Node:TWideIRNode;Parent,Child,Level:SizeInt):RawByteString;
var Words:TExactWords;Numeric:TExplicitNumeric;
begin
  Need((Node.Kind=wkAtom) and Node.OwnWord and
       (Node.Width=12) and (Length(Node.Bits)=12) and
       (Node.ParentIndex=Parent) and (Node.ChildIndex=Child) and
       (Node.Depth=Level) and (Node.RootIndex=0) and
       (not Node.HasPinnedKey),
       'непідтриманий або неправильно розміщений D12 атом');
  SetLength(Words,1);
  Words[0]:=Node.Bits;
  Result:=EncodeT5M(Words);
  Numeric:=ReadNumericPhysical(Result,12);
  Need((Numeric.DomainWidth=12) and (Numeric.ExactBits=Node.Bits),
       'пошкоджена точна фізична ідентичність D12');
end;

{ Цей compiler читає рівно одну canonical T5M D2 форму:
    (D5:10110 (D5:01011 D12 D12) D12).
  WideIR — локальні керовані масиви, lifetime до завершення виклику;
  pinned D5 голови зв'язує LoadPinnedDomains, не Pascal enum і не
  український рядок. Остаточний ELF належить викликачеві.
  Питання: чому структура з іншою арністю має відмовити до ELF?
  Чому дубльований D2 корінь заборонений? Чому машинний код не
  містить заздалегідь обчисленого T5M результату?
  Де незалежний SENS підтверджує обидва математичні закони?
  Що буде, коли проміжна різниця потребує D24? }
function BuildPhysicalNestedSubMulELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    A,B,C:RawByteString;Geometry:TELFGeometry;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
       'порожня або завелика фізична програма');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Roots=1) and (Stats.Nodes=7) and
       (Stats.PhysicalLeaves=5) and (Stats.OpaqueLeaves=3) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=7),'потрібна єдина вкладена D5(D5 D12 D12 D12)');
  Need((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
       (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].ParentIndex=-1) and
       (IR.Nodes[0].Depth=0) and (IR.Nodes[0].ChildIndex=0),
       'пошкоджений фізичний корінь D2');
  Need((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       (IR.Nodes[1].HasPinnedKey) and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('10110')) and
       (IR.Nodes[1].RootIndex=0) and (IR.Nodes[1].ParentIndex=0) and
       (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1),
       'зовнішня голова має бути точним pinned D5:10110');
  Need((IR.Nodes[2].Kind=wkList) and IR.Nodes[2].OwnWord and
       (IR.Nodes[2].RootIndex=0) and (IR.Nodes[2].ParentIndex=0) and
       (IR.Nodes[2].ChildIndex=1) and (IR.Nodes[2].Depth=1),
       'другий аргумент D5 має бути вкладеним D2 списком');
  Need((IR.Nodes[3].Kind=wkAtom) and IR.Nodes[3].OwnWord and
       IR.Nodes[3].HasPinnedKey and
       SameKey(IR.Nodes[3].NarrowKey,ExactKey('01011')) and
       (IR.Nodes[3].ParentIndex=2) and (IR.Nodes[3].ChildIndex=0) and
       (IR.Nodes[3].RootIndex=0) and (IR.Nodes[3].Depth=2),
       'вкладена голова має бути точним pinned D5:01011');
  A:=AdmitD12(IR.Nodes[4],2,1,2);
  B:=AdmitD12(IR.Nodes[5],2,2,2);
  C:=AdmitD12(IR.Nodes[6],0,2,1);
  { Наявний emitter сам перевіряє exact sum D12 і promotion product
    D12→D24; ніякого власного семантичного коду чи LUT законів тут. }
  Result:=BuildD12SubMulELF(A,B,C);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Result)),
       'вкладена фізична програма не знизилась до перевіреного ELF64');
end;
end.
