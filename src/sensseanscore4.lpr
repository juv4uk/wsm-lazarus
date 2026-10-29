{ G5.16. Постійний файловий сеанс реального вузького Core4.
  Стандартний ввід: один шлях до фізичного .sens на рядок.
  :вихід — команда хост-сеансу, не слово мови SENS.
  Стандартний вивід: тільки точна ширина і біти виконаного результату.
  Помилка одного виклику не знищує вже завантажене середовище.
  Це не повний REPL: довільні програми Core4 і .lisp тут не виконуються. }
program sensseanscore4;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.core4runtime, wsm.core4multiroot, wsm.bind, wsm.ukroundtrip{$IFDEF UNIX}, BaseUnix{$ENDIF};

const
  MaxPathLength = 4096;
  MaxUkrSourceBytes = 1024*1024; { квота host, не закон SENS }
  MaxStartupFiles = 32;
  MaxStartupBatchForms = 64; { host quota, не SENS закон }
  { Літерали команд/діагностики — байти UTF-8 без host-codepage трансформації. }
  OutputLabel: RawByteString = #$D0#$A0#$D0#$95#$D0#$97#$D0#$A3#$D0#$9B#$D0#$AC#$D0#$A2#$D0#$90#$D0#$A2;
  ErrorLabel: RawByteString = #$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90;
  { :корені — явний host-запит СКЛАДЕНИХ D2-відповідей, не слово SENS.
    Байтові літерали: не залежимо від locale/кодового набору console. }
  CompoundCommand:RawByteString = #$3A#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BD#$D1#$96;
  CompoundPrefix:RawByteString = #$3A#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BD#$D1#$96#$20;
  { :пакет — синтаксис хост-команди, а не SENS слово/проєкція. }
  BatchCommand: RawByteString = #$3A#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82;
  BatchPrefix: RawByteString = #$3A#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82#$20;
  { :укр — лише явний шлях людської проєкції; число/домен не вгадуємо. }
  UkrCommand: RawByteString = #$3A#$D1#$83#$D0#$BA#$D1#$80;
  UkrPrefix: RawByteString = #$3A#$D1#$83#$D0#$BA#$D1#$80#$20;
  { :укр-пакет — явна host-команда багатьох людських форм. }
  UkrBatchCommand:RawByteString =
    #$3A#$D1#$83#$D0#$BA#$D1#$80#$2D#$D0#$BF#$D0#$B0+
    #$D0#$BA#$D0#$B5#$D1#$82;
  UkrBatchPrefix:RawByteString =
    #$3A#$D1#$83#$D0#$BA#$D1#$80#$2D#$D0#$BF#$D0#$B0+
    #$D0#$BA#$D0#$B5#$D1#$82#$20;
  { Команда host зберігає тільки останні дійсні фізичні відповіді. }
  SaveRecentCommand:RawByteString =
    #$3A#$D0#$B7#$D0#$B1#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B3#$D1#$82#$D0+
    #$B8#$2D#$D0#$BE#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$94;
  SaveRecentPrefix:RawByteString =
    #$3A#$D0#$B7#$D0#$B1#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B3#$D1#$82#$D0+
    #$B8#$2D#$D0#$BE#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$94+
    #$20;
  { Явний inline host-ввід ОДНІЄЇ «укр» форми. D7 лише через
    pinned domain+біти+повну українську назву, без текстового dispatch. }
  InlineUkrCommand:RawByteString =
    #$3A#$D1#$83#$D0#$BA#$D1#$80#$2D#$D1#$80#$D1#$8F#$D0#$B4#$D0+
    #$BE#$D0#$BA;
  InlineUkrPrefix:RawByteString =
    #$3A#$D1#$83#$D0#$BA#$D1#$80#$2D#$D1#$80#$D1#$8F#$D0#$B4#$D0+
    #$BE#$D0#$BA#$20;
  { Окрема host-команда для багатьох звичайних «укр» форм в одному
    рядку. Вона НЕ змінює single-only :укр-рядок і SENS законів. }
  InlineUkrBatchCommand:RawByteString =
    #$3A#$D1#$83#$D0#$BA#$D1#$80#$2D#$D1#$80#$D1#$8F#$D0#$B4+
    #$D0#$BA#$D0#$B8;
  InlineUkrBatchPrefix:RawByteString =
    #$3A#$D1#$83#$D0#$BA#$D1#$80#$2D#$D1#$80#$D1#$8F#$D0#$B4+
    #$D0#$BA#$D0#$B8#$20;

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

