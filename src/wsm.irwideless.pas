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
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.verifiedless;

procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise EIRWideLessError.Create(Why) end;

{ Node — borrowed exact physical word, Result — managed owned packed T5M.
  Numeric admission only after the pinned D5 head and verified IR; W12
  itself is opaque. No text conversions, no English head/function dispatch.
  1) Чому ширина W12 не робить слово автоматично D12-числом?
  2) Навіщо перевіряти повторно через ReadNumericPhysical?
  3) Хто вивільняє локальні TExactWords і packed Result?
  4) Чому OpaqueLeaves=2? }
{ G6.191 інтеграція: уже злитий wsm.verifiedless має ЄДИНІ
  form/numeric/ELF-gates. У цьому unit немає дубльованого
  нижнього verifier та emitter. Чому другий набір перевірок тут
  був би небезпечним? Хто володіє borrowed verified IR? Чому
  D12 admission лишається в upstream lowerer? }
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
  Result:=wsm.verifiedless.LowerVerifiedLess(IR,Stats);
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
  Result:=Context.Lower(@wsm.verifiedless.LowerVerifiedLess);
end;
end.
