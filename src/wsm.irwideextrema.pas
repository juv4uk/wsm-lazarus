{ G6.101 — full physical D2/T5M SENS expressions for pinned D6 extrema.
  One verified WideIR (exact D6:110101 or D6:110111 + two W12 atoms)
  passes through existing native CMP/CMOVG or CMP/CMOVL ELF64 backend.
  Pascal defines only machine admission and never invents language laws. }
unit wsm.irwideextrema;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideExtremaError=class(Exception);
function BuildIRWideExtremaELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12min,wsm.elfd12max,wsm.elfgeometry;

procedure Require(Ok:Boolean;const Why:String);
begin if not Ok then raise EIRWideExtremaError.Create(Why) end;

{ Borrowed Node: exact W12 leaf in verified WideIR. Child: physical
  D2 child index. Result: owned packed canonical D12/T5M atom, never
  text or decimal. Local Words and Numeric are FPC managed values.
  Питання: 1) Чому W12 без контексту — непрозоре слово?
  2) Хто перевіряє його як число D12?
  3) Де зберігаються початкові нулі? 4) Хто звільняє Words? }
function AdmitAtom(const Node:TWideIRNode;Child:SizeInt):RawByteString;
var Words:TExactWords; Numeric:TExplicitNumeric;
begin
  Require((Node.Kind=wkAtom) and Node.OwnWord and
    (Node.ParentIndex=0) and (Node.RootIndex=0) and
    (Node.ChildIndex=Child) and (Node.Depth=1) and
    (Node.Width=12) and (Length(Node.Bits)=12) and
    (not Node.HasPinnedKey),
    'аргумент повинен бути точною непрозорою фізичною W12 координатою');
  SetLength(Words,1);Words[0]:=Node.Bits;
  Result:=EncodeT5M(Words);
  Numeric:=ReadNumericPhysical(Result,12);
  Require((Numeric.DomainWidth=12) and (Numeric.ExactBits=Node.Bits),
    'числовий D12 admission не підтвердив ті самі біти');
end;

{ Physical: borrowed exact packed D2/T5M program; AuthorityRoot: the
  pinned SENS directory, not a spelling->law registry.
  Result: owned ELF64 PIE bytes; verified shape and existing backend
  independently validate all numeric operands and image geometry.
  CPU executes signed CMP+CMOV; Pascal never precomputes min/max.
  Питання: 1) Чому потрібно довести один корінь та чотири IR-вузли?
  2) Чим D6:110101 відрізняється від D5:10101?
  3) Чому обидва backend знову перевіряють числові атоми?
  4) Чому результат D12, а не Pascal LongInt?
  5) Що стається з недопущеною D6 головою? }
function BuildIRWideExtremaELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;LeftAtom,RightAtom:RawByteString;
    Head:TWideIRNode;Geometry:TELFGeometry;
begin
  Result:='';
  Require((Length(Physical)>0) and (Length(Physical)<=65536),
    'порожня або надмірна фізична програма');
  DecodeT5M(Physical,Words);
  Require(EncodeT5M(Words)=Physical,'пошкоджене або неканонічне T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Require((Stats.Roots=1) and (Stats.Nodes=4) and
    (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=2) and
    (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Length(IR.Nodes)=4),'очікується одна пласка фізична D6 форма з двома D12');
  Require((IR.Nodes[0].Kind=wkList) and
    (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
    'фізичний D2 корінь не підтверджено');
  Head:=IR.Nodes[1];
  Require((Head.Kind=wkAtom) and Head.OwnWord and Head.HasPinnedKey and
    (Head.Width=6) and (Length(Head.Bits)=6) and
    SameKey(Head.NarrowKey,ExactKey(Head.Bits)) and
    (Head.ParentIndex=0) and (Head.RootIndex=0) and
    (Head.ChildIndex=0) and (Head.Depth=1),
    'голова не належить ратифікованому точному домену D6');
  Require((Head.Bits='110101') or (Head.Bits='110111'),
    'цей нативний профіль D6 не підтримується');
  LeftAtom:=AdmitAtom(IR.Nodes[2],1);
  RightAtom:=AdmitAtom(IR.Nodes[3],2);
  if Head.Bits='110101' then
    Result:=BuildD12MinELF(LeftAtom,RightAtom)
  else
    Result:=BuildD12MaxELF(LeftAtom,RightAtom);
  VerifySENSELF64(Result,Geometry);
  Require((Geometry.Kind=3) and (Geometry.Entry=120) and
    (Geometry.FileBytes=Length(Result)),
    'низхідний компілятор повернув некоректний ELF64 PIE');
end;
end.
