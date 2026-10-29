{ G6.110 — один native compiler entrypoint для ТРЬОХ уже доведених
  двогілкових фізичних SENS форм. Це host whitelist перевірених
  машинних профілів, НЕ власний реєстр мовних законів.
  Єдине семантичне джерело: pinned external/sens Contract 12.0.
  Підпорядковані verified backend повторно перевіряють ВСІ піддерева. }
unit wsm.irtwobranchfront;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRTwoBranchFrontError=class(Exception);
function BuildVerifiedTwoBranchELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.irtwobrancheq,wsm.irtwobranchless,wsm.irtwobranchgreater,
     wsm.elfgeometry;

procedure Need(Condition:Boolean;const Why:String);
begin if not Condition then raise EIRTwoBranchFrontError.Create(Why) end;

{ ProgramPhysical: borrowed byte-exact packed .sens, not source text.
  AuthorityRoot: borrowed host path to pinned SENS.
  IR: stack-owned structure with managed exact-width bitstrings, released
  automatically; Result: owned managed ELF64 bytes for atomic publishing.
  Head.NarrowKey: exact pinned domain-qualified address, never integer
  opcode inferred from text. Whitelist selects an EXISTING native emitter:
  downstream checks full D2 topology, D12 signed admission and D24 refusal.
  No intermediate numeric answer nor D1 truth value calculated here.

  Питання: чому фізична адреса складається з ширини та бітів?
  Навіщо HasPinnedKey перед вибором машинного профілю?
  Чому D3:101 не можна замінити D5:101?
  Де вторинна перевірка числових аргументів?
  Хто звільняє managed IR і повернений ELF? }
function BuildVerifiedTwoBranchELF(
  const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;Head:TWideIRNode;G:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
    'порожній або завеликий фізичний файл .sens');
  DecodeT5M(ProgramPhysical,Words);
  Need(EncodeT5M(Words)=ProgramPhysical,'неканонічний T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Roots=1) and (Length(IR.Roots)=1) and
    (IR.Roots[0]=0) and (Stats.Nodes=10) and
    (Length(IR.Nodes)=10) and (Stats.OpaqueLeaves=4) and
    (IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
    (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].Depth=0),
    'потрібна одна фізична десятивузлова D2 форма із двома піддеревами');
  Head:=IR.Nodes[1];
  Need((Head.Kind=wkAtom) and Head.OwnWord and Head.HasPinnedKey and
    (Head.RootIndex=0) and (Head.ParentIndex=0) and
    (Head.ChildIndex=0) and (Head.Depth=1) and
    (Length(Head.Bits)=Head.Width) and
    SameKey(Head.NarrowKey,ExactKey(Head.Bits)),
    'голова не є точною pinned координатою');
  if (Head.Width=3) and
     SameKey(Head.NarrowKey,ExactKey('101')) then
    Result:=BuildIRTwoBranchEqELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and
     SameKey(Head.NarrowKey,ExactKey('11010')) then
    Result:=BuildIRTwoBranchLessELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and
     SameKey(Head.NarrowKey,ExactKey('11011')) then
    Result:=BuildIRTwoBranchGreaterELF(ProgramPhysical,AuthorityRoot)
  else
    raise EIRTwoBranchFrontError.Create(
      'для цієї pinned фізичної голови двогілковий машинний профіль не підтримується');
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
    (G.FileBytes=Length(Result)),
    'невірна геометрія згенерованого ELF64 PIE');
end;
end.
