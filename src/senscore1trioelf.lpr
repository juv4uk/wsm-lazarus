{ G6.150 — три ОКРЕМІ справжні AOT ELF64 із ТРЬОХ оригінальних
  фізичних Core1 DEFINE, без підміни тіл Pascal.
  Вхід: два позичені шляхи до точних D12 packed .sens.
  Owned: повний вміст двох атомів та три ELF bytes, живуть до виходу Run.
  Output: тільки новий приватний каталог 0700 із трьома verified ELF.
  Це механізм пакування спеціалізацій, не три нові закони SENS.
  Питання:
  1. Чому не можна вивести закон з імені вихідного ELF?
  2. Де джерело бібліотечних тіл і перевірка exact D7-параметрів?
  3. Чому всі три збирання закінчуються ПЕРЕД створенням каталогу?
  4. Чому кожен ELF перевіряється вдруге до публикації?
  5. Хто видаляє приватний каталог після помилки публікації? }
program senscore1trioelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.lowerpinnedcore1add,
  wsm.lowerpinnedcore1mul,wsm.elfgeometry,wsm.elfpublish;
const
  MaxPhysical=65536;
  FileNames:array[0..2] of String=(
    'додати.elf','відняти.elf','помножити.elf');
type
  ECore1TrioError=class(Exception);
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Length(Path)<1) or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.sens') then
    raise ECore1TrioError.Create('вхід мусить бути фізичним файлом .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxPhysical) then
      raise ECore1TrioError.Create('вхідний T5M порожній або завеликий');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Run;
var Left,Right,OutDir:String;
    A,B:RawByteString;
    Images:array[0..2] of RawByteString;
    G:TELFGeometry;
    I:Integer;
    Created:Boolean;
begin
  {$IFNDEF LINUX}
  raise ECore1TrioError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECore1TrioError.Create('потрібен x86-64');
  {$ENDIF}
  if (ParamCount<>4) or
     (ParamStr(1)<>'--скомпілювати-три-ядро1') then
    raise ECore1TrioError.Create(
      'виклик: senscore1trioelf --скомпілювати-три-ядро1 ліва.sens права.sens новий-каталог');
  Left:=ParamStr(2);
  Right:=ParamStr(3);
  OutDir:=ExpandFileName(ParamStr(4));
  if (Length(ParamStr(4))<1) or (Length(OutDir)>4096) or
     (not DirectoryExists(ExtractFileDir(OutDir))) then
    raise ECore1TrioError.Create('невірний батьківський каталог виводу');

  A:=ReadPhysical(Left);
  B:=ReadPhysical(Right);

  { КОЖЕН donor сам перечитує pinned Core1.sens, перевіряє T5M/D2,
    точні D7 DEFINE/LAMBDA/параметри та admission у TCore1Selektor.
    Тут не відтворюються ні бібліотечні тіла, ні числовий закон. }
  Images[0]:=BuildPinnedCore1AddELF('.',A,B);
  Images[1]:=BuildPinnedCore1SubELF('.',A,B);
  Images[2]:=BuildPinnedCore1MulELF('.',A,B);

  for I:=0 to 2 do begin
    VerifySENSELF64(Images[I],G);
    if (G.Kind<>3) or (G.Entry<>120) or
       (G.MachineBytes<1) or (G.FileBytes<>Length(Images[I])) then
      raise ECore1TrioError.Create('неверифікована host-геометрія ELF64');
  end;

  { Створюємо саме новий каталог з правами 0700 — якщо вже існує,
    системний mkdir атомарно відмовляє, жодної підміни або clobber.
    Всі образи вже пройшли admission; відмова публікації прибирає
    лише власні назви із нового каталогу й сам каталог. }
  if fpMkdir(PChar(OutDir),&700)<>0 then
    raise ECore1TrioError.Create('каталог уже існує або не створений');
  Created:=True;
  try
    for I:=0 to 2 do
      PublishNewELF64(OutDir+PathDelim+FileNames[I],Images[I],3,G);
    Created:=False;
  finally
    if Created then begin
      for I:=0 to 2 do
        DeleteFile(OutDir+PathDelim+FileNames[I]);
      if not RemoveDir(OutDir) then
        raise ECore1TrioError.Create(
          'помилка очищення нового каталогу після відмови');
    end;
  end;
  WriteLn('ЯДРО1-ТРІО-ГОТОВО: фізичних=2 оригінальних-тіл=3 ELF64=3 ',
    'тип=PIE stdout=T5M без-перезапису=так');
end;

begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'ЯДРО1-ТРІО-ВІДМОВА: '+E.Message);
    ExitCode:=2;
  end end;
end.
