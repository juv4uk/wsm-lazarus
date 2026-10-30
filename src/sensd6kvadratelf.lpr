{ G6.128 — фізичний .sens D6 exponent2 → перевірений IMUL ELF64.
  Вхідні packed T5M байти належать caller; output ELF створюється
  атомарно через наявний PublishNewELF64, без перезапису.
  1) Чому .lisp не є канонічним машинним джерелом?
  2) Чому тільки exact D24:2 та один D2 корінь?
  3) Хто перевіряє no-clobber і ELF?
  4) Чому stdout пишемо тільки після публікації? }
program sensd6kvadratelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird6kvadrat,wsm.elfpublish,wsm.elfgeometry;
type ED6CLIError=class(Exception);
const BuildMode:RawByteString='--D6-010111-квадрат';

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise ED6CLIError.Create('потрібна канонічна фізична .sens програма');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ED6CLIError.Create('порушено host квоту фізичного .sens');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Say(const Message:UnicodeString;IsError:Boolean);
var Bytes:RawByteString;Stream:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if IsError then Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;

procedure Run;
var Physical,ELFImage:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>BuildMode) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ED6CLIError.Create(
      'виклик: sensd6kvadratelf --D6-010111-квадрат програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED6CLIError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED6CLIError.Create('потрібен Linux x86-64');
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  ELFImage:=BuildIRD6KvadratELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),ELFImage,3,G);
  Say('Д6-КВАДРАТ-ELF-ГОТОВО pinned=D6:010111 показник=D24:2 machine=IMUL байтів='+
      UnicodeString(IntToStr(G.FileBytes)),False);
end;

begin
  try Run
  except on E:Exception do begin
    Say('Д6-КВАДРАТ-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
