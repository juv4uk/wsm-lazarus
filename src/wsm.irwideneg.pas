{ G6.133 — ціла фізична D2/T5M форма D6:010010 «змінити-знак» над D12.
  Авторитет лише pinned SENS Contract12 і lib/domains/d6.lisp;
  FPC реалізує verified WideIR → наявний машинний NEG.
  Жодного нового закону чи копіювання бібліотечних функцій до Pascal. }
unit wsm.irwideneg;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.verifiedwidecontext;
type EIRWideNegError=class(Exception);
function BuildIRWideNegELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
function BuildIRWideNegFromContext(const Context:TVerifiedWideContext):RawByteString;
implementation
uses wsm.domain,wsm.bind,wsm.t5m,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12neg,wsm.elfgeometry;

procedure Require(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRWideNegError.Create(Why);
end;

{ IR is borrowed managed tree; no private language law. Caller must have
  passed the independent structural VerifyWideIRStructure gate.
  D6:010010 narrow key originates from pinned D6 domain table.
  1) Чому корінь D2 не тотожний numeric D12 atom?
  2) Чому pinned D6 має рівно шість бітів?
  3) Чому W12 у цьому IR лишається opaque до numeric admission?
  4) Де відхиляється D7-голова, зайва форма чи вкладений аргумент? }
procedure VerifyNegForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var Head,Operand:TWideIRNode;
begin
  Require((Stats.Nodes=3) and (Stats.Roots=1) and
    (Stats.PhysicalLeaves=2) and (Stats.OpaqueLeaves=1) and
    (Length(IR.Nodes)=3) and (Length(IR.Roots)=1) and
    (IR.Roots[0]=0),'потрібна одна фізична D6:010010(D12) форма');
  Require((IR.Nodes[0].Kind=wkList) and
    (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].RootIndex=0) and
    (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
    'корінь повинен бути точним списком D2');
  Head:=IR.Nodes[1];
  Operand:=IR.Nodes[2];
  Require((Head.Kind=wkAtom) and Head.OwnWord and
    Head.HasPinnedKey and (Head.Width=6) and (Head.Bits='010010') and
    SameKey(Head.NarrowKey,ExactKey('010010')) and
    (Head.ParentIndex=0) and (Head.RootIndex=0) and
    (Head.ChildIndex=0) and (Head.Depth=1),
    'голова не є ратифікованою pinned D6:010010');
  Require((Operand.Kind=wkAtom) and Operand.OwnWord and
    (Operand.Width=12) and (Length(Operand.Bits)=12) and
    (not Operand.HasPinnedKey) and
    (Operand.NarrowKey.Width=0) and
    (Operand.ParentIndex=0) and (Operand.RootIndex=0) and
    (Operand.ChildIndex=1) and (Operand.Depth=1),
    'операнд не є одним opaque signed W12 листком');
end;

{ Input: borrowed canonical packed .sens D2 source and pinned directory.
  Output: owned executable ELF64 ET_DYN bytes; no host-inferred numeric
  identity, no textual dispatch. W12 leaf is explicitly recertified by
  existing ReadNumericPhysical with D12 domain after verified D6 head.
  Existing BuildD12NegELF executes real CDQ/XOR/SUB and preserves D24
  promotion for physical D12:-2048; no value precomputed as ELF output.
  1) Чому repeated codec admission необхідний після WideIR?
  2) Хто перевіряє D12→D24 крайовий результат?
  3) Де саме виконується математична операція — у ELF чи Pascal?
  4) Хто володіє managed Words і ELF image?
  5) Чому VerifySENSELF64 перевіряється ще раз? }
{ IR/Stats — позичені керовані дані одного перевіреного WideIR.
  Той самий form/numeric/machine допуск для старого і нового маршруту.
  Відповідь — власний FPC RawByteString із перевіреним ELF64 PIE.
  1) Чому ширина W12 не є самостійним числовим законом?
  2) Хто відповідає за точне signed D12 та перехід -2048 до D24?
  3) Чому байти ELF створює лише наявний машинний emitter?
  4) Чому callback не має права змінювати IR? }
function LowerVerifiedNeg(const IR:TWideIR;
  const Stats:TWideIRGuardStats):RawByteString;
var InputWords:TExactWords;InputPhysical:RawByteString;
    Numeric:TExplicitNumeric;Geometry:TELFGeometry;
begin
  Result:='';
  VerifyNegForm(IR,Stats);
  SetLength(InputWords,1);
  InputWords[0]:=IR.Nodes[2].Bits;
  InputPhysical:=EncodeT5M(InputWords);
  Numeric:=ReadNumericPhysical(InputPhysical,12);
  Require((Numeric.DomainWidth=12) and
    (Numeric.ExactBits=IR.Nodes[2].Bits),
    'точний числовий D12 admission не пройдено');
  Result:=BuildD12NegELF(InputPhysical);
  VerifySENSELF64(Result,Geometry);
  Require((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)) and
    (Geometry.Entry=120),'машинний ELF64 PIE пошкоджений');
end;

{ Старий API: збережено повний канонічний допуск, без оптимізації.
  Фізичне джерело — позичені packed T5M байти; локальні Tables,
  Decoded, IR звільняються FPC після return або exception.
  1) Чому зберігаємо старе повторне декодування для byte baseline?
  2) Де перевіряється канонічність packed T5M?
  3) Чому цей маршрут не має спільного кешу між файлами? }
function BuildIRWideNegELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Decoded:TExactWords;
begin
  Result:='';
  Require((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
    'фізична .sens програма за межами розміру');
  DecodeT5M(ProgramPhysical,Decoded);
  Require(EncodeT5M(Decoded)=ProgramPhysical,
    'неканонічні фізичні байти T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Result:=LowerVerifiedNeg(IR,Stats);
end;

{ Контекст належить викликачеві, лише один Lower на екземпляр.
  Повторне T5M/Domain/IR тут відсутнє, але guard конкретної форми,
  числовий D12 admission та перевірка ELF лишилися тими самими.
  1) Чому контекст не повинен жити між двома програмами?
  2) Чому повторний виклик Lower має відмовляти?
  3) Де перевіряється D6 010010, а не D7-ім'я?
  4) Хто звільняє результуючий FPC ELF buffer? }
function BuildIRWideNegFromContext(
  const Context:TVerifiedWideContext):RawByteString;
begin
  Require(Context<>nil,'немає перевіреного WideIR контексту');
  Result:=Context.Lower(@LowerVerifiedNeg);
end;
end.
