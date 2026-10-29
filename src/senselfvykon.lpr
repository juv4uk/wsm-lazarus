{ G6.39 — фізичний .sens -> довірений x86-64 ELF -> новий .sens.
  Виклик лише раніше злитого G6.38 wsm.elfprobe; тут НЕ існує
  власних SENS законів, evaluator, compiler або іншого process runner. }
program senselfvykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.elfprobe,wsm.t5m;

const
  { CLI UTF-8 байти з уже чинного sensmashyna, тільки host перемикачі. }
  KQuote=#$2D#$2D#$D1#$86#$D0#$B8#$D1#$82#$D0#$B0#$D1#$82#$D0#$B0;
  KAtom=#$2D#$2D#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC;
  KEq=#$2D#$2D#$D1#$82#$D0#$BE#$D1#$82#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D1#$81#$D1#$82#$D1#$8C;
  KSelector=#$2D#$2D#$D1#$81#$D0#$B5#$D0#$BB#$D0#$B5#$D0#$BA#$D1#$82#$D0#$BE#$D1#$80;
  KCond=#$2D#$2D#$D1#$83#$D0#$BC#$D0#$BE#$D0#$B2#$D0#$B0;
  MaxPhysicalBytes=65536;

type EFileMachineError=class(Exception);

function UA(const Value:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(Value));
end;

function ReadCanonicalInput(const Path:String):RawByteString;
var
  F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxPhysicalBytes) then
      raise EFileMachineError.Create('Неприпустима довжина фізичного .sens');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally
    F.Free;
  end;
end;

procedure PublishAnswer(const Path:String;const Physical:RawByteString);
var
  Temp,Directory:String;
  F:TFileStream;
begin
  { Усі байти відвідані машинним admission перед будь-яким файлом.
    Передаємо лише новий inode, ніколи FileExists -> fmCreate на цілі. }
  Temp:='';
  try
    if (Physical='') or (Length(Physical)>MaxPhysicalBytes) then
      raise EFileMachineError.Create('Неприпустима машинна відповідь');
    Directory:=ExtractFilePath(ExpandFileName(Path));
    if not DirectoryExists(Directory) then
      raise EFileMachineError.Create('Не існує каталогу відповіді');
    Temp:=GetTempFileName(Directory,'sen');
    if Temp='' then
      raise EFileMachineError.Create('Не створено тимчасовий файл відповіді');
    F:=TFileStream.Create(Temp,fmOpenWrite);
    try
      F.WriteBuffer(Physical[1],Length(Physical));
    finally F.Free end;
    if fpChmod(PChar(Temp),&600)<>0 then
      raise EFileMachineError.Create('Не встановлено приватні права відповіді');
    { На Linux link створює нове ім’я лише якщо цілі НЕ існує;
      існуючий файл, директорія і dangling symlink не змінюються. }
    if fpLink(PChar(Temp),PChar(Path))<>0 then
      raise EFileMachineError.Create('Результат уже існує або недоступний');
    { Тепер ціль володіє inode. Навіть якщо unlink temp не вдався,
      не видаляємо щойно успішно опубліковане ім'я. }
    DeleteFile(Temp);
    Temp:='';
  finally
    if Temp<>'' then DeleteFile(Temp);
  end;
end;

procedure Run;
var
  Mode:RawByteString;
  Root,InputPath,OutputPath:String;
  Profile:TNativeELFProfile;
  Physical,Answer:RawByteString;
  Words:TExactWords;
begin
  if ParamCount<>4 then
    raise EFileMachineError.Create('Виклик: senselfvykon --цитата|--атом|--тотожність|--селектор|--умова pinned-root вхід.sens нова-відповідь.sens');
  Mode:=RawByteString(ParamStr(1));
  Root:=ParamStr(2);
  InputPath:=ParamStr(3);
  OutputPath:=ParamStr(4);
  if (InputPath='') or (OutputPath='') or
     (ExtractFileExt(InputPath)<>'.sens') or
     (ExtractFileExt(OutputPath)<>'.sens') then
    raise EFileMachineError.Create('Тільки фізичні .sens файли; .lisp — людська укр-проєкція');
  if Mode=KQuote then Profile:=npQuote
  else if Mode=KAtom then Profile:=npAtom
  else if Mode=KEq then Profile:=npEq
  else if Mode=KSelector then Profile:=npSelector
  else if Mode=KCond then Profile:=npCond
  else raise EFileMachineError.Create('Невідомий явний host-профіль машини');
  if not DirectoryExists(Root) then
    raise EFileMachineError.Create('Не існує pinned кореня SENS');

  {$IFNDEF LINUX}
  raise EFileMachineError.Create('Фізична публікація потребує Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EFileMachineError.Create('Машинне виконання потребує x86-64');
  {$ENDIF}
  Physical:=ReadCanonicalInput(InputPath);
  { Власник семантичного допуску — чинний pinned emitter у probe.
    Цей API вже створює ELF, перевіряє геометрію, виконує Linux child,
    звіряє точні canonical T5M байти з pinned native D3 executor. }
  ExecutePinnedNativeELF(Physical,RawByteString(Root),Profile,Answer);

  { Незалежний повторний механічний round-trip без тлумачення D7:
    ширину D1:0, D3:000 або W7 SYN ніколи не зрізаємо до host int. }
  DecodeT5M(Answer,Words);
  if (EncodeT5M(Words)<>Answer) or (Length(Words)<1) then
    raise EFileMachineError.Create('Машинна відповідь не канонічний T5M');
  PublishAnswer(OutputPath,Answer);
  WriteLn(UA('МАШИННЕ-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД профіль='),Mode,
    UA(' байтів='),Length(Answer),UA(' T5M=точний запис=атомарний'));
end;

begin
  try
    Run;
  except on E:Exception do begin
    WriteLn(StdErr,UA('МАШИННЕ-ELF-ПОМИЛКА: '),E.Message);
    ExitCode:=2;
  end end;
end.

{ Типи та володіння: Mode — raw UTF-8 bytes host CLI, не функція
  мови SENS; Profile — вибір вже існуючого машинного механізму.
  Physical/Answer — RawByteString із точними packed T5M байтами,
  тимчасові й автоматично звільняються Free Pascal. OutputPath — host
  шлях; власний тимчасовий inode створюється після завершеного
  Linux виконання і перейменовується НЕ через RenameFile, а через
  атомарний fpLink без перезапису. На помилці чужі байти не змінені.

  Питання: (1) Чому host-профіль не є законом Д3?
  (2) Чому перезаписувати .sens через FileExists -> fmCreate небезпечно?
  (3) Чому D7 SYN лишається 7-бітною координатою, не Unicode opcode?
  (4) Чому звірка з FPC runtime не є незалежним SENS REPL oracle?
  (5) Що гарантує повернення ExitCode=2 до файлової публікації? }
