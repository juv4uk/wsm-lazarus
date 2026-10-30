{ G6.158: canonical D5:01001 packed .sens -> verified native PIE.
  .lisp — лише людиночитана проєкція «укр», не машинний вхід.
  Програма не є повним компілятором; це ізольований профіль. }
program senswidenumberpelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidenumberp,wsm.elfpublish,wsm.elfgeometry;
type ENumberCLI=class(Exception);
function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path: borrowed host шлях до фізичного T5M.
  F: owned файлопотік; Result: owned bytes.
  1) Чому .lisp не приймаємо замість фізичного .sens?
  2) Що відрізняє довжину файлу від ширини SENS слова?
  3) Хто звільняє F при exceptions? }
function ReadSource(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ENumberCLI.Create(Ukr('потрібен фізичний файл .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ENumberCLI.Create(Ukr('розмір джерела поза квотою'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Host status — UTF-8, а не машина SENS і не D7 identity.
  1) Чому відмову друкуємо тільки у stderr?
  2) Чому ELF публікується після повної перевірки? }
procedure Say(const S:RawByteString;Fail:Boolean);
var H:THandleStream;B:RawByteString;
begin
  B:=S+#10;
  if Fail then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B));finally H.Free end;
end;
procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>Ukr('--скомпілювати-D5-число')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ENumberCLI.Create(
      Ukr('виклик: senswidenumberpelf --скомпілювати-D5-число вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise ENumberCLI.Create(Ukr('потрібен Linux'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ENumberCLI.Create(Ukr('потрібен x86-64'));
  {$ENDIF}
  Physical:=ReadSource(ParamStr(2));
  Image:=BuildIRWideNumberELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say(Ukr('ЕЛЬФ-Д5-ЧИСЛО-ГОТОВО: машинний=D1-T5M байтів=')+
      IntToStr(G.FileBytes),False);
end;
begin
  ExitCode:=0;
  try Run
  except on E:Exception do begin
    Say(Ukr('ЕЛЬФ-Д5-ЧИСЛО-ВІДМОВА: ')+Ukr(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
