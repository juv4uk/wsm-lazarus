{ G6.128 — публічний нативний компілятор ПОВНОЇ binary .sens програми.
  Це не eval і не SIR1 та не новий D3 закон: лише wrapper чинного
  BuildVerifiedD3ELF і host Linux no-clobber atomic ELF publisher.
  Профілі: pinned D3 EQ simple, D3 EQ nested, D3 COND 0..2 гілки.
  Всі назви ключів CLI — людська українська проєкція, НЕ dispatch мови.
  Input — borrowed physical file bytes owned local; Image — owned ELF;
  Temp — private inode, створений mkstemp у вихідному каталозі;
  fpLink гарантує no-clobber навіть за dangling symlink і race.
  На кожній помилці видаляється тільки ВЛАСНИЙ тимчасовий inode.
  Питання: 1) чому file extension не є SENS законом?
  2) навіщо private mkstemp замість GetTempFileName?
  3) чому link захищає від паралельного процесу?
  4) коли виникає перший побічний ефект компілятора?
  5) хто володіє вихідним inode після успішного link? }
program sensd3kompiliator;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.ird3entry,wsm.elfpublish,wsm.elfgeometry;

type EPhysicalD3CLIError=class(Exception);
function UA(const Value:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Value)) end;

function ReadInput(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EPhysicalD3CLIError.Create('Порожня або завелика фізична .sens програма');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Єдина публікація через вже перевірений механізм wsm.elfpublish:
  fd-local fchmod 0700 ДО close, атомарний link без перезапису,
  вилучення тільки власного тимчасового inode на відмові.
  Фізичний borrowed .sens уже пройшов pinned ExactIR до цього кроку.
  Image — owned FPC-managed ELF; Geometry — локальний host результат.
  Домен D3 / D7-проєкції НЕ маршрутизуються через права файлової системи.
  Питання:
  1) Чому fchmod(fd) безпечніший за chmod(тимчасовий-шлях)?
  2) Чому проваленої публікації не можна замінювати stdout «ГОТОВО»?
  3) Що відбувається з dangling symlink на цільовому шляху?
  4) Чому elf kind=3 означає Linux ET_DYN, не мовний D3?
  5) Хто володіє FPC Image до і після повернення з PublishNewELF64? }
var InputPath,OutputPath:String;Physical,Image:RawByteString;
    Profile:TNativeD3Profile;ProfileLabel:RawByteString;
    Geometry:TELFGeometry;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>UA('--породити')) or
    (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') or
    (LowerCase(ExtractFileExt(ParamStr(3)))<>'.elf') then begin
    WriteLn(StdErr,UA('Використання: sensd3kompiliator --породити програма.sens результат.elf'));
    Halt(64);
  end;
  InputPath:=ParamStr(2);
  OutputPath:=ParamStr(3);
  try
    Physical:=ReadInput(InputPath);
    Image:=BuildVerifiedD3ELF(Physical,'external/sens',Profile);
    PublishNewELF64(OutputPath,Image,3,Geometry);
    case Profile of
      dpSingleEq: ProfileLabel:='D3:101-одинарна';
      dpNestedEq: ProfileLabel:='D3:101-вкладена';
      dpCond:ProfileLabel:='D3:110-умова';
      else raise EPhysicalD3CLIError.Create('Неочікуваний host профіль');
    end;
    WriteLn(UA('ФІЗИЧНИЙ-D3-КОМПІЛЯТОР-ГОТОВО профіль='),ProfileLabel,
      UA(' ELF64-байтів='),Length(Image));
  except on E:Exception do begin
    WriteLn(StdErr,UA('ФІЗИЧНИЙ-D3-КОМПІЛЯТОР-ПОМИЛКА: '),E.Message);
    ExitCode:=2;
  end end;
end.
