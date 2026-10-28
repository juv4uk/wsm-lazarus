{ G5.16. Постійний файловий сеанс реального вузького Core4.
  Стандартний ввід: один шлях до фізичного .sens на рядок.
  :вихід — команда хост-сеансу, не слово мови SENS.
  Стандартний вивід: тільки точна ширина і біти виконаного результату.
  Помилка одного виклику не знищує вже завантажене середовище.
  Це не повний REPL: довільні програми Core4 і .lisp тут не виконуються. }
program sensseanscore4;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.core4runtime;

const
  MaxPathLength = 4096;
  MaxStartupFiles = 32;
  { Літерали команд/діагностики — байти UTF-8 без host-codepage трансформації. }
  OutputLabel: RawByteString = #$D0#$A0#$D0#$95#$D0#$97#$D0#$A3#$D0#$9B#$D0#$AC#$D0#$A2#$D0#$90#$D0#$A2;
  ErrorLabel: RawByteString = #$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90;

function ReadPhysicalFile(const Path: String): RawByteString;
var
  Source: TFileStream;
begin
  Result := '';
  if (Path = '') or (LowerCase(ExtractFileExt(Path)) <> '.sens') then
    raise ECore4RuntimeError.Create('потрібен файл фізичного .sens');
  Source := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    if (Source.Size < 1) or (Source.Size > MAX_T5M_FILE_BYTES) then
      raise ECore4RuntimeError.Create('розмір фізичного .sens поза межею');
    SetLength(Result, SizeInt(Source.Size));
    Source.ReadBuffer(Result[1], Length(Result));
  finally
    Source.Free;
  end;
end;

function ExactResultView(const Physical: RawByteString): String;
var
  Words: TExactWords;
begin
  { Діагностична проєкція. Ширина НЕ визначає семантичний домен.
    Жодного виведення значення D12/D24 із бітів. }
  DecodeT5M(Physical, Words);
  if Length(Words) <> 1 then
    raise ECore4RuntimeError.Create('виконавець повернув не один exact атом');
  Result := IntToStr(Length(Words[0])) + ':' + String(Words[0]);
end;

type
  TStartupPaths = array of String;

{ Один шлях фізичного виконання для стартових і stdin-форм. }
function ExecuteFile(Runtime: TCore4Runtime; const Path: String): String;
var Physical, Answer: RawByteString;
begin
  if Length(Path) > MaxPathLength then
    raise ECore4RuntimeError.Create('шлях перевищує дозволену довжину');
  Physical := ReadPhysicalFile(Path);
  Answer := Runtime.ExecutePhysicalCall(Physical);
  Result := ExactResultView(Answer);
end;

procedure RunSession(const RepoRoot: String; const Startup: TStartupPaths);
var
  Runtime: TCore4Runtime;
  Line, View: String;
  RequestNo, I: SizeInt;
  HadError: Boolean;
  Staged: RawByteString;
begin
  Runtime := TCore4Runtime.Create(RepoRoot);
  try
    RequestNo := 0;
    HadError := False;
    Staged := '';
    { Атомарна видимість початкового набору: семантика лише в Runtime. }
    for I := 0 to High(Startup) do
    begin
      View := ExecuteFile(Runtime, Startup[I]);
      Inc(RequestNo);
      Staged := Staged + OutputLabel + ' ' + IntToStr(RequestNo) + ' ' +
        RawByteString(View) + LineEnding;
    end;
    if Staged <> '' then Write(Staged);
    while not EOF(Input) do
    begin
      ReadLn(Input, Line);
      if RawByteString(Line) = #$3A#$D0#$B2#$D0#$B8#$D1#$85#$D1#$96#$D0#$B4 then Break;
      if Line = '' then Continue;
      Inc(RequestNo);
      try
        View := ExecuteFile(Runtime, Line);
        { Публікуємо один рядок лише після повного успіху виклику. }
        WriteLn(OutputLabel, ' ', RequestNo, ' ', View);
      except
        on E: Exception do
        begin
          HadError := True;
          WriteLn(StdErr, ErrorLabel, ' ', RequestNo, ' ', E.Message);
        end;
      end;
    end;
    if HadError then ExitCode := 2;
  finally
    Runtime.Free;
  end;
end;

{ Усі аргументи допускаються до запуску, без часткових startup-виводів. }
function ParseStartup(out Startup: TStartupPaths): Boolean;
const
  SessionArg: RawByteString = #$2D#$2D#$D1#$81#$D0#$B5#$D0#$B0#$D0#$BD#$D1#$81;
  LoadArg: RawByteString =
    #$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82+
    #$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8;
var I,N:SizeInt;
begin
  Startup := nil;
  Result := False;
  if (ParamCount < 2) or (ParamCount > 2 + 2*MaxStartupFiles) or
     ((ParamCount-2) mod 2 <> 0) then Exit;
  if RawByteString(ParamStr(1)) <> SessionArg then Exit;
  N := (ParamCount-2) div 2;
  SetLength(Startup,N);
  for I := 0 to N-1 do
  begin
    if RawByteString(ParamStr(3+2*I)) <> LoadArg then Exit;
    if (ParamStr(4+2*I)='') or
       (Length(ParamStr(4+2*I))>MaxPathLength) then Exit;
    Startup[I] := ParamStr(4+2*I);
  end;
  Result := True;
end;

var StartupPaths: TStartupPaths;
begin
  if not ParseStartup(StartupPaths) then
  begin
    WriteLn(StdErr, 'Використання: sensseanscore4 --сеанс КОРІНЬ_РЕПОЗИТОРІЮ',
      ' [--завантажити виклик.sens]...');
    Halt(64);
  end;
  try
    RunSession(ParamStr(2),StartupPaths);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'ПОМИЛКА ЗАВАНТАЖЕННЯ CORE4: ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
