{ G6.201 — D5:10111 «частка» через ОДНОРАЗОВИЙ перевірений контекст.
  Виконується машинна D5:10111 «частка» лише для рівних ненульових
  signed D12 через існуючий CQO/IDIV; це не загальне ділення.

  Тут НЕМАЄ ні DecodeT5M, ні перевірки канонічності EncodeT5M, ні
  LoadPinnedDomains, ні BuildWideIR, ні VerifyWideIRStructure — усе це
  вже зробив TVerifiedWideContext РІВНО ОДИН раз на цю програму.
  Лишається тільки те, що належить САМЕ цьому машинному профілю:
  форма D2, pinned-голова, D12-допуск операндів, ELF-геометрія.

  Машинний генератор не змінюється і не дублюється: той самий
  BuildD12QuotELF із wsm.elfd12quot, який викликає чинний
  wsm.irwidesub.BuildIRWideSubELF. Жодного нового закону, emitter-а
  чи альтернативного evaluator-а.
  1) Чому повторний DecodeT5M тут був би другим проходом, а не захистом?
  2) Чому ширина W12 сама по собі не робить листок числом?
  3) Чому pinned-голова перевіряється навіть після успішного контексту?
  4) Хто звільняє позичений IR і власні байти ELF після return? }
unit wsm.verifiedquot;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.wideir, wsm.wideirguard;
type EVerifiedQuotError=class(Exception);

{ Нижній рівень для TVerifiedWideContext.Lower: отримує ПОЗИЧЕНИЙ
  read-only IR і не має права його змінювати. Повертає власні байти ELF. }
function LowerVerifiedQuot(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;

implementation
uses wsm.domain, wsm.bind, wsm.t5m, wsm.numericplane, wsm.elfd12quot,
     wsm.elfgeometry;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EVerifiedQuotError.Create(Why) end;

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
       'не підтверджено точний opaque W12 аргумент D5-частки');
  SetLength(W,1);W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  N:=ReadNumericPhysical(Result,12);
  Must((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
       'числовий D12 admission не підтвердив фізичні біти');
end;

{ IR/Stats — позичені; Result — окремий власний ELF64.
  Тут лише профільні інваріанти: один плоский D2, pinned 10111,
  два opaque W12, і незмінний машинний IDIV. }
function LowerVerifiedQuot(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var LeftPhysical,RightPhysical:RawByteString; G:TELFGeometry;
begin
  Result:='';
  Must((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'потрібна одна плоска D5:10111(D12,D12) форма');
  Must((IR.Nodes[0].Kind=wkList) and (IR.Nodes[0].RootIndex=0) and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].ChildIndex=0) and
       (IR.Nodes[0].Depth=0),
       'корінь повинен бути рівно D2 списком');
  Must((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       IR.Nodes[1].HasPinnedKey and (IR.Nodes[1].Width=5) and
       (IR.Nodes[1].Bits='10111') and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('10111')) and
       (IR.Nodes[1].ParentIndex=0) and (IR.Nodes[1].RootIndex=0) and
       (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1),
       'потрібна pinned D5:10111 «частка» callable голова');
  LeftPhysical:=AdmitOperand(IR.Nodes[2],1);
  RightPhysical:=AdmitOperand(IR.Nodes[3],2);
  { Той самий незмінний машинний генератор, що й у чинному backend. }
  Result:=BuildD12QuotELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.FileBytes=Length(Result)) and (G.Entry=120),
       'чинний backend не повернув перевірений ELF64 PIE');
end;

end.
