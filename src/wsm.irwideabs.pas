{ G6.93 — ціла фізична D2/T5M форма D6:010011 «модуль» над D12.
  Авторитет лише pinned SENS Contract12 і lib/domains/d6.lisp;
  FPC реалізує verified WideIR → наявний машинний CDQ/XOR/SUB.
  Жодного нового закону чи копіювання бібліотечних функцій до Pascal. }
unit wsm.irwideabs;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideAbsError=class(Exception);
function BuildIRWideAbsELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.domain,wsm.bind,wsm.t5m,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12abs,wsm.elfgeometry;

procedure Require(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRWideAbsError.Create(Why);
end;

{ IR is borrowed managed tree; no private language law. Caller must have
  passed the independent structural VerifyWideIRStructure gate.
  D6:010011 narrow key originates from pinned D6 domain table.
  1) Чому корінь D2 не тотожний numeric D12 atom?
  2) Чому pinned D6 має рівно шість бітів?
  3) Чому W12 у цьому IR лишається opaque до numeric admission?
  4) Де відхиляється D7-голова, зайва форма чи вкладений аргумент? }
procedure VerifyAbsForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var Head,Operand:TWideIRNode;
begin
  Require((Stats.Nodes=3) and (Stats.Roots=1) and
    (Stats.PhysicalLeaves=2) and (Stats.OpaqueLeaves=1) and
    (Length(IR.Nodes)=3) and (Length(IR.Roots)=1) and
    (IR.Roots[0]=0),'потрібна одна фізична D6:010011(D12) форма');
  Require((IR.Nodes[0].Kind=wkList) and
    (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].RootIndex=0) and
    (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
    'корінь повинен бути точним списком D2');
  Head:=IR.Nodes[1];
  Operand:=IR.Nodes[2];
  Require((Head.Kind=wkAtom) and Head.OwnWord and
    Head.HasPinnedKey and (Head.Width=6) and (Head.Bits='010011') and
    SameKey(Head.NarrowKey,ExactKey('010011')) and
    (Head.ParentIndex=0) and (Head.RootIndex=0) and
    (Head.ChildIndex=0) and (Head.Depth=1),
    'голова не є ратифікованою pinned D6:010011');
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
  Existing BuildD12AbsELF executes real CDQ/XOR/SUB and preserves D24
  promotion for physical D12:-2048; no value precomputed as ELF output.
  1) Чому repeated codec admission необхідний після WideIR?
  2) Хто перевіряє D12→D24 крайовий результат?
  3) Де саме виконується математична операція — у ELF чи Pascal?
  4) Хто володіє managed Words і ELF image?
  5) Чому VerifySENSELF64 перевіряється ще раз? }
function BuildIRWideAbsELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    InputWords,Decoded:TExactWords;InputPhysical:RawByteString;
    Numeric:TExplicitNumeric;Geometry:TELFGeometry;
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
  VerifyAbsForm(IR,Stats);
  SetLength(InputWords,1);
  InputWords[0]:=IR.Nodes[2].Bits;
  InputPhysical:=EncodeT5M(InputWords);
  Numeric:=ReadNumericPhysical(InputPhysical,12);
  Require((Numeric.DomainWidth=12) and
    (Numeric.ExactBits=IR.Nodes[2].Bits),
    'точний числовий D12 admission не пройдено');
  Result:=BuildD12AbsELF(InputPhysical);
  VerifySENSELF64(Result,Geometry);
  Require((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)) and
    (Geometry.Entry=120),'машинний ELF64 PIE пошкоджений');
end;
end.
