{ G5.16. Постійний файловий сеанс реального вузького Core4.
  Стандартний ввід: один шлях до фізичного .sens на рядок.
  :вихід — команда хост-сеансу, не слово мови SENS.
  Стандартний вивід: тільки точна ширина і біти виконаного результату.
  Помилка одного виклику не знищує вже завантажене середовище.
  Це не повний REPL: довільні програми Core4 і .lisp тут не виконуються. }
program sensseanscore4;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core4runtime;

const
  MaxPathLength = 4096;
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

procedure RunSession(const RepoRoot: String);
var
  Runtime: TCore4Runtime;
  Line, View: String;
  Physical, Answer: RawByteString;
  RequestNo: SizeInt;
  HadError: Boolean;
begin
  Runtime := TCore4Runtime.Create(RepoRoot);
  try
    RequestNo := 0;
    HadError := False;
    while not EOF(Input) do
    begin
      ReadLn(Input, Line);
      if RawByteString(Line) = #$3A#$D0#$B2#$D0#$B8#$D1#$85#$D1#$96#$D0#$B4 then Break;
      if Line = '' then Continue;
      Inc(RequestNo);
      try
        if Length(Line) > MaxPathLength then
          raise ECore4RuntimeError.Create('шлях перевищує дозволену довжину');
        Physical := ReadPhysicalFile(Line);
        Answer := Runtime.ExecutePhysicalCall(Physical);
        View := ExactResultView(Answer);
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

begin
  if (ParamCount <> 2) or (RawByteString(ParamStr(1)) <> #$2D#$2D#$D1#$81#$D0#$B5#$D0#$B0#$D0#$BD#$D1#$81) then
  begin
    WriteLn(StdErr, 'Використання: sensseanscore4 --сеанс КОРІНЬ_РЕПОЗИТОРІЮ');
    Halt(64);
  end;
  try
    RunSession(ParamStr(2));
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'ПОМИЛКА ЗАВАНТАЖЕННЯ CORE4: ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
