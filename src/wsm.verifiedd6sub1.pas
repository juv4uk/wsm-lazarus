{ G6: одноразовий verified WideIR для pinned D6:001111 «відняти-1».
  НЕ reader, НЕ арифметичний закон, НЕ новий машинний генератор.
  IR та Stats запозичені на час callback; Result — керовані ELF64 байти.
  1) Чому W12 без ReadNumericPhysical не є числом SENS?
  2) Хто відповідає за DecodeT5M, BuildWideIR та pinned binder?
  3) Чому перевіряємо точну ширину та біти голови?
  4) Чому далі тільки чинний BuildD12SubELF?
  5) Хто володіє життям IR і Result? }
unit wsm.verifiedd6sub1;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.wideir, wsm.wideirguard;
type
  EVerifiedD6Sub1Error=class(Exception);

function LowerVerifiedD6Sub1(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;

implementation
uses wsm.domain, wsm.t5m, wsm.numericplane, wsm.elfd12sub;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise EVerifiedD6Sub1Error.Create(Why);
end;

{ Тільки три вузли одного D2 виклику, із фізичним pinned D6:001111.
  Ніякого повторного LoadPinnedDomains/DecodeT5M/BuildWideIR.
  Numeric admission займається вже наявний ReadNumericPhysical.
  Межа цього CPU fast-path рівно та сама, що у wsm.ird6sub1:
  signed D12 від 1 до 2047. Нуль/від'ємні/D24 не отримують машинний
  результат: це НЕ твердження про загальну SENS SUB1 семантику. }
function LowerVerifiedD6Sub1(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var
  Arg,One:RawByteString;
  W:TExactWords;
  N:TExplicitNumeric;
begin
  Result:='';
  Need((Stats.Roots=1) and (Stats.Nodes=3) and
    (Stats.PhysicalLeaves=2) and (Stats.OpaqueLeaves=1) and
    (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Length(IR.Nodes)=3),
    'відняти-1: потрібна одна D2 форма з двома точними атомами');
  Need((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
    (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].Depth=0) and
    (IR.Nodes[0].ChildIndex=0),
    'відняти-1: некоректний корінь D2');
  Need((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
    IR.Nodes[1].HasPinnedKey and (IR.Nodes[1].Width=6) and
    (IR.Nodes[1].Bits='001111') and
    SameKey(IR.Nodes[1].NarrowKey,ExactKey('001111')) and
    (IR.Nodes[1].ParentIndex=0) and
    (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1) and
    (IR.Nodes[1].RootIndex=0),
    'відняти-1: голова мусить бути рівно pinned D6:001111');
  Need((IR.Nodes[2].Kind=wkAtom) and IR.Nodes[2].OwnWord and
    (IR.Nodes[2].Width=12) and (Length(IR.Nodes[2].Bits)=12) and
    (not IR.Nodes[2].HasPinnedKey) and
    (IR.Nodes[2].NarrowKey.Width=0) and
    (IR.Nodes[2].ParentIndex=0) and
    (IR.Nodes[2].ChildIndex=1) and
    (IR.Nodes[2].RootIndex=0) and (IR.Nodes[2].Depth=1),
    'відняти-1: аргумент має бути тільки opaque D12');
  SetLength(W,1);
  W[0]:=IR.Nodes[2].Bits;
  Arg:=EncodeT5M(W);
  N:=ReadNumericPhysical(Arg,12);
  Need((N.DomainWidth=12) and (N.ExactBits=IR.Nodes[2].Bits),
    'відняти-1: фізичний D12 не пройшов числовий допуск');
  Need((N.ExactBits[1]='0') and (N.ExactBits<>'000000000000'),
    'відняти-1: машинний профіль дозволяє тільки D12 1..2047');
  One:=EncodeNumericDecimal('1',12);
  Result:=BuildD12SubELF(Arg,One);
  { Фінальну геометрію незалежно перевіряє TVerifiedWideContext.Lower. }
end;
end.
