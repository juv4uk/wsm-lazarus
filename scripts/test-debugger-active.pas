{ Задача #655 — свідки АКТИВНОЇ частини налагоджувача SENS.

  ПОЗИТИВНИЙ СВІДОК: точка зупину на фізичному вузлі образу ELF
  (зсув 120 + 10 = байт $01 $D8 інструкції `add`) справді спрацьовує,
  кадр у момент зупину показується, і програма після зупину дораховує
  те саме число (5) з тим самим кодом виходу.

  НЕГАТИВНИЙ СВІДОК: без жодної точки зупину жодного звернення до
  ptrace, жодного читання /proc, жодного запису в пам'ять процесу;
  вихід, stdout і байти образу — ті самі; час — у межах шуму проти
  контролю, який не знає про налагоджувач узагалі.

  СВІДОК ПОВТОРНОГО ЗУПИНУ (закриває обмеження 1 першого зрізу):
  образ «(додати 6 4)» друкує 10; цикл видобування цифр виконує ту
  саму інструкцію ДВІЧІ. Точка на цьому зсуві мусить дати stops=2, і
  обидва зупини мусять бути на ТІЙ САМІЙ адресі. Регістр rax на
  першому зупині — 10, на другому — 1: це справді друга ітерація.

  СВІДОК КІЛЬКОХ ТОЧОК (закриває обмеження 2): той самий образ, дві
  точки — на `add` і на `div`. Один запуск дає три зупини: add один
  раз, div двічі.

  СВІДОК ІНШОГО ФІЗИЧНОГО ОБРАЗУ (закриває обмеження 4): зовсім інший
  генератор — wsm.elfd12loop, ET_EXEC, інша інструкція `add eax,imm32`
  (опкод $05) і `dec ecx` ($FF $C9), інші зсуви. Три ітерації дають
  шість зупинів. Образ нічого не друкує — це його законна поведінка.

  ОГЛЯД ЛЕКСИЧНОГО КАДРУ: реальний TDebugTrace (wsm.debugtrace) плюс
  реальний ланцюг IEnvFrame (wsm.envframe) — зв'язування, значення,
  батьківський кадр. Огляд не створює жодного нового зв'язування.

  Це механічні свідки. Вони НЕ перевіряють законів SENS. }
program test_debugger_active;
{$mode objfpc}{$H+}{$codepage utf8}

uses
  SysUtils, Classes, BaseUnix, Unix,
  wsm.domain, wsm.debugtrace, wsm.envframe, wsm.lexframe, wsm.debugbreak,
  wsm.elfd12adddesiatka, wsm.elfd12loop, wsm.numericplane;

var
  Zlamiv: SizeInt = 0;

{ Точні UTF-8 байти з літерала — інакше FPC згортає кирилицю в «?»
  під час конкатенації з RawByteString. }
function U(const S: UnicodeString): RawByteString;
begin
  Result := UTF8Encode(S);
end;

procedure Perevir(Umozva: Boolean; const Prychyna: RawByteString);
begin
  if not Umozva then
  begin
    WriteLn(StdErr, U('DEBAGER-ПРОВАЛ: '), Prychyna);
    Halt(1);
  end;
end;

function Mikrosekundy: QWord;
var
  Tv: TTimeVal;
begin
  if fpGetTimeOfDay(@Tv, nil) <> 0 then
    Exit(QWord(GetTickCount64) * 1000);
  Result := QWord(Tv.tv_sec) * 1000000 + QWord(Tv.tv_usec);
end;

function Median(const Chasy: array of QWord): QWord;
var
  I, J: SizeInt;
  T: QWord;
  Copy: array of QWord;
begin
  SetLength(Copy, Length(Chasy));
  for I := 0 to High(Chasy) do Copy[I] := Chasy[I];
  for I := 1 to High(Copy) do
  begin
    T := Copy[I];
    J := I - 1;
    while (J >= 0) and (Copy[J] > T) do
    begin
      Copy[J + 1] := Copy[J];
      Dec(J);
    end;
    Copy[J + 1] := T;
  end;
  Result := Copy[Length(Copy) div 2];
end;

function VmistFailu(const Shliakh: RawByteString): RawByteString;
var
  F: TFileStream;
begin
  Result := '';
  F := TFileStream.Create(Shliakh, fmOpenRead);
  try
    SetLength(Result, F.Size);
    if F.Size > 0 then F.ReadBuffer(Result[1], F.Size);
  finally
    F.Free;
  end;
end;

{ Контроль швидкості: той самий fork/execve/waitpid, що й у
  ZapustytyBezZupynky, але БЕЗ налагоджувача взагалі — цей текст не
  знає про wsm.debugbreak. Якщо шлях без точки зупину справді не
  проходить через дебагер, медіани мусять збігтися в межах шуму. }
function ChasKontrolu(const Obraz: RawByteString; Kilkist: SizeInt): QWord;
var
  Chasy: array of QWord;
  I: SizeInt;
  Kataloh, ShliakhElf, ShliakhVyhid: RawByteString;
  F: TFileStream;
  Pid: TPid;
  Status: LongInt;
  Argv: array[0..1] of PChar;
  Fd, DevNull: LongInt;
  Start: QWord;
  Vmist: RawByteString;
