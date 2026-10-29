{ G6.91 — CLI компілює лише ОДНУ ратифіковану фізичну форму
  D5:11010 (укр менше?) над двома exact D12. Host mode не є SENS opcode.
  Немає англійського семантичного dispatch, Core1/CL runtime чи нового закону. }
program senswidemenelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwideless,wsm.elfpublish,wsm.elfgeometry;
type EWideLessCLI=class(Exception);
const MaxFileSize=65536;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — host-owned path; фізичні bytes є managed owned Result.
  Файл відкривається read-only; output file змінює тільки publisher.
  1) Чому .lisp не дозволений тут?
  2) Чи можна вгадувати SENS domain за розміром файла?
  3) Чому треба закрити stream навіть після exception? }
function ReadPhysicalProgram(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (ExtractFileExt(Path)<>'.sens') then
    raise EWideLessCLI.Create('потрібна канонічна двійкова .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxFileSize) then
      raise EWideLessCLI.Create('порожня або надмірна фізична програма');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ UTF8 — тільки людський host status, не source SENS/D7/T5M.
  THandleStream is owned and freed on all code paths.
  1) Коли stdout має лишатися порожнім?
  2) Чому no-clobber публікація відбувається наприкінці?
  3) Хто перевіряє ELF geometry? }
procedure SendLine(const Value:RawByteString;ErrorOutput:Boolean);
var H:THandleStream;B:RawByteString;
begin
  B:=Value+#10;
  if ErrorOutput then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)); finally H.Free end;
end;

procedure Run;
var Physical,Image:RawByteString; G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-D5-менше-D12')) then
    raise EWideLessCLI.Create(
      'виклик: senswidemenelf --скомпілювати-D5-менше-D12 програма.sens новий.elf');
  {$IFNDEF LINUX}
    raise EWideLessCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
    raise EWideLessCLI.Create('потрібен x86-64');
  {$ENDIF}
  if ExtractFileExt(ParamStr(3))<>'.elf' then
    raise EWideLessCLI.Create('потрібен новий вихідний .elf');
  Physical:=ReadPhysicalProgram(ParamStr(2));
  Image:=BuildIRWideLessELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  SendLine(UA('ЕЛФ-D5-ШИРОКЕ-МЕНШЕ-ГОТОВО: байтів=')+
    IntToStr(G.FileBytes)+' machine=CMP/SETL/MOVZX stdout=T5M-D1',False);
end;

begin
  try Run
  except on E:Exception do begin
    SendLine(UA('ЕЛФ-D5-ШИРОКЕ-МЕНШЕ-ВІДМОВА: ')+
      UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
