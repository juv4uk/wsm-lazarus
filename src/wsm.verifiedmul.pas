{ G6.199 — D5:10110 «помножити» з одноразового verified WideIR.
  Канонічне T5M, pinned-домени та WideIR уже перевірив
  TVerifiedWideContext; цей механізм лише перевіряє профіль D5/D12
  і передає фізичні операнди незміненому x86-64 IMUL backend.
  1) Чому W12 без D5 контексту не є числовим допуском?
  2) Чому Lower не повторює DecodeT5M і BuildWideIR?
  3) Хто визначає вихідну ширину D12/D24?
  4) Хто звільняє позичений IR та результат ELF?
  5) Чому pinned key перевіряється ще раз перед IMUL? }
unit wsm.verifiedmul;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.wideir, wsm.wideirguard;
type EVerifiedMulError=class(Exception);

{ IR/Stats позичені лише на час виклику; результат — власні
  FPC-managed байти ELF64. Немає локального реєстру законів. }
function LowerVerifiedMul(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;

implementation
uses wsm.domain, wsm.bind, wsm.t5m, wsm.numericplane,
     wsm.elfd12mul, wsm.elfgeometry;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EVerifiedMulError.Create(Why) end;

{ Точний непрозорий W12 перетворюється на фізичний атом
  лише ПІСЛЯ допуску pinned D5:10110. }
function AdmitOperand(const Node:TWideIRNode;Child:SizeInt):RawByteString;
var W:TExactWords;N:TExplicitNumeric;
begin
  Must((Node.Kind=wkAtom) and Node.OwnWord and
       (Node.Width=12) and (Length(Node.Bits)=12) and
       (Node.ParentIndex=0) and (Node.RootIndex=0) and
       (Node.ChildIndex=Child) and (Node.Depth=1) and
       (not Node.HasPinnedKey) and (Node.NarrowKey.Width=0),
       'не підтверджено точний opaque W12 аргумент D5-множення');
  SetLength(W,1);W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  N:=ReadNumericPhysical(Result,12);
  Must((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
       'числовий D12 admission не підтвердив фізичні біти');
end;

{ Жодного повторного читання T5M, нових таблиць чи IR.
  Остання перевірка ELF — механічна; семантику множення
  визначають лише pinned SENS та чинний numeric/backend. }
function LowerVerifiedMul(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var LeftPhysical,RightPhysical:RawByteString;G:TELFGeometry;
begin
  Result:='';
  Must((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'потрібна одна плоска D5:10110(D12,D12) форма');
  Must((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
       (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].ParentIndex=-1) and
       (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
       'корінь повинен бути рівно D2 списком');
  Must((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       IR.Nodes[1].HasPinnedKey and (IR.Nodes[1].Width=5) and
       (IR.Nodes[1].Bits='10110') and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('10110')) and
       (IR.Nodes[1].ParentIndex=0) and (IR.Nodes[1].RootIndex=0) and
       (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1),
       'потрібна ратифікована pinned D5:10110 callable голова');
  LeftPhysical:=AdmitOperand(IR.Nodes[2],1);
  RightPhysical:=AdmitOperand(IR.Nodes[3],2);
  Result:=BuildD12MulELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.FileBytes=Length(Result)) and
       (G.Entry=120) and (G.MachineBytes>0),
       'чинний IMUL backend не повернув перевірений ELF64 PIE');
end;
end.
