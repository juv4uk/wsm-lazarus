{ G6.149 — host CLI для чотирьох ратифікованих двійкових
  форм, без текстового, англійського або Lisp-dispatch.
  Canonical .sens -> pinned verified WideIR -> existing ELF64 backend.
  Далі тільки verified host postpass RequireCompleteNativeWrite:
  Linux sys_write повинен завершитися ПОВНИМ записом, інакше exit(1).
  Жодного копіювання законів/нового ISA/SENS dispatch. }
program senswidezakhystzahalelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidefront,wsm.elfwriteguard,wsm.elfpublish,wsm.elfgeometry;
type EWideGuardFrontCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — borrowed host path. Result — owned physical T5M, not a D7
  text surface. A file ending .lisp is rejected before parsing.
  1) Хто володіє F:TFileStream?
  2) Чому ширина домену не встановлюється за розміром файла?
  3) Де перевіряється ратифікована голова? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (ExtractFileExt(Path)<>'.sens') or
     (Length(Path)>4096) then
    raise EWideGuardFrontCLI.Create('потрібна фізична канонічна програма .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EWideGuardFrontCLI.Create('фізичне джерело порожнє або завелике');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Human host status is UTF-8, not source language or D1/T5M result.
  Handle is borrowed, stream and bytes are owned/freed after call.
  1) Чому output .elf не змінюється до повної верифікації?
  2) Чому stderr незалежний від фізичного stdout ELF?
  3) Який механізм захищає від перезапису існуючого ELF?
  4) Чому перевірка write є host I/O законом, а НЕ SENS функцією?
  5) Як вихідний двійковий T5M лишається незмінним? }
procedure Say(const Value:RawByteString;Failure:Boolean);
var H:THandleStream;B:RawByteString;
begin
  B:=Value+#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)); finally H.Free end;
end;

procedure Run;
var Source,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-захищену-форму')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EWideGuardFrontCLI.Create(
      'виклик: senswidezakhystzahalelf --скомпілювати-захищену-форму програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EWideGuardFrontCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWideGuardFrontCLI.Create('потрібен x86-64');
  {$ENDIF}
  Source:=ReadPhysical(ParamStr(2));
  Image:=RequireCompleteNativeWrite(
    BuildVerifiedWideELF(Source,'external/sens'));
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say(UA('ЕЛЬФ-ОБЄДНАНИЙ-ГОТОВО: байтів=')+IntToStr(G.FileBytes)+
      ' machine=pinned-exact-WideIR stdout=T5M write=checked',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
