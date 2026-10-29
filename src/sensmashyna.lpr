{ G6.31 — користувацький файловий вхід до існуючих x86-64 backend.
  G6.60 — явний файловий PIE-зріз уже перевіреного ExactIR D3:110.
  G6.36 — два нових CLI профілі з наявних emitters без нових законів.
  G6.40 — жоден користувацький ELF не обходить фізичний ExactIR proof.
  Мовні закони й допуск залишаються в pinned SENS та чинних emitter-ах.
  Режим обирається лише явно, без dispatch за написанням Lisp-функції. }
program sensmashyna;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes,
  wsm.bind, wsm.exactir, wsm.exactirtoelf, wsm.ircond,
  wsm.elfpublish, wsm.elfgeometry;
const MaxSourceBytes=65536;
  { CLI параметри рівно UTF-8 байтами, без host codepage fallback. }
  KQuote=#$2D#$2D#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0;
  KAtom=#$2D#$2D#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC;
  KEq=#$2D#$2D#$D1#$82#$D0#$BE#$D1#$82#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D1#$81#$D1#$82#$D1#$8C;
  { Лише явні host-профілі вже злитих SENS pinned emitters. }
  KSelector=#$2D#$2D#$D1#$81#$D0#$B5#$D0#$BB#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BE#$D1#$80;
  KCond=#$2D#$2D#$D1#$83#$D0#$BC#$D0#$BE#$D0#$B2#$D0#$B0;
  { G6.60: явний український режим наявного ExactIR→PIE; НЕ SENS opcode. }
  KCondPie=#$2D#$2D#$D1#$83#$D0#$BC#$D0#$BE#$D0#$B2#$D0#$B0+
    #$2D#$D0#$BF#$D1#$96;
  { Профіль лише МЕХАНІЧНО маршрутизує вже зв'язану D3-голову. }
  KAuto=#$2D#$2D#$D0#$B0#$D0#$B2#$D1#$82#$D0#$BE#$D0#$BC+
    #$D0#$B0#$D1#$82#$D0#$B8#$D1#$87#$D0#$BD#$D0#$BE;
type EMashynaError=class(Exception);
function ReadExactFile(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxSourceBytes) then
      raise EMashynaError.Create('Фізичне джерело порожнє або завелике');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ G6.35: публікація тепер тільки через спільний VerifySENSELF64
  + атомарний O_EXCL writer; власного профілю ELF тут немає. }
procedure Run;
var Root,InputPath,OutputPath:String;
    Mode:RawByteString;
    Physical,Image:RawByteString;
    Geometry:TELFGeometry;
    Tables:TDomainSet;
    CandidateIR:TExactIR;
    ExpectedKind:Word;
    AutoSelected:Boolean;
