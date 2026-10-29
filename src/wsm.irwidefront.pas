{ G6.97 — СПІЛЬНИЙ ВХІД для ШЕСТИ уже доведених physical D2 форм.
  НЕ новий evaluator, НЕ реєстр мовних законів і НЕ новий x86 emitter.
  Pinned SENS визначає значення/identity; це тільки whitelist наявних
  *машинних профілів* за exact domain-qualified bit key.
  Кожен старий backend самостійно повторно перевіряє повну структуру. }
unit wsm.irwidefront;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideFrontError=class(Exception);
function BuildVerifiedWideELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.irwidezero,wsm.irwideless,wsm.irwidegreater,wsm.irwideabs,
     wsm.irwideaddreg,wsm.irwidemul,
     wsm.elfgeometry;

procedure Demand(Allowed:Boolean;const Why:String);
begin if not Allowed then raise EIRWideFrontError.Create(Why) end;

{ ProgramPhysical: borrowed canonical packed T5M bytes for a single D2
  program, NOT text. AuthorityRoot: borrowed pinned external/sens dir.
  Result: owned byte-exact ELF64 PIE, only after final machine geometry.
  No SENS function names are dispatched; a small set of compiled
  machine profiles is selected by a proven pinned (width,bits) head.
  Every existing Build*Wide*ELF independently rechecks all children,
  numeric admission, D12/D24, and output geometry; thus this entrypoint
  cannot silently broaden the domain of any compiler backend.

  1) Чому HasPinnedKey потрібен окрім самих бітів голови?
  2) Чому для D5 та D6 перевіряється ще й Width?
  3) Чому opaque W12 не є автоматично числовим D12?
  4) Чому підлеглий backend знову повністю звіряє IR та числовий допуск?
  5) Хто володіє керованими масивами IR та байтами поверненого ELF? }
function BuildVerifiedWideELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;Head:TWideIRNode;Geom:TELFGeometry;
begin
  Result:='';
  Demand((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
    'фізична .sens програма порожня або завелика');
  DecodeT5M(ProgramPhysical,Words);
  Demand(EncodeT5M(Words)=ProgramPhysical,
    'джерело не є канонічним T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Demand((Stats.Roots=1) and (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Stats.Nodes>=3) and (Length(IR.Nodes)>=3) and
    (IR.Nodes[0].Kind=wkList) and (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].Depth=0),
    'потрібен лише один canonical D2 список');
  Head:=IR.Nodes[1];
  Demand((Head.Kind=wkAtom) and Head.OwnWord and Head.HasPinnedKey and
    (Head.ParentIndex=0) and (Head.RootIndex=0) and
    (Head.ChildIndex=0) and (Head.Depth=1) and
    SameKey(Head.NarrowKey,ExactKey(Head.Bits)),
    'виклична голова не підтверджена pinned D5/D6');
  { Вибираємо лише НАЯВНІ ратифіковані механічні профілі; жодного
    закону не реалізуємо вдруге. Width позначає точний домен,
    не машинний opcode або людську функціональну назву. }
  if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('01000')) then
    Result:=BuildIRWideZeroELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('11010')) then
    Result:=BuildIRWideLessELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('11011')) then
    Result:=BuildPhysicalGreaterELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('01010')) then
    Result:=BuildIRWideAddRegisterELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=5) and SameKey(Head.NarrowKey,ExactKey('10110')) then
    Result:=BuildIRWideMulELF(ProgramPhysical,AuthorityRoot)
  else if (Head.Width=6) and SameKey(Head.NarrowKey,ExactKey('010011')) then
    Result:=BuildIRWideAbsELF(ProgramPhysical,AuthorityRoot)
  else
    raise EIRWideFrontError.Create(
      'вузький нативний профіль цієї pinned координати ще не реалізовано');
  VerifySENSELF64(Result,Geom);
  Demand((Geom.Kind=3) and (Geom.Entry=120) and
    (Geom.FileBytes=Length(Result)),
    'некоректний ELF64 PIE від перевіреного backend');
end;
end.
