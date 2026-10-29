{ Фізичний командний інтерфейс допуску закріпленого Core4.
  SIR1 залишається приватним структурним форматом, не канонічним .sens.
  Мовні закони, виконання та допустимість викликів тут не визначаються. }
program senscore4;
{$mode objfpc}{$H+}

uses SysUtils, Classes, wsm.core4source, wsm.compiler
  {$IFDEF UNIX}, BaseUnix{$ENDIF}
  {$IFDEF WINDOWS}, Windows{$ENDIF};

procedure Reject(const MessageText: String);
begin
  raise Exception.Create(MessageText);
end;

{ G4.31: лише файловий механізм приватного SIR1, не SENS виконання.
  GetTempFileName атомарно створює тимчасове ім'я у каталозі призначення.
  fpLink / MoveFileW публікують НОВЕ ім'я без заміни цілі, включно з
  висячим symlink. Перевірка FileExists сама по собі не захищає від гонок. }
procedure WriteSafely(const TargetPath: String; SourceStream: TMemoryStream);
var
  TempPath, TargetDir: String;
  OutputStream: TFileStream;
begin
  if TargetPath = '' then Reject('не вказано вихідний шлях');
  if SourceStream = nil then Reject('немає перевіреної структури SIR1');
  TempPath := '';
  TargetDir := ExtractFilePath(ExpandFileName(TargetPath));
  try
    TempPath := GetTempFileName(TargetDir, 'c4ir');
    if TempPath = '' then Reject('не вдалося створити тимчасовий файл');
    { Файл уже створено ексклюзивно; не перевідкривати через fmCreate.
      SourceStream запозичений, пам'яттю володіє caller. }
    OutputStream := TFileStream.Create(TempPath, fmOpenWrite or fmShareDenyWrite);
    try
      SourceStream.Position := 0;
      OutputStream.CopyFrom(SourceStream, SourceStream.Size);
    finally
      OutputStream.Free;
    end;
    {$IFDEF UNIX}
    if fpLink(PChar(TempPath), PChar(TargetPath)) <> 0 then
      Reject('вихідний файл уже існує або атомарний запис неможливий');
    {$ELSE}
      {$IFDEF WINDOWS}
      if not Windows.MoveFileW(PWideChar(UTF8Decode(TempPath)),
                               PWideChar(UTF8Decode(TargetPath))) then
        Reject('вихідний файл уже існує або атомарний запис неможливий');
      {$ELSE}
      Reject('платформа не підтримує захищену публікацію SIR1');
      {$ENDIF}
    {$ENDIF}
  finally
    { Після успішного hardlink очищаємо лише тимчасове ім'я.
      Після будь-якої невдачі теж: без часткового результату. }
    if (TempPath <> '') and FileExists(TempPath) then
      DeleteFile(TempPath);
  end;
end;

procedure RunCommand;
var
  Action, RootPath: String;
  Buffer: TMemoryStream;
  Stats: TSIR1Stats;
  RawSource: RawByteString;
begin
  if (ParamCount <> 2) and (ParamCount <> 3) then
    Reject('використання: senscore4 --check КОРІНЬ або --emit-ir КОРІНЬ ФАЙЛ');
  Action := ParamStr(1);
  RootPath := ParamStr(2);
  if RootPath = '' then Reject('порожній корінь репозиторію');
  if (Action = '--check') and (ParamCount <> 2) then
    Reject('для перевірки потрібні рівно два аргументи');
  if (Action = '--emit-ir') and (ParamCount <> 3) then
    Reject('для виводу потрібні рівно три аргументи');
  if (Action <> '--check') and (Action <> '--emit-ir') then
    Reject('невідома дія');
  { Наявний перевірений завантажувач сам обмежує байти, валідує
    UTF-8/структуру, а також відкидає некоректний SIR1 до видачі. }
  RawSource := ReadPinnedCore4(RootPath);
  Buffer := TMemoryStream.Create;
  try
    CompilePinnedCore4Structure(RootPath, Buffer);
    Buffer.Position := 0;
    InspectSIR1(Buffer, Stats);
    if Action = '--emit-ir' then
      WriteSafely(ParamStr(3), Buffer);
    WriteLn('CORE4-ДОПУСК-ГАРАЗД байти=', Length(RawSource),
      ' структура=', Buffer.Size,
      ' форми-списки=', Stats.ListOpens,
      ' атоми=', Stats.Atoms,
      ' рядки=', Stats.Strings,
      ' виконання=ні');
  finally
    Buffer.Free;
  end;
end;

begin
  try
    RunCommand;
  except
    on E: ECore4SourceError do begin
      WriteLn(StdErr, 'CORE4-ДОПУСК-ПОМИЛКА ', E.Message,
        ' байт=', E.ByteOffset, ' рядок=', E.Line,
        ' стовпець=', E.ByteColumn);
      Halt(2);
    end;
    on E: Exception do begin
      WriteLn(StdErr, 'CORE4-ДОПУСК-ПОМИЛКА ', E.Message);
      Halt(2);
    end;
  end;
end.
