{ G6.103 — фізична ратифікована D5:10110(W12,W12) до x86-64 IMUL.
  Єдиний закон — pinned SENS Contract 12 і lib/domains/d5.lisp.
  Механізм: канонічний T5M → pinned WideIR → exact D5 admission →
  opaque D12 числові операнди → вже доведений BuildD12MulELF.
  Немає власного реєстру законів, dispatch за іменем або копії IMUL.
  Result — owned managed ELF64 ET_DYN, вхід — borrowed packed .sens.
  1) Чому непрозоре W12 не дорівнює числу без D5 контексту?
  2) Хто визначає та перевіряє розширення результату до D24?
  3) Чим фізичний D2 root відрізняється від Lisp-проєкції?
  4) Чому навіть успішний IR guard не дозволяє довільну голову?
  5) Хто звільняє IR, TExactWords і байти ELF після return? }
unit wsm.irwidemul;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideMulError=class(Exception);
function BuildIRWideMulELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12mul,wsm.elfgeometry;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRWideMulError.Create(Why);
end;

{ Borrowed IR: кожен вузол зберігає власний бітовий рисунок та
  фізичні адреси; структурний guard уже підтвердив ці інваріанти.
  Допускаємо тільки один D2 список: exact D5:10110 і два opaque W12.
  Це machine profile, а не новий мовний закон. }
procedure CheckMulForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var H,N:TWideIRNode;I:SizeInt;
begin
  Need((Stats.Roots=1) and (Stats.Nodes=4) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),
       'потрібна одна фізична D2 форма D5-множення з двома D12');
  N:=IR.Nodes[0];
  Need((N.Kind=wkList) and N.OwnWord and
       (N.ParentIndex=-1) and (N.ChildIndex=0) and
       (N.RootIndex=0) and (N.Depth=0),
       'корінь не є однією фізичною формою D2');
  H:=IR.Nodes[1];
  Need((H.Kind=wkAtom) and H.OwnWord and H.HasPinnedKey and
       (H.Width=5) and (H.Bits='10110') and
       SameKey(H.NarrowKey,ExactKey('10110')) and
       (H.ParentIndex=0) and (H.ChildIndex=0) and
       (H.RootIndex=0) and (H.Depth=1),
       'голова не є ратифікованою pinned D5:10110');
  for I:=2 to 3 do begin
    N:=IR.Nodes[I];
    Need((N.Kind=wkAtom) and N.OwnWord and
         (N.Width=12) and (Length(N.Bits)=12) and
         (not N.HasPinnedKey) and
         (N.ParentIndex=0) and (N.ChildIndex=I-1) and
         (N.RootIndex=0) and (N.Depth=1),
         'операнд не є точним непрозорим W12 листком');
  end;
end;

{ Node — borrowed, Result — окремий packed T5M W12 атом.
  Повторний ReadNumericPhysical є дозволеним лише після pinned D5
  голови; не виводимо числову ідентичність із самої ширини. }
function D12Atom(const N:TWideIRNode):RawByteString;
var W:TExactWords;Numeric:TExplicitNumeric;
begin
  SetLength(W,1);W[0]:=N.Bits;
  Result:=EncodeT5M(W);
  Numeric:=ReadNumericPhysical(Result,12);
  Need((Numeric.DomainWidth=12) and (Numeric.ExactBits=N.Bits),
       'втрачено точну D12 ідентичність');
end;

function BuildIRWideMulELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;Left,Right:RawByteString;Geometry:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
       'фізична .sens програма порожня або завелика');
  DecodeT5M(ProgramPhysical,Words);
  Need(EncodeT5M(Words)=ProgramPhysical,
       'фізичне T5M пакування неканонічне');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  CheckMulForm(IR,Stats);
  Left:=D12Atom(IR.Nodes[2]);Right:=D12Atom(IR.Nodes[3]);
  { Тільки раніше перевірені numeric/machine механізми вирішують
    D12/D24 і породжують виконуваний IMUL, не Pascal-local law. }
  Result:=BuildD12MulELF(Left,Right);
  VerifySENSELF64(Result,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Result)),
       'некоректна фінальна геометрія ELF64 PIE');
end;
end.
