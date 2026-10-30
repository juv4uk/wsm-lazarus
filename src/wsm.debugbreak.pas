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

  Що саме неможливо без зміни генератора (названо, не обійдено):
    1) повторне спрацьовування тієї самої точки в циклі — після
       відновлення байта ми продовжуємо без PTRACE_SINGLESTEP, тож
       друга ітерація циклу не зупиниться. Це механічна межа саме
       цього кроку, а не вирок: singlestep + повторна постановка $CC
       її знімає;
    2) більше однієї точки за один запуск — реєстр це відхиляє
       явною відмовою, а не тихо ігнорує другу;
    3) зупин «перед вузлом ExactIR» — ExactIR не має виконувача й
       лічильника інструкцій, тому моменту «перед вузлом» фізично
       немає; тут вузол — байт машинного коду, який генератор уже
       публікує.

  Питання на розуміння саме цього фрагмента:
    1) Чому PTRACE_PEEKTEXT мусить повертати Int64, а не LongInt?
    2) Чому після SIGTRAP треба і відновити байт, і повернути RIP?
    3) Чому адреса зупину = початок відображення + зсув у файлі, а не
       p_vaddr + зсув?
    4) Чому в дочірньому процесі немає жодного лічильника звернень до
       ptrace, а в батьківському він є?
    5) Що саме змінилося б у негативному свідку, якби перевірка
       FBps.Count стояла ПІСЛЯ Pidgotuvaty? }
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
begin
  if ImageOffset < 0 then
    raise EDebugBreakError.Create(U('зсув вузла не може бути від''ємним'));
  if FCount >= MaxBreakpoints then
    raise EDebugBreakError.Create(U('перевищено межу точок зупину'));
  if FCount > 0 then
    raise EDebugBreakError.Create(
      U('цей механізм зупиняється рівно на одному вузлі за запуск'));
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
  Result := ProchytatyVyhid(Slot, Run.Stdout);
  if not Result then
    Run.ErrorText := U('образ не надрукував нічого');
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

{ Один зупин на вузлі Bp: підміна байта в пам'яті, SIGTRAP, огляд
  регістрів, відновлення байта, продовження до exit. }
function ZupynytyNaVuzli(const Slot: TImageSlot; const Image: RawByteString;
  Bp: TDebugBreakpoint; out Run: TDebugRun; out Stop: TDebugStop): Boolean;
var
  Pid: TPid;
  Status: LongInt;
  Argv: array[0..1] of PChar;
  Fd, DevNull: LongInt;
  Start: QWord;
  Base, Addr, Slovo, Save: QWord;
  Regs: TUserRegs;
  I: SizeInt;
  SameBytes: Boolean;

  procedure UrakhuvatyPtrace;
  begin
    Inc(Run.PtraceRequests);
  end;

  function Adr(A: QWord): Pointer;
  begin
    Result := Pointer(PtrUInt(A));
  end;