begin
  SetLength(Chasy, Kilkist);
  for I := 0 to Kilkist - 1 do
  begin
    { Рівно та сама підготовка, що й у ZapustytyBezZupynky: свій
      каталог, свій файл, chmod, читання stdout і прибирання. }
    Start := Mikrosekundy;
    Kataloh := RawByteString(GetTempDir) + 'wsm-kontrol-' +
      RawByteString(IntToStr(fpGetPid)) + '-' + RawByteString(IntToStr(I));
    fpMkdir(PChar(Kataloh), &700);
    ShliakhElf := Kataloh + '/obraz.elf';
    ShliakhVyhid := Kataloh + '/stdout';
    F := TFileStream.Create(ShliakhElf, fmCreate);
    try
      F.WriteBuffer(Obraz[1], Length(Obraz));
    finally
      F.Free;
    end;
    fpChmod(PChar(ShliakhElf), &755);
    Argv[0] := PChar(ShliakhElf);
    Argv[1] := nil;
    Fd := fpOpen(PChar(ShliakhVyhid), O_WRONLY or O_CREAT or O_TRUNC, &644);
    DevNull := fpOpen('/dev/null', O_WRONLY);
    Pid := fpFork;
    if Pid = 0 then
    begin
      if DevNull >= 0 then fpDup2(DevNull, 2);
      fpDup2(Fd, 1);
      fpExecve(PChar(ShliakhElf), @Argv[0], nil);
      Halt(127);
    end;
    if DevNull >= 0 then fpClose(DevNull);
    fpClose(Fd);
    Status := 0;
    fpWaitPid(Pid, Status, 0);
    Vmist := VmistFailu(ShliakhVyhid);
    fpUnlink(PChar(ShliakhElf));
    fpUnlink(PChar(ShliakhVyhid));
    fpRmdir(PChar(Kataloh));
    Chasy[I] := Mikrosekundy - Start;
  end;
  Result := Median(Chasy);
end;

{ ------------------------------------------------------------------ }
{ ПОЗИТИВНИЙ СВІДОК: точка зупину спрацьовує                          }
{ ------------------------------------------------------------------ }
procedure SvidokTochkyZupynu(const Obraz: RawByteString;
  out ZupynokTekst: RawByteString; out ChasTrace: QWord);
var
  Seans: TDebugSession;
  Run: TDebugRun;
  S: TDebugStop;
  Vuzol: SizeInt;
  Kopiia: RawByteString;
