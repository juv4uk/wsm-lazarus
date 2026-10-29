{ G6.74 — незалежний файловий compiler фізичної D7 рівності.
  На вході тільки packed canonical .sens; .lisp — лише укр-проєкція.
  На виході перевірений ELF64 ET_DYN без перезапису. }
program sensird7eqelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird7eq,wsm.elfpublish,wsm.elfgeometry;
const MaxPhysicalBytes=65536;
type EIRD7CLIError=class(Exception);

{ InputPath/Root — borrowed host-шляхи; Source — owned RawByteString,
  фізичні T5M bytes, не український текст. FileStream закривається.
  Що означає точна ширина? Чому input .lisp не допускається?
  Чому вхід не можна читати через звичайний TextFile? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxPhysicalBytes) then
      raise EIRD7CLIError.Create('Некоректна довжина фізичного входу');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Host stdout/stderr explicit UTF-8; never T5M. Sink does not own handle.
  Чому вихідний ELF не повинен містити UTF-8? Як stderr відрізняється
  від фізичного машинного stdout? Де помилка зупиняє публікацію ELF? }
procedure Message(const S:UnicodeString;ToError:Boolean);
var Bytes:UTF8String;Sink:THandleStream;
begin
  Bytes:=UTF8Encode(S)+#10;
  if ToError then Sink:=THandleStream.Create(TextRec(StdErr).Handle)
  else Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Bytes[1],Length(Bytes))
  finally Sink.Free end;
end;

procedure Run;
var Mode,Root,InputPath,OutputPath:String;
    Image,Physical:RawByteString;
    Geometry:TELFGeometry;
begin
  if ParamCount<>3 then
    raise EIRD7CLIError.Create(
      'Виклик: sensird7eqelf pinned-root вхід.sens новий.elf');
  Root:=ParamStr(1);InputPath:=ParamStr(2);OutputPath:=ParamStr(3);
  if (ExtractFileExt(InputPath)<>'.sens') or
     (ExtractFileExt(OutputPath)<>'.elf') then
    raise EIRD7CLIError.Create(
      'Потрібні саме фізичний .sens та новий .elf');
  if not DirectoryExists(Root) then
    raise EIRD7CLIError.Create('Відсутній pinned SENS');
  Physical:=ReadPhysical(InputPath);
  Image:=BuildPinnedQuotedD7EqIRELF(Physical,RawByteString(Root));
  { Вже перевірений host ELF publisher: mode 0700, no-clobber.
    Немає D12+ числового dispatch або виклику за D7-проєкцією. }
  PublishNewELF64(OutputPath,Image,3,Geometry);
  Message('ПЕРЕВІРЕНИЙ-Д7-ЕЛФ-ГОТОВИЙ байтів='+
    IntToStr(Geometry.FileBytes),False);
end;
begin
  try Run
  except on E:Exception do begin
    Message('ПРЯМИЙ-Д7-ЕЛФ-ПОМИЛКА: '+UnicodeString(E.Message),True);
    ExitCode:=2
  end end;
end.
