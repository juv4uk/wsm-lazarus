{ G6.105 — повна канонічна D2/T5M форма НСД за pinned D6:010101.
  Цілісний physical .sens → чинний WideIR/guard → exact D6 голова і два
  opaque D12 атоми → повторний numeric admission → злитий x86-64
  BuildD12NsdELF. Жодного локального реєстру законів або semantic
  dispatch за ук/укр назвою; machine Euclid виконується лише в ELF.
  Фізична форма, біти, ширина та походження зберігаються. }
unit wsm.irwidensd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideNsdError=class(Exception);
function BuildIRWideNsdELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.domain,wsm.bind,wsm.t5m,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12nsd,wsm.elfgeometry;

procedure Require(OK:Boolean;const Why:String);
begin
  if not OK then raise EIRWideNsdError.Create(Why);
end;

procedure VerifyNsdForm(const IR:TWideIR;const Stats:TWideIRGuardStats);
var Head:TWideIRNode; I:SizeInt;
begin
  Require((Stats.Nodes=4) and (Stats.Roots=1) and
    (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
    (Length(IR.Nodes)=4) and (Length(IR.Roots)=1) and
    (IR.Roots[0]=0),'потрібна рівно одна форма D6:010101(D12,D12)');
  Require((IR.Nodes[0].Kind=wkList) and
    (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].RootIndex=0) and
    (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
    'корінь не є D2-списком');
  Head:=IR.Nodes[1];
  Require((Head.Kind=wkAtom) and Head.OwnWord and
    Head.HasPinnedKey and (Head.Width=6) and
    (Head.Bits='010101') and
    SameKey(Head.NarrowKey,ExactKey('010101')) and
    (Head.ParentIndex=0) and (Head.RootIndex=0) and
    (Head.ChildIndex=0) and (Head.Depth=1),
    'голова не є pinned D6:010101');
  for I:=2 to 3 do
    Require((IR.Nodes[I].Kind=wkAtom) and IR.Nodes[I].OwnWord and
      (IR.Nodes[I].Width=12) and
      (Length(IR.Nodes[I].Bits)=12) and
      (not IR.Nodes[I].HasPinnedKey) and
      (IR.Nodes[I].NarrowKey.Width=0) and
      (IR.Nodes[I].ParentIndex=0) and (IR.Nodes[I].RootIndex=0) and
      (IR.Nodes[I].ChildIndex=I-1) and (IR.Nodes[I].Depth=1),
      'аргумент не є opaque D12 атомом');
end;

function BuildIRWideNsdELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet; IR:TWideIR; Stats:TWideIRGuardStats;
    Decoded,Words:TExactWords;
    LPhysical,RPhysical:RawByteString;
    L,R:TExplicitNumeric; G:TELFGeometry;
begin
  Result:='';
  Require((Length(ProgramPhysical)>0) and
    (Length(ProgramPhysical)<=65536),
    'фізична програма виходить за межі');
  DecodeT5M(ProgramPhysical,Decoded);
  Require(EncodeT5M(Decoded)=ProgramPhysical,
    'неканонічне фізичне T5M джерело');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  VerifyNsdForm(IR,Stats);
  SetLength(Words,1);
  Words[0]:=IR.Nodes[2].Bits;
  LPhysical:=EncodeT5M(Words);
  L:=ReadNumericPhysical(LPhysical,12);
  Words[0]:=IR.Nodes[3].Bits;
  RPhysical:=EncodeT5M(Words);
  R:=ReadNumericPhysical(RPhysical,12);
  Require((L.DomainWidth=12) and (R.DomainWidth=12) and
    (L.ExactBits=IR.Nodes[2].Bits) and
    (R.ExactBits=IR.Nodes[3].Bits),
    'фізичний D12 admission втратив біти');
  Result:=BuildD12NsdELF(LPhysical,RPhysical);
  VerifySENSELF64(Result,G);
  Require((G.Kind=3) and (G.FileBytes=Length(Result)) and
    (G.Entry=120),'некоректна ELF64 PIE геометрія');
end;
end.
