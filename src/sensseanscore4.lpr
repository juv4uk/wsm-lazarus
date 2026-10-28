{ G5.16. Постійний файловий сеанс реального вузького Core4.
  Стандартний ввід: один шлях до фізичного .sens на рядок.
  :вихід — команда хост-сеансу, не слово мови SENS.
  Стандартний вивід: тільки точна ширина і біти виконаного результату.
  Помилка одного виклику не знищує вже завантажене середовище.
  Це не повний REPL: довільні програми Core4 і .lisp тут не виконуються. }
program sensseanscore4;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.core4runtime;

const
  MaxPathLength = 4096;
  MaxStartupFiles = 32;
  MaxStartupBatchForms = 64; { host quota, не SENS закон }
  { Літерали команд/діагностики — байти UTF-8 без host-codepage трансформації. }
  OutputLabel: RawByteString = #$D0#$A0#$D0#$95#$D0#$97#$D0#$A3#$D0#$9B#$D0#$AC#$D0#$A2#$D0#$90#$D0#$A2;
  ErrorLabel: RawByteString = #$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90;
  { :пакет — синтаксис хост-команди, а не SENS слово/проєкція. }
  BatchCommand: RawByteString = #$3A#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82;
  BatchPrefix: RawByteString = #$3A#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82#$20;

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
  TStartupEntry = record
    Path: String;
    IsBatch: Boolean;
  end;
  TStartupPaths = array of TStartupEntry;
  TStartupViews = array of String;

{ Реальне багатоформове початкове виконання в одному pinned runtime.
  Чинні T5M/D2/physloc єдині для фізичного admission; не дублюємо
  ні SENS evaluator, ні числову інтерпретацію W12+.
  Зовнішній результат стає видимим тільки після повного виконання. }
function ExecuteBatchFile(Runtime:TCore4Runtime;const Path:String):TStartupViews;
var
  Physical, Response:RawByteString;
  Words, Part:TExactWords;
  Spans:TPhysicalWordSpans;
  Doc:TD2Document;
  Candidate:TStartupViews;
  I,J,First,AfterLast:SizeInt;
begin
  Result:=nil;Doc:=nil;Candidate:=nil;
  Physical:=ReadPhysicalFile(Path);
  DecodeT5MWithLocations(Physical,Words,Spans);
  Doc:=ParseD2WordsWide(Words);
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxStartupBatchForms) then
      raise ECore4RuntimeError.Create('пакет має містити 1..64 фізичні форми');
    SetLength(Candidate,Length(Doc.Roots));
    for I:=0 to High(Doc.Roots) do begin
      First:=Doc.Roots[I].WordIndex-1;
      if I<High(Doc.Roots) then
        AfterLast:=Doc.Roots[I+1].WordIndex-1
      else
        AfterLast:=Length(Words);
      if (First<0) or (AfterLast<=First) or (AfterLast>Length(Words)) then
        raise ECore4RuntimeError.Create('пошкоджені межі коренів Core4-пакета');
      SetLength(Part,AfterLast-First);
      for J:=0 to High(Part) do Part[J]:=Words[First+J];
      try
        Response:=Runtime.ExecutePhysicalCall(EncodeT5M(Part));
        Candidate[I]:=ExactResultView(Response);
      except on E:Exception do
        raise ECore4RuntimeError.Create('пакетна форма='+IntToStr(I+1)+
          ': '+E.Message);
      end;
    end;
    Result:=Candidate;
  finally Doc.Free end;
end;

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

{ G5.18: bounded host-ввід шляхів, а не читач SENS.
  Line зберігає до 4096 UTF-8 байтів + опціональний CR.
  Після переповнення зайві байти дочитуються без накопичення. }
function ReadBoundedSessionLine(out Line: RawByteString;
  out OverLimit: Boolean): Boolean;
var
  C: Char;
  Used: SizeInt;
