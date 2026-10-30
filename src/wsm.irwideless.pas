{ G6.91 — одна canonical D2/T5M форма D5:11010 «менше?» над ДВОМА
  точними opaque W12 словами → verified WideIR → вже злитий ELF64.
  Єдиний закон — pinned Contract12 + lib/domains/d5.lisp + CPU profile.
  Не створювати власних таблиць семантики чи host-boolean SENS. }
unit wsm.irwideless;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.verifiedwidecontext;
type EIRWideLessError=class(Exception);
function BuildIRWideLessELF(const PhysicalProgram,AuthorityRoot:RawByteString):RawByteString;
function BuildIRWideLessFromContext(const Context:TVerifiedWideContext):RawByteString;
implementation
uses wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.t5m,wsm.numericplane,wsm.elfd12less,wsm.elfgeometry;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EIRWideLessError.Create(Why) end;

{ Node — borrowed exact physical word, Result — managed owned packed T5M.
  Numeric admission only after the pinned D5 head and verified IR; W12
  itself is opaque. No text conversions, no English head/function dispatch.
  1) Чому ширина W12 не робить слово автоматично D12-числом?
  2) Навіщо перевіряти повторно через ReadNumericPhysical?
  3) Хто вивільняє локальні TExactWords і packed Result?
  4) Чому OpaqueLeaves=2? }
function AdmitNumericOperand(const Node:TWideIRNode;Child:SizeInt):RawByteString;
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

{ PhysicalProgram — borrowed canonical packed binary .sens program;
  AuthorityRoot — pinned SENS gitlink, local managed domain tables.
  Result — owned executable Linux x86-64 ELF64 PIE bytes: real signed
  CMP/SETL/MOVZX at machine run, exact packed D1 stdout. No precomputed
  Pascal comparison; no new SENS language law. Caller publishes atomically.
  1) Чому D5:11010 head повинен мати ExactKey?
  2) Чому один D2 корінь і саме чотири IR вузли?
  3) Хто формує D1 під час виконання?
  4) Чому після machine emitter знову VerifySENSELF64?
  5) Де відхиляються D1/D7/D24 аргументи? }
{ Стара точка входу не втрачає жодної повної admission-перевірки.
  LowerVerifiedLess містить ті самі D5 form, D12 numeric і x86/ELF
  механізми для ОБОХ маршрутів; тільки контекст пропускає дубльований
  T5M→WideIR. П'ять питань: де pinned head, де точний D12, хто володіє
  Result, чи є міжпрограмний cache, хто перевіряє фінальний ELF? }
function LowerVerifiedLess(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var LeftPhysical,RightPhysical:RawByteString; G:TELFGeometry;
begin
  Result:='';
  Must((Stats.Nodes=4) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=4),'потрібна одна плоска D5:11010(D12,D12) форма');
  Must((IR.Nodes[0].Kind=wkList) and
       (IR.Nodes[0].RootIndex=0) and
       (IR.Nodes[0].ParentIndex=-1) and
       (IR.Nodes[0].ChildIndex=0) and
       (IR.Nodes[0].Depth=0),
       'корінь повинен бути рівно D2 списком');
  Must((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       IR.Nodes[1].HasPinnedKey and (IR.Nodes[1].Width=5) and
       (IR.Nodes[1].Bits='11010') and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('11010')) and
       (IR.Nodes[1].ParentIndex=0) and
       (IR.Nodes[1].RootIndex=0) and (IR.Nodes[1].ChildIndex=0) and
       (IR.Nodes[1].Depth=1),
       'потрібна pinned D5:11010 «менше?» callable голова');
  LeftPhysical:=AdmitNumericOperand(IR.Nodes[2],1);
  RightPhysical:=AdmitNumericOperand(IR.Nodes[3],2);
  Result:=BuildD12LessELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Result,G);
  Must((G.Kind=3) and (G.FileBytes=Length(Result)) and (G.Entry=120),
       'чинний backend не повернув перевірений ELF64 PIE');
end;

{ Старий public API збережено для суворої байтової parity:
  Decode/Encode, pinned load, BuildWideIR, guard — без зміни.
  Фізичний borrowed source, два owned IR managed buffers і ELF. }
function BuildIRWideLessELF(const PhysicalProgram,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet; IR:TWideIR; Stats:TWideIRGuardStats;
    Words:TExactWords;
begin
  Result:='';
  Must((Length(PhysicalProgram)>0) and (Length(PhysicalProgram)<=65536),
       'неприпустимий розмір фізичної .sens форми');
  DecodeT5M(PhysicalProgram,Words);
  Must(EncodeT5M(Words)=PhysicalProgram,
       'неканонічна фізична T5M форма');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(PhysicalProgram,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Result:=LowerVerifiedLess(IR,Stats);
end;

{ Лише constructor TVerifiedWideContext може видати verified IR,
  внутрішні mutable вузли назовні не повертаються; lifetime однієї
  компіляції — у caller try/finally. Backend зберігає ВСІ вузькі
  перевірки: D5 head, 2 opaque D12, exact numeric, ELF geometry.
  Питання: де повторно читаємо D1–D10 для нової програми?
  Чому цей шлях не приймає D24? Чому ніколи не кешуємо ELF?
  Чи повинен GUI/Lazarus використовувати саме цей headless API?
  Чому один і той самий native emitter залишається без змін? }
function BuildIRWideLessFromContext(
  const Context:TVerifiedWideContext):RawByteString;
begin
  Must(Context<>nil,'немає перевіреного WideIR контексту');
  Result:=Context.Lower(@LowerVerifiedLess);
end;
end.
