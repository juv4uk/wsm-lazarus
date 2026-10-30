{ G6.184 — знакова машинна Д6:010100, два runtime D12 T5M.
  Canonical input .sens — borrowed фізичні паковані слова.
  Result — owned ELF bytes, PublishNewELF64 no-clobber.
  .lisp лишається повною українською людиночитаною проєкцією.
  1) Чому CLI не читає .lisp як машинний код?
  2) Чому перевірка домену в pinned WideIR, а не тут?
  3) Чому знакова остача D12, а не довільний host integer?
  4) Чому не перезаписуємо існуючий ELF? }
program sensd12restsigned;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12restsigned,wsm.elfpublish,wsm.elfgeometry;
type ESignedRestCLI=class(Exception);
const ModeBuild:RawByteString='--зібрати-D6-остачу-зі-знаком';

procedure Say(const Message:UnicodeString;ToError:Boolean);
var Bytes:RawByteString;Stream:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  if ToError then Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;

{ Borrowed host Path, Result owned canonical physical RawByteString.
  TFileStream destroyed even on exceptions. No text name dispatch.
  1) Why require exact .sens extension?
  2) Why bound size before allocation?
  3) Why restrict share mode?
  4) How does downstream pinned WideIR validate the content? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ESignedRestCLI.Create('потрібен фізичний canonical .sens якір');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ESignedRestCLI.Create('фізичне джерело порожнє або завелике');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ The compiler calls verified pinned WideIR and machine builder.
  It never computes arithmetic in Pascal. One saved ELF is reusable
  for multiple distinct runtime physical D12 pairs. }
procedure Run;
var Anchor,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>ModeBuild) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ESignedRestCLI.Create(
      'виклик: sensd12restsigned --зібрати-D6-остачу-зі-знаком якір.sens новий.elf');
  {$IFNDEF LINUX}
  raise ESignedRestCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ESignedRestCLI.Create('потрібен x86-64');
  {$ENDIF}
  Anchor:=ReadPhysical(ParamStr(2));
  Image:=BuildSignedD12RestStreamELF(Anchor,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say('Д6-ОСТАЧА-ЗНАК-ГОТОВО байтів='+IntToStr(G.FileBytes)+
    ' machine=CDQ_IDIV_R9D stdin=2xT5M-D12 stdout=T5M-D12',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say('Д6-ОСТАЧА-ЗНАК-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
