{ G6.x — текстовий REPL на Free Vision над наявним D12-додавачем.

  Що тут справді відбувається: рядок «(додати 2 3)», введений у TInputLine,
  іде в наявний модуль wsm.elfd12adddesiatka. Той модуль будує ELF64, у
  машинному коді якого лежить справжня інструкція add (01 D8). Цей образ
  записується в тимчасовий файл, отримує право на виконання, запускається
  як процес Linux, і його stdout (десяткові ASCII-цифри) повертається в
  історію вікна. Отже число рахує машина, а не Pascal-функція друку.

  Це НЕ повний REPL SENS: немає користувацьких визначень, немає голів-
  механізмів, немає GC і немає середовища сеансу. Єдина прийнята форма —
  канонічна «(додати <доданок> <доданок>)» у межах D12. Усе інше — названа
  діагностика в історії, а не мовчазний пропуск.

  Два режими одного бінарника:
    1) TUI (типово): TApplication + TMenuBar + TStatusLine + TWindow +
       TListBox + TStringCollection + TInputLine. Потрібен термінал.
    2) --без-вікон: той самий обчислювач без Free Vision, лише stdout —
       механічний свідок для CI. «sensrepltui --без-вікон "(додати 2 3)"»
       друкує рівно «5».

  ЧОМУ КИРИЛИЦЯ БУЛА СПОТВОРЕНОЮ І ЯК ЦЕ ВИПРАВЛЕНО (виміряно, а не
  припущено). Клітинка екрана Free Vision — це ОДИН байт (tchattr: ch +
  attr у слові TVideoCell). Консольний драйвер FPC 3.2.2
  (packages/rtl-console/src/unix/video.pp) тримає буфер у CP437 і, якщо
  LANG містить «.UTF-8», ставить convert := cv_cp437_to_UTF8 і перекодовує
  КОЖЕН байт клітинки як знак CP437 (OutData(transform(chattr.ch))).
  Українська літера займає в буфері два байти UTF-8, тобто дві клітинки, і
  кожен з них перекодовувався окремо: «→» (E2 86 92) ставало «ΓåÆ».

  Тому тут зроблено дві речі, і обидві — на нашому боці, чужого коду не
  торкаємось:
    а) власний екранний набір SENS-1: один байт — рівно один знак
       (0x00..0x1F — знаки CP437 для стрілок і позначок вікна, 0x20..0x7F —
       ASCII, 0x80..0xFF — кирилиця і рамки; таблиці Sens1Nyzhni і
       Sens1Verkhni). Клітинка знову відповідає знаку, тож курсор, рамки й
       вирівнювання лишаються точними;
    б) власний UpdateScreen, поставлений через публічний SetVideoDriver:
       він малює буфер сам, перетворюючи байт клітинки в UTF-8 за нашою
       таблицею, і обходить cv_cp437_to_UTF8 з video.pp. video.pp не
       змінюється — це чужий код FPC.

  Питання на розуміння саме цього фрагмента:
  1) Чому Enter у TInputLine доходить до застосунку як cmDefault, а тут ще
     й як cmObchyslyty через статус-рядок, і чому це не подвійне обчислення?
  2) Чому образ пишеться в тимчасовий каталог, а не в теку репозиторію, і
     хто саме прибирає файли після запуску?
  3) Чому результат читається з файлу stdout, а не з пам'яті процесу?
  4) Чому в headless-режимі перевіряється наявність опкоду 01 D8 в образі,
     і що саме це відрізняє від echo-loop?
  5) Чому без термінала застосунок відмовляє кодом 3, а не намагається
     ініціалізувати екран?
  6) Чому власний UpdateScreen мусить сам копіювати VideoBuf в OldVideoBuf,
     і що зламалося б, якби він цього не робив?
  7) Чому провідний байт UTF-8 з клавіатури з'їдається, а на байті-
     продовженні віддається одна подія evKeyDown?
}
program sensrepltui;
{$mode objfpc}{$H+}{$codepage utf8}

uses
  SysUtils, Classes, BaseUnix, Unix,
  { rtl-console: публічні SetVideoDriver/GetVideoDriver і буфер екрана.
    Імена з цього модуля всюди вживаємо з префіксом video. — нижче є
    однойменні процедури у Free Vision Drivers. }
  video,
  Drivers, Objects, Views, Menus, Dialogs, App, FVConsts,
  wsm.elfd12adddesiatka;

