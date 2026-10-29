{ G6.116 — двогілковий фізичний D3/D5 compiler до одного native ELF64.
  CLI — лише host-операція публікації; жодного D7 dispatch мови. }
program senstwoarithchoiceelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irtwoarithchoice,wsm.elfpublish,wsm.elfgeometry;
const MaxPhysicalBytes=4096;
type ETwoBranchCLIError=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ S — borrowed host-рядок, OutputBytes — owned UTF-8.
  Це лише діагностика CLI, не canonical D7 чи SENS resident.
  Питання: чому UTF8Encode не використовується для .sens?
  Хто закриває THandleStream при винятку?
  Чому status не повинен потрапляти у machine stdout? }
procedure Status(const S:UnicodeString;IsError:Boolean);
var B:RawByteString;St:THandleStream;
begin
  B:=UA(S)+#10;
  if IsError then St:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else St:=THandleStream.Create(TextRec(Output).Handle);
  try St.WriteBuffer(B[1],Length(B))
  finally St.Free end;
end;

{ Borrowed FileName — тільки шлях Linux host. Result — власні packed
  T5M bytes, без будь-яких спроб відобразити їх у .lisp проєкцію.
  Host size 1..4096 обмежує пам'ять, exact-домени перевірить WideIR.
  Питання: чому .lisp відмовляє?
  Чому фіксований size-limit не додає мовного закону?
  Хто звільняє TFileStream?
  Де перевіряється canonical padding? }
function ReadPhysical(const FileName:String):RawByteString;
var Stream:TFileStream;
begin
  Result:='';
  if ExtractFileExt(FileName)<>'.sens' then
    raise ETwoBranchCLIError.Create('потрібен тільки канонічний двійковий .sens');
  Stream:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>MaxPhysicalBytes) then
      raise ETwoBranchCLIError.Create('порожнє або завелике фізичне джерело');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

{ Входи — borrowed host args. Image — owned managed ELF64.
  Publisher атомарно створює новий файл без overwrite чи symlink.
  Компілятор не повертає D1; машинний ELF під час запуску сам рахує
  ADD/SUB/CMP/SETE та серіалізує D1 через pinned T5M codec.
  Питання: чому вихід — .elf, а не .sens?
  Чому на наявний inode має бути відмова?
  Чому машина не може покладатися на Pascal bool?
  Де гарантія точних D3/D5 слів перед emit? }
procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>UA('--скомпілювати-вибір-двох-арифметичних-гілок')) then
    raise ETwoBranchCLIError.Create(
      'виклик: senstwoarithchoiceelf --скомпілювати-вибір-двох-арифметичних-гілок програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise ETwoBranchCLIError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ETwoBranchCLIError.Create('потрібен процесор x86-64');
  {$ENDIF}
  if ExtractFileExt(ParamStr(3))<>'.elf' then
    raise ETwoBranchCLIError.Create('потрібен новий вихідний .elf');
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildIRTwoArithChoiceELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Status('ВИБІР-ДВОХ-АРИФМЕТИЧНИХ-ГІЛОК-ELF-ГОТОВО: ALU/XCHG/ALU/XCHG/CMP/SETE D1-T5M bytes='+
    IntToStr(G.FileBytes),False);
end;

begin
  try Run
  except on E:Exception do begin
    Status('ВИБІР-ДВОХ-АРИФМЕТИЧНИХ-ГІЛОК-ELF-ВІДМОВА: '+UnicodeString(E.Message),True);
    ExitCode:=2;
  end end;
end.
