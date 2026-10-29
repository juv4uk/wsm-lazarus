{ G6.65 — вузький справжній FPC compiler CLI для сталої D3:111.
  Канонічне джерело тільки packed .sens; .lisp не є машинним кодом.
  D7 і D12+ не перетворюються на виконуваний opcode чи host числа.
  Результат — перевірений native ELF64 PIE, без перезапису цілі. }
program sensspoluchelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irconstcons,wsm.elfpublish,wsm.elfgeometry;

function Uk(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Вхідний Path — host файл, не source projection. Власні RawByteString
  байти читаються один раз, без проміжного unicode чи десяткового числа.
  Потік закривається й при синтаксичних або файлових помилках.
  Питання: чому .lisp не допускається як .sens?
  Чому великий файл відмовляється ще до алокації?
  Хто володіє прочитаними байтами?
  Чому назва файлу не є SENS законом? }
function ReadSource(const Path:String):RawByteString;
var S:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create(Uk('потрібне канонічне фізичне джерело .sens'));
  S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (S.Size<1) or (S.Size>65536) then
      raise Exception.Create(Uk('довжина фізичного джерела поза host-лімітом'));
    SetLength(Result,SizeInt(S.Size));
    S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;

{ Побудова та публікація відбуваються в двох окремих кроках.
  Unit виконує admission через pinned ExactIR і єдиний runtime;
  PublishNewELF64 вдруге перевіряє геометрію і використовує
  приватний ексклюзивний POSIX fd для atomic no-clobber.
  Питання: чому нема прямого TFileStream(fmCreate) для ELF?
  Хто перевіряє семантику до emission?
  Чим відрізняється ET_DYN від домену D3?
  Чому негатив не повинен залишати цільовий файл? }
procedure Run;
var Root,Path,Dest:String; Physical,Image:RawByteString;
    Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>Uk('--згорнути-сполучення')) then
    raise Exception.Create(Uk(
      'використання: sensspoluchelf --згорнути-сполучення КОРІНЬ ВХІД.sens ВИХІД.elf'));
  Root:=ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
  Path:=ParamStr(3); Dest:=ParamStr(4);
  Physical:=ReadSource(Path);
  Image:=BuildPinnedConstConsELF(Physical,RawByteString(Root));
  PublishNewELF64(Dest,Image,3,Geometry);
  WriteLn(Uk('СПОЛУЧЕННЯ-ELF-ГОТОВО байтів='),Geometry.FileBytes,
    Uk(' формат=ELF64-PIE результат=пакований-T5M'));
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,Uk('СПОЛУЧЕННЯ-ELF-ПОМИЛКА: '),E.Message);
    ExitCode:=2;
  end end;
end.
