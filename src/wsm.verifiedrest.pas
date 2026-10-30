{ G6.206 — D6:010100 «остача» через ОДНОРАЗОВИЙ перевірений контекст.
  Шоста хвиля рою після G6.190 (D5:01000), G6.191 (D5:11010),
  G6.192 (D5:01011), G6.199 (D5:10110) і G6.200 (D5:10111): той самий
  шаблон поширено на машинний профіль фізичної остачі.

  Тут НЕМАЄ ні DecodeT5M, ні перевірки канонічності EncodeT5M, ні
  LoadPinnedDomains, ні BuildWideIR, ні VerifyWideIRStructure — усе це
  вже зробив TVerifiedWideContext РІВНО ОДИН раз на цю програму.
  Лишається тільки те, що належить САМЕ цьому машинному профілю:
  форма D2, pinned-голова D6:010100, D12-допуск операндів, ELF-геометрія.

  Машинний генератор не змінюється і не дублюється: той самий
  BuildD12RestELF із wsm.elfd12rest, який викликає чинний
  wsm.irwiderest.BuildIRWideRestELF. Разом із ним незмінно
  успадковується ЙОГО відмова на нульовий дільник, на signed D12
  мінімум -2048 та на клас проміжного D12 overflow при від'ємному
  дільнику — жодної нової чи ослабленої числової перевірки цей unit
  не додає.
  1) Чому повторний DecodeT5M тут був би другим проходом, а не захистом?
  2) Чому ширина W12 сама по собі не робить листок числом?
  3) Чому pinned-голова перевіряється навіть після успішного контексту?
  4) Чому відмова на нульовий дільник лишається в машинному генераторі?
  5) Хто звільняє позичений IR і власні байти ELF після return? }
unit wsm.verifiedrest;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.wideir, wsm.wideirguard;
type EVerifiedRestError=class(Exception);

{ Нижній рівень для TVerifiedWideContext.Lower: отримує ПОЗИЧЕНИЙ
  read-only IR і не має права його змінювати. Повертає власні байти ELF. }
function LowerVerifiedRest(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;

implementation
uses wsm.domain, wsm.bind, wsm.t5m, wsm.numericplane, wsm.elfd12rest,
     wsm.elfgeometry;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EVerifiedRestError.Create(Why) end;

{ Точний opaque W12 аргумент: ширина НЕ робить слово числом.
  Числовий допуск — окремий чинний ReadNumericPhysical, як і раніше.
  Нульовий дільник, -2048 і overflow-клас тут НЕ перевіряються: це межа
  машинного профілю і вона мусить лишитися рівно там, де її тримає
  BuildD12RestELF. }
function AdmitOperand(const Node:TWideIRNode;Child:SizeInt):RawByteString;
var W:TExactWords;N:TExplicitNumeric;
begin
  Must((Node.Kind=wkAtom) and Node.OwnWord and
       (Node.Width=12) and (Length(Node.Bits)=12) and
       (Node.ParentIndex=0) and (Node.RootIndex=0) and
       (Node.ChildIndex=Child) and (Node.Depth=1) and
       (not Node.HasPinnedKey) and (Node.NarrowKey.Width=0),
       'не підтверджено точний opaque W12 аргумент D6-остачі');
  SetLength(W,1);W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  N:=ReadNumericPhysical(Result,12);
  Must((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
       'числовий D12 admission не підтвердив фізичні біти');
end;

{ IR/Stats — позичені; Result — окремий власний ELF64.
  Тут лише профільні інваріанти: один плоский D2, pinned 010100,
  два opaque W12, і незмінний машинний CQO/IDIV із корекцією знака
  остачі за знаком дільника.
  Нульовий дільник, -2048 і D12-overflow відхиляє сам BuildD12RestELF,
  тому жодного способу обійти ці відмови звідси немає. }
function LowerVerifiedRest(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var LeftPhysical,RightPhysical:RawByteString; G:TELFGeometry;
begin
  Result:='';
  Must((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'потрібна одна плоска D6:010100(D12,D12) форма');
  Must((IR.Nodes[0].Kind=wkList) and (IR.Nodes[0].RootIndex=0) and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].ChildIndex=0) and
       (IR.Nodes[0].Depth=0),
       'корінь повинен бути рівно D2 списком');
  Must((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       IR.Nodes[1].HasPinnedKey and (IR.Nodes[1].Width=6) and
       (IR.Nodes[1].Bits='010100') and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('010100')) and
       (IR.Nodes[1].ParentIndex=0) and (IR.Nodes[1].RootIndex=0) and
       (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1),
       'потрібна pinned D6:010100 «остача» callable голова');
  LeftPhysical:=AdmitOperand(IR.Nodes[2],1);
  RightPhysical:=AdmitOperand(IR.Nodes[3],2);
  { Той самий незмінний машинний генератор, що й у чинному backend.
    Саме він відхиляє нульовий дільник, -2048 і overflow-клас —
    ці перевірки не послаблені. }
  Result:=BuildD12RestELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.FileBytes=Length(Result)) and (G.Entry=120),
       'чинний backend не повернув перевірений ELF64 PIE');
end;

end.
