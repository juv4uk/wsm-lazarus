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

  Обмеження поверхні (перевірено, а не припущено): консольний драйвер
  Free Vision у FPC 3.2.2 тримає екранний буфер у CP437 і, якщо LANG
  містить «.UTF-8», перекодовує кожен байт буфера в UTF-8
  (packages/rtl-console/src/unix/video.pp: decide_codepages →
  cv_cp437_to_UTF8). Тому українські літери у вікні можуть виглядати
  спотворено, хоч обчислення від цього не залежить: ASCII-частини рядка
  історії — дужки, цифри, пробіли — лишаються читабельними, а
  headless-режим друкує точні байти.

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
}
program sensrepltui;
{$mode objfpc}{$H+}{$codepage utf8}

uses
  SysUtils, Classes, BaseUnix, Unix,
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
  наявним модулем, перевірка опкоду, запуск, читання stdout. }
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
  Okno := New(PWindow, Init(R, 'Середовище SENS — обчислювач D12',
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
  DodatyVIstoriiu(UA('Введіть (додати 2 3) і натисніть Enter'));
  DodatyVIstoriiu(UA('Число рахує машинна інструкція add у ELF64'));
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
    Середовище → Очистити історію. }
  MenuBar := New(PMenuBar, Init(R,
    NewMenu(
      NewSubMenu('~Ф~айл', hcNoContext,
        NewMenu(
          NewItem('~В~ихід', 'Alt-X', kbAltX, cmQuit, hcNoContext,
            Nil)
        ),
        NewSubMenu('~С~ередовище', hcNoContext,
          NewMenu(
            NewItem('~О~чистити історію', '', 0, cmOchystyty, hcNoContext,
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
      NewStatusKey('~F10~ Меню', kbF10, cmMenu,
      NewStatusKey('~Enter~ Обчислити', kbEnter, cmObchyslyty,
      NewStatusKey('~Alt-X~ Вихід', kbAltX, cmQuit,
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
  Zapyt: RawByteString;
  Rez: TObchyslennia;
begin
  if Vvid = nil then Exit;
  Tekst := '';
  { GetData переносить байти поля у наш буфер; розмір буфера більший за
    DataSize поля, тому перенесення не виходить за межі. }
  Vvid^.GetData(Tekst);
  Zapyt := RawByteString(Trim(Tekst));
  Pusto := '';
  Vvid^.SetData(Pusto);
  if Length(Zapyt) = 0 then Exit;
  Rez := ObchyslytyTekst(Zapyt);
  if Rez.Uspikh then
    DodatyVIstoriiu(Zapyt + UA(' → ') + Rez.Rezultat)
  else
    DodatyVIstoriiu(Zapyt + UA(' ⛔ ') + Rez.Diahnostyka);
end;

procedure TSensReplApp.OchytytyIstoriiu;
begin
  if Istoriia = nil then Exit;
  { NewList сам прибирає попередню колекцію. }
  Istoriia^.NewList(New(PStringCollection, Init(0, 10)));
  DodatyVIstoriiu(UA('Історію очищено'));
end;

procedure TSensReplApp.HandleEvent(var Event: TEvent);
begin
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
  свідок і діагностика — у stderr. }
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
    перекодовувати кирилицю в CP437 на шляху до PString-історії. }
  SetMultiByteConversionCodePage(CP_UTF8);
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
  Zastosunok := New(PSensReplApp, Init);
  Zastosunok^.Run;
  Dispose(Zastosunok, Done);
end.
