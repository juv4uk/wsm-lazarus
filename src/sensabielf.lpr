{ G6.69 — файловий host CLI для незалежного машинного CALL/RET.
  Фізичний .sens канонічний; .lisp є лише людською укр-проєкцією. }
program sensabielf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ircallabi,wsm.elfpublish,wsm.elfgeometry;

function Uk(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ InputPath — host шлях, не ім'я функції. Result — owned T5M bytes
  після ReadBuffer. Не допускаємо текстове .lisp як machine input.
  Питання: чому розширення не є доказом T5M саме по собі?
  Чому треба перевірити канонічне кодування в unit?
  Хто звільняє потік у випадку exception?
  Чому D12 не числовий літерал у цьому зрізі? }
function PhysicalSource(const InputPath:String):RawByteString;
var Stream:TFileStream;
begin
  if LowerCase(ExtractFileExt(InputPath))<>'.sens' then
    raise Exception.Create(Uk('потрібен канонічний фізичний файл .sens'));
  Stream:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>65536) then
      raise Exception.Create(Uk('фізичне джерело поза host квотою'));
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

{ Компільований ELF є owned byte string у цьому FPC процесі.
  До publication проходить повний pinned ExactIR та machine guard;
  Publisher атомарно створює ексклюзивний файл із правами 0700.
  Питання: чому не відкриваємо existing target через fmCreate?
  Чому success виводиться тільки після PublishNewELF64?
  Чому ET_DYN — host ABI, не SENS Dn?
  Чому stdout CLI не замінює stdout майбутньої ELF-програми? }
procedure Run;
var Root,InputPath,Target:String;
    Physical,Image:RawByteString; Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>Uk('--виклик-рівності')) then
    raise Exception.Create(Uk(
      'використання: sensabielf --виклик-рівності КОРІНЬ ВХІД.sens ВИХІД.elf'));
  Root:=ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
  InputPath:=ParamStr(3);Target:=ParamStr(4);
  Physical:=PhysicalSource(InputPath);
  Image:=BuildPinnedD1EqCallELF(Physical,RawByteString(Root));
  PublishNewELF64(Target,Image,3,Geometry);
  WriteLn(Uk('ABI-ELF-ГОТОВО формат=ELF64-PIE CALL=так RET=так байтів='),
    Geometry.FileBytes,Uk(' фізичний-вихід=T5M'));
end;

begin
  try Run
  except
    on E:Exception do begin
      WriteLn(StdErr,Uk('ABI-ELF-ПОМИЛКА: '),E.Message);
      ExitCode:=2;
    end;
  end;
end.