begin
  Vuzol := D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt;
  Perevir(Length(Obraz) > Vuzol + 1, U('образ коротший за вузол'));
  Perevir(Ord(Obraz[Vuzol + 1]) = D12DesiatkaAddOpcodeLo,
    U('у образі немає $01 за вузлом'));
  Perevir(Ord(Obraz[Vuzol + 2]) = D12DesiatkaAddOpcodeHi,
    U('у образі немає $D8 за вузлом'));

  Kopiia := Obraz;
  Seans := TDebugSession.Create;
  try
    Seans.KeepImage := True;
    Seans.Breakpoints.Add(Vuzol);
    Perevir(Seans.Breakpoints.Count = 1, U('точку не додано'));
    Perevir(Seans.RunImage(Obraz, Run), U('запуск із точкою не вдався: ') +
      Run.ErrorText);
    Perevir(Run.Traced, U('запуск із точкою пішов нетраced-шляхом'));
    Perevir(Run.PtraceRequests > 0, U('точка зупину не зверталася до ptrace'));
    Perevir(Seans.StopCount = 1, U('зупин не зафіксовано'));
    S := Seans.StopAt(0);
    Perevir(S.Hit, U('зупин не позначено як такий, що стався'));
    Perevir(S.ImageOffset = Vuzol, U('зупин не на тому вузлі'));
    Perevir((S.OpcodeLo = D12DesiatkaAddOpcodeLo) and
            (S.OpcodeHi = D12DesiatkaAddOpcodeHi),
      U('у зупині не та інструкція'));
    Perevir(S.Address <> 0, U('адреса зупину нульова'));
    Perevir(S.Address and QWord($FFF) = QWord(Vuzol),
      U('адреса зупину не збігається зі зсувом у сторінці'));
    { Кадр у момент зупину: операнди ще не додані, `add` не виконано. }
    Perevir(S.Rax = 2, U('у кадрі не лівий доданок (rax)'));
    Perevir(S.Rbx = 3, U('у кадрі не правий доданок (rbx)'));
    { Після зупину програма мусить дорахувати те саме число. }
    Perevir(Run.ExitCode = 0, U('образ завершився з ненульовим кодом'));
    Perevir(Run.Stdout = '5', U('після зупину образ надрукував не 5'));
    ZupynokTekst := Seans.ZupynkaTekst;
    Perevir(Pos(U('вузол=образ:') + RawByteString(IntToStr(Vuzol)),
      ZupynokTekst) > 0, U('у поданні зупину немає вузла'));
    Perevir(Pos('rax=2', ZupynokTekst) > 0, U('у поданні зупину немає rax'));
    Perevir(Pos('rbx=3', ZupynokTekst) > 0, U('у поданні зупину немає rbx'));
    Perevir(Pos(U('батьківського кадру немає'), ZupynokTekst) > 0,
      U('подання зупину не називає відсутність батьківського кадру'));
    { Файл на диску лишається побайтово тим самим: $CC пішов у
      пам'ять процесу, а не в образ. }
    Perevir(FileExists(Run.ImagePath), U('образ на диску зник'));
    Perevir(VmistFailu(Run.ImagePath) = Kopiia,
      U('файл образу змінився після зупину'));
    ChasTrace := Run.ElapsedMicros;
  finally
    Seans.Free;
  end;
  Perevir(CompareMem(@Obraz[1], @Kopiia[1], Length(Obraz)),
    U('образ у пам''яті змінився після зупину'));
end;

{ ------------------------------------------------------------------ }
{ НЕГАТИВНИЙ СВІДОК: без точки зупину — нуль змін                    }
{ ------------------------------------------------------------------ }
procedure SvidokBezTochky(const Obraz: RawByteString;
  const ObrazPisliaZupynu: RawByteString; out ChasProstyi: QWord;
  out ChasKontrolnyi: QWord);
const
  Kilkist = 41;
var
  Seans: TDebugSession;
  Run: TDebugRun;
  Chasy: array of QWord;
  I: SizeInt;
  Kopiia: RawByteString;
begin
  Kopiia := Obraz;
  Seans := TDebugSession.Create;
  try
    Seans.KeepImage := True;
    Perevir(Seans.Breakpoints.Count = 0, U('сеанс почався з точкою зупину'));
    Perevir(Seans.RunImage(Obraz, Run), U('запуск без точки не вдався: ') +
      Run.ErrorText);
    { Структурний доказ: шляху через дебагер не було. }
    Perevir(not Run.Traced, U('без точки обрано traced-шлях'));
    Perevir(Run.PtraceRequests = 0, U('без точки було звернення до ptrace'));
    Perevir(Run.StopCount = 0, U('без точки стався зупин'));
    Perevir(Seans.StopCount = 0, U('сеанс запам''ятав зупин без точки'));
    { Поведінка та сама, що й із точкою. }
    Perevir(Run.ExitCode = 0, U('код виходу змінився без точки'));
    Perevir(Run.Stdout = '5', U('stdout змінився без точки'));
    { Байти ті самі — і в пам'яті, і на диску. }
    Perevir(Run.ImageHash = VidbytokObrazu(Obraz), U('відбиток образу інший'));
    Perevir(CompareMem(@Obraz[1], @Kopiia[1], Length(Obraz)),
      U('образ у пам''яті змінився без точки'));
    Perevir(VmistFailu(Run.ImagePath) = Kopiia,
      U('файл образу змінився без точки'));
    Perevir(Kopiia = ObrazPisliaZupynu,
      U('образ після зупину відрізняється від образу без зупину'));
    { Швидкість: медіана без точки проти контролю без налагоджувача. }
    SetLength(Chasy, Kilkist);
    for I := 0 to Kilkist - 1 do
    begin
      Perevir(Seans.RunImage(Obraz, Run), U('повторний запуск не вдався'));
      Perevir(Run.PtraceRequests = 0, U('на повторі з''явився ptrace'));
      Chasy[I] := Run.ElapsedMicros;
    end;
    ChasProstyi := Median(Chasy);
    { Після Clear кількість точок нульова — шлях знову простий. }
    Seans.Breakpoints.Add(D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt);
    Seans.Breakpoints.Clear;
    Perevir(Seans.Breakpoints.Count = 0, U('Clear не прибрав точку'));
    Perevir(Seans.RunImage(Obraz, Run), U('запуск після Clear не вдався'));
    Perevir(Run.PtraceRequests = 0, U('після Clear лишився ptrace'));
    Perevir(Run.Stdout = '5', U('після Clear stdout інший'));
  finally
    Seans.Free;
  end;
  ChasKontrolnyi := ChasKontrolu(Obraz, Kilkist);
end;

{ ------------------------------------------------------------------ }
{ СВІДОК ПОВТОРНОГО ЗУПИНУ ТІЄЇ САМОЇ ТОЧКИ (обмеження 1)            }
{ ------------------------------------------------------------------ }

{ Шукає в образі РІВНО ОДИН збіг байтового взірця і повертає 0-based
  зсув. Двоїстий збіг — відмова: інакше «той самий вузол» був би
  недоведеним, а випадковим. }
function ZnaytyVzir(const Obraz: RawByteString;
  const Vzir: array of Byte): SizeInt;
var
  I, J, Zbigiv, Zn: SizeInt;
  Ok: Boolean;
begin
  Zbigiv := 0;
  Zn := -1;
  for I := 0 to Length(Obraz) - (High(Vzir) + 1) do
  begin
    Ok := True;
    for J := 0 to High(Vzir) do
      if Ord(Obraz[I + J + 1]) <> Vzir[J] then
      begin
        Ok := False;
        Break;
      end;
    if Ok then
    begin
      Inc(Zbigiv);
      Zn := I;
    end;
  end;
  Perevir(Zbigiv = 1, U('взірець інструкції не єдиний в образі'));
  Result := Zn;
end;

procedure SvidokPovtornohoZupynu(const Obraz: RawByteString; Vuzol: SizeInt);
var
  Seans: TDebugSession;
  Run: TDebugRun;
  S0, S1: TDebugStop;
  Kopiia: RawByteString;
  Tekst: RawByteString;
begin
  Kopiia := Obraz;
  Seans := TDebugSession.Create;
  try
    Seans.KeepImage := True;
    Seans.Breakpoints.Add(Vuzol);
    Perevir(Seans.RunImage(Obraz, Run),
      U('запуск із точкою в циклі не вдався: ') + Run.ErrorText);
    Perevir(Run.Traced, U('цикл пішов не traced-шляхом'));
    { Головне твердження цього кроку: дві ітерації — два зупини. }
    Perevir(Seans.StopCount = 2,
      U('точка в циклі спрацювала не двічі, а ') +
      RawByteString(IntToStr(Seans.StopCount)));
    Perevir(Run.StopCount = 2, U('запуск звітує не два зупини'));
    S0 := Seans.StopAt(0);
    S1 := Seans.StopAt(1);
    Perevir(S0.ImageOffset = Vuzol, U('перший зупин не на тому вузлі'));
    Perevir(S1.ImageOffset = Vuzol, U('другий зупин не на тому вузлі'));
    Perevir(S0.Address <> 0, U('адреса першого зупину нульова'));
    { Та сама адреса — це і є повторне спрацьовування, а не друга точка. }
    Perevir(S0.Address = S1.Address,
      U('два зупини сталися на різних адресах'));
    Perevir(S0.Index = 0, U('перший зупин має індекс не 0'));
    Perevir(S1.Index = 1, U('другий зупин має індекс не 1'));
    { Різні значення регістрів доводять, що це справді друга ітерація,
      а не той самий знімок, показаний двічі. }
    Perevir(S0.Rax = 10, U('перший зупин не на сумі 10'));
    Perevir(S1.Rax = 1, U('другий зупин не на другій ітерації'));
    { Після двох зупинів програма дорахувала те саме, що й без них. }
    Perevir(Run.ExitCode = 0, U('образ із точкою в циклі вийшов не з 0'));
    Perevir(Run.Stdout = '10', U('образ із точкою в циклі надрукував не 10'));
    Perevir(VmistFailu(Run.ImagePath) = Kopiia,
      U('файл образу змінився після двох зупинів'));
    Tekst := Seans.ZupynkaTekst;
    Perevir(Pos(U('зупин 1:'), Tekst) > 0, U('подання не показало другий зупин'));
  finally
    Seans.Free;
  end;
  Perevir(CompareMem(@Obraz[1], @Kopiia[1], Length(Obraz)),
    U('образ у пам''яті змінився після двох зупинів'));
  WriteLn('DEBUGGER-REPEAT-OK node=image:', Vuzol,
    ' stops=2 same_address=1 rax_seq=10,1 value_after_stop=10 bytes=same');
end;

{ ------------------------------------------------------------------ }
{ СВІДОК КІЛЬКОХ ТОЧОК ЗА ОДИН ЗАПУСК (обмеження 2)                  }
{ ------------------------------------------------------------------ }
procedure SvidokKilkohTochok(const Obraz: RawByteString;
  VuzolAdd, VuzolDiv: SizeInt);
var
  Seans: TDebugSession;
  Run: TDebugRun;
  I: SizeInt;
  Por: RawByteString;
begin
  Perevir(VuzolAdd <> VuzolDiv, U('дві точки на одному зсуві'));
  Seans := TDebugSession.Create;
  try
    Seans.Breakpoints.Add(VuzolAdd);
    Seans.Breakpoints.Add(VuzolDiv);
    Perevir(Seans.Breakpoints.Count = 2, U('реєстр не прийняв другу точку'));
    Perevir(Seans.RunImage(Obraz, Run),
      U('запуск із двома точками не вдався: ') + Run.ErrorText);
    { add виконується раз, div — двічі: три зупини за один запуск. }
    Perevir(Seans.StopCount = 3,
      U('дві точки дали не три зупини, а ') +
      RawByteString(IntToStr(Seans.StopCount)));
    Perevir(Seans.StopAt(0).ImageOffset = VuzolAdd,
      U('перший зупин не на add'));
    Perevir(Seans.StopAt(1).ImageOffset = VuzolDiv,
      U('другий зупин не на div'));
    Perevir(Seans.StopAt(2).ImageOffset = VuzolDiv,
      U('третій зупин не на div'));
    Por := '';
    for I := 0 to Seans.StopCount - 1 do
    begin
      if I > 0 then Por := Por + ',';
      Por := Por + RawByteString(IntToStr(Seans.StopAt(I).ImageOffset));
    end;
    Perevir(Run.Stdout = '10', U('образ із двома точками надрукував не 10'));
    Perevir(Run.ExitCode = 0, U('образ із двома точками вийшов не з 0'));
    WriteLn('DEBUGGER-MULTI-OK nodes=image:', VuzolAdd, ',image:', VuzolDiv,
      ' stops=3 order=', Por, ' value_after_stop=10');
  finally
    Seans.Free;
  end;
end;

{ ------------------------------------------------------------------ }
{ СВІДОК ІНШОГО ФІЗИЧНОГО ОБРАЗУ (обмеження 4)                       }
{ ------------------------------------------------------------------ }

{ Зсув машинного коду в образі wsm.elfd12loop: 64-байтовий ELF64-заголовок
  плюс рівно один 56-байтовий program header. Генератор тримає цю сталу
  в implementation-секції, тому вона повторена тут — і одразу
  перевіряється побайтово нижче, а не береться на віру. }
const
  VuzolLoopHeaderBytes = 64 + 56;
  { `add eax,imm32` — 0-based 10 у машинному коді. }
  VuzolLoopAddAt = 10;
  { `dec ecx` — 0-based 15 у машинному коді. }
  VuzolLoopDecAt = 15;

procedure SvidokInshohoObrazu;
var
  Fizychne, Obraz: RawByteString;
  Seans: TDebugSession;
  Run: TDebugRun;
  I: SizeInt;
  Adresy: RawByteString;
  Ochikuvani: array[0..5] of SizeInt;
begin
  Fizychne := EncodeNumericDecimal('2', 12);
  Obraz := BuildD12LoopELF(Fizychne, 3);
  Perevir(Length(Obraz) > VuzolLoopHeaderBytes + VuzolLoopDecAt + 2,
    U('образ циклу закороткий'));
  { Інший образ, інша інструкція, інший опкод: $05 + imm32, а не $01 $D8. }
  Perevir(Ord(Obraz[VuzolLoopHeaderBytes + VuzolLoopAddAt + 1]) = $05,
    U('за зсувом add у циклі не $05'));
  Perevir(Ord(Obraz[VuzolLoopHeaderBytes + VuzolLoopDecAt + 1]) = $FF,
    U('за зсувом dec у циклі не $FF'));
  Perevir(Ord(Obraz[VuzolLoopHeaderBytes + VuzolLoopDecAt + 2]) = $C9,
    U('за зсувом dec у циклі не $C9'));

  Seans := TDebugSession.Create;
  try
    Seans.Breakpoints.Add(VuzolLoopHeaderBytes + VuzolLoopAddAt);
    Seans.Breakpoints.Add(VuzolLoopHeaderBytes + VuzolLoopDecAt);
    Perevir(Seans.RunImage(Obraz, Run),
      U('запуск на іншому образі не вдався: ') + Run.ErrorText);
    Perevir(Run.Traced, U('інший образ пішов не traced-шляхом'));
    { Три ітерації × дві інструкції = шість зупинів. }
    Perevir(Seans.StopCount = 6,
      U('інший образ дав не шість зупинів, а ') +
      RawByteString(IntToStr(Seans.StopCount)));
    Ochikuvani[0] := VuzolLoopHeaderBytes + VuzolLoopAddAt;
    Ochikuvani[1] := VuzolLoopHeaderBytes + VuzolLoopDecAt;
    Ochikuvani[2] := VuzolLoopHeaderBytes + VuzolLoopAddAt;
    Ochikuvani[3] := VuzolLoopHeaderBytes + VuzolLoopDecAt;
    Ochikuvani[4] := VuzolLoopHeaderBytes + VuzolLoopAddAt;
    Ochikuvani[5] := VuzolLoopHeaderBytes + VuzolLoopDecAt;
    Adresy := '';
    for I := 0 to 5 do
    begin
      Perevir(Seans.StopAt(I).ImageOffset = Ochikuvani[I],
        U('порядок зупинів на іншому образі інший'));
      if I > 0 then Adresy := Adresy + ',';
      Adresy := Adresy + RawByteString(IntToStr(Seans.StopAt(I).ImageOffset));
    end;
    { Лічильник циклу зменшується — це справді три різні ітерації. }
    Perevir(Seans.StopAt(1).Rcx = 3, U('перший dec не на rcx=3'));
    Perevir(Seans.StopAt(3).Rcx = 2, U('другий dec не на rcx=2'));
    Perevir(Seans.StopAt(5).Rcx = 1, U('третій dec не на rcx=1'));
    { Той самий результат, що й без налагоджувача: 3 × 2 = 6 у коді виходу. }
    Perevir(Run.ExitCode = 6, U('образ циклу вийшов не з 6'));
    Perevir(Run.Stdout = '', U('образ циклу несподівано щось надрукував'));
    WriteLn('DEBUGGER-OTHER-NODE-OK image=loop nodes=image:', Adresy,
      ' opcodes=05,ffc9 stops=6 exit=6 stdout=empty');
  finally
    Seans.Free;
  end;
end;

{ ------------------------------------------------------------------ }
{ НЕГАТИВНИЙ СВІДОК НА ІНШОМУ ОБРАЗІ                                 }
{ ------------------------------------------------------------------ }
procedure SvidokBezTochkyNaInshomuObrazi(const Obraz: RawByteString;
  OchikuvanyiVyhid: LongInt);
var
  Seans: TDebugSession;
  Run: TDebugRun;
  I: SizeInt;
  Kopiia: RawByteString;
begin
  Kopiia := Obraz;
  Seans := TDebugSession.Create;
  try
    Seans.KeepImage := True;
    Perevir(Seans.RunImage(Obraz, Run),
      U('запуск іншого образу без точки не вдався: ') + Run.ErrorText);
    Perevir(not Run.Traced, U('без точки обрано traced-шлях'));
    Perevir(Run.PtraceRequests = 0, U('без точки було звернення до ptrace'));
    Perevir(Run.StopCount = 0, U('без точки стався зупин'));
    Perevir(Run.ExitCode = OchikuvanyiVyhid,
      U('код виходу іншого образу змінився без точки'));
    Perevir(Run.Stdout = '', U('без точки в іншого образу з''явився stdout'));
    Perevir(Run.ImageHash = VidbytokObrazu(Obraz),
      U('відбиток іншого образу інший'));
    Perevir(VmistFailu(Run.ImagePath) = Kopiia,
      U('файл іншого образу змінився без точки'));
    for I := 0 to 4 do
    begin
      Perevir(Seans.RunImage(Obraz, Run), U('повтор іншого образу не вдався'));
      Perevir(Run.PtraceRequests = 0, U('на повторі іншого образу з''явився ptrace'));
    end;
  finally
    Seans.Free;
  end;
  Perevir(CompareMem(@Obraz[1], @Kopiia[1], Length(Obraz)),
    U('інший образ у пам''яті змінився без точки'));
  WriteLn('DEBUGGER-OTHER-NEGATIVE-OK image=loop ptrace_when_disabled=0 ',
    'stops_when_disabled=0 exit=', OchikuvanyiVyhid, ' bytes=same');
end;

{ ------------------------------------------------------------------ }
{ ОГЛЯД ЛЕКСИЧНОГО КАДРУ                                           }
{ ------------------------------------------------------------------ }
procedure SvidokKadru;
var
  Stek: TDebugTrace;
  Zovnishnii, Vnutrishnii, Trety: TDebugToken;
  Zovnishnia, Vnutrishnia: IEnvFrame;
  Ohliad: TOhliadKadriv;
  Tekst, Ochekuvane: RawByteString;
  Vidmovleno: Boolean;
  H: QWord;
  Bezkadrovyi: TDebugFrames;
  ZatZovnishnia, ZatVnutrishnia: IEnvFrame;
  Lanziuh, LanziuhKorotkyi: array of IEnvFrame;
begin
  Stek := TDebugTrace.Create;
  try
    Zovnishnia := NewEnvFrame(nil);
    Vnutrishnia := NewEnvFrame(Zovnishnia);
    Zovnishnii := Stek.Push(ExactKey('0'), 10, 2, 3);
    Vnutrishnii := Stek.Push(ExactKey('000'), 29, 3, 8);
    Zovnishnia.InstallLocal(ExactKey('0'), 10);
    Vnutrishnia.InstallLocal(ExactKey('000'), 29);

    Ohliad := OhliadLexychnykhKadriv(Stek.Snapshot, Vnutrishnia);
    Perevir(Length(Ohliad) = 2, U('огляд не побачив два кадри'));
    Perevir(Ohliad[0].Index = 0, U('найглибший кадр не перший'));
    Perevir(SameKey(Ohliad[0].Key, ExactKey('000')), U('кадр 0 не D3:000'));
    Perevir(Ohliad[0].Bound and (Ohliad[0].Value = 29),
      U('значення кадру 0 не 29'));
    Perevir(Ohliad[0].ParentIndex = 1, U('батько кадру 0 не 1'));
    Perevir(SameKey(Ohliad[1].Key, ExactKey('0')), U('кадр 1 не D1:0'));
    Perevir(Ohliad[1].Bound and (Ohliad[1].Value = 10),
      U('значення кадру 1 не 10 (батьківський кадр не питався)'));
    Perevir(Ohliad[1].ParentIndex = -1, U('у кадру 1 не має бути батька'));
    Perevir(Ohliad[1].ByteOffset = 10, U('байт батьківського кадру інший'));
    Perevir(Ohliad[1].Line = 2, U('рядок батьківського кадру інший'));

    Ochekuvane :=
      #$D0#$BA#$D0#$B0#$D0#$B4#$D1#$80 + ' 0: ' +
      #$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD + ' D3, ' +
      #$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE + ' 000, ' +
      #$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82 + ' 29, ' +
      #$D1#$80#$D1#$8F#$D0#$B4#$D0#$BE#$D0#$BA + ' 3, ' +
      #$D1#$81#$D1#$82#$D0#$BE#$D0#$B2#$D0#$BF#$D0#$B5#$D1#$86#$D1#$8C + ' 8, ' +
      #$D0#$B7#$D0#$BD#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F + ' 29, ' +
      #$D0#$B1#$D0#$B0#$D1#$82#$D1#$8C#$D0#$BA#$D0#$BE + ' 1' + #10 +
      #$D0#$BA#$D0#$B0#$D0#$B4#$D1#$80 + ' 1: ' +
      #$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD + ' D1, ' +
      #$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE + ' 0, ' +
      #$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82 + ' 10, ' +
      #$D1#$80#$D1#$8F#$D0#$B4#$D0#$BE#$D0#$BA + ' 2, ' +
      #$D1#$81#$D1#$82#$D0#$BE#$D0#$B2#$D0#$BF#$D0#$B5#$D1#$86#$D1#$8C + ' 3, ' +
      #$D0#$B7#$D0#$BD#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F + ' 10, ' +
      #$D0#$B1#$D0#$B0#$D1#$82#$D1#$8C#$D0#$BA#$D0#$BE + ' ' +
      #$D0#$BD#$D0#$B5#$D0#$BC#$D0#$B0#$D1#$94 + #10;
    Tekst := OhliadTekstom(Ohliad);
    Perevir(Tekst = Ochekuvane, U('подання огляду не збіглося з очікуваним'));
    Perevir(Pos('D3, ' + #$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE + ' 000',
      Tekst) > 0, U('D3:000 не можна змішувати з D1:0'));
    Perevir(Pos('byte=', Tekst) = 0, U('англомовних міток немає'));

    { Огляд — лише читання: повторний InstallLocal того самого ключа
      мусить усе ще відмовляти, тобто нових звU('язувань не з')явилося. }
    Vidmovleno := False;
    try Vnutrishnia.InstallLocal(ExactKey('000'), 7);
    except on E: EFrameError do Vidmovleno := True; end;
    Perevir(Vidmovleno, U('огляд створив нове зв''язування'));
    Perevir(Vnutrishnia.Resolve(ExactKey('000')) = 29,
      U('огляд змінив значення кадру'));
    Perevir(Vnutrishnia.Resolve(ExactKey('0')) = 10,
      U('ланцюг батьківського кадру зламався після огляду'));

    { Кадр без зв'язування — чесно каже «немає», а не вигадує нуль. }
    Trety := Stek.Push(ExactKey('01'), 40, 4, 2);
    Ohliad := OhliadLexychnykhKadriv(Stek.Snapshot, Vnutrishnia);
    Perevir(Length(Ohliad) = 3, U('огляд не побачив третій кадр'));
    Perevir(not Ohliad[0].Bound, U('незв''язаний кадр позначено зв''язаним'));
    Perevir(Ohliad[0].ParentIndex = 1, U('батько нового кадру не 1'));
    Tekst := OhliadTekstom(Ohliad);
    Perevir(Pos(#$D0#$B7#$D0#$BD#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BD#$D1#$8F +
      ' ' + #$D0#$BD#$D0#$B5#$D0#$BC#$D0#$B0#$D1#$94, Tekst) > 0,
      U('незв''язаний кадр не названо чесно'));
    Stek.Pop(Trety);

    { Без кадру взагалі і без ланцюга — порожній огляд, а не помилка. }
    SetLength(Bezkadrovyi, 0);
    Ohliad := OhliadLexychnykhKadriv(Bezkadrovyi, nil);
    Perevir(Length(Ohliad) = 0, U('порожній стек дав непорожній огляд'));
    Perevir(OhliadTekstom(Ohliad) = '', U('порожній огляд дав текст'));

    { Огляд із nil-кадром показує кадри, але не вигадує значень. }
    Ohliad := OhliadLexychnykhKadriv(Stek.Snapshot, nil);
    Perevir(Length(Ohliad) = 2, U('огляд без ланцюга втратив кадри'));
    Perevir(not Ohliad[0].Bound, U('без ланцюга кадр позначено зв''язаним'));
    Perevir(Ohliad[0].ParentIndex = 1, U('без ланцюга зламався батько'));

    { Відмови: некоректні координати не можна тихо показати. }
    SetLength(Bezkadrovyi, 1);
    Bezkadrovyi[0].Key.Width := 0;
    Bezkadrovyi[0].Key.Bits := 0;
    Bezkadrovyi[0].ByteOffset := 1;
    Bezkadrovyi[0].Line := 1;
    Bezkadrovyi[0].ByteColumn := 1;
    Vidmovleno := False;
    try Ohliad := OhliadLexychnykhKadriv(Bezkadrovyi, nil);
    except on E: ELexFrameError do Vidmovleno := True; end;
    Perevir(Vidmovleno, U('нульову ширину прийнято в огляді'));

    Bezkadrovyi[0].Key := ExactKey('01');
    Bezkadrovyi[0].Line := 0;
    Vidmovleno := False;
    try Ohliad := OhliadLexychnykhKadriv(Bezkadrovyi, nil);
    except on E: ELexFrameError do Vidmovleno := True; end;
    Perevir(Vidmovleno, U('нульовий рядок прийнято в огляді'));

    SetLength(Bezkadrovyi, MaxTraceDepth + 1);
    Vidmovleno := False;
    try Ohliad := OhliadLexychnykhKadriv(Bezkadrovyi, nil);
    except on E: ELexFrameError do Vidmovleno := True; end;
    Perevir(Vidmovleno, U('надмірну кількість кадрів прийнято в огляді'));

    { ЗАТІНЕННЯ ЗОВНІШНЬОГО СЛОВА (обмеження 3). Обидва кадри мають
      слово «0». Стара форма питає ОДИН найглибший кадр, тому в рядку
      зовнішнього кадру видно внутрішнє значення — це і є назване
      обмеження. Явний ланцюг питає кожен кадр про нього самого. }
    ZatZovnishnia := NewEnvFrame(nil);
    ZatVnutrishnia := NewEnvFrame(ZatZovnishnia);
    ZatZovnishnia.InstallLocal(ExactKey('0'), 10);
    ZatVnutrishnia.InstallLocal(ExactKey('0'), 29);
    ZatVnutrishnia.InstallLocal(ExactKey('000'), 29);
    Ohliad := OhliadLexychnykhKadriv(Stek.Snapshot, ZatVnutrishnia);
    Perevir(Ohliad[1].Bound and (Ohliad[1].Value = 29),
      U('затінення не відтворене: старий огляд не показав внутрішнє значення'));
    SetLength(Lanziuh, 2);
    Lanziuh[0] := ZatVnutrishnia;
    Lanziuh[1] := ZatZovnishnia;
    Ohliad := OhliadLexychnykhKadrivZLanziuhom(Stek.Snapshot, Lanziuh);
    Perevir(Ohliad[0].Bound and (Ohliad[0].Value = 29),
      U('ланцюг зіпсував внутрішній кадр'));
    Perevir(Ohliad[1].Bound and (Ohliad[1].Value = 10),
      U('ланцюг не показав власне значення зовнішнього кадру'));
    Perevir(Ohliad[1].ParentIndex = -1,
      U('у зовнішнього кадру з''явився батько'));
    Perevir(Length(Ohliad) = 2, U('ланцюг змінив кількість кадрів'));
    { Ланцюг неправильної довжини — відмова, а не тихе підставляння. }
    SetLength(LanziuhKorotkyi, 1);
    LanziuhKorotkyi[0] := ZatVnutrishnia;
    Vidmovleno := False;
    try Ohliad := OhliadLexychnykhKadrivZLanziuhom(Stek.Snapshot, LanziuhKorotkyi);
    except on E: ELexFrameError do Vidmovleno := True; end;
    Perevir(Vidmovleno, U('ланцюг неправильної довжини прийнято'));
    WriteLn('DEBUGGER-FRAME-CHAIN-OK shadowed=29 outer_own=10 chain_len=2');

    Stek.Pop(Vnutrishnii);
    Stek.Pop(Zovnishnii);
    Perevir(Stek.Depth = 0, U('стек не спорожнів'));
    H := VidbytokObrazu('abc');
    Perevir(H <> VidbytokObrazu('abd'), U('відбиток не розрізняє байти'));
    Perevir(H = VidbytokObrazu('abc'), U('відбиток нестабільний'));
  finally
    Stek.Free;
  end;
end;

var
  Obraz, Obraz2, ObrazDesiat, ObrazTsykl: RawByteString;
  TekstZupynky: RawByteString;
  Livo, Pravo: RawByteString;
  ChasTrace, ChasProstyi, ChasKontrolnyi: QWord;
  Vidnoshennia: Double;
  VuzolCykly: SizeInt;
  { Тіло циклу видобування цифр у wsm.elfd12adddesiatka:
      xor edx,edx (31 D2); div ecx (F7 F1); add dl,$30 (80 C2 30).
    Зсув не експортований генератором, тому він ЗНАХОДИТЬСЯ в образі й
    мусить бути єдиним — інакше свідок нічого не доводить. }
  VzirCykly: array[0..5] of Byte = ($31, $D2, $F7, $F1, $80, $C2);
begin
  Perevir(ParseAddProgram(U('(додати 2 3)'), Livo, Pravo), U('форму не прийнято'));
  Obraz := BuildD12AddDecimalELF(Livo, Pravo);
  Perevir(Length(Obraz) > D12DesiatkaHeaderBytes, U('образ закороткий'));

  SvidokTochkyZupynu(Obraz, TekstZupynky, ChasTrace);
  Obraz2 := Obraz;
  SvidokBezTochky(Obraz, Obraz2, ChasProstyi, ChasKontrolnyi);

  { Образ «(додати 6 4)» друкує 10, тож цикл видобування цифр
    виконується двічі — це і є повторне спрацьовування тієї самої
    точки. }
  Perevir(ParseAddProgram(U('(додати 6 4)'), Livo, Pravo),
    U('форму з двозначною сумою не прийнято'));
  ObrazDesiat := BuildD12AddDecimalELF(Livo, Pravo);
  VuzolCykly := ZnaytyVzir(ObrazDesiat, VzirCykly);
  SvidokPovtornohoZupynu(ObrazDesiat, VuzolCykly);
  SvidokKilkohTochok(ObrazDesiat,
    D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt, VuzolCykly + 2);

  { Зовсім інший фізичний образ: wsm.elfd12loop, ET_EXEC, інші
    інструкції та інші зсуви. }
  SvidokInshohoObrazu;
  ObrazTsykl := BuildD12LoopELF(EncodeNumericDecimal('2', 12), 3);
  SvidokBezTochkyNaInshomuObrazi(ObrazTsykl, 6);

  SvidokKadru;

  if ChasProstyi > 0 then
    Vidnoshennia := ChasProstyi / ChasKontrolnyi
  else
    Vidnoshennia := 0;
  { Шлях без точки зупину не мусить бути помітно повільнішим за
    контроль, який про налагоджувач не знає. Межі широкі: у CI час
    запуску процесу шумить, і вузький допуск дав би фальшивий провал. }
  Perevir((Vidnoshennia >= 0.5) and (Vidnoshennia <= 2.0),
    U('шлях без точки зупину помітно повільніший за контроль'));

  WriteLn(TekstZupynky);
  WriteLn(U('DEBAGER-АКТИВНИЙ-ГАРАЗД '),
    U('точка=спрацювала вузол=образ:'), D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt,
    U(' кадр=rax2/rbx3 значення-після-зупину=5 '),
    U('ptrace-без-точки=0 зупинів-без-точки=0 байти=ті-самі '),
    U('час-без-точки-мкс='), ChasProstyi,
    U(' час-контролю-мкс='), ChasKontrolnyi,
    U(' час-із-точкою-мкс='), ChasTrace,
    U(' відношення='), FormatFloat('0.00', Vidnoshennia),
    U(' закони-SENS=не-перевіряються'));
  { Другий, суто ASCII-рядок: його зручно шукати grep-ом у будь-якій
    локалі CI, не залежачи від кодування виводу. }
  WriteLn('DEBUGGER-ACTIVE-OK node=image:130 stops=1 frame=rax2,rbx3 ',
    'value_after_stop=5 ptrace_when_disabled=0 stops_when_disabled=0 ',
    'bytes=same ratio=', FormatFloat('0.00', Vidnoshennia));
end.