{ Текстова `укр` поверхня — не канонічні машинні байти.
  Читаємо окремий файл лише з явним розширенням; життєвий цикл
  TFileStream обмежений цією функцією, результат — raw UTF-8. }
function ReadUkrProjectionFile(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>MaxPathLength) or
     (LowerCase(ExtractFileExt(Path))<>'.lisp') then
    raise EUkRoundtripError.Create('команда :укр потребує файл .lisp');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=0) or (F.Size>MaxUkrSourceBytes) then
      raise EUkRoundtripError.Create('українська проєкція порожня або більша за 1 MiB');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
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
    IsUkr: Boolean; { явний host-перемикач, не SENS-координата }
  end;
  TStartupPaths = array of TStartupEntry;
  TStartupViews = array of String;

{ Реальне багатоформове початкове виконання в одному pinned runtime.
  Чинні T5M/D2/physloc єдині для фізичного admission; не дублюємо
  ні SENS evaluator, ні числову інтерпретацію W12+.
  Зовнішній результат стає видимим тільки після повного виконання. }
function ExecuteBatchPhysical(Runtime:TCore4Runtime;
  const Physical:RawByteString;out ResultWords:TExactWords):TStartupViews;
var
  Response:RawByteString;
  Words, Part:TExactWords;
  Spans:TPhysicalWordSpans;
  Doc:TD2Document;
  Candidate:TStartupViews;
  CandidateWords:TExactWords;
  I,J,First,AfterLast:SizeInt;
begin
  Result:=nil;ResultWords:=nil;Doc:=nil;Candidate:=nil;
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

{ G5.55: одна HOST-команда, що використовує вже існуючий
  ExecuteCore4Roots — жодного іншого runtime/evaluator/кодека.
  Позичений Runtime зберігає свої pinned D7 DEFINE між stdin-запитами.
  CandidateWords — власні канонічні фізичні слова, передаються у
  LatestWords лише після повної перевірки всіх коренів.
  Відображення "довжина:біти|..." — ДІАГНОСТИКА, не .lisp і не SENS.
  Пара TD2Document коренів має точні інтервали; її звільняємо завжди. }
function ExecuteCompoundRootsFile(Runtime:TCore4Runtime;const Path:String;
  out ResultWords:TExactWords):TStartupViews;
var
  Response:RawByteString;
  CandidateWords:TExactWords;
  Candidate:TStartupViews;
  Doc:TD2Document;
  I,J,First,Finish:SizeInt;
  View:RawByteString;
begin
  Result:=nil;ResultWords:=nil;Doc:=nil;
  Response:=ExecuteCore4Roots(Runtime,ReadPhysicalFile(Path));
  DecodeT5M(Response,CandidateWords);
  Doc:=ParseD2WordsWide(CandidateWords);
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxStartupBatchForms) then
      raise ECore4RuntimeError.Create('непідтримана кількість складених D2-коренів');
    SetLength(Candidate,Length(Doc.Roots));
    for I:=0 to High(Doc.Roots) do begin
      First:=Doc.Roots[I].WordIndex-1;
      Finish:=Doc.Roots[I].EndWordIndexExclusive-1;
      if (First<0) or (Finish<=First) or (Finish>Length(CandidateWords)) then
        raise ECore4RuntimeError.Create('пошкоджені межі фізичної відповіді Core4');
      View:='';
      for J:=First to Finish-1 do begin
        if J>First then View:=View+'|';
        View:=View+RawByteString(IntToStr(Length(CandidateWords[J])))+
          ':'+CandidateWords[J];
      end;
      Candidate[I]:=String(View);
    end;
    Result:=Candidate;
    ResultWords:=CandidateWords;
  finally Doc.Free end;
