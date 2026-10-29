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
uses SysUtils,Classes,BaseUnix,wsm.ird3entry;

type EPhysicalD3CLIError=class(Exception);
function CreatePrivateTemp(Template:PChar):CInt; cdecl;
  external 'c' name 'mkstemp';

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

{ Borrowed owned Image bytes <= 376; temp private FD + target hardlink.
  Source and target path are host strings, not SENS data. }
procedure PublishAtomic(const Target:String;const Image:RawByteString);
var Temp:RawByteString;FD:CInt;Directory:String;
    Written,Position:SizeInt;Closed,Created:Boolean;
begin
  Temp:='';Created:=False;Closed:=True;
  if (Image='') or (Length(Image)>4096) then
    raise EPhysicalD3CLIError.Create('Порожній або надмірний ELF образ');
  Directory:=ExtractFilePath(ExpandFileName(Target));
  if not DirectoryExists(Directory) then
    raise EPhysicalD3CLIError.Create('Не існує каталогу ELF результату');
  try
    Temp:=RawByteString(IncludeTrailingPathDelimiter(Directory)+'d3cXXXXXX');
    UniqueString(Temp);
    FD:=CreatePrivateTemp(PChar(Temp));
    if FD<0 then
      raise EPhysicalD3CLIError.Create('Неможливо створити приватний ELF inode');
    Created:=True;Closed:=False;
    try
      Position:=1;
      while Position<=Length(Image) do begin
        Written:=fpWrite(FD,Image[Position],Length(Image)-Position+1);
        if Written<=0 then
          raise EPhysicalD3CLIError.Create('Неповний машинний запис ELF');
        Inc(Position,Written);
      end;
      if fpClose(FD)<>0 then begin
        Closed:=True;
        raise EPhysicalD3CLIError.Create('Не закрито ELF перед оприлюдненням')
      end;
      Closed:=True;
    finally if not Closed then fpClose(FD) end;
    if fpChmod(PChar(Temp),&700)<>0 then
      raise EPhysicalD3CLIError.Create('Неможливо встановити права ELF');
    if fpLink(PChar(Temp),PChar(Target))<>0 then
      raise EPhysicalD3CLIError.Create(
        'Вихідний ELF уже існує або недоступний: не перезаписано');
    { Temp link and target link point to same fully written executable. }
    fpUnlink(PChar(Temp));
    Created:=False;Temp:='';
  finally
    if Created then fpUnlink(PChar(Temp))
  end;
end;

var InputPath,OutputPath:String;Physical,Image:RawByteString;
    Profile:TNativeD3Profile;ProfileLabel:RawByteString;
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
    PublishAtomic(OutputPath,Image);
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
