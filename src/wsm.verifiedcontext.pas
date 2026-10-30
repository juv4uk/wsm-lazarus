{ G6.180 — ПЕРЕВІРЕНИЙ КОНТЕКСТ КОМПІЛЯЦІЇ (один прохід T5M → WideIR).
  Замінює повторне декодування: раніше фронт і backend незалежно робили
  DecodeT5M + EncodeT5M-перевірку + LoadPinnedDomains + BuildWideIR +
  VerifyWideIRStructure. Тепер це відбувається РІВНО ОДИН раз, а
  результат передається далі як незмінний контекст.

  Це НЕ новий реєстр законів, НЕ другий evaluator і НЕ emitter.
  Pinned SENS лишається єдиним джерелом значень та identity. }
unit wsm.verifiedcontext;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.domain, wsm.wideir, wsm.wideirguard;

type
  EVerifiedContextError = class(Exception);

  { Контекст існує ЛИШЕ протягом однієї компіляції. Створити його можна
    тільки через AdmitVerifiedProgram: жодного публічного конструктора,
    жодного поля, яке можна заповнити ззовні. Після Admission фізичні
    байти та IR є приватними копіями, тому мутація зовнішніх структур
    не може змінити перевірений вміст. }
  { Точний домен голови: ширина + фізичні біти. Не назва, не значення. }
  TVerifiedHead = record
    Width: Byte;
    Bits: RawByteString;
  end;

  TVerifiedProgram = class
  private
    FPhysical: RawByteString;   { власна канонічна копія }
    FIR: TWideIR;               { власна копія перевіреного IR }
    FStats: TWideIRGuardStats;
    FHead: TVerifiedHead;       { точний домен голови, не назва }
    FSealed: Boolean;
    constructor CreateSealed(const Physical: RawByteString;
      const IR: TWideIR; const Stats: TWideIRGuardStats;
      const Head: TVerifiedHead);
  public
    destructor Destroy; override;
    { Повертаємо копії: викликач не може змінити перевірений стан. }
    function PhysicalCopy: RawByteString;
    function IRCopy: TWideIR;
    function StatsCopy: TWideIRGuardStats;
    function HeadDomain: TVerifiedHead;
  end;

{ ЄДИНИЙ шлях створення. Робить повну перевірку один раз:
  розмір → DecodeT5M → канонічність T5M → pinned-таблиці → WideIR →
  структурна перевірка → один канонічний D2-корінь. Будь-яка помилка
  знищує тимчасовий стан і не лишає нічого по собі. }
function AdmitVerifiedProgram(const ProgramPhysical, AuthorityRoot: RawByteString): TVerifiedProgram;

{ Лічильники для доказу, що прохід справді один (лише читання). }
function AdmissionCount: LongInt;
procedure ResetAdmissionCount;

implementation

uses wsm.t5m, wsm.bind;

var
  GAdmissions: LongInt = 0;

function AdmissionCount: LongInt;
begin
  Result := GAdmissions;
end;

procedure ResetAdmissionCount;
begin
  GAdmissions := 0;
end;

constructor TVerifiedProgram.CreateSealed(const Physical: RawByteString;
  const IR: TWideIR; const Stats: TWideIRGuardStats;
  const Head: TVerifiedHead);
begin
  inherited Create;
  FPhysical := Physical;
  FIR := IR;
  FStats := Stats;
  FHead := Head;
  FSealed := True;
end;

destructor TVerifiedProgram.Destroy;
begin
  FPhysical := '';
  SetLength(FIR.Nodes, 0);
  SetLength(FIR.Roots, 0);
  inherited Destroy;
end;

function TVerifiedProgram.PhysicalCopy: RawByteString;
begin
  Result := FPhysical;
end;

function TVerifiedProgram.IRCopy: TWideIR;
begin
  Result := FIR;
end;

function TVerifiedProgram.StatsCopy: TWideIRGuardStats;
begin
  Result := FStats;
end;

function TVerifiedProgram.HeadDomain: TVerifiedHead;
begin
  Result := FHead;
end;

function AdmitVerifiedProgram(const ProgramPhysical, AuthorityRoot: RawByteString): TVerifiedProgram;
var
  Tables: TDomainSet;
  IR: TWideIR;
  Stats: TWideIRGuardStats;
  Words: TExactWords;
  Head: TWideIRNode;
  HeadKey: TVerifiedHead;
begin
  Result := nil;
  if (Length(ProgramPhysical) = 0) or (Length(ProgramPhysical) > 65536) then
    raise EVerifiedContextError.Create('фізична .sens програма порожня або завелика');
  DecodeT5M(ProgramPhysical, Words);
  if EncodeT5M(Words) <> ProgramPhysical then
    raise EVerifiedContextError.Create('джерело не є канонічним T5M');
  LoadPinnedDomains(String(AuthorityRoot), Tables);
  BuildWideIR(ProgramPhysical, Tables, IR);
  VerifyWideIRStructure(IR, Stats);
  if not ((Stats.Roots = 1) and (Length(IR.Roots) = 1) and (IR.Roots[0] = 0) and
          (Stats.Nodes >= 3) and (Length(IR.Nodes) >= 3)) then
    raise EVerifiedContextError.Create('потрібен рівно один канонічний D2 корінь');
  if (IR.Nodes[0].Kind <> wkList) or (IR.Nodes[0].ParentIndex <> -1) or
     (IR.Nodes[0].RootIndex <> 0) or (IR.Nodes[0].Depth <> 0) then
    raise EVerifiedContextError.Create('корінь IR не є структурою D2');
  Head := IR.Nodes[1];
  if (Head.Kind <> wkAtom) or (not Head.OwnWord) or (not Head.HasPinnedKey) or
     (Head.ParentIndex <> 0) or (Head.ChildIndex <> 0) or (Head.Depth <> 1) then
    raise EVerifiedContextError.Create('виклична голова не підтверджена pinned');
  { Точний домен голови: ширина та фізичні біти, без виведення з назви. }
  HeadKey.Width := Head.Width;
  HeadKey.Bits := Head.Bits;
  Inc(GAdmissions);
  Result := TVerifiedProgram.CreateSealed(ProgramPhysical, IR, Stats, HeadKey);
end;

end.
