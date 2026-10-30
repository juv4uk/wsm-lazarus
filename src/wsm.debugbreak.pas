{ G7.8 (задача #655) — АКТИВНА частина нативного налагоджувача SENS:
  точка зупину на фізичному вузлі машинного коду й огляд кадру в момент
  зупину.

  На чому саме стоїть точка зупину і чому саме там.
  -------------------------------------------------
  У цій архітектурі виконуваних одиниць рівно дві:
    а) Pascal-обчислювач wsm.eval / wsm.nativeeval — він не виконує
       машинний код і не має власного лічильника інструкцій, тож
       «зупинитись перед вузлом» там означало б вставити гачок у сам
       evaluator (це зміна семантичного шляху, а не налагоджувач);
    б) фізичний ELF64, який збирає wsm.elfd12adddesiatka і запускає
       sensrepltui. Саме він справді виконує інструкцію `add`.

  Тому точка зупину стоїть на ФІЗИЧНОМУ ЗСУВІ В ОБРАЗІ ELF — на тому
  самому байті, який модуль-генератор уже публікує як
  D12DesiatkaAddOpcodeAt. Це не вигаданий вузол: генератор сам звіряє
  цей зсув (Need(Length(Code) = D12DesiatkaAddOpcodeAt, ...)) і сам
  перевіряє, що в образі лежить $01 $D8.

  Зупинка НЕ потребує зміни генератора, і це головне: налагоджувач не
  чіпає ні файл, ні модуль-генератор. Він, як gdb, пише байт $CC в
  ПАМ'ЯТЬ уже запущеного процесу (PTRACE_POKETEXT), ловить SIGTRAP,
  відновлює початковий байт і повертає RIP на початок інструкції.
  Файл на диску лишається побайтово тим самим — це перевіряють
  позитивний і негативний свідки в scripts/test-debugger-active.pas.

  НЕГАТИВНИЙ СВІДОК (головна вимога задачі).
  ------------------------------------------
  Якщо в TDebugBreakpoints немає жодної точки, RunImage іде в гілку
  ZapustytyBezZupynky: там немає ні ptrace, ні PTRACE_POKETEXT, ні
  читання /proc/<pid>/maps, ні запису в пам'ять чужого процесу — лише
  той самий fork/execve/waitpid, що й до появи цього модуля. Кількість
  звернень до ptrace повертається в TDebugRun.PtraceRequests і мусить
  бути рівно 0. Це структурний доказ, а не обіцянка.

  Цей модуль не визначає жодного закону SENS: він не рахує, не
  порівнює домени й не вирішує викличність. Числа, які він показує, —
  це вміст регістрів зупиненого процесу.

  ПОВТОРНЕ СПРАЦЬОВУВАННЯ ТІЄЇ САМОЇ ТОЧКИ (закрито в цьому кроці).
  ------------------------------------------------------------------
  Попередній зріз відновлював байт і йшов PTRACE_CONT з RIP, уже
  повернутого на початок інструкції. Друга ітерація циклу виконувала
  ту саму інструкцію, але $CC там уже не стояв — зупину не було.
  Тепер після відновлення байта й повернення RIP робиться РІВНО ОДИН
  крок PTRACE_SINGLESTEP (інструкція виконується), і лише потім $CC
  ставиться назад. Тому наступне проходження тієї самої адреси знову
  ловить SIGTRAP. Це і є цикл:
     зупин → зняти регістри → відновити оригінальний байт →
     PTRACE_SINGLESTEP → повернути $CC → PTRACE_CONT.

  КІЛЬКА ТОЧОК ЗА ОДИН ЗАПУСК (закрито в цьому кроці).
  ----------------------------------------------------
  Реєстр більше не відмовляє на другій точці: усі точки ставляться
  перед першим PTRACE_CONT, а на кожному зупині RIP звіряється з
  адресою КОЖНОЇ точки. Збіг із жодною — відмова, а не вдавання
  зупину. Відмова лишається лише на ДУБЛЬ зсуву: два $CC в одному
  байті — це не дві точки, а одна.

  Що саме неможливо без зміни генератора (названо, не обійдено):
    1) зупин «перед вузлом ExactIR» — ExactIR не має виконувача й
       лічильника інструкцій, тому моменту «перед вузлом» фізично
       немає; тут вузол — байт машинного коду, який генератор уже
       публікує.
    2) сеанс пам'ятає не більше MaxStops зупинів; на довгому циклі
       це межа сеансу, а не межа механізму — вона названа відмовою,
       а не тихою втратою зупинів.

  Питання на розуміння саме цього фрагмента:
    1) Чому PTRACE_PEEKTEXT мусить повертати Int64, а не LongInt?
    2) Чому після SIGTRAP треба і відновити байт, і повернути RIP?
    3) Чому адреса зупину = початок відображення + зсув у файлі, а не
       p_vaddr + зсув?
    4) Чому в дочірньому процесі немає жодного лічильника звернень до
       ptrace, а в батьківському він є?
    5) Що саме змінилося б у негативному свідку, якби перевірка
       FBps.Count стояла ПІСЛЯ Pidgotuvaty?
    6) Чому без PTRACE_SINGLESTEP друга ітерація циклу не зупинилась
       би, навіть якби $CC лишався на місці?
    7) Чому $CC ставиться назад ПІСЛЯ кроку, а не ДО нього?
    8) Чому дві точки з однаковим зсувом — це відмова, а дві точки в
       сусідніх байтах одного машинного слова — ні? }
