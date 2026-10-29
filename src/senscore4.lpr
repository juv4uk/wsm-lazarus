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
  GetTempFileName обирає ім'я; файл створюється лише через O_EXCL/CREATE_NEW.
  fpLink / MoveFileW публікують НОВЕ ім'я без заміни цілі, включно з
  висячим symlink. Перевірка FileExists сама по собі не захищає від гонок. }
procedure WriteSafely(const TargetPath: String; SourceStream: TMemoryStream);
var
  TempPath, TargetDir: String;
  OutputStream: THandleStream;
  CreatedTemp: Boolean;
  {$IFDEF UNIX}
  FD: cint;
  {$ENDIF}
  {$IFDEF WINDOWS}
  WinHandle: Windows.THandle;
  {$ENDIF}
begin
  if TargetPath = '' then Reject('не вказано вихідний шлях');
  if SourceStream = nil then Reject('немає перевіреної структури SIR1');
  TempPath := '';
  CreatedTemp := False;
  TargetDir := ExtractFilePath(ExpandFileName(TargetPath));
  try
    { FPC 3.2.x GetTempFileName на Unix НЕ створює файл:
      спочатку ексклюзивно відкриваємо ім'я; не використовуємо fmCreate. }
    TempPath := GetTempFileName(TargetDir, 'c4ir');
    if TempPath = '' then Reject('не вдалося отримати тимчасове ім''я');
    {$IFDEF UNIX}
    FD := fpOpen(PChar(TempPath), O_WRONLY or O_CREAT or O_EXCL, &600);
    if FD < 0 then Reject('не вдалося ексклюзивно створити тимчасовий SIR1');
    CreatedTemp := True;
    try
      OutputStream := THandleStream.Create(FD);
      try
        SourceStream.Position := 0;
        OutputStream.CopyFrom(SourceStream, SourceStream.Size);
      finally
        OutputStream.Free;
      end;
    finally
      fpClose(FD);
    end;
    if fpLink(PChar(TempPath), PChar(TargetPath)) <> 0 then
      Reject('вихідний файл уже існує або атомарний запис неможливий');
    {$ELSE}
      {$IFDEF WINDOWS}
      WinHandle := Windows.CreateFileW(PWideChar(UTF8Decode(TempPath)),
        GENERIC_WRITE, 0, nil, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, 0);
      if WinHandle = INVALID_HANDLE_VALUE then
        Reject('не вдалося ексклюзивно створити тимчасовий SIR1');
      CreatedTemp := True;
      try
        OutputStream := THandleStream.Create(WinHandle);
        try
          SourceStream.Position := 0;
          OutputStream.CopyFrom(SourceStream, SourceStream.Size);
        finally
          OutputStream.Free;
        end;
      finally
        Windows.CloseHandle(WinHandle);
      end;
      if not Windows.MoveFileW(PWideChar(UTF8Decode(TempPath)),
                                PWideChar(UTF8Decode(TargetPath))) then
        Reject('вихідний файл уже існує або атомарний запис неможливий');
      {$ELSE}
      Reject('платформа не підтримує захищену публікацію SIR1');
      {$ENDIF}
    {$ENDIF}
  finally
    { Не торкаємось невласного файла при невдалому O_EXCL.
      Успішний hardlink залишає незмінну ціль, прибираємо лише temp. }
    if CreatedTemp and (TempPath <> '') then DeleteFile(TempPath);
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