const
  { У Turbo Vision була стала cmUser = 100 — межа користувацьких команд.
    У Free Vision, що входить до FPC 3.2.2, такої сталої немає (перевірено
    пошуком по packages/fv/src: там є cmValid..cmListItemSelected, далі
    нічого). Тому ту саму межу фіксуємо тут явно числом 100, а не беремо
    довільне число. }
  cmSensOsnova = 100;
  cmObchyslyty = cmSensOsnova + 1;
  cmOchystyty  = cmSensOsnova + 2;

  { Перемикач headless-режиму — точні UTF-8 байти. }
  PeremykachBezVikon: RawByteString = '--без-вікон';

  { Скільки байтів приймає поле вводу. Форма «(додати 2047 -2048)» —
    це 24 байти, тож 200 лишає великий запас. }
  VelychinaVvodu = 200;

  { Код відмови, коли немає термінала: TUI фізично неможливий. }
  KodBezTerminala = 3;
  { Код відмови для хибного виклику або неприйнятої форми. }
  KodVidmovy = 2;

  { ------------------------------------------------------------------
    Екранний набір SENS-1 — 128 знаків для байтів $80..$FF.

    0x80..0xA0 — українські малі а..я, 0xA1..0xAD — великі А..Й,
    0xAE 0xAF — «», 0xB0..0xDF і 0xFE — графіка CP437, якою Free Vision
    малює рамки, тіні, смуги прокручування й позначки списку (ці байти
    лишено на їхніх місцях, щоб код Views не довелося чіпати),
    0xE0..0xEF — великі К..Ш, 0xF0..0xF3 — Щ Ь Ю Я, 0xF4..0xF6 — — → ⛔.

    Кожен байт тут — окремий знак, тому клітинка буфера = один знак
    екрана, і жодна літера не «розповзається» на дві клітинки. }
  Sens1Verkhni: UnicodeString =
    'абвгґдеєжзиіїйкл' +
    'мнопрстуфхцчшщью' +
    'яАБВГҐДЕЄЖЗИІЇ«»' +
    '░▒▓│┤╡╢╖╕╣║╗╝╜╛┐' +
    '└┴┬├─┼╞╟╚╔╩╦╠═╬╧' +
    '╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀' +
    'ЙКЛМНОПРСТУФХЦЧШ' +
    'ЩЬЮЯ—→⛔≈°∙·√ⁿ²■ ';
  { 32 знаки CP437 для байтів $00..$1F — точно та таблиця, якою
    video.pp перекодовує ці байти (convert_lowascii_to_UTF8). }
  Sens1Nyzhni: UnicodeString =
    #8199#9786#9787#9829#9830#9827#9824#8226 +
    #9688#9675#9689#9794#9792#9834#9835#9788 +
    #9658#9668#8597#8252#0182#0167#9644#8616 +
    #8593#8595#8594#8592#8735#8596#9650#9660;

type
  { Результат одного обчислення: або десятковий рядок, або діагностика.
    Svidok — окремий рядок-свідок про фізичний образ, він іде в stderr
    і ніколи не змішується з числом у stdout. }
  TObchyslennia = record
    Uspikh: Boolean;
    Rezultat: RawByteString;
    Diahnostyka: RawByteString;
    Svidok: RawByteString;
  end;

  PSensReplApp = ^TSensReplApp;
  { Застосунок Free Vision. Init — конструктор базового TApplication
    (у FPC 3.2.2 це CONSTRUCTOR Init, не procedure), тому об'єкт
    створюється звичайним для Turbo Vision способом:
    New(PSensReplApp, Init). }
  TSensReplApp = object(TApplication)
    Okno: PWindow;
    Istoriia: PListBox;
    Vvid: PInputLine;
    constructor Init;
    destructor Done; virtual;
    procedure InitMenuBar; virtual;
    procedure InitStatusLine; virtual;
    procedure HandleEvent(var Event: TEvent); virtual;
    procedure ObchyslytyVvid;
    procedure OchytytyIstoriiu;
    procedure DodatyVIstoriiu(const Radok: RawByteString);
  end;

var
  { Лічильник тимчасових каталогів у межах одного процесу. }
  LichylnykKatalohiv: LongInt = 0;

  { Байт екрана → знак і байт екрана → готові UTF-8 байти. }
  Sens1ZnakU: array[0..255] of UnicodeString;
  Sens1Znak: array[0..255] of RawByteString;

  { Драйвер, що був до нас, і наш власний. }
  BazovyiVodii: TVideoDriver;
  NashVodii: TVideoDriver;

  { Незавершена UTF-8 послідовність із клавіатури. }
  Nedopysane: RawByteString = '';

