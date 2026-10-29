{ G6.85 — реальна компіляція єдиної фізичної D5:11011 форми.
  CLI — host-межа, не новий закон SENS і не текстовий dispatch. }
program senswidebilsh_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidegreater,wsm.elfpublish,wsm.elfgeometry;
const MaxProgramBytes=4096;
type EWideGreaterCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure SendLine(const S:UnicodeString;ErrorOutput:Boolean);
var B:RawByteString;H:THandleStream;
begin
  B:=UA(S)+#10;
  if ErrorOutput then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B));
  finally H.Free end;
end;

{ Borrowed Path — лише шлях host. Вихід — owned exact bytes до 4096;
  TFileStream закривається і при винятку. Жодної конверсії у .lisp.
  1) Чому не читаємо UTF8 як джерело мови?
  2) Чи визначає розмір файлa доменну адресу?
  3) Хто володіє RawByteString?
  4) Чому заборонено .lisp? }
function ReadSource(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (ExtractFileExt(Path)<>'.sens') then
    raise EWideGreaterCLI.Create('потрібне канонічне двійкове .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxProgramBytes) then
      raise EWideGreaterCLI.Create('порожня або завелика фізична програма');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Рівно один режим компіляції фізичної форми; Image managed owned.
  Publisher гарантує no-clobber нової цілі та executable mode.
  1) Чому не виводимо результат порівняння з Pascal?
  2) Як відрізняються .sens та .elf?
  3) Хто перевіряє фізичний WideIR?
  4) Чому machine-time результат є D1? }
procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-D5-більше-D12')) then
    raise EWideGreaterCLI.Create(
      'виклик: senswidebilsh-elf --скомпілювати-D5-більше-D12 програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EWideGreaterCLI.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWideGreaterCLI.Create('потрібен x86-64');
  {$ENDIF}
  if ExtractFileExt(ParamStr(3))<>'.elf' then
    raise EWideGreaterCLI.Create('потрібен новий .elf');
  Physical:=ReadSource(ParamStr(2));
  Image:=BuildPhysicalGreaterELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  SendLine('ЕЛФ-D5-ШИРОКЕ-БІЛЬШЕ-ГОТОВО: machine=CMP/SETG '+
    'stdout=T5M-D1 bytes='+IntToStr(G.FileBytes),False);
end;
begin
  try Run
  except on E:Exception do begin
    SendLine('ЕЛФ-D5-ШИРОКЕ-БІЛЬШЕ-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
