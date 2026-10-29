{ G6.89 — вузький CLI для справжньої вкладеної фізичної SENS програми.
  Скомпільований ELF виконує ADD/CMP/SETG, не host Pascal evaluator. }
program senswideaddgreaterelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwideaddgreater,wsm.elfpublish,wsm.elfgeometry;
const MaxPhysicalProgram=4096;
type EWideAddGreaterCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Message(const S:UnicodeString;ErrorOutput:Boolean);
var B:RawByteString;St:THandleStream;
begin
  B:=UA(S)+#10;
  if ErrorOutput then St:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else St:=THandleStream.Create(TextRec(Output).Handle);
  try St.WriteBuffer(B[1],Length(B));
  finally St.Free end;
end;

{ Borrowed FileName — шлях host, НЕ мовний D7 resident. Result — owned
  RawByteString із canonical T5M bytes (пізніше перевіряє reader).
  Максимум 4 КіБ обмежує host I/O, не змінює SENS закони.
  1) Чому потрібне .sens?
  2) Чому не перекодовуємо байти у текст?
  3) Коли звільняється stream?
  4) Хто перевіряє exact widths? }
function ReadPhysical(const FileName:String):RawByteString;
var St:TFileStream;
begin
  Result:='';
  if ExtractFileExt(FileName)<>'.sens' then
    raise EWideAddGreaterCLI.Create('вхід — тільки фізичний двійковий .sens');
  St:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if (St.Size<1) or (St.Size>MaxPhysicalProgram) then
      raise EWideAddGreaterCLI.Create('порожній або завеликий T5M');
    SetLength(Result,SizeInt(St.Size));
    St.ReadBuffer(Result[1],Length(Result));
  finally St.Free end;
end;

{ Borrowed source / managed Image; PublishNewELF64 забезпечує атомарний
  no-clobber executable файл після кінцевого ELF64 geometry guard.
  Нульова відповідь D1 не є порожнім списком D3:000.
  1) Чому текстова проєкція не є executable?
  2) Чому machine генерує результат при виконанні?
  3) Що забороняє перезапис чужого ELF?
  4) Чому тут немає семантичної таблиці? }
procedure Run;
var Source,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-вкладене-більше')) then
    raise EWideAddGreaterCLI.Create(
      'виклик: senswideaddgreaterelf --скомпілювати-вкладене-більше програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EWideAddGreaterCLI.Create('потрібний Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWideAddGreaterCLI.Create('потрібний x86-64');
  {$ENDIF}
  if ExtractFileExt(ParamStr(3))<>'.elf' then
    raise EWideAddGreaterCLI.Create('потрібний новий вихід .elf');
  Source:=ReadPhysical(ParamStr(2));
  Image:=BuildIRWideAddGreaterELF(Source,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Message('ВКЛАДЕНИЙ-Д5-ЕЛФ-ГОТОВО ADD+CMP+SETG → D1-T5M, байтів='+
    IntToStr(G.FileBytes),False);
end;
begin
  try Run
  except on E:Exception do begin
    Message('ВКЛАДЕНИЙ-Д5-ЕЛФ-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