end;

{ Та сама фізична перевірка й та сама семантика, що у старті.
  Шлях до файла — суто transport, не інший інтерпретатор. }
function ExecuteBatchFile(Runtime:TCore4Runtime;const Path:String;
  out ResultWords:TExactWords):TStartupViews;
begin
  Result:=ExecuteBatchPhysical(Runtime,ReadPhysicalFile(Path),ResultWords);
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
  Words, RecentWords, LatestWords:TExactWords;
  OneWord:RawByteString;
  HadError: Boolean;
  Staged, StagedBatch, PhysicalProjection: RawByteString;
  ProjectionTables:TDomainSet;
  ProjectionLongs:TLongProjection;
  ProjectionReady:Boolean;
  PinRoot,ProjectionPath:String;
  procedure EnsureProjectionReady;
  begin
    if ProjectionReady then Exit;
    PinRoot:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
      'external'+PathDelim+'sens';
    LoadPinnedDomains(RawByteString(PinRoot),ProjectionTables);
    LoadPinnedLongProjection(RawByteString(PinRoot),
      ProjectionTables,ProjectionLongs);
    ProjectionReady:=True;
  end;
begin
  Runtime := TCore4Runtime.Create(RepoRoot);
  try
    RequestNo := 0;
    ProjectionReady:=False;
    HadError := False;
    Staged := '';
    Words:=nil;
    LatestWords:=nil; { Жодного cached результату з початкового завантаження. }
    { Атомарна видимість початкового набору: семантика лише в Runtime. }
    for I := 0 to High(Startup) do
    begin
      if Startup[I].IsUkr then begin
        { Явна звичайна укр .lisp-проєкція старту:
          bounded UTF-8 → pinned exact names → canonical T5M.
          Обидва режими використовують ТІ САМІ machine executors. }
        PhysicalProjection:=ReadUkrProjectionFile(Startup[I].Path);
        EnsureProjectionReady;
        PhysicalProjection:=UkrainianToPhysical(PhysicalProjection,
          ProjectionTables,ProjectionLongs);
        if Startup[I].IsBatch then
          Views:=ExecuteBatchPhysical(Runtime,PhysicalProjection,RecentWords)
        else begin
          SetLength(Views,1);
          OneWord:=ExactResultWord(Runtime.ExecutePhysicalCall(PhysicalProjection));
          Views[0]:=IntToStr(Length(OneWord))+':'+String(OneWord);
          SetLength(RecentWords,1);
          RecentWords[0]:=OneWord;
        end;
      end else if Startup[I].IsBatch then
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
        if Line=SaveRecentCommand then
          raise ECore4RuntimeError.Create('команда :зберегти-останнє потребує новий фізичний файл .sens');
        if Copy(Line,1,Length(SaveRecentPrefix))=SaveRecentPrefix then begin
          if Length(LatestWords)=0 then
            raise ECore4RuntimeError.Create('немає останніх успішних фізичних відповідей');
          { Повторне застосування чинного атомарного G5.21 SaveStartupAnswers.
            Ніякого Render/парсингу людського Wn:bits. }
          SaveStartupAnswers(String(Copy(Line,Length(SaveRecentPrefix)+1,
            Length(Line)-Length(SaveRecentPrefix))),LatestWords);
        end else begin
          { Кожен новий запит на виконання замінює snapshot; помилка
            не дозволяє помилково експортувати стару відповідь. }
          LatestWords:=nil;
        if Line=CompoundCommand then
          raise ECore4RuntimeError.Create('команда :корені потребує фізичний шлях .sens');
        if Line=BatchCommand then
          raise ECore4RuntimeError.Create('команда :пакет потребує фізичний шлях .sens');
        if Line=UkrCommand then
          raise EUkRoundtripError.Create('команда :укр потребує файл .lisp');
        if Line=UkrBatchCommand then
          raise EUkRoundtripError.Create('команда :укр-пакет потребує файл .lisp');
        if Line=InlineUkrCommand then
          raise EUkRoundtripError.Create('команда :укр-рядок потребує одну українську форму');
        if Line=InlineUkrBatchCommand then
          raise EUkRoundtripError.Create('команда :укр-рядки потребує 1..64 українські форми');
        if Copy(Line,1,Length(CompoundPrefix))=CompoundPrefix then begin
          { Жодної проміжної людської .lisp, жодного сплющування
            D2-списку до одного atom: всі exact слова повертаються.
            Стадіюємо stdout до завершення всіх виконаних коренів. }
          Views:=ExecuteCompoundRootsFile(Runtime,
            String(Copy(Line,Length(CompoundPrefix)+1,
              Length(Line)-Length(CompoundPrefix))),RecentWords);
          StagedBatch:='';
          for J:=0 to High(Views) do
            StagedBatch:=StagedBatch+OutputLabel+' '+IntToStr(RequestNo+J)+
              ' '+RawByteString(Views[J])+LineEnding;
          Write(StagedBatch);
          Flush(Output);
          LatestWords:=Copy(RecentWords,0,Length(RecentWords));
          Inc(RequestNo,Length(Views)-1);
        end else if Copy(Line,1,Length(InlineUkrBatchPrefix))=InlineUkrBatchPrefix then begin
          { Весь inline UTF-8 вже обмежений 4096 байтами host reader.
            Тільки чинний pinned український exact binder до T5M,
            потім чинний D2 root splitter + справжній Core4 runtime.
            Стадіюємо stdout до успіху ВСІХ форм, не гарантуємо
            rollback побічних ефектів середовища. }
          EnsureProjectionReady;
          PhysicalProjection:=UkrainianToPhysical(
            Copy(Line,Length(InlineUkrBatchPrefix)+1,
              Length(Line)-Length(InlineUkrBatchPrefix))+#10,
            ProjectionTables,ProjectionLongs);
          Views:=ExecuteBatchPhysical(Runtime,PhysicalProjection,RecentWords);
          StagedBatch:='';
          for J:=0 to High(Views) do
            StagedBatch:=StagedBatch+OutputLabel+' '+IntToStr(RequestNo+J)+' '+
              RawByteString(Views[J])+LineEnding;
          Write(StagedBatch);
          Flush(Output);
          LatestWords:=Copy(RecentWords,0,Length(RecentWords));
          Inc(RequestNo,Length(Views)-1);
        end else if Copy(Line,1,Length(InlineUkrPrefix))=InlineUkrPrefix then begin
          { Текст — звичайна pinned «укр» проєкція ОДНІЄЇ форми.
            Конвертуємо до EXACT фізичного T5M, не до host opcode.
            Фізичний виконавець сам відхиляє 0/2+ коренів.
            Ліміт raw UTF-8 4096 байтів уже перевірений host-reader. }
          EnsureProjectionReady;
          PhysicalProjection:=UkrainianToPhysical(
            Copy(Line,Length(InlineUkrPrefix)+1,
              Length(Line)-Length(InlineUkrPrefix))+#10,
            ProjectionTables,ProjectionLongs);
          OneWord:=ExactResultWord(Runtime.ExecutePhysicalCall(PhysicalProjection));
          View:=IntToStr(Length(OneWord))+':'+String(OneWord);
          WriteLn(OutputLabel,' ',RequestNo,' ',View);
          Flush(Output);
          SetLength(LatestWords,1);
          LatestWords[0]:=OneWord;
        end else if Copy(Line,1,Length(UkrBatchPrefix))=UkrBatchPrefix then begin
          { Українське `укр` — тільки проєкція: спочатку точний
            round-trip до canonical T5M, потім спільний фізичний
            пакетний evaluator. Жодної часткової відповіді. }
          ProjectionPath:=String(Copy(Line,Length(UkrBatchPrefix)+1,
            Length(Line)-Length(UkrBatchPrefix)));
          PhysicalProjection:=ReadUkrProjectionFile(ProjectionPath);
          EnsureProjectionReady;
          PhysicalProjection:=UkrainianToPhysical(PhysicalProjection,
            ProjectionTables,ProjectionLongs);
          Views:=ExecuteBatchPhysical(Runtime,PhysicalProjection,RecentWords);
          StagedBatch:='';
          for J:=0 to High(Views) do
            StagedBatch:=StagedBatch+OutputLabel+' '+IntToStr(RequestNo+J)+' '+
              RawByteString(Views[J])+LineEnding;
          Write(StagedBatch);
          Flush(Output);
          LatestWords:=Copy(RecentWords,0,Length(RecentWords));
          Inc(RequestNo,Length(Views)-1);
        end else if Copy(Line,1,Length(UkrPrefix))=UkrPrefix then begin
          { Дві незалежні межі: спочатку правильний `.lisp` файл,
            потім pinned таблиці української проєкції, потім
            фізичний exact T5M. Тільки вузький чинний runtime виконує. }
          ProjectionPath:=String(Copy(Line,Length(UkrPrefix)+1,
            Length(Line)-Length(UkrPrefix)));
          PhysicalProjection:=ReadUkrProjectionFile(ProjectionPath);
          EnsureProjectionReady;
          PhysicalProjection:=UkrainianToPhysical(PhysicalProjection,
            ProjectionTables,ProjectionLongs);
          OneWord:=ExactResultWord(Runtime.ExecutePhysicalCall(PhysicalProjection));
          View:=IntToStr(Length(OneWord))+':'+String(OneWord);
          WriteLn(OutputLabel,' ',RequestNo,' ',View);
          Flush(Output);
          SetLength(LatestWords,1);LatestWords[0]:=OneWord;
        end else if Copy(Line,1,Length(BatchPrefix))=BatchPrefix then begin
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
          LatestWords:=Copy(RecentWords,0,Length(RecentWords));
          Inc(RequestNo,Length(Views)-1);
        end else begin
          View := ExecuteFile(Runtime, String(Line),OneWord);
          { Звичайний один фізичний виклик зберігає попередній протокол. }
          WriteLn(OutputLabel, ' ', RequestNo, ' ', View);
          Flush(Output);
          SetLength(LatestWords,1);LatestWords[0]:=OneWord;
        end;
        end; { закрито host-запит виконання, не збереження }
      except
        on E: Exception do
        begin
          HadError := True;
          LatestWords:=nil; { помилка очищає last-success cache }
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
  { Лише явні прапорці проєкції; жодних неявних .lisp→.sens. }
  UkrLoadArg:RawByteString =
    #$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82+
    #$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8#$2D#$D1#$83+
    #$D0#$BA#$D1#$80;
  UkrBatchArg:RawByteString =
    #$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82+
    #$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8#$2D#$D1#$83+
    #$D0#$BA#$D1#$80#$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5+
    #$D1#$82;
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
    if (Flag<>LoadArg) and (Flag<>BatchArg) and
       (Flag<>UkrLoadArg) and (Flag<>UkrBatchArg) then Exit;
    if (ParamStr(4+2*I)='') or
       (Length(ParamStr(4+2*I))>MaxPathLength) then Exit;
    Startup[I].Path:=ParamStr(4+2*I);
    Startup[I].IsBatch:=(Flag=BatchArg) or (Flag=UkrBatchArg);
    Startup[I].IsUkr:=(Flag=UkrLoadArg) or (Flag=UkrBatchArg);
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
      ' [--завантажити виклик.sens|--завантажити-пакет пакет.sens', 
      '|--завантажити-укр форма.lisp|--завантажити-укр-пакет пакет.lisp]...',
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
