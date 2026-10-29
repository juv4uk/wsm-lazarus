{ G6.105 — повна фізична D6:010101 форма НСД → WideIR → справжній ELF64.
  Вхід: лише канонічний .sens D2, не .lisp/укр назва.
  Вихід: owned машинний ELF із атомарною no-clobber публікацією.
  Принципи: 1) Шлях не визначає домен. 2) WideIR перевіряє exact head.
  3) Лише виконуваний ELF обчислює НСД. 4) Чому D7 не в dispatch?
  5) Хто володіє Stream та managed RawByteString? }
program senswidensdelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidensd,wsm.elfpublish,wsm.elfgeometry;
type EIRWideNsdCLI=class(Exception);
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
    raise EIRWideNsdCLI.Create('потрібна канонічна packed .sens форма');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EIRWideNsdCLI.Create('фізична програма за межами допустимого розміру');
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
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-D6-нсд-D12')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EIRWideNsdCLI.Create(
      'виклик: senswidensdelf --скомпілювати-D6-нсд-D12 програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EIRWideNsdCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EIRWideNsdCLI.Create('потрібен x86-64');
  {$ENDIF}
  Source:=LoadPhysical(ParamStr(2));
  ELF:=BuildIRWideNsdELF(Source,'external/sens');
  PublishNewELF64(ParamStr(3),ELF,3,G);
  Send(UA('ЕЛФ-D6-НСД-ГОТОВО: байтів=')+IntToStr(G.FileBytes)+
    ' machine=EUCLID_DIV_LOOP stdout=T5M-D12',False);
end;
begin
  try Run
  except on E:Exception do begin
    Send(UA('ЕЛФ-D6-НСД-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