begin
  if ParamCount<>4 then
    raise EMashynaError.Create(
      'Виклик: sensmashyna --автоматично|--цитата|--атом|--тотожність|--селектор|--умова|--умова-пі pinned-root вхід.sens новий.elf');
  Mode:=RawByteString(ParamStr(1)); Root:=ParamStr(2);
  InputPath:=ParamStr(3); OutputPath:=ParamStr(4);
  if (ExtractFileExt(InputPath)<>'.sens') or
     (ExtractFileExt(OutputPath)<>'.elf') then
    raise EMashynaError.Create(
      'Очікується бінарний .sens і новий .elf; .lisp тут не виконується');
  if (Mode<>KQuote) and (Mode<>KAtom) and
     (Mode<>KEq) and (Mode<>KSelector) and
     (Mode<>KCond) and (Mode<>KCondPie) and (Mode<>KAuto) then
    raise EMashynaError.Create('Невідомий явний нативний профіль');
  if not DirectoryExists(Root) then
    raise EMashynaError.Create('Не знайдено корінь pinned SENS');
  Physical:=ReadExactFile(InputPath);
  AutoSelected:=Mode=KAuto;
  { G6.62: у режимі host-auto вибір тільки за ПОВНОЮ вже
    завантаженою з pinned таблиць координатою exact D3 (width+bits).
    Цей case маршрутизує ДО наявного verified lowering, а НЕ
    ратифікує закон чи викличність форми: кожен BuildVerified*IR
    окремо перевіряє T5M/структуру/арність/фізичне походження.
    FPC керовані масиви CandidateIR живуть у Run; raw T5M лишається
    власним Physical; немає ні другого reader, ні SENS enum.
    Питання: чому W3 поза D3 не допускається? Хто перевіряє арність?
    Чому публікація ELF лише після успішної перевірки? }
  if AutoSelected then begin
    LoadPinnedDomains(RawByteString(Root),Tables);
    BuildExactIR(Physical,Tables,CandidateIR);
    if (Length(CandidateIR.Roots)<>1) or
       (Length(CandidateIR.Nodes)<2) or
       (CandidateIR.Roots[0]<>0) or
       (CandidateIR.Nodes[0].Kind<>ikList) or
       (CandidateIR.Nodes[1].Kind<>ikIdentity) or
       (not CandidateIR.Nodes[1].HasKey) or
       (CandidateIR.Nodes[1].ParentIndex<>0) or
       (CandidateIR.Nodes[1].ChildIndex<>0) or
       (CandidateIR.Nodes[1].Key.Width<>3) then
      raise EMashynaError.Create(
        'Автоматичний профіль потребує одну точну фізичну D3-голову');
    case CandidateIR.Nodes[1].Key.Bits of
      1: Mode:=KQuote;       { D3:001 — перевіряє BuildVerifiedQuoteIR }
      2: Mode:=KAtom;        { D3:010 }
      3,4: Mode:=KSelector;  { D3:011 / D3:100 }
      5: Mode:=KEq;          { D3:101 }
      6: Mode:=KCond;        { D3:110, чинний ET_EXEC }
      else raise EMashynaError.Create(
        'Немає ратифікованого нативного backend для цієї точної голови');
    end;
  end;
  { G6.40: лише pinned таблиці й фізичний reader створюють exact
    граф. Жодне текстове поле, зокрема D7/укр/en, не є викличною
    адресою, а D12+ не примушується до D1. }
  if Mode=KCondPie then begin
    { Цей шлях уже включає LoadPinnedDomains → BuildExactIR →
      VerifyExactIRStructure → вузький D3:110 lowering. Не переносити
      D1/D7/D12 закони у CLI і не створювати другого емітера. }
    Image:=BuildPinnedIRCondELF(Physical,RawByteString(Root));
    ExpectedKind:=3; { host ET_DYN/PIE, не мовний D3 }
  end else begin
  if not AutoSelected then begin
    LoadPinnedDomains(RawByteString(Root),Tables);
    BuildExactIR(Physical,Tables,CandidateIR);
  end;
  { УСІ п'ять профілів тепер звіряють CandidateIR з НЕЗАЛЕЖНО
    відновленим T5M→D2→pinned-domain деревом до emission. Старі
    emitter-и повторно перевіряють викличність і арність; жодних
    додаткових законів у CLI або BuildVerified*IR немає. }
  if Mode=KQuote then
    Image:=BuildVerifiedQuoteIR(Physical,RawByteString(Root),CandidateIR)
  else if Mode=KAtom then
    Image:=BuildVerifiedAtomIR(Physical,RawByteString(Root),CandidateIR)
  else if Mode=KEq then
    Image:=BuildVerifiedEqIR(Physical,RawByteString(Root),CandidateIR)
  else if Mode=KSelector then
    Image:=BuildVerifiedSelectorIR(Physical,RawByteString(Root),CandidateIR)
  else
    Image:=BuildVerifiedCondIR(Physical,RawByteString(Root),CandidateIR);
  { Профіль визначає лише очікуваний host ELF ABI, не мовний закон.
    Selector D3:100/011 — ET_DYN; старий COND D3:110 — ET_EXEC.
    УСІ п'ять emitters самостійно виконують pinned фізичний admission. }
  ExpectedKind:=3; { quote, EQ, selector — ET_DYN }
  if (Mode=KAtom) or (Mode=KCond) then
    ExpectedKind:=2; { atom, legacy COND — ET_EXEC }
  end;
  { G6.60: обидва режими використовують ТОЙ САМИЙ no-clobber
    перевірений публікатор; PIE отримує 0700 лише після ELF guard. }
  PublishNewELF64(OutputPath,Image,ExpectedKind,Geometry);
  WriteLn('НАТИВНИЙ-ELF-ГОТОВИЙ профіль=',Mode,
    ' байтів=',Geometry.FileBytes,' ELF-тип=',Geometry.Kind,
    ' формат=ELF64-x86-64 фізичний-вихід=T5M');
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'НАТИВНИЙ-ELF-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end end;
end.

{ Типи: Physical і Image — owned FPC RawByteString, тимчасові.
  Root — шлях до закріпленого authority, InputPath — справжні байти
  T5M, OutputPath — новий ELF64. Tables — pinned TDomainSet (D1–D10),
  CandidateIR — керовані FPC масиви, які живуть до завершення Run;
  BuildVerified*IR вдруге перевіряє provenance T5M перед ELF.
  Geometry — host ELF64 метадані,
  out заповнюється лише після успішного VerifySENSELF64+O_EXCL
  запису в wsm.elfpublish (0700 з урахуванням umask).
  Питання: 1) Чому тут немає Lisp-імен у викличній позиції?
  2) Чому зовнішній CandidateIR не довірений до нового фізичного звіряння?
  3) Що захищає існуючий файл від перезапису?
  4) Чому D7 SYN не стає Unicode scalar D12?
  5) Чому це не загальний compiler або REPL? }
