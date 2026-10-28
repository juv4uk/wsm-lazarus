{ Фізичний командний інтерфейс допуску закріпленого Core4.
  SIR1 залишається приватним структурним форматом, не канонічним .sens.
  Мовні закони, виконання та допустимість викликів тут не визначаються. }
program senscore4;
{$mode objfpc}{$H+}

uses SysUtils, Classes, wsm.core4source, wsm.compiler;

procedure Reject(const MessageText: String);
begin
  raise Exception.Create(MessageText);
end;

procedure WriteSafely(const TargetPath: String; SourceStream: TMemoryStream);
var
  TempPath: String;
  OutputStream: TFileStream;
  CreatedTemp: Boolean;
begin
  if TargetPath = '' then Reject('не вказано вихідний шлях');
  if FileExists(TargetPath) then Reject('вихідний файл уже існує');
  TempPath := TargetPath + '.tmp';
  if FileExists(TempPath) then Reject('тимчасовий файл уже існує');
  CreatedTemp := False;
  try
    OutputStream := TFileStream.Create(TempPath, fmCreate);
    CreatedTemp := True;
    try
      SourceStream.Position := 0;
      OutputStream.CopyFrom(SourceStream, SourceStream.Size);
    finally
      OutputStream.Free;
    end;
    if FileExists(TargetPath) then Reject('вихідний шлях зайнято під час запису');
    if not RenameFile(TempPath, TargetPath) then
      Reject('не вдалось завершити запис вихідного файлу');
    CreatedTemp := False;
  finally
    if CreatedTemp then DeleteFile(TempPath);
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