begin
  Result := False;
  FillChar(Stop, SizeOf(Stop), 0);
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
  Addr := Base + QWord(Bp.Offset);
  Stop.Address := Addr;
  Stop.ImageOffset := Bp.Offset;
  Stop.Index := 0;

  if SizeInt(Bp.Offset) + 8 > Length(Image) then
  begin
    Run.ErrorText := U('вузол лежить поза образом');
    ptrace(PTRACE_CONT, Pid, nil, nil);
    Exit;
  end;

  { Перед підміною байта переконуємось, що за цією адресою справді
    лежить образ, а не щось інше: інакше зупин був би фальшивим. }
  UrakhuvatyPtrace;
  Slovo := QWord(ptrace(PTRACE_PEEKTEXT, Pid, Adr(Addr), nil));
  SameBytes := True;
  for I := 0 to 7 do
    if Byte(Slovo shr (8 * I)) <> Ord(Image[Bp.Offset + I + 1]) then
      SameBytes := False;
  if not SameBytes then
  begin
    Run.ErrorText := U('за адресою вузла лежать не ті байти образу');
    ptrace(PTRACE_CONT, Pid, nil, nil);
    Exit;
  end;
  Save := Slovo;
  Stop.OpcodeLo := Byte(Save and $FF);
  Stop.OpcodeHi := Byte((Save shr 8) and $FF);

  { Ставимо $CC лише в ПАМ'ЯТЬ процесу; файл не змінюється. }
  UrakhuvatyPtrace;
  if ptrace(PTRACE_POKETEXT, Pid, Adr(Addr),
      Pointer(PtrUInt((Save and (not QWord($FF))) or QWord($CC)))) <> 0 then
  begin
    Run.ErrorText := U('не вдалося записати точку зупину в пам''ять образу');
    ptrace(PTRACE_CONT, Pid, nil, nil);
    Exit;
  end;

  UrakhuvatyPtrace;
  ptrace(PTRACE_CONT, Pid, nil, nil);
  Status := 0;
  if fpWaitPid(Pid, Status, 0) <> Pid then
  begin
    Run.ErrorText := U('немає зупину на вузлі');
    Exit;
  end;
  if not (WIFSTOPPED(Status) and (WSTOPSIG(Status) = SIGTRAP)) then
  begin
    Run.ErrorText := U('вузол не спрацював: образ завершився без SIGTRAP');
    Exit;
  end;

  FillChar(Regs, SizeOf(Regs), 0);
  UrakhuvatyPtrace;
  if ptrace(PTRACE_GETREGS, Pid, nil, @Regs) <> 0 then
  begin
    Run.ErrorText := U('не вдалося зняти регістри зупиненого кадру');
    Exit;
  end;
  { Єдиний доказ, що це НАША точка, а не чужий SIGTRAP: RIP стоїть
    рівно за байтом $CC. Інакше — відмова, без удавання зупину. }
  if Regs.rip <> Addr + 1 then
  begin
    Run.ErrorText := U('SIGTRAP не на нашому вузлі (RIP не збігся)');
    ptrace(PTRACE_POKETEXT, Pid, Adr(Addr), Adr(Save));
    ptrace(PTRACE_CONT, Pid, nil, nil);
    Exit;
  end;

  Stop.Hit := True;
  Stop.Rax := Regs.rax;
  Stop.Rbx := Regs.rbx;
  Stop.Rcx := Regs.rcx;
  Stop.Rdx := Regs.rdx;
  Stop.Rsi := Regs.rsi;
  Stop.Rdi := Regs.rdi;
  Stop.Rsp := Regs.rsp;
  Stop.Rip := Addr;

  { Відновлюємо початковий байт і повертаємо RIP на початок інструкції:
    без цього продовження почалося б із другого байта `add`. }
  UrakhuvatyPtrace;
  ptrace(PTRACE_POKETEXT, Pid, Adr(Addr), Adr(Save));
  Regs.rip := Addr;
  UrakhuvatyPtrace;
  ptrace(PTRACE_SETREGS, Pid, nil, @Regs);
  UrakhuvatyPtrace;
  ptrace(PTRACE_CONT, Pid, nil, nil);

  Status := 0;
  if fpWaitPid(Pid, Status, 0) <> Pid then
  begin
    Run.ErrorText := U('образ не завершився після продовження');
    Exit;
  end;
  Run.ElapsedMicros := Mikrosekundy - Start;
  if not WIFEXITED(Status) then
  begin
    Run.ErrorText := U('образ завершився не через exit після зупину');
    Exit;
  end;
  Run.ExitCode := WEXITSTATUS(Status);
  Result := ProchytatyVyhid(Slot, Run.Stdout);
  if not Result then
    Run.ErrorText := U('образ не надрукував нічого');
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
  Stop: TDebugStop;
  Start: QWord;
begin
  FillChar(Run, SizeOf(Run), 0);
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
    Result := ZupynytyNaVuzli(Slot, Image, FBps.At(0), Run, Stop);
    if Result and Stop.Hit then
    begin
      if FStopCount < MaxStops then
      begin
        FStops[FStopCount] := Stop;
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
