{ G6.191 — D5:11010 «менше?» через ОДНОРАЗОВИЙ перевірений контекст.
  Третя хвиля рою: шаблон G6.190 (D5:01000) поширено на другий backend.

  Тут НЕМАЄ ні DecodeT5M, ні EncodeT5M-канонічності, ні LoadPinnedDomains,
  ні BuildWideIR, ні VerifyWideIRStructure — усе це вже зробив
  TVerifiedWideContext рівно один раз. Лишається тільки те, що належить
  САМЕ цьому машинному профілю: форма, голова, D12-допуск, ELF-геометрія.

  Машинний генератор не змінюється: той самий BuildD12LessELF.
  Жодного нового закону, emitter-а чи альтернативного evaluator-а. }
unit wsm.verifiedless;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.wideir, wsm.wideirguard;
type EVerifiedLessError=class(Exception);

{ Нижній рівень для TVerifiedWideContext.Lower: отримує ПОЗИЧЕНИЙ
  read-only IR і не має права його змінювати. Повертає власні байти ELF. }
function LowerVerifiedLess(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;

implementation
uses wsm.domain, wsm.bind, wsm.t5m, wsm.numericplane, wsm.elfd12less,
     wsm.elfgeometry;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EVerifiedLessError.Create(Why) end;

{ Точний opaque W12 аргумент: ширина НЕ робить слово числом.
  Числовий допуск — окремий чинний ReadNumericPhysical, як і раніше. }
function AdmitOperand(const Node:TWideIRNode;Child:SizeInt):RawByteString;
var W:TExactWords;N:TExplicitNumeric;
begin
  Must((Node.Kind=wkAtom) and Node.OwnWord and
       (Node.Width=12) and (Length(Node.Bits)=12) and
       (Node.ParentIndex=0) and (Node.RootIndex=0) and
       (Node.ChildIndex=Child) and (Node.Depth=1) and
       (not Node.HasPinnedKey) and (Node.NarrowKey.Width=0),
       'не підтверджено точний opaque W12 аргумент D5');
  SetLength(W,1);W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  N:=ReadNumericPhysical(Result,12);
  Must((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
       'числовий D12 admission не підтвердив фізичні біти');
end;

function LowerVerifiedLess(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var LeftPhysical,RightPhysical:RawByteString; G:TELFGeometry;
begin
  Result:='';
  Must((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),'потрібна одна плоска D5:11010(D12,D12) форма');
  Must((IR.Nodes[0].Kind=wkList) and (IR.Nodes[0].RootIndex=0) and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].ChildIndex=0) and
       (IR.Nodes[0].Depth=0),
       'корінь повинен бути рівно D2 списком');
  Must((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       IR.Nodes[1].HasPinnedKey and (IR.Nodes[1].Width=5) and
       (IR.Nodes[1].Bits='11010') and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('11010')) and
       (IR.Nodes[1].ParentIndex=0) and (IR.Nodes[1].RootIndex=0) and
       (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1),
       'потрібна pinned D5:11010 «менше?» callable голова');
  LeftPhysical:=AdmitOperand(IR.Nodes[2],1);
  RightPhysical:=AdmitOperand(IR.Nodes[3],2);
  Result:=BuildD12LessELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.FileBytes=Length(Result)) and (G.Entry=120),
       'чинний backend не повернув перевірений ELF64 PIE');
end;

end.
