{ G6.190 — opaque verified WideIR лише на ЧАС ОДНІЄЇ компіляції.
  BuildWideIR уже використовує DecodeT5MWithLocations, який сам виконує
  DecodeT5M+EncodeT5M canonical check; перед ним не потрібен дубль.
  Це host compile context, не SENS закон, кеш чи новий evaluator. }
unit wsm.verifiedwidecontext;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.wideir,wsm.wideirguard;
type
  EVerifiedWideContext=class(Exception);
  { Нижній callback отримує тільки позичене read-only IR, не право
    змінювати структуру та не власну копію. }
  TVerifiedWideLowerer=function(const IR:TWideIR;
    const Stats:TWideIRGuardStats):RawByteString;
  TVerifiedWideContext=class
  private
    FIR:TWideIR;
    FStats:TWideIRGuardStats;
    FUsed:Boolean; { Один допуск Lower на один verified context. }
  public
    constructor Create(const ProgramPhysical,AuthorityRoot:RawByteString);
    function Lower(const Lowerer:TVerifiedWideLowerer):RawByteString;
  end;
implementation
uses wsm.t5m,wsm.bind,wsm.domain,wsm.elfgeometry;

procedure Require(Allowed:Boolean;const Why:String);
begin if not Allowed then raise EVerifiedWideContext.Create(Why) end;

{ ProgramPhysical/AuthorityRoot — позичені canonical bytes і pinned шлях.
  FIR/Stats — керовані ВЛАСНІ приватні дані об'єкта, без публічного setter;
  таблиці D1–D10 завантажуються заново на КОЖНУ нову програму.
  BuildWideIR сам виконує повний decode+re-encode canonical, exact D2,
  pinned key binding, а VerifyWideIRStructure — незалежну перевірку.
  Не тримаємо ні IR, ні доменні таблиці між викликами/програмами.
  1) Чому повторний DecodeT5M перед BuildWideIR зайвий?
  2) Чому ширина D12 не означає numeric admission?
  3) Чому після exception немає старого IR?
  4) Чому thread-local pinned scope не використовується тут?
  5) Чому вузький backend знову звіряє голову й арність? }
constructor TVerifiedWideContext.Create(
  const ProgramPhysical,AuthorityRoot:RawByteString);
var Tables:TDomainSet;Head:TWideIRNode;
begin
  inherited Create;
  FUsed:=False;
  Require((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
    'порожня або завелика фізична .sens програма');
  Require(AuthorityRoot<>'','потрібен pinned SENS authority root');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(ProgramPhysical,Tables,FIR);
  VerifyWideIRStructure(FIR,FStats);
  Require((FStats.Roots=1) and (Length(FIR.Roots)=1) and
    (FIR.Roots[0]=0) and (FStats.Nodes>=3) and
    (Length(FIR.Nodes)>=3) and
    (FIR.Nodes[0].Kind=wkList) and
    (FIR.Nodes[0].ParentIndex=-1) and
    (FIR.Nodes[0].RootIndex=0) and
    (FIR.Nodes[0].Depth=0),
    'потрібна одна повністю перевірена D2 форма');
  Head:=FIR.Nodes[1];
  Require((Head.Kind=wkAtom) and Head.OwnWord and Head.HasPinnedKey and
    (Head.ParentIndex=0) and (Head.ChildIndex=0) and
    (Head.RootIndex=0) and (Head.Depth=1) and
    SameKey(Head.NarrowKey,ExactKey(Head.Bits)),
    'голова не має точного pinned допуску');
end;

{ Lowerer — лише локальний callback на borrowed const FPC managed IR.
  Тільки перевірений конструктор створює контекст; Lower не створює
  другого читання T5M, нової таблиці чи копії IR. Result — власний
  перевірений ELF64, caller звільняє його через FPC refcount.
  Не дозволяє "успішне" повернення довільних байтів нижнього механізму.
  1) Чому контекст не має доступного setter?
  2) Чому lowerer має лишити незмінні власні form/numeric перевірки?
  3) Де перевіряємо машину після нижнього compiler?
  4) Чому Result не є даними .lisp чи D1?
  5) Хто завершує lifetime контексту? }
function TVerifiedWideContext.Lower(
  const Lowerer:TVerifiedWideLowerer):RawByteString;
var G:TELFGeometry;
begin
  Result:='';
  { Host Boolean не є SENS D1 і не бере участі в мовній семантиці.
    Контекст короткоживучий і має право РІВНО на одну спробу lowering.
    Позначаємо використання ПЕРЕД callback: повтор і reentry не можуть
    отримати внутрішній IR навіть після винятку або хибного ELF.
    Caller володіє контекстом; managed IR очищається при Free.
    1) Чому FUsed встановлюється до виклику нижнього механізму?
    2) Чому невдалий callback не дає право повторити Lower?
    3) Чому прапорець FUsed не є мовним D1?
    4) Як ізолюється наступна фізична програма? }
  Require(not FUsed,'перевірений WideIR контекст уже використано');
  Require(Assigned(Lowerer),'не задано механізму перевіреного lowering');
  FUsed:=True;
  Result:=Lowerer(FIR,FStats);
  VerifySENSELF64(Result,G);
  Require((G.Kind=3) and (G.Entry=120) and
    (G.FileBytes=Length(Result)) and (G.MachineBytes>0),
    'нижній механізм не видав перевірений ELF64 PIE');
end;
end.