unit wsm.debugbreak;
{$mode objfpc}{$H+}{$codepage utf8}

interface

uses
  SysUtils, Classes, BaseUnix, Unix;

const
  { Скільки точок зупину тримає один сеанс. Межа механічна, не
    семантична. }
  MaxBreakpoints = 16;
  { Скільки зупинів сеанс пам'ятає для огляду. }
  MaxStops = 16;

type
  EDebugBreakError = class(Exception);

  { Фізичний вузол зупину. Наразі єдиний вид, який справді існує в
    цій архітектурі: зсув байта у фізичному образі ELF (0-based).
    ExactIR-вузол сюди НЕ підставляється: ExactIR не має лічильника
    виконання, і оголосити його «точкою зупину» означало б вигадати
    механізм, якого немає. }
  TBreakNodeKind = (bkImageOffset);

  TDebugBreakpoint = record
    Kind: TBreakNodeKind;
    Offset: SizeInt;
  end;

  { Один зупин. Регістри — фізичний вміст кадру зупиненого процесу,
    знятий PTRACE_GETREGS до виконання інструкції за адресою Address. }
  TDebugStop = record
    Hit: Boolean;
    Index: SizeInt;
    ImageOffset: SizeInt;
    Address: QWord;
    Rax, Rbx, Rcx, Rdx, Rsi, Rdi, Rsp, Rip: QWord;
    OpcodeLo, OpcodeHi: Byte;
  end;

  { Усі зупини одного запуску, у порядку, у якому вони сталися. Один
    і той самий вузол може з'явитися тут кілька разів — саме це й
    доводить свідок повторного спрацьовування. }
  TDebugStops = array of TDebugStop;

  { Результат одного запуску образу. PtraceRequests — лічильник
    звернень до ptrace; без точки зупину він мусить бути 0. }
  TDebugRun = record
    ExitCode: LongInt;
    Stdout: RawByteString;
    Traced: Boolean;
    PtraceRequests: QWord;
    StopCount: SizeInt;
    ElapsedMicros: QWord;
    ImageBytes: SizeInt;
    ImageHash: QWord;
    ImagePath: RawByteString;
    ErrorText: RawByteString;
  end;

  { Спільна підготовка образу: тимчасовий каталог, файл, право на
    виконання. Однакова для обох шляхів — щоб різниця між ними була
    рівно в налагоджувачі, а не в підготовці. }
  TImageSlot = record
    Dir: RawByteString;
    Elf: RawByteString;
    Out: RawByteString;
    Ready: Boolean;
  end;

  { Реєстр точок одного сеансу. Кілька точок за запуск — норма; дві
    точки з тим самим зсувом — відмова, бо це не дві точки, а одна. }
  TDebugBreakpoints = class
  private
    FItems: array[0..MaxBreakpoints-1] of TDebugBreakpoint;
    FCount: SizeInt;
  public
    procedure Add(ImageOffset: SizeInt);
    procedure Clear;
    function Count: SizeInt;
    function At(Index: SizeInt): TDebugBreakpoint;
  end;

  TDebugSession = class
  private
    FBps: TDebugBreakpoints;
    FStops: array[0..MaxStops-1] of TDebugStop;
    FStopCount: SizeInt;
    FLast: TDebugRun;
    FKeepImage: Boolean;
    FKeptDir: RawByteString;
    FKeptElf: RawByteString;
    FKeptOut: RawByteString;
    procedure PrybratySlot(var Slot: TImageSlot);
    procedure PrybratyZberezhene;
  public
    constructor Create;
    destructor Destroy; override;
    property Breakpoints: TDebugBreakpoints read FBps;
    { Для свідка «файл на диску не змінився»: коли True, RunImage не
      прибирає тимчасовий образ, а віддає його шлях у Run.ImagePath.
      Прибирання — у деструкторі. У звичайному режимі False. }
    property KeepImage: Boolean read FKeepImage write FKeepImage;
    { Запускає фізичний образ. Якщо точок немає — жодного звернення
      до ptrace. Повертає False лише з названою причиною в Run.ErrorText. }
    function RunImage(const Image: RawByteString; out Run: TDebugRun): Boolean;
    function StopCount: SizeInt;
    function StopAt(Index: SizeInt): TDebugStop;
    { Українське подання останнього зупину: вузол, адреса, кадр. }
    function ZupynkaTekst: RawByteString;
    property Last: TDebugRun read FLast;
  end;

{ Компактний відбиток образу для свідка «ті самі байти» (FNV-1a 64).
  Не криптографія: потрібна рівність, а не стійкість. }
function VidbytokObrazu(const Image: RawByteString): QWord;

{ Точні UTF-8 байти з літерала. FPC згортає літерал у константу типу
  RawByteString через системну кодову сторінку, і кирилиця стає «?»;
  UTF8Encode(UnicodeString) такого шляху не має. }
function U(const S: UnicodeString): RawByteString;

{ Мікросекунди монотонного джерела: GetTickCount64 має 1 мс, цього
  замало для чесного порівняння швидкості двох запусків. }
function Mikrosekundy: QWord;

implementation

{$ifdef CPUX64}
const
  PTRACE_TRACEME  = 0;
  PTRACE_PEEKTEXT = 1;
  PTRACE_POKETEXT = 4;
  PTRACE_CONT     = 7;
  PTRACE_SINGLESTEP = 9;
  PTRACE_GETREGS  = 12;
  PTRACE_SETREGS  = 13;

type
  { struct user_regs_struct для x86_64 Linux: 27 послідовних QWord.
    Порядок полів — ABI ядра, не наш вибір. }
  TUserRegs = record
    r15, r14, r13, r12, rbp, rbx, r11, r10, r9, r8,
    rax, rcx, rdx, rsi, rdi, orig_rax, rip, cs, eflags, rsp, ss,
    fs_base, gs_base, ds, es, fs, gs: QWord;
  end;

{ Повертаємо Int64: ptrace віддає `long`, і PEEKTEXT кладе в нього ціле
  машинне слово. Вузький LongInt тут мовчки обрізав би старші байти. }
function ptrace(Request: LongInt; Pid: TPid; Addr: Pointer;
  Data: Pointer): Int64; cdecl; external 'c' name 'ptrace';
{$endif}

function VidbytokObrazu(const Image: RawByteString): QWord;
var
  I: SizeInt;
  H: QWord;
begin
  H := QWord(14695981039346656037);
  for I := 1 to Length(Image) do
  begin
    H := H xor QWord(Ord(Image[I]));
    H := H * QWord(1099511628211);
  end;
  Result := H;
end;

function U(const S: UnicodeString): RawByteString;
begin
  Result := UTF8Encode(S);
end;

function Mikrosekundy: QWord;
var
  Tv: TTimeVal;
begin
  if fpGetTimeOfDay(@Tv, nil) <> 0 then
    Exit(QWord(GetTickCount64) * 1000);
  Result := QWord(Tv.tv_sec) * 1000000 + QWord(Tv.tv_usec);
end;
procedure TDebugBreakpoints.Add(ImageOffset: SizeInt);
var
  I: SizeInt;
begin
  if ImageOffset < 0 then
    raise EDebugBreakError.Create(U('зсув вузла не може бути від''ємним'));
  if FCount >= MaxBreakpoints then
    raise EDebugBreakError.Create(U('перевищено межу точок зупину'));
  { Дубль зсуву — не друга точка: у тому самому байті стояв би один
    $CC, і реєстр обіцяв би те, чого не станеться. Відмова, не
    тихе схлопування. }
  for I := 0 to FCount - 1 do
    if FItems[I].Offset = ImageOffset then
      raise EDebugBreakError.Create(
        U('цей зсув уже стоїть у реєстрі точок зупину'));
  FItems[FCount].Kind := bkImageOffset;
  FItems[FCount].Offset := ImageOffset;
  Inc(FCount);
end;

procedure TDebugBreakpoints.Clear;
begin
  FCount := 0;
end;

function TDebugBreakpoints.Count: SizeInt;
begin
  Result := FCount;
end;

function TDebugBreakpoints.At(Index: SizeInt): TDebugBreakpoint;
begin
  if (Index < 0) or (Index >= FCount) then
    raise EDebugBreakError.Create(U('точка зупину поза реєстром'));
  Result := FItems[Index];
end;

{ ---------------------------------------------------------------- }
{ Спільна підготовка образу                                        }
{ ---------------------------------------------------------------- }

var
  GLichylnykKatalohiv: LongInt = 0;

function Pidgotuvaty(const Image: RawByteString; out Slot: TImageSlot): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  Slot.Ready := False;
  Slot.Dir := '';
  Slot.Elf := '';
  Slot.Out := '';
  Inc(GLichylnykKatalohiv);
  Slot.Dir := RawByteString(GetTempDir) + 'wsm-dbgbk-' +
    RawByteString(IntToStr(fpGetPid)) + '-' +
    RawByteString(IntToStr(GLichylnykKatalohiv));
  if fpMkdir(PChar(Slot.Dir), &700) <> 0 then
  begin
    Slot.Dir := '';
    Exit;
  end;
  Slot.Elf := Slot.Dir + '/obraz.elf';
  Slot.Out := Slot.Dir + '/stdout';
  try
    F := TFileStream.Create(Slot.Elf, fmCreate);
    try
      if Length(Image) > 0 then F.WriteBuffer(Image[1], Length(Image));
    finally
      F.Free;
    end;
  except
    Exit;
  end;
  if fpChmod(PChar(Slot.Elf), &755) <> 0 then
    Exit;
  Slot.Ready := True;
  Result := True;
end;

procedure Prybraty(var Slot: TImageSlot);
begin
  if Slot.Elf <> '' then fpUnlink(PChar(Slot.Elf));
  if Slot.Out <> '' then fpUnlink(PChar(Slot.Out));
  if Slot.Dir <> '' then fpRmdir(PChar(Slot.Dir));
  Slot.Ready := False;
  Slot.Elf := '';
  Slot.Out := '';
  Slot.Dir := '';
end;

{ Читає stdout образу й прибирає лише хвіст CR/LF: решта байтів
  лишається точною. Порожній stdout — це відмова, а не «нуль». }
function ProchytatyVyhid(const Slot: TImageSlot; out Text: RawByteString): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  Text := '';
  if not FileExists(Slot.Out) then Exit;
  F := TFileStream.Create(Slot.Out, fmOpenRead);
  try
    SetLength(Text, F.Size);
    if F.Size > 0 then F.ReadBuffer(Text[1], F.Size);
  finally
    F.Free;
  end;
  while (Length(Text) > 0) and
        ((Text[Length(Text)] = #10) or (Text[Length(Text)] = #13)) do
    SetLength(Text, Length(Text) - 1);
  Result := Length(Text) > 0;
end;

{ Запуск без налагоджувача: рівно fork → execve → waitpid → stdout.
  Жодного ptrace, жодного /proc, жодного запису в пам'ять. }
function ZapustytyBezZupynky(const Slot: TImageSlot; out Run: TDebugRun): Boolean;
var
  Pid: TPid;
  Status: LongInt;
  Argv: array[0..1] of PChar;
  Fd, DevNull: LongInt;
  Start: QWord;
begin
  Result := False;
  Run.Traced := False;
  Run.PtraceRequests := 0;
  Run.StopCount := 0;
  Argv[0] := PChar(Slot.Elf);
  Argv[1] := nil;
  Fd := fpOpen(PChar(Slot.Out), O_WRONLY or O_CREAT or O_TRUNC, &644);
  if Fd < 0 then
  begin
    Run.ErrorText := U('не вдалося відкрити stdout образу');
    Exit;
  end;
  DevNull := fpOpen('/dev/null', O_WRONLY);
  Start := Mikrosekundy;
  Pid := fpFork;
  if Pid = 0 then
  begin
    { Дочірній процес: жодного слова про налагоджувач. }
    if DevNull >= 0 then fpDup2(DevNull, 2);
    fpDup2(Fd, 1);
    fpExecve(PChar(Slot.Elf), @Argv[0], nil);
    Halt(127);
  end;
  if DevNull >= 0 then fpClose(DevNull);
  fpClose(Fd);
  if Pid < 0 then
  begin
    Run.ErrorText := U('fork не вдався');
    Exit;
  end;
  Status := 0;
  if fpWaitPid(Pid, Status, 0) <> Pid then
  begin
    Run.ErrorText := U('waitpid не дочекався образу');
    Exit;
  end;
  Run.ElapsedMicros := Mikrosekundy - Start;
  if not WIFEXITED(Status) then
  begin
    Run.ErrorText := U('образ завершився не через exit');
    Exit;
  end;
  Run.ExitCode := WEXITSTATUS(Status);
  { Та сама угода, що й у traced-шляху: порожній stdout не є відмовою.
    Обидва шляхи мусять звітувати однаково, інакше негативний свідок
    порівнював би різні угоди, а не різні механізми. }
  if not ProchytatyVyhid(Slot, Run.Stdout) then
    Run.Stdout := '';
  Result := True;
end;

{$ifdef CPUX64}
{ База завантаження PIE-образу: перший рядок /proc/<pid>/maps для
  нашого файлу з offset 0. Єдиний PT_LOAD має p_offset=0, тож початок
  цього відображення відповідає байту 0 образу. }
function BazaObrazu(Pid: TPid; const Elf: RawByteString; out Base: QWord): Boolean;
var
  L: TStringList;
  I, P: SizeInt;
  Line, Hex: RawByteString;
begin
  Result := False;
  Base := 0;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile('/proc/' + IntToStr(Pid) + '/maps');
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
    begin
      Line := RawByteString(L[I]);
      if Pos(Elf, Line) = 0 then Continue;
      if Pos(' 00000000 ', Line) = 0 then Continue;
      P := Pos(' ', Line);
      if P = 0 then Continue;
      Hex := Copy(Line, 1, P - 1);
      P := Pos('-', Hex);
      if P = 0 then Continue;
      Hex := Copy(Hex, 1, P - 1);
      Base := StrToQWordDef('$' + String(Hex), 0);
      Result := Base <> 0;
      Exit;
    end;
  finally
    L.Free;
  end;
end;

{ Адреса в чужому адресному просторі: ptrace бере Pointer, а не QWord. }
function Adr(A: QWord): Pointer;
begin
  Result := Pointer(PtrUInt(A));
end;

{ Замінює РІВНО ОДИН байт за адресою A, не затираючи сусідні байти
  того самого машинного слова. Це важливо, коли дві точки стоять у
  межах одного 8-байтового слова: наївний запис цілого слова затер би
  $CC сусідньої точки. Повертає в Bulo те, що лежало там до заміни. }
function ZminytyBait(Pid: TPid; A: QWord; Bait: Byte; out Bulo: Byte): Boolean;
var
  Slovo: QWord;
begin
  Slovo := QWord(ptrace(PTRACE_PEEKTEXT, Pid, Adr(A), nil));
  Bulo := Byte(Slovo and QWord($FF));
  Slovo := (Slovo and (not QWord($FF))) or QWord(Bait);
  Result := ptrace(PTRACE_POKETEXT, Pid, Adr(A), Adr(Slovo)) = 0;
end;

{ Запуск із точками зупину. Головний цикл на кожен зупин:
    PTRACE_CONT → SIGTRAP → зняти регістри → відновити оригінальний
    байт → повернути RIP на початок інструкції → PTRACE_SINGLESTEP
    (рівно один крок) → повернути $CC → PTRACE_CONT.
  Крок і є те, що робить повторне спрацьовування можливим: інструкція
  справді виконується, RIP іде за неї, і наступне проходження тієї самої
  адреси знову натрапляє на $CC.

  Файл образу не змінюється: $CC живе лише в ПАМ'ЯТІ процесу. }
function ZupynytyNaVuzlakh(const Slot: TImageSlot;
  const Image: RawByteString; Bps: TDebugBreakpoints; out Run: TDebugRun;
  out Stops: TDebugStops): Boolean;
var
  Pid: TPid;
  Status: LongInt;
  Argv: array[0..1] of PChar;
  Fd, DevNull: LongInt;
  Start: QWord;
  Base: QWord;
  Adresy: array of QWord;
  PershiBaity: array of Byte;
  Regs: TUserRegs;
  Nb, I, K, Nzupynok, Vuzol: SizeInt;
  Slovo: QWord;
  Bulo: Byte;
  SameBytes: Boolean;
  Stop: TDebugStop;
begin
  Result := False;
  SetLength(Stops, 0);
  Nb := Bps.Count;
  if Nb <= 0 then
  begin
    Run.ErrorText := U('запуск із точками без жодної точки');
    Exit;
  end;
  SetLength(Adresy, Nb);
  SetLength(PershiBaity, Nb);
  Nzupynok := 0;
  Argv[0] := PChar(Slot.Elf);
  Argv[1] := nil;
  Fd := fpOpen(PChar(Slot.Out), O_WRONLY or O_CREAT or O_TRUNC, &644);
  if Fd < 0 then
  begin
    Run.ErrorText := U('не вдалося відкрити stdout образу');
    Exit;
  end;
  DevNull := fpOpen('/dev/null', O_WRONLY);
  Start := Mikrosekundy;
  Pid := fpFork;
  if Pid = 0 then
  begin
    ptrace(PTRACE_TRACEME, 0, nil, nil);
    if DevNull >= 0 then fpDup2(DevNull, 2);
    fpDup2(Fd, 1);
    fpExecve(PChar(Slot.Elf), @Argv[0], nil);
    Halt(127);
  end;
  if DevNull >= 0 then fpClose(DevNull);
  fpClose(Fd);
  if Pid < 0 then
  begin
    Run.ErrorText := U('fork не вдався');
    Exit;
  end;
  Run.Traced := True;

  Status := 0;
  if fpWaitPid(Pid, Status, 0) <> Pid then
  begin
    Run.ErrorText := U('немає зупину після exec');
    Exit;
  end;
  if not (WIFSTOPPED(Status) and (WSTOPSIG(Status) = SIGTRAP)) then
  begin
    Run.ErrorText := U('exec не дав очікуваного SIGTRAP');
    Exit;
  end;

  if not BazaObrazu(Pid, Slot.Elf, Base) then
  begin
    Run.ErrorText := U('не знайдено базу завантаження образу в /proc/maps');
    Exit;
  end;

  { Перший прохід — ЛИШЕ перевірка. Нічого ще не підмінено, тому кожне
    слово мусить побайтово збігатися з образом: інакше зупин був би
    фальшивим. }
  for I := 0 to Nb - 1 do
  begin
    Adresy[I] := Base + QWord(Bps.At(I).Offset);
    if SizeInt(Bps.At(I).Offset) + 8 > Length(Image) then
    begin
      Run.ErrorText := U('вузол лежить поза образом');
      ptrace(PTRACE_CONT, Pid, nil, nil);
      Exit;
    end;
    Inc(Run.PtraceRequests);
    Slovo := QWord(ptrace(PTRACE_PEEKTEXT, Pid, Adr(Adresy[I]), nil));
    SameBytes := True;
    for K := 0 to 7 do
      if Byte(Slovo shr (8 * K)) <>
         Ord(Image[Bps.At(I).Offset + K + 1]) then
        SameBytes := False;
    if not SameBytes then
    begin
      Run.ErrorText := U('за адресою вузла лежать не ті байти образу');
      ptrace(PTRACE_CONT, Pid, nil, nil);
      Exit;
    end;
    PershiBaity[I] := Byte(Slovo and QWord($FF));
  end;

  { Другий прохід — постановка $CC у пам'ять процесу. }
  for I := 0 to Nb - 1 do
  begin
    Inc(Run.PtraceRequests);
    if not ZminytyBait(Pid, Adresy[I], $CC, Bulo) then
    begin
      Run.ErrorText := U('не вдалося записати точку зупину в пам''ять образу');
      ptrace(PTRACE_CONT, Pid, nil, nil);
      Exit;
    end;
    if Bulo <> PershiBaity[I] then
    begin
      Run.ErrorText := U('байт під точкою змінився між перевіркою й записом');
      ptrace(PTRACE_CONT, Pid, nil, nil);
      Exit;
    end;
  end;

  { Головний цикл. Кожна ітерація — один зупин і один крок. }
  while True do
  begin
    Inc(Run.PtraceRequests);
    ptrace(PTRACE_CONT, Pid, nil, nil);
    Status := 0;
    if fpWaitPid(Pid, Status, 0) <> Pid then
    begin
      Run.ErrorText := U('waitpid не дочекався зупину');
      Exit;
    end;
    if WIFEXITED(Status) then Break;
    if not WIFSTOPPED(Status) then
    begin
      Run.ErrorText := U('образ завершився не через exit');
      Exit;
    end;
    if WSTOPSIG(Status) <> SIGTRAP then
    begin
      Run.ErrorText := U('зупин не через SIGTRAP (сигнал ') +
        RawByteString(IntToStr(WSTOPSIG(Status))) + ')';
      Exit;
    end;

    FillChar(Regs, SizeOf(Regs), 0);
    Inc(Run.PtraceRequests);
    if ptrace(PTRACE_GETREGS, Pid, nil, @Regs) <> 0 then
    begin
      Run.ErrorText := U('не вдалося зняти регістри зупиненого кадру');
      Exit;
    end;
    { Єдиний доказ, що це НАША точка, а не чужий SIGTRAP: RIP стоїть
      рівно за байтом $CC. Шукаємо серед УСІХ точок реєстру. }
    Vuzol := -1;
    for I := 0 to Nb - 1 do
      if Regs.rip = Adresy[I] + 1 then
      begin
        Vuzol := I;
        Break;
      end;
    if Vuzol < 0 then
    begin
      Run.ErrorText := U('SIGTRAP не на нашому вузлі (RIP не збігся)');
      for I := 0 to Nb - 1 do
        ZminytyBait(Pid, Adresy[I], PershiBaity[I], Bulo);
      ptrace(PTRACE_CONT, Pid, nil, nil);
      Exit;
    end;

    FillChar(Stop, SizeOf(Stop), 0);
    Stop.Hit := True;
    Stop.Index := Nzupynok;
    Stop.ImageOffset := Bps.At(Vuzol).Offset;
    Stop.Address := Adresy[Vuzol];
    Stop.Rax := Regs.rax;
    Stop.Rbx := Regs.rbx;
    Stop.Rcx := Regs.rcx;
    Stop.Rdx := Regs.rdx;
    Stop.Rsi := Regs.rsi;
    Stop.Rdi := Regs.rdi;
    Stop.Rsp := Regs.rsp;
    Stop.Rip := Adresy[Vuzol];
    Stop.OpcodeLo := PershiBaity[Vuzol];
    Inc(Run.PtraceRequests);
    Slovo := QWord(ptrace(PTRACE_PEEKTEXT, Pid, Adr(Adresy[Vuzol]), nil));
    Stop.OpcodeHi := Byte((Slovo shr 8) and QWord($FF));
    SetLength(Stops, Nzupynok + 1);
    Stops[Nzupynok] := Stop;
    Inc(Nzupynok);

    { 1. Відновлюємо оригінальний байт: інакше крок виконав би $CC. }
    Inc(Run.PtraceRequests);
    if not ZminytyBait(Pid, Adresy[Vuzol], PershiBaity[Vuzol], Bulo) then
    begin
      Run.ErrorText := U('не вдалося відновити байт під точкою');
      Exit;
    end;
    { 2. Повертаємо RIP на початок інструкції: після SIGTRAP він стоїть
      за байтом $CC, і без цього крок виконав би обрізану інструкцію. }
    Regs.rip := Adresy[Vuzol];
    Inc(Run.PtraceRequests);
    if ptrace(PTRACE_SETREGS, Pid, nil, @Regs) <> 0 then
    begin
      Run.ErrorText := U('не вдалося повернути RIP на початок інструкції');
      Exit;
    end;
    { 3. РІВНО ОДИН крок — саме він виконує інструкцію й веде RIP за неї. }
    Inc(Run.PtraceRequests);
    ptrace(PTRACE_SINGLESTEP, Pid, nil, nil);
    Status := 0;
    if fpWaitPid(Pid, Status, 0) <> Pid then
    begin
      Run.ErrorText := U('waitpid не дочекався кроку');
      Exit;
    end;
    if WIFEXITED(Status) then Break;
    if not WIFSTOPPED(Status) then
    begin
      Run.ErrorText := U('образ завершився не через exit під час кроку');
      Exit;
    end;
    if WSTOPSIG(Status) <> SIGTRAP then
    begin
      Run.ErrorText := U('крок завершився не через SIGTRAP (сигнал ') +
        RawByteString(IntToStr(WSTOPSIG(Status))) + ')';
      Exit;
    end;
    { 4. Ставимо $CC назад — ПІСЛЯ кроку, інакше крок виконав би $CC. }
    Inc(Run.PtraceRequests);
    if not ZminytyBait(Pid, Adresy[Vuzol], $CC, Bulo) then
    begin
      Run.ErrorText := U('не вдалося повернути точку зупину після кроку');
      Exit;
    end;
    if Bulo <> PershiBaity[Vuzol] then
    begin
      Run.ErrorText := U('крок змінив більше, ніж один байт під точкою');
      Exit;
    end;

    if Nzupynok >= MaxStops then
    begin
      Run.ErrorText := U('перевищено межу зупинів одного сеансу (') +
        RawByteString(IntToStr(MaxStops)) + ')';
      Exit;
    end;
  end;

  if Nzupynok = 0 then
  begin
    Run.ErrorText := U('жодна точка зупину не спрацювала');
    Exit;
  end;
  Run.ElapsedMicros := Mikrosekundy - Start;
  if not WIFEXITED(Status) then
  begin
    Run.ErrorText := U('образ завершився не через exit після зупину');
    Exit;
  end;
  Run.ExitCode := WEXITSTATUS(Status);
  Run.StopCount := Nzupynok;
  { Порожній stdout — законний результат образу (наприклад цикл, який
    нічого не друкує), а не відмова. Вміст stdout перевіряють свідки;
    сам запуск звітує рівно те, що образ надрукував. }
  if not ProchytatyVyhid(Slot, Run.Stdout) then
    Run.Stdout := '';
  Result := True;
end;
{$endif}

constructor TDebugSession.Create;
begin
  inherited Create;
  FBps := TDebugBreakpoints.Create;
  FStopCount := 0;
  FillChar(FLast, SizeOf(FLast), 0);
end;

destructor TDebugSession.Destroy;
begin
  PrybratyZberezhene;
  FBps.Free;
  inherited Destroy;
end;

procedure TDebugSession.PrybratyZberezhene;
begin
  if FKeptElf <> '' then fpUnlink(PChar(FKeptElf));
  if FKeptOut <> '' then fpUnlink(PChar(FKeptOut));
  if FKeptDir <> '' then fpRmdir(PChar(FKeptDir));
  FKeptElf := '';
  FKeptOut := '';
  FKeptDir := '';
end;

procedure TDebugSession.PrybratySlot(var Slot: TImageSlot);
begin
  if FKeepImage and Slot.Ready then
  begin
    FKeptDir := Slot.Dir;
    FKeptElf := Slot.Elf;
    FKeptOut := Slot.Out;
    Slot.Dir := '';
    Slot.Elf := '';
    Slot.Out := '';
    Slot.Ready := False;
    Exit;
  end;
  Prybraty(Slot);
end;

function TDebugSession.StopCount: SizeInt;
begin
  Result := FStopCount;
end;

function TDebugSession.StopAt(Index: SizeInt): TDebugStop;
begin
  if (Index < 0) or (Index >= FStopCount) then
    raise EDebugBreakError.Create(U('зупин поза збереженим списком'));
  Result := FStops[Index];
end;

function TDebugSession.RunImage(const Image: RawByteString;
  out Run: TDebugRun): Boolean;
var
  Slot: TImageSlot;
  Zupyny: TDebugStops;
  I: SizeInt;
  Start: QWord;
begin
  FillChar(Run, SizeOf(Run), 0);
  { Кожен запуск має власний список зупинів: інакше другий запуск
    того самого сеансу показував би зупини першого. }
  FStopCount := 0;
  Run.ImageBytes := Length(Image);
  Run.ImageHash := VidbytokObrazu(Image);
  Slot.Ready := False;
  Slot.Dir := '';
  Slot.Elf := '';
  Slot.Out := '';
  PrybratyZberezhene;
  Result := False;
  Start := Mikrosekundy;

  { НЕГАТИВНИЙ СВІДОК: без жодної точки зупину шляху через
    налагоджувач немає взагалі. Тут лише перевірка довжини масиву. }
  if FBps.Count = 0 then
  begin
    if not Pidgotuvaty(Image, Slot) then
    begin
      Run.ErrorText := U('не вдалося підготувати образ');
      Exit;
    end;
    try
      Result := ZapustytyBezZupynky(Slot, Run);
    finally
      PrybratySlot(Slot);
    end;
    if FKeepImage then Run.ImagePath := FKeptElf;
    Run.ElapsedMicros := Mikrosekundy - Start;
    FLast := Run;
    Exit;
  end;

  {$ifndef CPUX64}
  Run.ErrorText := U('точки зупину підтримані лише на x86-64 Linux');
  Exit;
  {$else}
  if not Pidgotuvaty(Image, Slot) then
  begin
    Run.ErrorText := U('не вдалося підготувати образ');
    Exit;
  end;
  try
    Result := ZupynytyNaVuzlakh(Slot, Image, FBps, Run, Zupyny);
    if Result then
    begin
      for I := 0 to High(Zupyny) do
        if FStopCount < MaxStops then
        begin
          FStops[FStopCount] := Zupyny[I];
          Inc(FStopCount);
        end;
      Run.StopCount := FStopCount;
    end;
  finally
    PrybratySlot(Slot);
  end;
  if FKeepImage then Run.ImagePath := FKeptElf;
  {$endif}
  Run.ElapsedMicros := Mikrosekundy - Start;
  FLast := Run;
end;

function TDebugSession.ZupynkaTekst: RawByteString;
var
  S: TDebugStop;
  I: SizeInt;
begin
  if FStopCount = 0 then
  begin
    Result := U('зупинів немає');
    Exit;
  end;
  Result := '';
  for I := 0 to FStopCount - 1 do
  begin
    S := FStops[I];
    Result := Result +
      U('зупин ') + RawByteString(IntToStr(I)) +
      U(': вузол=образ:') + RawByteString(IntToStr(S.ImageOffset)) +
      U(' адреса=0x') + RawByteString(IntToHex(Int64(S.Address), 12)) +
      U(' опкод=') + RawByteString(IntToHex(S.OpcodeLo, 2)) +
      RawByteString(IntToHex(S.OpcodeHi, 2)) + #10 +
      U('  кадр 0: rax=') + RawByteString(IntToStr(S.Rax)) +
      U(' rbx=') + RawByteString(IntToStr(S.Rbx)) +
      U(' rcx=') + RawByteString(IntToStr(S.Rcx)) +
      U(' rdx=') + RawByteString(IntToStr(S.Rdx)) + #10 +
      U('  батьківського кадру немає: образ не має викликів') + #10;
  end;
end;

end.