begin
  Line := '';
  OverLimit := False;
  Result := not EOF(Input);
  if not Result then Exit;
  SetLength(Line, MaxPathLength + 1);
  Used := 0;
  while (not EOF(Input)) and (not Eoln(Input)) do
  begin
    Read(Input, C);
    if Used < MaxPathLength + 1 then
    begin
      Inc(Used);
      Line[Used] := C;
    end
    else
      OverLimit := True;
  end;
  if not EOF(Input) then ReadLn(Input);
  if (Used > 0) and (Line[Used] = #13) then Dec(Used);
  if Used > MaxPathLength then OverLimit := True;
  if Used > MaxPathLength then Used := MaxPathLength;
  SetLength(Line, Used);
end;

procedure RunSession(const RepoRoot: String; const Startup: TStartupPaths);
var
  Runtime: TCore4Runtime;
  View: String;
  Line: RawByteString;
  OverLimit: Boolean;
  RequestNo, I, J: SizeInt;
  Views: TStartupViews;
  HadError: Boolean;
  Staged, StagedBatch: RawByteString;
begin
  Runtime := TCore4Runtime.Create(RepoRoot);
  try
    RequestNo := 0;
    HadError := False;
    Staged := '';
    { Атомарна видимість початкового набору: семантика лише в Runtime. }
    for I := 0 to High(Startup) do
    begin
      if Startup[I].IsBatch then
        Views:=ExecuteBatchFile(Runtime,Startup[I].Path)
      else begin
        SetLength(Views,1);
        Views[0]:=ExecuteFile(Runtime,Startup[I].Path);
      end;
      for J:=0 to High(Views) do begin
        Inc(RequestNo);
        Staged:=Staged+OutputLabel+' '+IntToStr(RequestNo)+' '+
          RawByteString(Views[J])+LineEnding;
      end;
    end;
    if Staged <> '' then Write(Staged);
    while ReadBoundedSessionLine(Line, OverLimit) do
    begin
      if (not OverLimit) and
        (Line = #$3A#$D0#$B2#$D0#$B8#$D1#$85#$D1#$96#$D0#$B4) then Break;
      if (not OverLimit) and (Line = '') then Continue;
      Inc(RequestNo);
      try
        if OverLimit then
          raise ECore4RuntimeError.Create('шлях перевищує дозволену довжину; межа=4096');
        if Line=BatchCommand then
          raise ECore4RuntimeError.Create('команда :пакет потребує фізичний шлях .sens');
        if Copy(Line,1,Length(BatchPrefix))=BatchPrefix then begin
          { Цілий багатоформовий файл виконується тим самим pinned Runtime.
            Жоден рядок не потрапляє у stdout до успіху ВСІХ коренів. }
          Views:=ExecuteBatchFile(Runtime,String(Copy(Line,Length(BatchPrefix)+1,
            Length(Line)-Length(BatchPrefix))));
          StagedBatch:='';
          for J:=0 to High(Views) do
            StagedBatch:=StagedBatch+OutputLabel+' '+IntToStr(RequestNo+J)+' '+
              RawByteString(Views[J])+LineEnding;
          Write(StagedBatch);
          Flush(Output);
          Inc(RequestNo,Length(Views)-1);
        end else begin
          View := ExecuteFile(Runtime, String(Line));
          { Звичайний один фізичний виклик зберігає попередній протокол. }
          WriteLn(OutputLabel, ' ', RequestNo, ' ', View);
          Flush(Output);
        end;
      except
        on E: Exception do
        begin
          HadError := True;
          WriteLn(StdErr, ErrorLabel, ' ', RequestNo, ' ', E.Message);
          Flush(StdErr);
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
  BatchArg: RawByteString =
    #$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82+
    #$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8+
    #$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82;
var I,N:SizeInt;
    Flag:RawByteString;
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
    Flag:=RawByteString(ParamStr(3+2*I));
    if (Flag<>LoadArg) and (Flag<>BatchArg) then Exit;
    if (ParamStr(4+2*I)='') or
       (Length(ParamStr(4+2*I))>MaxPathLength) then Exit;
    Startup[I].Path:=ParamStr(4+2*I);
    Startup[I].IsBatch:=(Flag=BatchArg);
  end;
  Result := True;
end;

var StartupPaths: TStartupPaths;
begin
  if not ParseStartup(StartupPaths) then
  begin
    WriteLn(StdErr, 'Використання: sensseanscore4 --сеанс КОРІНЬ_РЕПОЗИТОРІЮ',
      ' [--завантажити виклик.sens|--завантажити-пакет пакет.sens]...');
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
