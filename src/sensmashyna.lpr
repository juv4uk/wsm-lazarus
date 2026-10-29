{ G6.31 — користувацький файловий вхід до існуючих x86-64 backend.
  G6.36 — два нових CLI профілі з наявних emitters без нових законів.
  Мовні закони й допуск залишаються в pinned SENS та чинних emitter-ах.
  Режим обирається лише явно, без dispatch за написанням Lisp-функції. }
program sensmashyna;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes,
  wsm.elfquotet5m, wsm.elfatomt5m, wsm.elfeqt5m,
  wsm.elfselectort5m, wsm.elfcondt5m,
  wsm.elfpublish, wsm.elfgeometry;
const MaxSourceBytes=65536;
  { CLI параметри рівно UTF-8 байтами, без host codepage fallback. }
  KQuote=#$2D#$2D#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0;
  KAtom=#$2D#$2D#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC;
  KEq=#$2D#$2D#$D1#$82#$D0#$BE#$D1#$82#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D1#$81#$D1#$82#$D1#$8C;
  { Лише явні host-профілі вже злитих SENS pinned emitters. }
  KSelector=#$2D#$2D#$D1#$81#$D0#$B5#$D0#$BB#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BE#$D1#$80;
  KCond=#$2D#$2D#$D1#$83#$D0#$BC#$D0#$BE#$D0#$B2#$D0#$B0;
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
    ExpectedKind:Word;
begin
  if ParamCount<>4 then
    raise EMashynaError.Create(
      'Виклик: sensmashyna --цитата|--атом|--тотожність|--селектор|--умова pinned-root вхід.sens новий.elf');
  Mode:=RawByteString(ParamStr(1)); Root:=ParamStr(2);
  InputPath:=ParamStr(3); OutputPath:=ParamStr(4);
  if (ExtractFileExt(InputPath)<>'.sens') or
     (ExtractFileExt(OutputPath)<>'.elf') then
    raise EMashynaError.Create(
      'Очікується бінарний .sens і новий .elf; .lisp тут не виконується');
  if (Mode<>KQuote) and (Mode<>KAtom) and
     (Mode<>KEq) and (Mode<>KSelector) and (Mode<>KCond) then
    raise EMashynaError.Create('Невідомий явний нативний профіль');
  if not DirectoryExists(Root) then
    raise EMashynaError.Create('Не знайдено корінь pinned SENS');
  Physical:=ReadExactFile(InputPath);
  { Кожен backend сам виконує T5M/D2/pinned допуск, а не fallback.
    Довжини, коди D7 і D12 не тлумачаться з тексту у цьому CLI. }
  if Mode=KQuote then
    Image:=BuildQuoteT5MELF(Physical,RawByteString(Root))
  else if Mode=KAtom then
    Image:=BuildAtomT5MELF(Physical,RawByteString(Root))
  else if Mode=KEq then
    Image:=BuildEqT5MELF(Physical,RawByteString(Root))
  else if Mode=KSelector then
    Image:=BuildSelectorT5MELF(Physical,RawByteString(Root))
  else
    Image:=BuildCondT5MELF(Physical,RawByteString(Root));
  { Профіль визначає лише очікуваний host ELF ABI, не мовний закон.
    Selector D3:100/011 — ET_DYN; COND D3:110 — ET_EXEC.
    УСІ п'ять emitters самостійно виконують pinned фізичний admission. }
  ExpectedKind:=3; { quote, EQ, selector — ET_DYN }
  if (Mode=KAtom) or (Mode=KCond) then
    ExpectedKind:=2; { atom, COND — ET_EXEC }
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
  T5M, OutputPath — новий ELF64. Geometry — host ELF64 метадані,
  out заповнюється лише після успішного VerifySENSELF64+O_EXCL
  запису в wsm.elfpublish (0700 з урахуванням umask).
  Питання: 1) Чому тут немає Lisp-імен у викличній позиції?
  2) Який із п'яти backend володіє перевіркою exact D3?
  3) Що захищає існуючий файл від перезапису?
  4) Чому D7 SYN не стає Unicode scalar D12?
  5) Чому це не загальний compiler або REPL? }
