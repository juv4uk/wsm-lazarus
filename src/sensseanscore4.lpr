{ G5.16. Постійний файловий сеанс реального вузького Core4.
  Стандартний ввід: один шлях до фізичного .sens на рядок.
  :вихід — команда хост-сеансу, не слово мови SENS.
  Стандартний вивід: тільки точна ширина і біти виконаного результату.
  Помилка одного виклику не знищує вже завантажене середовище.
  Це не повний REPL: довільні програми Core4 і .lisp тут не виконуються. }
program sensseanscore4;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.core4runtime{$IFDEF UNIX}, BaseUnix{$ENDIF};

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

function ExactResultWord(const Physical: RawByteString): RawByteString;
var
  Words: TExactWords;
begin
  { Діагностична проєкція. Ширина НЕ визначає семантичний домен.
    Жодного виведення значення D12/D24 із бітів. }
  DecodeT5M(Physical, Words);
  if Length(Words) <> 1 then
    raise ECore4RuntimeError.Create('виконавець повернув не один exact атом');
  Result := Words[0];
end;

function ExactResultView(const Physical:RawByteString):String;
var BitWord:RawByteString;
begin
  BitWord:=ExactResultWord(Physical);
  Result:=IntToStr(Length(BitWord))+':'+String(BitWord);
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
function ExecuteBatchFile(Runtime:TCore4Runtime;const Path:String;
  out ResultWords:TExactWords):TStartupViews;
var
  Physical, Response:RawByteString;
  Words, Part:TExactWords;
  Spans:TPhysicalWordSpans;
  Doc:TD2Document;
  Candidate:TStartupViews;
  CandidateWords:TExactWords;
  I,J,First,AfterLast:SizeInt;
begin
  Result:=nil;ResultWords:=nil;Doc:=nil;Candidate:=nil;
  Physical:=ReadPhysicalFile(Path);
  DecodeT5MWithLocations(Physical,Words,Spans);
  Doc:=ParseD2WordsWide(Words);
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxStartupBatchForms) then
      raise ECore4RuntimeError.Create('пакет має містити 1..64 фізичні форми');
    SetLength(Candidate,Length(Doc.Roots));
    SetLength(CandidateWords,Length(Doc.Roots));
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
        CandidateWords[I]:=ExactResultWord(Response);
        Candidate[I]:=IntToStr(Length(CandidateWords[I]))+':'+
          String(CandidateWords[I]);
      except on E:Exception do
        raise ECore4RuntimeError.Create('пакетна форма='+IntToStr(I+1)+
          ': '+E.Message);
      end;
    end;
    Result:=Candidate;
    ResultWords:=CandidateWords;
  finally Doc.Free end;
end;

{ Один шлях фізичного виконання для стартових і stdin-форм. }
function ExecuteFile(Runtime: TCore4Runtime; const Path: String;
  out ResultWord:RawByteString): String;
var Physical, Answer: RawByteString;
begin
  if Length(Path) > MaxPathLength then
    raise ECore4RuntimeError.Create('шлях перевищує дозволену довжину');
  Physical := ReadPhysicalFile(Path);
  Answer := Runtime.ExecutePhysicalCall(Physical);
  ResultWord:=ExactResultWord(Answer);
  Result:=IntToStr(Length(ResultWord))+':'+String(ResultWord);
end;

{ Вихід — T5M фізичні відповіді, а не програма для повторного запуску.
  Всі слова отримані безпосередньо з ExecutePhysicalCall. Створюємо
  тимчасовий файл У тій самій директорії; Unix hard-link гарантує
  створення без перезапису, а відмова залишає target недоторканим. }
procedure SaveStartupAnswers(const Path:String;const Words:TExactWords);
var Physical:RawByteString;TempPath:String;Stream:TFileStream;
begin
  if (Path='') or (Length(Path)>MaxPathLength) or
     (LowerCase(ExtractFileExt(Path))<>'.sens') then
    raise ECore4RuntimeError.Create('вихід має бути новим фізичним файлом .sens');
  if (Length(Words)=0) or (Length(Words)>MaxStartupFiles*MaxStartupBatchForms) then
    raise ECore4RuntimeError.Create('немає допустимих стартових відповідей');
  if FileExists(Path) or DirectoryExists(Path) then
    raise ECore4RuntimeError.Create('вихідний фізичний файл уже існує');
  Physical:=EncodeT5M(Words);
  if (Length(Physical)=0) or (Length(Physical)>MAX_T5M_FILE_BYTES) then
    raise ECore4RuntimeError.Create('вихідні фізичні байти поза межею T5M');
  TempPath:=GetTempFileName(ExtractFilePath(ExpandFileName(Path)),'sr4');
  if TempPath='' then
    raise ECore4RuntimeError.Create('тимчасовий файл не створено');
  try
    Stream:=TFileStream.Create(TempPath,fmCreate);
    try
      Stream.WriteBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    {$IFDEF UNIX}
    if fpLink(RawByteString(TempPath),RawByteString(Path))<>0 then
      raise ECore4RuntimeError.Create('не вдалося створити новий фізичний вихід');
    {$ELSE}
    if FileExists(Path) or DirectoryExists(Path) or
       (not RenameFile(TempPath,Path)) then
      raise ECore4RuntimeError.Create('не вдалося створити новий фізичний вихід');
    {$ENDIF}
  finally
    if FileExists(TempPath) then DeleteFile(TempPath);
  end;
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

