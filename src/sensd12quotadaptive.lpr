{ G6.178 — адаптивна машинна D5:10111, два runtime D12 T5M.
  Canonical input .sens — borrowed фізичні паковані слова.
  Result — owned ELF bytes, PublishNewELF64 no-clobber.
  .lisp лишається повною українською людиночитаною проєкцією.
  1) Чому CLI не читає .lisp як машинний код?
  2) Чому перевірка домену в pinned WideIR, а не тут?
  3) Де з'являється D24 і хто володіє ELF?
  4) Чому не перезаписуємо існуючий ELF? }
program sensd12quotadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12quotadaptive,wsm.elfpublish,wsm.elfgeometry;
type EAdaptiveQuotCLI=class(Exception);
const ModeBuild:RawByteString='--зібрати-адаптивну-D5-частку';

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
    raise EAdaptiveQuotCLI.Create('потрібен фізичний canonical .sens якір');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EAdaptiveQuotCLI.Create('фізичне джерело порожнє або завелике');
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
    raise EAdaptiveQuotCLI.Create(
      'виклик: sensd12quotadaptive --зібрати-адаптивну-D5-частку якір.sens новий.elf');
  {$IFNDEF LINUX}
  raise EAdaptiveQuotCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EAdaptiveQuotCLI.Create('потрібен x86-64');
  {$ENDIF}
  Anchor:=ReadPhysical(ParamStr(2));
  Image:=BuildAdaptiveD12QuotStreamELF(Anchor,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say('Д5-ЧАСТКА-АДАПТИВНА-ГОТОВО байтів='+IntToStr(G.FileBytes)+
    ' machine=CDQ_IDIV_R9D stdin=2xT5M-D12 stdout=T5M-D12-or-D24',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say('Д5-ЧАСТКА-АДАПТИВНА-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
