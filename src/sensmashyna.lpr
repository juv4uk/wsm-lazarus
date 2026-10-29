{ G6.31 — користувацький файловий вхід до існуючих x86-64 backend.
  Мовні закони й допуск залишаються в pinned SENS та чинних emitter-ах.
  Режим обирається лише явно, без dispatch за написанням Lisp-функції. }
program sensmashyna;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix,
  wsm.elfquotet5m, wsm.elfatomt5m, wsm.elfeqt5m;
const MaxSourceBytes=65536;
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
{ Створення тільки після повного допуску; O_EXCL гарантує no-clobber.
  Якщо запис не завершився, новостворений файл вилучається. }
procedure WriteNewExecutable(const Path:String;const Image:RawByteString);
var FD:CInt; Position,Written:SizeInt; Closed:Boolean;
begin
  if (Length(Image)<121) or (Copy(Image,1,4)<>#$7F'ELF') then
    raise EMashynaError.Create('Backend не повернув повний ELF64');
  FD:=fpOpen(PChar(Path), O_WRONLY or O_CREAT or O_EXCL, &700);
  if FD<0 then
    raise EMashynaError.Create('Неможливо створити новий ELF без перезапису');
  Closed:=False;
  try
    Position:=1;
    while Position<=Length(Image) do begin
      Written:=fpWrite(FD,Image[Position],Length(Image)-Position+1);
      if Written<=0 then raise EMashynaError.Create('Не вдалося записати ELF64');
      Inc(Position,Written);
    end;
    if fpClose(FD)<>0 then
      raise EMashynaError.Create('Неможливо закрити готовий ELF64');
    Closed:=True;
  except
    if not Closed then fpClose(FD);
    fpUnlink(PChar(Path));
    raise;
  end;
end;
procedure Run;
var Mode,Root,InputPath,OutputPath:String;
    Physical,Image:RawByteString;
begin
  if ParamCount<>4 then
    raise EMashynaError.Create(
      'Виклик: sensmashyna --цитата|--атом|--тотожність pinned-root вхід.sens новий.elf');
  Mode:=ParamStr(1); Root:=ParamStr(2);
  InputPath:=ParamStr(3); OutputPath:=ParamStr(4);
  if (ExtractFileExt(InputPath)<>'.sens') or
     (ExtractFileExt(OutputPath)<>'.elf') then
    raise EMashynaError.Create(
      'Очікується бінарний .sens і новий .elf; .lisp тут не виконується');
  if (Mode<>'--цитата') and (Mode<>'--атом') and
     (Mode<>'--тотожність') then
    raise EMashynaError.Create('Невідомий явний нативний профіль');
  if not DirectoryExists(Root) then
    raise EMashynaError.Create('Не знайдено корінь pinned SENS');
  Physical:=ReadExactFile(InputPath);
  { Кожен backend сам виконує T5M/D2/pinned допуск, а не fallback.
    Довжини, коди D7 і D12 не тлумачаться з тексту у цьому CLI. }
  if Mode='--цитата' then
    Image:=BuildQuoteT5MELF(Physical,RawByteString(Root))
  else if Mode='--атом' then
    Image:=BuildAtomT5MELF(Physical,RawByteString(Root))
  else
    Image:=BuildEqT5MELF(Physical,RawByteString(Root));
  WriteNewExecutable(OutputPath,Image);
  WriteLn('НАТИВНИЙ-ELF-ГОТОВИЙ профіль=',Mode,
    ' байтів=',Length(Image),' формат=ELF64-x86-64 фізичний-вихід=T5M');
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
  T5M, OutputPath — новий ELF64. FD створюється O_EXCL з правами 0700
  (з урахуванням umask), закривається після повного запису.
  Питання: 1) Чому тут немає Lisp-імен у викличній позиції?
  2) Який backend володіє перевіркою exact D3?
  3) Що захищає існуючий файл від перезапису?
  4) Чому D7 SYN не стає Unicode scalar D12?
  5) Чому це не загальний compiler або REPL? }
