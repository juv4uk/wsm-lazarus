{ G6.261 — CLI обмеженого pinned D5:01010(D24,D24) AOT-компілятора.
  Єдиний source: ОДНА канонічна фізична програма .sens (packed T5M).
  Домен/закон перевіряє існуючий TVerifiedWideContext, не ця команда.
  BuildIRWideD24CarryELF виконує pinned D5 admission та машинний ADD/ADC.
  PublishNewELF64 видає власні ELF bytes новою ціллю без перезапису.
  Вхід: позичений файловий шлях, фізичні bytes живуть у RawByteString.
  Вихід: новий ELF64 PIE 0700; stdout — тільки український host-звіт;
  stderr — українська діагностика, exit 2 на відмові, часткового ELF нема.
  Запитання:
  1) Чому .sens — фізичний T5M, а .lisp не можна підставити як байти?
  2) Хто підтверджує D5:01010 і W24 без англійського dispatch?
  3) Чому вихід .elf можна публікувати тільки після WideIR/ELF gate?
  4) Чому атомарний no-clobber є host-властивістю, а не SENS законом?
  5) Чим цей AOT відрізняється від динамічного ABI? }
program sensirwided24elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwided24carry,wsm.elfpublish,
     wsm.elfgeometry;
type EPhysicalD24CLI=class(Exception);
const
  MaxSourceBytes=65536;
  MaxPathBytes=4096;
  ModeCompile:RawByteString='--скомпілювати-D24-форму';

{ UnicodeString — тільки людиночитана host діагностика.
  THandleStream обгортає ПОЗИЧЕНИЙ fd stdout/stderr, не закриває його;
  у stdout нічого не друкуємо до успішної атомарної публікації. }
procedure Report(const MessageText:UnicodeString;IsFailure:Boolean);
var Buffer:RawByteString;Stream:THandleStream;
begin
  Buffer:=RawByteString(UTF8Encode(MessageText))+#10;
  if IsFailure then
    Stream:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else
    Stream:=THandleStream.Create(TextRec(Output).Handle);
  try
    Stream.WriteBuffer(Buffer[1],Length(Buffer));
  finally
    Stream.Free;
  end;
end;

{ ReadFile: позичений абсолютний/відносний host шлях до .sens,
  Result: власні 1..65536 packed T5M байтів.
  Ніякого перетворення в ASCII/Unicode, width із файлу НЕ вгадуємо.
  Відмова на не-.sens, порожньому/надмірному файлі до allocation.
  1) Чому двійкові 0x00 байти зберігаємо без переведення рядків?
  2) Чому width D24 підтверджує лише pinned binder після читання?
  3) Хто звільняє TFileStream за помилки ReadBuffer?
  4) Чому нема часткових output ELF під час читання? }
function ReadPhysicalFile(const Path:String):RawByteString;
var Source:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>MaxPathBytes) or
     (ExtractFileExt(Path)<>'.sens') then
    raise EPhysicalD24CLI.Create('потрібне фізичне джерело .sens');
  Source:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Source.Size<1) or (Source.Size>MaxSourceBytes) then
      raise EPhysicalD24CLI.Create('фізична програма порожня або понад 65536 байтів');
    SetLength(Result,SizeInt(Source.Size));
    Source.ReadBuffer(Result[1],Length(Result));
  finally
    Source.Free;
  end;
end;

{ Справжній compiler CLI: source→verified WideIR→ELF → no-clobber.
  Root — borrowed pinned external/sens з cwd (не пошук у PATH).
  Image та Physical — FPC owned managed raw byte strings.
  Geometry — стековий verified host ELF descriptor, не мовне число.
  1) Де відбувається fail-closed D24→D48 overflow?
  2) Чому Linux x86-64 перевіряємо до компіляції?
  3) Як відрізнити фізичний D5 від host stdout статусу?
  4) Чому вже зайнятий output ніколи не перезаписуємо? }
procedure Run;
var Physical,Image:RawByteString;Geometry:TELFGeometry;Dest:String;
begin
  if (ParamCount<>3) or (RawByteString(ParamStr(1))<>ModeCompile) or
     (ExtractFileExt(ParamStr(3))<>'.elf') or
     (ParamStr(3)='') or (Length(ParamStr(3))>MaxPathBytes) then
    raise EPhysicalD24CLI.Create(
      'виклик: sensirwided24elf --скомпілювати-D24-форму програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EPhysicalD24CLI.Create('потрібна Linux x86-64 система');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EPhysicalD24CLI.Create('потрібен процесор x86-64');
  {$ENDIF}
  Physical:=ReadPhysicalFile(ParamStr(2));
  Image:=BuildIRWideD24CarryELF(Physical,'external/sens');
  Dest:=ParamStr(3);
  PublishNewELF64(Dest,Image,3,Geometry);
  if (Geometry.Kind<>3) or (Geometry.Entry<>120) or
     (Geometry.FileBytes<>Length(Image)) or (Geometry.MachineBytes<1) then
    raise EPhysicalD24CLI.Create('ELF64 не відповідає перевіреній геометрії');
  Report('КОМПІЛЯТОР-D24-ГОТОВО: source=physical-D5-W24 IR=pinned-wide'+
         ' machine=ADD-ADC ELF64=PIE bytes='+IntToStr(Geometry.FileBytes),False);
end;

begin
  try
    Run;
  except
    on E:Exception do begin
      Report('КОМПІЛЯТОР-D24-ВІДМОВА: '+UnicodeString(E.Message),True);
      ExitCode:=2;
    end;
  end;
end.
