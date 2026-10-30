{ G6.145 — CLI компілює цілу двійкову .sens форму D6:010010(D12).
  --скомпілювати-D6-безпечний-вивід — host interface, НЕ мовний opcode.
  Лише pinned external/sens визначає значення слова «змінити-знак».
  Guard механічно відкидає короткий write/ENOSPC після реального NEG. }
program senswidezakhystelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwideneg,wsm.elfwriteguard,wsm.elfpublish,wsm.elfgeometry;
type EWriteGuardCLI=class(Exception);
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
    raise EWriteGuardCLI.Create('потрібна канонічна packed .sens форма');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EWriteGuardCLI.Create('фізична програма за межами допустимого розміру');
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
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-D6-безпечний-вивід')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EWriteGuardCLI.Create(
      'виклик: senswidezakhystelf --скомпілювати-D6-безпечний-вивід програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EWriteGuardCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWriteGuardCLI.Create('потрібен x86-64');
  {$ENDIF}
  Source:=LoadPhysical(ParamStr(2));
  ELF:=RequireCompleteNativeWrite(BuildIRWideNegELF(Source,'external/sens'));
  PublishNewELF64(ParamStr(3),ELF,3,G);
  Send(UA('ЕЛФ-D6-ЗНАК-ГОТОВО: байтів=')+IntToStr(G.FileBytes)+
    ' machine=NEG stdout=T5M-D12-D24 write=checked',False);
end;
begin
  try Run
  except on E:Exception do begin
    Send(UA('ЕЛФ-D6-ЗНАК-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
