{ G6.99 — CLI цілої packed .sens D6:010100(D12,D12) форми.
  Вхід: borrowed локальні шляхи та явний host режим.
  Вихід: owned ELF64 PIE через checked WideIR і atomic publisher.
  Це не текстовий .lisp reader і не власний закон SENS.
  1) Чому фізичний файл мусить мати суфікс .sens?
  2) Чому тут нема обчислення математичної остачі?
  3) Де перевірено provenance?
  4) Чому публікація має no-clobber? }
program senswiderestelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwiderest,wsm.elfpublish,wsm.elfgeometry;
type EIRWideRestCLI=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Borrowed host path; Result managed exact physical bytes. No .lisp
  translation or name-based semantic inference. Stream freed in finally.
  1) Чому .sens і .lisp мають різні механічні шляхи?
  2) Хто перевіряє signed numeric D12?
  3) Чому file length не визначає сам по собі домен? }
function LoadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise EIRWideRestCLI.Create('потрібна канонічна packed .sens форма');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EIRWideRestCLI.Create('фізична програма за межами допустимого розміру');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Human-readable UTF-8 status is NOT D7 SENS source or packed T5M result.
  Handle borrowed, THandleStream owned; no partial publication on errors.
  1) Коли новий ELF отримує ім’я?
  2) Чому stderr має залишатися доступним після відмови?
  3) Як захищено existing ELF від перезапису? }
procedure Send(const Message:RawByteString;Failure:Boolean);
var H:THandleStream;B:RawByteString;
begin
  B:=Message+#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)); finally H.Free end;
end;

procedure Run;
var Source,ELF:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-D6-остача-D12')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EIRWideRestCLI.Create(
      'виклик: senswiderestelf --скомпілювати-D6-остача-D12 програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EIRWideRestCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EIRWideRestCLI.Create('потрібен x86-64');
  {$ENDIF}
  Source:=LoadPhysical(ParamStr(2));
  ELF:=BuildIRWideRestELF(Source,'external/sens');
  PublishNewELF64(ParamStr(3),ELF,3,G);
  Send(UA('ЕЛФ-D6-ОСТАЧА-ГОТОВО: байтів=')+IntToStr(G.FileBytes)+
    ' machine=CQO_IDIV_RDX stdout=T5M-D12',False);
end;
begin
  try Run
  except on E:Exception do begin
    Send(UA('ЕЛФ-D6-ОСТАЧА-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
