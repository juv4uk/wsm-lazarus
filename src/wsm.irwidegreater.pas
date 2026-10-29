{ G6.85 — фізична D2-форма D5:11011(W12,W12) до справжнього ELF.
  Єдиний мовний закон — pinned SENS Contract12. WideIR перевіряє
  структуру/координати; чинний D12 emitter перевіряє numeric admission
  та генерує x86-64 CMP/SETG. Це НЕ загальний evaluator чи compiler. }
unit wsm.irwidegreater;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EWideGreaterError=class(Exception);
function BuildPhysicalGreaterELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.t5m,wsm.numericplane,wsm.elfd12greater,wsm.elfgeometry;

procedure Demand(OK:Boolean;const Why:String);
begin
  if not OK then raise EWideGreaterError.Create(Why);
end;

{ Borrowed WideIR вузол позначає лише фізичне W12. Саме явний
  вузький профіль D5:11011 з двома numeric D12 надає контекст для
  повторної механічної admission через ReadNumericPhysical.
  Result — owned canonical packed standalone D12 байти. Це НЕ
  відновлення всього джерела з окремого raw span.
  1) Чому W12 саме по собі не є числом?
  2) Чому окремий T5M може займати інші байти, ніж всередині форми?
  3) Хто гарантує точні провідні нулі?
  4) Чому не можна допустити D24 за аналогією? }
function AdmitOperand(const Node:TWideIRNode;ExpectedChild:SizeInt):RawByteString;
var W:TExactWords;Numeric:TExplicitNumeric;
begin
  Demand((Node.Kind=wkAtom) and Node.OwnWord and
         (Node.Width=12) and (Length(Node.Bits)=12) and
         (Node.ParentIndex=0) and (Node.ChildIndex=ExpectedChild) and
         (Node.RootIndex=0) and (Node.Depth=1) and
         (not Node.HasPinnedKey),
         'аргумент не є фізичним opaque D12 атомом');
  SetLength(W,1);
  W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  Numeric:=ReadNumericPhysical(Result,12);
  Demand((Numeric.DomainWidth=12) and (Numeric.ExactBits=Node.Bits),
         'числовий допуск втратив точну ідентичність D12');
end;

{ Physical — borrowed byte string однієї canonical T5M D2 форми;
  AuthorityRoot — borrowed pinned directory (gitlink checked separately).
  Result — owned native ELF64 PIE. WideIR/Tables — local managed arrays,
  released by FPC after return/exception; no evaluator/GC is invoked.
  Compiler accepts only one 4-node flat list and its exact pinned D5 key;
  calls existing machine emitter with independently admitted D12 values.
  Machine computes D1 during ELF execution (no Pascal predicate).
  1) Why verify wide IR rather than blindly DecodeT5M?
  2) Why check exact D5 key instead of Ukrainian name?
  3) Why can this not compile arbitrary nested Core1?
  4) Who owns Result ELF bytes and publish inode?
  5) Why is byte identity with the old emitter a useful regression? }
function BuildPhysicalGreaterELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    LeftAtom,RightAtom:RawByteString;Geom:TELFGeometry;
begin
  Result:='';
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Demand((Stats.Nodes=4) and (Stats.Roots=1) and
    (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
    (Length(IR.Nodes)=4) and (Length(IR.Roots)=1) and (IR.Roots[0]=0),
    'очікується рівно одна плоска D5 форма із двома D12');
  Demand((IR.Nodes[0].Kind=wkList) and
         (IR.Nodes[0].RootIndex=0) and
         (IR.Nodes[0].ParentIndex=-1) and
         (IR.Nodes[0].ChildIndex=0) and
         (IR.Nodes[0].Depth=0),
    'відхилено неточний фізичний корінь D2');
  Demand((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
    IR.Nodes[1].HasPinnedKey and
    SameKey(IR.Nodes[1].NarrowKey,ExactKey('11011')) and
    (IR.Nodes[1].ParentIndex=0) and (IR.Nodes[1].ChildIndex=0) and
    (IR.Nodes[1].RootIndex=0) and (IR.Nodes[1].Depth=1),
    'непідтримана callable голова (потрібно exact D5:11011)');
  LeftAtom:=AdmitOperand(IR.Nodes[2],1);
  RightAtom:=AdmitOperand(IR.Nodes[3],2);
  Result:=BuildD12GreaterELF(LeftAtom,RightAtom);
  VerifySENSELF64(Result,Geom);
  Demand((Geom.Kind=3) and (Geom.FileBytes=Length(Result)),
    'machine emitter не повернув допустимий ELF64 PIE');
end;
end.
