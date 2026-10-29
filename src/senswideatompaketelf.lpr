{ G6.134 — атомарна публікація ЦІЛОГО каталогу ELF64.
  Exact SENS admission — тільки вже злитий pinned BuildVerifiedWideELF.
  Linux renameat2(RENAME_NOREPLACE) — host filesystem, НЕ закон SENS. }
program senswideatompaketelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, wsm.irwidefront, wsm.elfpublish,
     wsm.elfgeometry;

type EAtomPackageError=class(Exception);
     TItem=record
       Name: String;
       Image: RawByteString;
     end;
     TItems=array of TItem;

function MakeTempDir(Template:PChar):PChar; cdecl;
  external 'c' name 'mkdtemp';
function RenameNew(OldFd:cint;OldName:PChar;NewFd:cint;
  NewName:PChar;Flags:cuint):cint; cdecl;
  external 'c' name 'renameat2';
const LinuxAtCurrentDir=-100;
      LinuxRenameNoReplace=1;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Say(const Message:RawByteString; Bad:Boolean);
var H:THandleStream; B:RawByteString;
begin
  B:=Message+#10;
  if Bad then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)); finally H.Free end;
end;

procedure Need(Ok:Boolean;const Message:String);
begin if not Ok then raise EAtomPackageError.Create(Message) end;

{ Вхідний шлях — host параметр; результат — власні packed T5M bytes.
  Ширину, домен, D7 та числовий допуск визначає тільки downstream
  pinned SENS WideIR compiler. TFileStream живе тільки під час читання.
  1) Чому розширення .lisp відхиляємо? 2) Хто володіє RawByteString?
  3) Де перевіряється T5M canonical round-trip? 4) Чи є host байт D12? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  Need((Path<>'') and (Length(Path)<=4096) and
    (ExtractFileExt(Path)='.sens'),
    'вхід має бути фізичною canonical .sens програмою');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>=1) and (F.Size<=65536),
      'фізичний .sens порожній або перевищує межу');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Програми — приватні managed Image байти ELF64 до ВСЯКОГО запису;
  1..16 фізичних програм компілюються через готовий native backend.
  Повторні імена output у межах пакета заборонено навіть для двох
  різних каталогів inputs. Ні текстових імен для семантичного dispatch,
  ні нового Pascal register законів.
  1) Чому все admission у пам'яті? 2) Чому дубльоване ім'я відхилено?
  3) Що робить BuildVerifiedWideELF із W12 і D12? 4) Хто володіє Image?
  5) Яка межа підтриманих операцій в existing WideIR? }
function Prepare:TItems;
var I,J,N:Integer; Name:String; Physical:RawByteString;
begin
  N:=ParamCount-2;
  Need((N>=1) and (N<=16),'потрібно 1..16 фізичних програм');
  SetLength(Result,N);
  for I:=0 to N-1 do begin
    Name:=ChangeFileExt(ExtractFileName(ParamStr(I+3)),'.elf');
    Need((Name<>'.elf') and (Name<>'') and (Length(Name)<=255),
      'неправильне ім’я фізичного виходу');
    for J:=0 to I-1 do
      Need(Result[J].Name<>Name,'два входи мають однакове ім’я ELF');
    Physical:=ReadPhysical(ParamStr(I+3));
    Result[I].Name:=Name;
    Result[I].Image:=BuildVerifiedWideELF(Physical,'external/sens');
  end;
end;

{ Всі ELF створюються приватно: mkdtemp робить 0700, чинний
  PublishNewELF64 повторно перевіряє ELF і записує новий host файл.
  ЄДИНИЙ renameat2(RENAME_NOREPLACE) відкриває готовий каталог
  атомарно. На невдачі прибираємо ТІЛЬКИ власний private staging
  (жодних видалень/overwrite цільових файлів). Final path та
  згенеровані Images — позичені дані; Items звільнить FPC.
  1) Чому rename(2) без RENAME_NOREPLACE небезпечний?
  2) Чому mkdtemp у тому самому parent для atomic directory move?
  3) Чому staging каталог може існувати, але final не частковий?
  4) Як поведеться змагання двох процесів за ту саму ціль?
  5) Що трапиться за відсутності host renameat2 support? }
procedure Run;
var Items:TItems; FinalDir,Parent,Template,StageDir:String;
    Temp:RawByteString; I:Integer; G:TELFGeometry;
    StageReady:Boolean;
begin
  Need((ParamCount>=3) and (ParamCount<=18) and
    (RawByteString(ParamStr(1))=UA('--скомпілювати-атомарний-пакет')),
    'виклик: senswideatompaketelf --скомпілювати-атомарний-пакет НОВА-ТЕКА форма1.sens [..до 16]');
  {$IFNDEF LINUX}
  raise EAtomPackageError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EAtomPackageError.Create('потрібен x86-64');
  {$ENDIF}

  Need((ParamStr(2)<>'') and (Length(ParamStr(2))<=4096),
    'неправильний шлях вихідного каталогу');
  FinalDir:=ExpandFileName(ParamStr(2));
  Parent:=ExtractFileDir(FinalDir);
  Need((Parent<>'') and DirectoryExists(Parent),
    'батьківський каталог не існує');
  Need(not FileExists(FinalDir) and not DirectoryExists(FinalDir),
    'вихідний каталог уже зайнятий');
  Items:=Prepare;   { усі форми допущено ДО створення staging }
  Template:=IncludeTrailingPathDelimiter(Parent)+'.senpakXXXXXX';
  Need(Length(Template)<4096,'завелика назва тимчасової теки');

  Temp:=RawByteString(Template);
  UniqueString(Temp);
  StageReady:=False;
  StageDir:='';
  try
    Need(MakeTempDir(PChar(Temp))<>nil,
      'не створено приватний staging 0700');
    StageDir:=String(Temp);
    StageReady:=True;
    for I:=0 to High(Items) do
      PublishNewELF64(IncludeTrailingPathDelimiter(StageDir)+Items[I].Name,
        Items[I].Image,3,G);
    Need(RenameNew(LinuxAtCurrentDir,PChar(StageDir),
       LinuxAtCurrentDir,PChar(FinalDir),LinuxRenameNoReplace)=0,
       'атомарна публікація не вдалася: ціль зайнята або syscall недоступний');
    StageReady:=False; { тепер власник — фінальний каталог }
  finally
    if StageReady then begin
      for I:=0 to High(Items) do
        fpUnlink(PChar(IncludeTrailingPathDelimiter(StageDir)+Items[I].Name));
      fpRmdir(PChar(StageDir));
    end;
  end;
  Say(UA('АТОМ-ПАКЕТ-ГОТОВО: фізичних-ELF=')+IntToStr(Length(Items))+
    ' machine=pinned-exact-WideIR каталог=atomic-no-replace energy=NOT-MEASURED',False);
end;

begin
  try Run
  except on E:Exception do begin
    Say(UA('АТОМ-ПАКЕТ-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
