{ G6.67 — вузький нативний компілятор D5:10011 через pinned ExactIR.
  Лише фізичний .sens, вихід справжній ELF64 Linux x86-64. }
program sensd5thirdelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird5third,wsm.elfpublish,wsm.elfgeometry;

function Uk(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Вхідні T5M-байти належать Result, потік звільняється у finally.
  Людський .lisp ніколи не примушується до фізичної програми.
  Питання: хто володіє вхідним масивом? Що відбувається при EOF?
  Чому extension — host admission, а не мовний закон? }
function ReadSource(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise Exception.Create(Uk('потрібне тільки канонічне .sens джерело'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise Exception.Create(Uk('Фізична програма поза host-межею'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Геометрія й no-clobber перевіряються спільним PublishNewELF64.
  Весь Image готовий до публікації, жодного часткового stdout/ELF.
  Питання: чому ET_DYN не є SENS D3? Чому ELF має виконуватися?
  Хто перевіряє exact-width до запису файлу? }
procedure Run;
var Root,InputPath,OutputPath:String; Physical,Image:RawByteString;
    Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or
    (RawByteString(ParamStr(1))<>Uk('--третій-ельф')) then
    raise Exception.Create(Uk(
      'Використання: sensd5thirdelf --третій-ельф pinned-root вхід.sens новий.elf'));
  Root:=ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
  InputPath:=ParamStr(3);OutputPath:=ParamStr(4);
  if ExtractFileExt(OutputPath)<>'.elf' then
    raise Exception.Create(Uk('Вихід мусить бути новим ELF64 файлом .elf'));
  Physical:=ReadSource(InputPath);
  Image:=BuildPinnedIRThirdELF(Physical,RawByteString(Root));
  PublishNewELF64(OutputPath,Image,3,Geometry);
  WriteLn(Uk('D5-ТРЕТЄ-ELF-ГОТОВО машинний-вибір=так байтів='),
    Geometry.FileBytes,Uk(' T5M=точний'));
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,Uk('D5-ТРЕТЄ-ELF-ПОМИЛКА: '),E.Message);
    ExitCode:=2;
  end end;
end.