procedure RunSession(const RepoRoot: String; const Startup: TStartupPaths;
  const ArchivePath:String);
var
  Runtime: TCore4Runtime;
  View: String;
  Line: RawByteString;
  OverLimit: Boolean;
  RequestNo, I, J, K: SizeInt;
  Views: TStartupViews;
  Words, RecentWords:TExactWords;
  OneWord:RawByteString;
  HadError: Boolean;
  Staged, StagedBatch: RawByteString;
begin
  Runtime := TCore4Runtime.Create(RepoRoot);
  try
    RequestNo := 0;
    HadError := False;
    Staged := '';
    Words:=nil;
    { Атомарна видимість початкового набору: семантика лише в Runtime. }
    for I := 0 to High(Startup) do
    begin
      if Startup[I].IsBatch then
        Views:=ExecuteBatchFile(Runtime,Startup[I].Path,RecentWords)
      else begin
        SetLength(Views,1);
        Views[0]:=ExecuteFile(Runtime,Startup[I].Path,OneWord);
        SetLength(RecentWords,1);
        RecentWords[0]:=OneWord;
      end;
      for J:=0 to High(Views) do begin
        K:=Length(Words);
        if K>=MaxStartupFiles*MaxStartupBatchForms then
          raise ECore4RuntimeError.Create('вичерпано межу відповідей startup');
        SetLength(Words,K+1);
        Words[K]:=RecentWords[J];
        Inc(RequestNo);
        Staged:=Staged+OutputLabel+' '+IntToStr(RequestNo)+' '+
          RawByteString(Views[J])+LineEnding;
      end;
    end;
    if ArchivePath<>'' then SaveStartupAnswers(ArchivePath,Words);
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
            Length(Line)-Length(BatchPrefix))),RecentWords);
          StagedBatch:='';
          for J:=0 to High(Views) do
            StagedBatch:=StagedBatch+OutputLabel+' '+IntToStr(RequestNo+J)+' '+
              RawByteString(Views[J])+LineEnding;
          Write(StagedBatch);
          Flush(Output);
          Inc(RequestNo,Length(Views)-1);
        end else begin
          View := ExecuteFile(Runtime, String(Line),OneWord);
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
function ParseStartup(out Startup: TStartupPaths;
  out ArchivePath:String): Boolean;
const
  SessionArg: RawByteString = #$2D#$2D#$D1#$81#$D0#$B5#$D0#$B0#$D0#$BD#$D1#$81;
  LoadArg: RawByteString =
    #$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82+
    #$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8;
  BatchArg: RawByteString =
    #$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82+
    #$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8+
    #$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82;
  SaveArg: RawByteString = #$2D#$2D#$D0#$B7#$D0#$B1#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B3#$D1#$82#$D0#$B8#$2D#$D0#$BF#$D0#$BE#$D1#$87#$D0#$B0#$D1#$82#$D0#$BA#$D0#$BE#$D0#$B2#$D1#$96;
var I,N:SizeInt;
    Flag:RawByteString;
begin
  Startup := nil;
  ArchivePath:='';
  Result := False;
  if (ParamCount < 2) or (ParamCount > 2 + 2*(MaxStartupFiles+1)) or
     ((ParamCount-2) mod 2 <> 0) then Exit;
  if RawByteString(ParamStr(1)) <> SessionArg then Exit;
  N := (ParamCount-2) div 2;
  SetLength(Startup,N);
  for I := 0 to N-1 do
  begin
    Flag:=RawByteString(ParamStr(3+2*I));
    if Flag=SaveArg then begin
      if (I<>N-1) or (I=0) then Exit;
      ArchivePath:=ParamStr(4+2*I);
      if (ArchivePath='') or (Length(ArchivePath)>MaxPathLength) or
         (LowerCase(ExtractFileExt(ArchivePath))<>'.sens') then Exit;
      SetLength(Startup,I);
      Break;
    end;
    if (Flag<>LoadArg) and (Flag<>BatchArg) then Exit;
    if (ParamStr(4+2*I)='') or
       (Length(ParamStr(4+2*I))>MaxPathLength) then Exit;
    Startup[I].Path:=ParamStr(4+2*I);
    Startup[I].IsBatch:=(Flag=BatchArg);
  end;
  if Length(Startup)>MaxStartupFiles then Exit;
  Result := True;
end;

var StartupPaths: TStartupPaths;
    ArchivePath:String;
begin
  if not ParseStartup(StartupPaths,ArchivePath) then
  begin
    WriteLn(StdErr, 'Використання: sensseanscore4 --сеанс КОРІНЬ_РЕПОЗИТОРІЮ',
      ' [--завантажити виклик.sens|--завантажити-пакет пакет.sens]...',
      ' [--зберегти-початкові новий-результат.sens]');
    Halt(64);
  end;
  try
    RunSession(ParamStr(2),StartupPaths,ArchivePath);
  except
    on E: Exception do
    begin
      WriteLn(StdErr, 'ПОМИЛКА ЗАВАНТАЖЕННЯ CORE4: ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