{ Чи є справжній термінал: і stdin, і stdout мусять бути символьними
  пристроями, і процес мусить мати керуючий термінал (/dev/tty). Без
  цього Free Vision нема куди малювати. S_IFCHR = &0020000, S_IFMT =
  &0170000 — це POSIX-константи, а не вигадка SENS. }
function MaieTerminal: Boolean;
var
  St: Stat;
  Fd: cint;
begin
  Result := False;
  if fpFStat(0, St) <> 0 then Exit;
  if (St.st_mode and &0170000) <> &0020000 then Exit;
  if fpFStat(1, St) <> 0 then Exit;
  if (St.st_mode and &0170000) <> &0020000 then Exit;
  Fd := fpOpen('/dev/tty', O_RDWR);
  if Fd < 0 then Exit;
  fpClose(Fd);
  Result := True;
end;

{ Точні UTF-8 байти з тексту програми: жодна кодова сторінка компілятора
  не має впливати на діагностику. }
function UA(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

{ Діагностика йде точними байтами в позичений handle, без системного
  перетворення AnsiString у WriteLn. Той самий прийом, що в
  src/sensd12adddesiatka.lpr. }
procedure Say(const Text: RawByteString; ToError: Boolean);
var
  B: RawByteString;
  F: THandleStream;
begin
  B := Text + #10;
  if ToError then
    F := THandleStream.Create(TextRec(ErrOutput).Handle)
  else
    F := THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(B) > 0 then F.WriteBuffer(B[1], Length(B));
  finally
    F.Free;
  end;
end;

{ ------------------------------------------------------------------
  Екранний набір SENS-1.
  ------------------------------------------------------------------ }

{ Будує таблицю «байт → знак» один раз на старті. }
procedure PidhotuvatyTablytsiu;
var
  I: Integer;
begin
  if Length(Sens1Verkhni) <> 128 then begin
    { Цього не може бути, поки таблиця в коді; але мовчазна зсунута
      таблиця — це саме той дефект, який ми лікуємо, тому краще
      відмовити голосно. }
    Say(UA('SENS-REPL-TUI-ВІДМОВА: таблиця SENS-1 не має 128 знаків'),
      True);
    Halt(KodVidmovy);
  end;
  for I := 0 to 255 do begin
    { Байти $00..$1F — не службові коди, а знаки CP437: саме ними Free
      Vision малює стрілки смуги прокручування (► ◄ ↕ ▲ ▼) і позначки
      вікна. Показуємо їх тими самими знаками, що й video.pp у своїй
      таблиці convert_lowascii_to_UTF8. }
    if I < 32 then
      Sens1ZnakU[I] := Sens1Nyzhni[I + 1]
    else if I < 128 then
      Sens1ZnakU[I] := Chr(I)
    else
      Sens1ZnakU[I] := Sens1Verkhni[I - 128 + 1];
    Sens1Znak[I] := RawByteString(UTF8Encode(Sens1ZnakU[I]));
  end;
end;

{ Знак → байт SENS-1. 0 позначає «немає такого знака». }
function KodZnaka(const Z: UnicodeChar): Byte;
var
  I: Integer;
begin
  if Ord(Z) < 128 then begin
    Result := Byte(Ord(Z));
    Exit;
  end;
  Result := 0;
  for I := 128 to 255 do
    if Sens1ZnakU[I] = Z then begin
      Result := Byte(I);
      Exit;
    end;
end;

{ UTF-8 текст програми → байти екрана. Невідомий знак стає «?», а не
  зсуває решту рядка. }
function Utf8DoSens1(const S: RawByteString): RawByteString;
var
  U: UnicodeString;
  I: Integer;
  K: Byte;
begin
  U := UTF8Decode(S);
  Result := '';
  for I := 1 to Length(U) do begin
    K := KodZnaka(U[I]);
    if K = 0 then K := Ord('?');
    Result := Result + Chr(K);
  end;
end;

{ Байти екрана → UTF-8: те, що треба віддати в термінал або в розбір
  форми. }
function Sens1DoUtf8(const S: RawByteString): RawByteString;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    Result := Result + Sens1Znak[Ord(S[I])];
end;

{ ------------------------------------------------------------------
  Власний відеодрайвер: малює буфер Free Vision сам.

  Клітинка екрана — слово: молодший байт знак, старший байт атрибут
  (tchattr у video.pp, порядок байтів x86-64). Малюємо не «як є», а через
  таблицю SENS-1, тому в термінал ідуть справжні UTF-8 байти.
  ------------------------------------------------------------------ }

function Komirka(X, Y: Integer): PVideoCell;
begin
  Result := PVideoCell(video.VideoBuf);
  Inc(Result, LongInt(Y) * LongInt(video.ScreenWidth) + X);
end;

function StaraKomirka(X, Y: Integer): PVideoCell;
begin
  Result := PVideoCell(video.OldVideoBuf);
  Inc(Result, LongInt(Y) * LongInt(video.ScreenWidth) + X);
end;

{ Повний ANSI-припис кольору без покрокового порівняння з попереднім:
  так стан термінала завжди відомий і не залежить від історії. }
function AnsiKolir(A: Byte): RawByteString;
var
  Fg, Bg: Byte;
begin
  Fg := A and $0F;
  Bg := (A shr 4) and $07;
  Result := #27'[0';
  if Fg >= 8 then Result := Result + ';1';
  Result := Result + ';3' + RawByteString(IntToStr(Fg and 7)) +
    ';4' + RawByteString(IntToStr(Bg)) + 'm';
end;

procedure VyvestyEkran(const B: RawByteString);
begin
  if Length(B) > 0 then
    fpWrite(cint(TextRec(Output).Handle), B[1], Length(B));
end;

procedure NashUpdateScreen(Force: Boolean);
var
  X, Y: Integer;
  P, PO: PVideoCell;
  Atr, Ch: Byte;
  Potribna: Boolean;
  Ost: Integer;
  Vyhid: RawByteString;
begin
  if (video.VideoBuf = nil) or (video.OldVideoBuf = nil) or
     (video.ScreenWidth = 0) or (video.ScreenHeight = 0) then Exit;
  Vyhid := '';
  Ost := -1;
  for Y := 0 to Integer(video.ScreenHeight) - 1 do begin
    Potribna := True;
    for X := 0 to Integer(video.ScreenWidth) - 1 do begin
      P := Komirka(X, Y);
      if (not Force) then begin
        PO := StaraKomirka(X, Y);
        if P^ = PO^ then begin
          Potribna := True;
          Continue;
        end;
      end;
      { Абсолютне позиціонування на початку кожного зміненого відрізка:
        довжина відрізка в клітинках більше не залежить від того, скільки
        байтів займає знак у терміналі. }
      if Potribna then begin
        Vyhid := Vyhid + #27'[' + RawByteString(IntToStr(Y + 1)) + ';' +
          RawByteString(IntToStr(X + 1)) + 'H';
        Potribna := False;
      end;
      Atr := Byte(P^ shr 8);
      if Atr <> Ost then begin
        Vyhid := Vyhid + AnsiKolir(Atr);
        Ost := Atr;
      end;
      Ch := Byte(P^ and $FF);
      Vyhid := Vyhid + Sens1Znak[Ch];
    end;
  end;
  Vyhid := Vyhid + #27'[' + RawByteString(IntToStr(video.CursorY + 1)) +
    ';' + RawByteString(IntToStr(video.CursorX + 1)) + 'H';
  VyvestyEkran(Vyhid);
  { video.pp робив це сам у SysUpdateScreen; ми його замінили, тому
    зобов'язані тримати OldVideoBuf у згоді з екраном — інакше наступний
    прохід пропустить клітинки, яких на терміналі вже немає. }
  Move(video.VideoBuf^, video.OldVideoBuf^, video.VideoBufSize);
end;

procedure NashClearScreen;
begin
  BazovyiVodii.ClearScreen;
  { Термінал очищено, а старий буфер лишився заповненим: позначаємо всі
    клітинки зміненими, щоб наступний прохід намалював усе. }
  if (video.OldVideoBuf <> nil) and (video.VideoBufSize > 0) then
    FillChar(video.OldVideoBuf^, video.VideoBufSize, $FF);
end;

{ Ставимо наш драйвер поверх наявного: усе, крім малювання й очищення,
  робить драйвер FPC (ініціалізація термінала, курсор, режим, здатності).
  Це публічний SetVideoDriver із rtl-console — video.pp не змінюється. }
procedure VstanovytyNashEkran;
begin
  video.GetVideoDriver(BazovyiVodii);
  NashVodii := BazovyiVodii;
  NashVodii.UpdateScreen := @NashUpdateScreen;
  NashVodii.ClearScreen := @NashClearScreen;
  video.SetVideoDriver(NashVodii);
end;

{ ------------------------------------------------------------------
  Обчислювач: розбір форми → фізичний ELF → запуск → stdout.
  Це єдина точка, де народжується число; і TUI, і headless кличуть саме
  її, тому свідок у CI перевіряє той самий шлях, що й вікно.
  ------------------------------------------------------------------ }

{ Чи справді в образі лежить опкод add за відомим зсувом. Модуль уже
  перевіряє це сам, але свідок мусить бути в цьому файлі: саме він
  відрізняє обчислення від echo-loop. }
function ObrazMaieAdd(const Obraz: RawByteString; out Zsuv: LongInt): Boolean;
begin
  Zsuv := D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt;
  Result := False;
  if Length(Obraz) < Zsuv + 2 then Exit;
  Result := (Ord(Obraz[Zsuv + 1]) = D12DesiatkaAddOpcodeLo) and
            (Ord(Obraz[Zsuv + 2]) = D12DesiatkaAddOpcodeHi);
end;

{ Записує образ у тимчасовий каталог, дає право на виконання, запускає
  і читає stdout. Каталог прибирається у finally — навіть на відмові. }
function VykonatyObraz(const Obraz: RawByteString;
  out Rezultat, Diahnostyka: RawByteString): Boolean;
var
  Kataloh, ShliakhElf, ShliakhVyhid, Komanda, Vmist: RawByteString;
  F: TFileStream;
  Kod: LongInt;
  I: SizeInt;
  Desiatkove: Boolean;
begin
  Result := False;
  Rezultat := '';
  Diahnostyka := '';
  Inc(LichylnykKatalohiv);
  Kataloh := RawByteString(GetTempDir) + 'sensrepltui-' +
    RawByteString(IntToStr(fpGetPid)) + '-' +
    RawByteString(IntToStr(LichylnykKatalohiv));
  if fpMkdir(PChar(Kataloh), &700) <> 0 then begin
    Diahnostyka := UA('не вдалося створити тимчасовий каталог: ') + Kataloh;
    Exit;
  end;
  ShliakhElf := Kataloh + '/obraz.elf';
  ShliakhVyhid := Kataloh + '/stdout';
  try
    try
      F := TFileStream.Create(ShliakhElf, fmCreate);
      try
        if Length(Obraz) > 0 then F.WriteBuffer(Obraz[1], Length(Obraz));
      finally
        F.Free;
      end;
    except
      on E: Exception do begin
        Diahnostyka := UA('не вдалося записати образ: ') +
          RawByteString(E.Message);
        Exit;
      end;
    end;
    if fpChmod(PChar(ShliakhElf), &755) <> 0 then begin
      Diahnostyka := UA('не вдалося дати право на виконання: ') + ShliakhElf;
      Exit;
    end;
    { Один sh-виклик: сам образ пише свій stdout у файл, stderr образу
      відкидаємо — він не є результатом обчислення. }
    Komanda := '"' + ShliakhElf + '" > "' + ShliakhVyhid + '" 2>/dev/null';
    Kod := fpSystem(Komanda);
    if Kod <> 0 then begin
      Diahnostyka := UA('машинний образ завершився з кодом ') +
        RawByteString(IntToStr(Kod));
      Exit;
    end;
    if not FileExists(ShliakhVyhid) then begin
      Diahnostyka := UA('машинний образ не надрукував нічого');
      Exit;
    end;
    try
      F := TFileStream.Create(ShliakhVyhid, fmOpenRead);
      try
        SetLength(Vmist, F.Size);
        if F.Size > 0 then F.ReadBuffer(Vmist[1], F.Size);
      finally
        F.Free;
      end;
    except
      on E: Exception do begin
        Diahnostyka := UA('не вдалося прочитати stdout образу: ') +
          RawByteString(E.Message);
        Exit;
      end;
    end;
    while (Length(Vmist) > 0) and
          ((Vmist[Length(Vmist)] = #10) or (Vmist[Length(Vmist)] = #13)) do
      SetLength(Vmist, Length(Vmist) - 1);
    { Образ друкує лише десяткові цифри з можливим провідним мінусом.
      Будь-який інший вміст — це не результат додавання. }
    Desiatkove := Length(Vmist) > 0;
    for I := 1 to Length(Vmist) do
      if not (Vmist[I] in ['0'..'9', '-']) then Desiatkove := False;
    if not Desiatkove then begin
      Diahnostyka := UA('машинний образ надрукував не десяткове число: ') +
        Vmist;
      Exit;
    end;
    Rezultat := Vmist;
    Result := True;
  finally
    fpUnlink(PChar(ShliakhElf));
    fpUnlink(PChar(ShliakhVyhid));
    fpRmdir(PChar(Kataloh));
  end;
end;

{ Повний шлях одного запиту: розбір канонічної форми, побудова образу
  наявним модулем, перевірка опкоду, запуск, читання stdout.
  На вході — UTF-8 (так його розуміє ParseAddProgram). }
function ObchyslytyTekst(const Tekst: RawByteString): TObchyslennia;
var
  Livo, Pravo, Obraz: RawByteString;
  Zsuv: LongInt;
begin
  Result.Uspikh := False;
  Result.Rezultat := '';
  Result.Diahnostyka := '';
  Result.Svidok := '';
  try
    { Розбирає рівно «(додати N M)». Хибна форма — виняток із названою
      причиною, а не тихе «не зрозумів». }
    if not ParseAddProgram(Tekst, Livo, Pravo) then begin
      Result.Diahnostyka := UA('форму не прийнято');
      Exit;
    end;
    { Числова механіка — тільки в наявному модулі; тут жодного
      Pascal-додавання. }
    Obraz := BuildD12AddDecimalELF(Livo, Pravo);
  except
    on E: Exception do begin
      Result.Diahnostyka := RawByteString(E.Message);
      Exit;
    end;
  end;
  if not ObrazMaieAdd(Obraz, Zsuv) then begin
    Result.Diahnostyka := UA('в образі немає опкоду add');
    Exit;
  end;
  Result.Svidok := UA('опкод-add=01d8 зсув-у-файлі=') +
    RawByteString(IntToStr(Zsuv)) + UA(' байтів=') +
    RawByteString(IntToStr(Length(Obraz)));
  Result.Uspikh := VykonatyObraz(Obraz, Result.Rezultat, Result.Diahnostyka);
end;

{ ------------------------------------------------------------------
  Застосунок Free Vision.
  ------------------------------------------------------------------ }

constructor TSensReplApp.Init;
var
  R: TRect;
  Rozmir: TPoint;
  Smuh: PScrollBar;
begin
  { Базовий Init будує екран, меню, статус-рядок і робочий стіл. Він же
    викликає наші InitMenuBar/InitStatusLine, бо ті віртуальні. }
  inherited Init;
  Desktop^.GetExtent(R);
  Okno := New(PWindow, Init(R,
    RawByteString(Utf8DoSens1(UA('Середовище SENS — обчислювач D12'))),
    wnNoNumber));
  Desktop^.Insert(Okno);
  Rozmir := Okno^.Size;
  { Поле вводу — перший рядок під рамкою. }
  R.Assign(1, 1, Rozmir.X - 1, 2);
  Vvid := New(PInputLine, Init(R, VelychinaVvodu));
  Okno^.Insert(Vvid);
  { Смуга прокручування історії. }
  R.Assign(Rozmir.X - 1, 3, Rozmir.X, Rozmir.Y - 1);
  Smuh := New(PScrollBar, Init(R));
  Okno^.Insert(Smuh);
  { Історія — TListBox над TStringCollection, не абстрактний TListViewer. }
  R.Assign(1, 3, Rozmir.X - 1, Rozmir.Y - 1);
  Istoriia := New(PListBox, Init(R, 1, Smuh));
  Istoriia^.NewList(New(PStringCollection, Init(0, 10)));
  Okno^.Insert(Istoriia);
  DodatyVIstoriiu(Utf8DoSens1(UA('Введіть (додати 2 3) і натисніть Enter')));
  DodatyVIstoriiu(Utf8DoSens1(
    UA('Число рахує машинна інструкція add у ELF64')));
  Vvid^.Select;
end;

destructor TSensReplApp.Done;
begin
  { Вікна й колекції належать робочому столу: TProgram.Done прибирає
    Desktop разом із нащадками, а TListBox.Done — свою колекцію. }
  inherited Done;
end;

procedure TSensReplApp.InitMenuBar;
var
  R: TRect;
begin
  GetExtent(R);
  R.B.Y := R.A.Y + 1;
  { Дужки NewMenu/NewSubMenu/NewItem збалансовані: Файл → Вихід,
    Середовище → Очистити історію. Підписи йдуть через Utf8DoSens1:
    у буфері екрана живуть байти SENS-1, а не UTF-8. }
  MenuBar := New(PMenuBar, Init(R,
    NewMenu(
      NewSubMenu(RawByteString(Utf8DoSens1(UA('~Ф~айл'))), hcNoContext,
        NewMenu(
          NewItem(RawByteString(Utf8DoSens1(UA('~В~ихід'))), 'Alt-X', kbAltX,
            cmQuit, hcNoContext,
            Nil)
        ),
        NewSubMenu(RawByteString(Utf8DoSens1(UA('~С~ередовище'))), hcNoContext,
          NewMenu(
            NewItem(RawByteString(Utf8DoSens1(UA('~О~чистити історію'))), '',
              0, cmOchystyty, hcNoContext,
              Nil)
          ),
          Nil)
      )
    )
  ));
end;

procedure TSensReplApp.InitStatusLine;
var
  R: TRect;
begin
  GetExtent(R);
  R.A.Y := R.B.Y - 1;
  { Статус-рядок — вид ofPreProcess: він бачить натискання раніше за
    сфокусоване поле, тому Enter стає командою, а не текстом. }
  StatusLine := New(PStatusLine, Init(R,
    NewStatusDef(0, $FFFF,
      NewStatusKey(RawByteString(Utf8DoSens1(UA('~F10~ Меню'))), kbF10,
        cmMenu,
      NewStatusKey(RawByteString(Utf8DoSens1(UA('~Enter~ Обчислити'))),
        kbEnter, cmObchyslyty,
      NewStatusKey(RawByteString(Utf8DoSens1(UA('~Alt-X~ Вихід'))), kbAltX,
        cmQuit,
        Nil))),
      Nil)));
end;

procedure TSensReplApp.DodatyVIstoriiu(const Radok: RawByteString);
begin
  if (Istoriia = nil) or (Length(Radok) = 0) then Exit;
  Istoriia^.Insert(NewStr(Radok));
  if Istoriia^.Range > 0 then Istoriia^.FocusItem(Istoriia^.Range - 1);
end;

procedure TSensReplApp.ObchyslytyVvid;
var
  Tekst: ShortString;
  Pusto: ShortString;
  Vyd: RawByteString;
  Zapyt: RawByteString;
  Rez: TObchyslennia;
begin
  if Vvid = nil then Exit;
  Tekst := '';
  { GetData переносить байти поля у наш буфер; розмір буфера більший за
    DataSize поля, тому перенесення не виходить за межі. }
  Vvid^.GetData(Tekst);
  { У полі лежать байти SENS-1 — так вони й мають потрапити назад в
    історію. Для розбору форми їх треба повернути в UTF-8. }
  Vyd := RawByteString(Trim(Tekst));
  Pusto := '';
  Vvid^.SetData(Pusto);
  if Length(Vyd) = 0 then Exit;
  Zapyt := Sens1DoUtf8(Vyd);
  Rez := ObchyslytyTekst(Zapyt);
  if Rez.Uspikh then
    DodatyVIstoriiu(Vyd + Utf8DoSens1(UA(' → ')) + Rez.Rezultat)
  else
    DodatyVIstoriiu(Vyd + Utf8DoSens1(UA(' ⛔ ')) +
      Utf8DoSens1(Rez.Diahnostyka));
end;

procedure TSensReplApp.OchytytyIstoriiu;
begin
  if Istoriia = nil then Exit;
  { NewList сам прибирає попередню колекцію. }
  Istoriia^.NewList(New(PStringCollection, Init(0, 10)));
  DodatyVIstoriiu(Utf8DoSens1(UA('Історію очищено')));
end;

{ Розбирає накопичені байти як одну UTF-8 послідовність. True — Kod
  заповнено. }
function RozibratyUtf8(const B: RawByteString; out Kod: LongWord): Boolean;
var
  I, N: Integer;
  C: Byte;
begin
  Result := False;
  Kod := 0;
  if Length(B) = 0 then Exit;
  C := Ord(B[1]);
  if C < $80 then begin
    Kod := C;
    Result := True;
    Exit;
  end;
  if (C and $E0) = $C0 then N := 2
  else if (C and $F0) = $E0 then N := 3
  else if (C and $F8) = $F0 then N := 4
  else Exit;
  if Length(B) < N then Exit;
  case N of
    2: Kod := C and $1F;
    3: Kod := C and $0F;
    else Kod := C and $07;
  end;
  for I := 2 to N do begin
    C := Ord(B[I]);
    if (C and $C0) <> $80 then Exit;
    Kod := (Kod shl 6) or (C and $3F);
  end;
  Result := True;
end;

procedure TSensReplApp.HandleEvent(var Event: TEvent);
var
  B: Byte;
  Kod: LongWord;
  K: Byte;
begin
  { Клавіатура віддає UTF-8 побайтово: кирилиця приходить двома подіями
    evKeyDown. Провідний байт з'їдаємо, на продовженні віддаємо одну
    подію з байтом SENS-1 — інакше одна літера зайняла б у полі вводу дві
    клітинки і виглядала б двома знаками. }
  if Event.What = evKeyDown then begin
    B := Ord(Event.CharCode);
    if B >= $80 then begin
      if (B and $C0) = $C0 then begin
        Nedopysane := Chr(B);
        ClearEvent(Event);
        Exit;
      end;
      if (B and $C0) = $80 then begin
        if Length(Nedopysane) = 0 then begin
          ClearEvent(Event);
          Exit;
        end;
        Nedopysane := Nedopysane + Chr(B);
        if RozibratyUtf8(Nedopysane, Kod) then begin
          Nedopysane := '';
          if Kod <= $FFFF then
            K := KodZnaka(UnicodeChar(Kod))
          else
            K := 0;
          if K = 0 then
            Event.CharCode := '?'
          else
            Event.CharCode := Chr(K);
        end else begin
          ClearEvent(Event);
          Exit;
        end;
      end;
    end;
  end;
  { Enter у полі вводу TInputLine перетворює на широкомовний cmDefault.
    Ловимо його, щоб обчислення працювало навіть тоді, коли статус-рядок
    з якоїсь причини не перехопив клавішу. }
  if (Event.What = evBroadcast) and (Event.Command = cmDefault) then begin
    ObchyslytyVvid;
    ClearEvent(Event);
    Exit;
  end;
  if Event.What = evCommand then begin
    if Event.Command = cmObchyslyty then begin
      ObchyslytyVvid;
      ClearEvent(Event);
      Exit;
    end;
    if Event.Command = cmOchystyty then begin
      OchytytyIstoriiu;
      ClearEvent(Event);
      Exit;
    end;
  end;
  inherited HandleEvent(Event);
end;

{ ------------------------------------------------------------------
  Режими запуску.
  ------------------------------------------------------------------ }

{ Headless: той самий обчислювач без Free Vision. Число — у stdout,
  свідок і діагностика — у stderr. Тут усе у UTF-8: екранного набору
  немає, бо немає екрана. }
procedure RezhymBezVikon;
var
  Rez: TObchyslennia;
begin
  if ParamCount <> 2 then begin
    Say(UA('виклик: sensrepltui --без-вікон "(додати 2 3)"'), True);
    ExitCode := KodVidmovy;
    Exit;
  end;
  Rez := ObchyslytyTekst(RawByteString(ParamStr(2)));
  if Rez.Uspikh then begin
    Say(Rez.Rezultat, False);
    Say(UA('SENS-REPL-БЕЗ-ВІКОН-СВІДОК ') + Rez.Svidok, True);
  end else begin
    Say(UA('SENS-REPL-БЕЗ-ВІКОН-ВІДМОВА: ') + Rez.Diahnostyka, True);
    ExitCode := KodVidmovy;
  end;
end;

var
  Zastosunok: PSensReplApp;
begin
  ExitCode := 0;
  { Поверхня людська — UTF-8. Локаль процесу (у CI часто C/POSIX) не має
    перекодовувати кирилицю на шляху до PString-історії. }
  SetMultiByteConversionCodePage(CP_UTF8);
  PidhotuvatyTablytsiu;
  if (ParamCount >= 1) and
     (RawByteString(ParamStr(1)) = PeremykachBezVikon) then begin
    RezhymBezVikon;
    Exit;
  end;
  { Без термінала Free Vision не має куди малювати: відмовляємо названо,
    а не мовчки падаємо в InitVideo. }
  if not MaieTerminal then begin
    Say(UA('SENS-REPL-TUI-ВІДМОВА: потрібен термінал; ' +
      'для CI є --без-вікон'), True);
    ExitCode := KodBezTerminala;
    Exit;
  end;
  { Наш екран ставимо до InitVideo: базовий Init застосунку підніме
    драйвер, і це вже буде наш UpdateScreen. }
  VstanovytyNashEkran;
  Zastosunok := New(PSensReplApp, Init);
  Zastosunok^.Run;
  Dispose(Zastosunok, Done);
end.
