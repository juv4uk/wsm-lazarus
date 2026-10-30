{ Задача #866 — незалежний FPC-свідок того, що замикання ВИКОНУЮТЬСЯ,
  тобто що захоплене оточення справді бере участь у виклику, а не що
  файли з назвами evlis/appq існують.

  ЩО САМЕ ПЕРЕВІРЯЄТЬСЯ (лише те, що є в src/wsm.nativeeval.pas):
    1. D10:0100111100 «створити-лямбда-замикання» створює замикання,
       яке ЗАХОПЛЮЄ оточення створення (FClosureEnvs[..], рядок 362).
    2. Виклик замикання йде ланцюгом
         голова-атом без доменного ключа -> Assoc -> ncClosure ->
         Appq(Evlis(N,1,Depth+1,Env),N) ->
         Pairlis(FCells[A].First,B,FClosureEnvs[FCells[A].Rest],N) ->
         Eval(FNodes[FCells[A].Rest], Depth+1, ...)
       (рядки 630-634; те саме для обчисленої голови — 621-623).
       Свідок не читає ці рядки, а спостерігає їхній НАСЛІДОК:
       захоплене значення перемагає аргумент виклику.
    3. Одне й те саме замикання, викликане ДВІЧІ з різними аргументами,
       повертає те саме захоплене значення — тобто воно зберігається
       між викликами, а не перечитується з аргументів.
    4. D5:00100 «мітка» (d5.lisp:13) досяжна в драбині: вона звʼязує імʼя
       з замиканням і замикання за цим імʼям викликається.

  СПІЛЬНА КОМІРКА, А НЕ ЗНІМОК (друге питання, додане після #866):
    5. Замикання тримає ПОСИЛАННЯ на комірку звʼязування, а не копію
       значення: створене ДО присвоєння, воно після виклику віддає НОВЕ
       значення (встановити-імʼя, D5:00111). Знімок дав би старе —
       саме тому негативний свідок тут — це ЗНІМОК, виражений у самій
       мові (копіювання значення в нове звʼязування), і він мусить
       дати ІНШИЙ результат. Третій, диференційний бік того самого
       питання ставить scripts/test-zamykannia-svidok.sh: ту саму форму
       обчислює ПОПЕРЕДНЯ реалізація (знімок) і поточна (комірка).
    Увага до поверхні: встановити-ім'я пишеться з ASCII апострофом,
    як у pinned d5.lisp:16. З U+02BC (як у коментарях до коду) поверхня
    не резолвиться — "unknown native call head", і жодне присвоєння
    через неї зробити неможливо.

  НЕГАТИВНИЙ СВІДОК (обовʼязковий):
    Ті самі форми з тілом (y) y — звичайна функція без захоплення —
    мусять дати ІНШИЙ результат: аргумент, а не захоплене значення.
    Додатково перевіряється, що позитивна й негативна форми
    відрізняються РІВНО ОДНИМ байтом тіла (x -> y): інакше «негативний
    свідок» ставив би інше питання, і його результат нічого не доводив.

  ОЧІКУВАННЯ СФОРМУЛЬОВАНІ ЗА ЗАКОНАМИ, А НЕ ЗА СПОСТЕРЕЖЕНИМ ВИВОДОМ.
  Якщо механізм не виконується — рядок стає «ПОМИЛКА-ТЕСТУ» з фактичним
  виводом, і це результат прогону, а не дефект свідка.

  Це СУБʼЄКТ перевірки, а не оракул: програма викликає сам механізм.
  Незалежність забезпечує scripts/test-zamykannia-svidok.sh — воно
  звіряє ці самі форми з окремою моделлю іншою мовою
  (scripts/zamykannia-orakul-model.py) і окремо фіксує, чи доступний
  pinned SENS REPL.

  Машинний рядок для .sh:
    СВІДОК<TAB>назва<TAB>OK|ERR<TAB>форма<TAB>текст
  Людські рядки: «ok …» / «ПОМИЛКА-ТЕСТУ: …». }
program test_zamykannia_svidok;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.nativeeval, wsm.source;

type
  TVypadok=record
    Nazva:RawByteString;
    Forma:RawByteString;
    { Ochikuvane — те, що мусить дати закон. Для Vidmova=True це
      підрядок причини відмови, а не повний текст. }
    Ochikuvane:RawByteString;
    Vidmova:Boolean;
  end;

const
  { Українські рядки мусять дійти до виводу байт-у-байт: RawByteString
    не перекодовується у кодування консолі (той самий прийом, що в
    scripts/test-core1-closure.pas і src/sens_oracle.lpr). }
  PrefiksZboiu:RawByteString='ПОМИЛКА-ТЕСТУ: ';
  PrefiksOchik:RawByteString=' — очікували ';
  PrefiksFakt:RawByteString='; фактично: ';
  PrefiksPidsumku:RawByteString='ЗАМИКАННЯ-СВІДОК перевірок=';
  PrefiksPidsumku2:RawByteString=' збоїв=';
  PrefiksVnutrishnoi:RawByteString='ЗАМИКАННЯ-СВІДОК-ПОМИЛКА: ';
  PrefiksSvidok:RawByteString='СВІДОК'#9;
  SlovoZakhoplennia:RawByteString='захоплення=';
  SlovoBezZakhoplennia:RawByteString=' без-захоплення=';
  SlovoPozytsiia:RawByteString=' позиція ';
  SlovoFormyNeOdynBait:RawByteString=
    'форми не відрізняються рівно одним байтом тіла ';
  SlovoOdynBaitTila:RawByteString='рівно один байт тіла ';
  SlovoRizniRezultaty:RawByteString='різні результати з захопленням і без';
  SlovoBezOchikuvannia:RawByteString=' без';
  SlovoKomirka:RawByteString=' комірка=';
  SlovoZnimok:RawByteString=' знімок=';
  SlovoBezPrysvoiennia:RawByteString=' без-присвоєння=';
  SlovoRizniRezultatyKomirky:RawByteString=
    'різні результати зі спільною коміркою і зі знімком';
  TAb:RawByteString=#9;
  TekstBezDomeniv:RawByteString='немає pinned доменів external/sens';
  TekstBezArhumentiv:RawByteString='запуск без аргументів із кореня репозиторію';

  { Форми. Дослівно. Адреси — з pinned доменних таблиць:
    D10:0100111100 — створити-лямбда-замикання (d10.lisp:327);
    D5:00100      — мітка (d5.lisp:13);
    D3:001        — як-є (вживається всередині appq, не в цих формах). }

  { Позитив 1: внутрішнє замикання створене в оточенні, де x=так,
    і викликане з аргументом ні. Захоплення -> 1 (так), не 0. }
  F1:RawByteString=
    '(((створити-лямбда-замикання (x) '+
    '(створити-лямбда-замикання (y) x)) так) ні)';
  { Негатив 1: те саме, але тіло — (y) y, без захоплення -> 0 (ні). }
  F2:RawByteString=
    '(((створити-лямбда-замикання (x) '+
    '(створити-лямбда-замикання (y) y)) так) ні)';
  { Позитив 2: ОДНЕ замикання викликане двічі з різними аргументами
    (так, ні) через параметр f. Захоплене x=так зберігається між
    викликами -> (1 . 1). }
  F3:RawByteString=
    '((створити-лямбда-замикання (x) '+
    '((створити-лямбда-замикання (f) (сполучити (f так) (f ні))) '+
    '(створити-лямбда-замикання (y) x))) так)';
  { Негатив 2: та сама подвійна викликана функція без захоплення ->
    (1 . 0): результат іде за аргументами. }
  F4:RawByteString=
    '((створити-лямбда-замикання (x) '+
    '((створити-лямбда-замикання (f) (сполучити (f так) (f ні))) '+
    '(створити-лямбда-замикання (y) y))) так)';
  { Позитив 3: те саме, але зовнішнє оточення створене з ні. Захоплене
    значення мусить піти за оточенням створення -> (0 . 0), а не (1 . 1).
    Це відрізняє «справді захоплено» від «зашита константа». }
  F5:RawByteString=
    '((створити-лямбда-замикання (x) '+
    '((створити-лямбда-замикання (f) (сполучити (f так) (f ні))) '+
    '(створити-лямбда-замикання (y) x))) ні)';
  { Позитив 4 (D5:00100): мітка звʼязує імʼя k із замиканням, створеним
    в оточенні x=так, і за цим імʼям замикання викликається з ні.
    решта бере друге поле пари, щоб результат був значенням, а не
    контейнером: -> 1. }
  F6:RawByteString=
    '(решта (сполучити ((створити-лямбда-замикання (x) '+
    '(мітка k (створити-лямбда-замикання (y) x))) так) (k ні)))';
  { Негатив 4: та сама мітка без захоплення -> 0. }
  F7:RawByteString=
    '(решта (сполучити ((створити-лямбда-замикання (x) '+
    '(мітка k (створити-лямбда-замикання (y) y))) так) (k ні)))';
  { Границя appq->pairlis: кількість аргументів перевіряється саме там,
    тобто аргументи справді пройшли Evlis/Appq. }
  F8:RawByteString='((створити-лямбда-замикання (x) x))';
  F9:RawByteString='((створити-лямбда-замикання (x) x) так ні)';

  { СПІЛЬНА КОМІРКА (задача після #866). Питання не "чи захоплено",
    а "чи захоплено САМУ комірку звʼязування, а не її значення":
    замикання, створене ДО присвоєння, мусить побачити НОВЕ значення.
    встановити-ім'я (D5:00111, d5.lisp:16) пишеться з ASCII апострофом,
    як у pinned таблиці: з U+02BC поверхня не резолвиться взагалі
    ("unknown native call head"), і це окремо зафіксовано нижче. }

  { Позитив 5: замикання g створене, коли x=так, потім x присвоєно ні,
    і ЛИШЕ ПОТІМ g викликається. Спільна комірка -> 0 (ні).
    Знімок дав би 1 (старе так) — саме це й розрізняє два устрої. }
  F10:RawByteString=
    '((створити-лямбда-замикання (x) (решта (сполучити '+
    '(сполучити (мітка g (створити-лямбда-замикання (y) x)) '+
    '(встановити-ім''я x ні)) (g так)))) так)';
  { Негатив 5 (ЗНІМОК, виражений у самій мові): те саме, але значення x
    спершу копіюється в НОВЕ звʼязування викликом ((...) x). Присвоєння
    зовнішнього x не може дістатися до нової комірки -> 1 (старе так).
    Різниця з F10 рівно в тому, чи комірка спільна. }
  F11:RawByteString=
    '((створити-лямбда-замикання (x) (решта (сполучити '+
    '(сполучити (мітка g ((створити-лямбда-замикання (x) '+
    '(створити-лямбда-замикання (y) x)) x)) '+
    '(встановити-ім''я x ні)) (g так)))) так)';
  { Контроль 5: та сама форма БЕЗ присвоєння -> 1 (захоплене так).
    Доводить, що F10 дає 0 саме через присвоєння, а не через іншу форму. }
  F12:RawByteString=
    '((створити-лямбда-замикання (x) (решта (сполучити '+
    '(сполучити (мітка g (створити-лямбда-замикання (y) x)) ні) '+
    '(g так)))) так)';
  { Незвʼязане імʼя: присвоєння мусить, як і досі, створити звʼязування,
    а не відмовити. Нових правил для цього випадку не вводимо -> 1. }
  F13:RawByteString=
    '(решта (сполучити (встановити-ім''я q так) q))';
  { Позитив 6: присвоєння робить ІНШЕ замикання, а бачить його g.
    Це і є спільна комірка: комірку тримають двоє, а не копію кожен
    свою. Спільна комірка -> 0 (ні). }
  F14:RawByteString=
    '((створити-лямбда-замикання (x) (решта (сполучити '+
    '(сполучити (мітка g (створити-лямбда-замикання (y) x)) '+
    '((створити-лямбда-замикання (z) (встановити-ім''я x ні)) так)) '+
    '(g так)))) так)';

var
  Vypadky:array of TVypadok;
  Peremohy,Zboi:SizeInt;

procedure Dodaty(const Nazva,Forma,Ochikuvane:RawByteString; Vidmova:Boolean);
var I:SizeInt;
begin
  I:=Length(Vypadky);
  SetLength(Vypadky,I+1);
  Vypadky[I].Nazva:=Nazva;
  Vypadky[I].Forma:=Forma;
  Vypadky[I].Ochikuvane:=Ochikuvane;
  Vypadky[I].Vidmova:=Vidmova;
end;

{ Один виклик механізму. Uspih=False означає відмову, і Tekst тоді —
  причина; інакше Tekst — відображення результату. }
procedure Vyikonaty(V:TNativeEvaluator; const Forma:RawByteString;
  out Uspih:Boolean; out Tekst:RawByteString);
begin
  Uspih:=True;
  Tekst:='';
  try
    Tekst:=V.EvaluateSource(Forma);
  except
    on E:Exception do begin
      Uspih:=False;
      Tekst:=RawByteString(E.Message);
    end;
  end;
end;

{ Захоплення проти не-захоплення: дві форми мусять відрізнятися РІВНО
  одним байтом тіла. Інакше негативний свідок ставив би інше питання. }
function RiznytsiaOdynBait(const A,B:RawByteString; out Poz:SizeInt;
  out BaitA,BaitB:AnsiChar):Boolean;
var I:SizeInt; N:SizeInt;
begin
  Result:=False; Poz:=-1; BaitA:=#0; BaitB:=#0;
  if Length(A)<>Length(B) then Exit;
  N:=0;
  for I:=1 to Length(A) do
    if A[I]<>B[I] then begin
      Inc(N);
      if N>1 then Exit;
      Poz:=I; BaitA:=A[I]; BaitB:=B[I];
    end;
  Result:=N=1;
end;

procedure PerevirytyRiznytsiu(const Nazva,A,B:RawByteString;
  const OchikA,OchikB:AnsiChar);
var Poz:SizeInt; BA,BB:AnsiChar; Fakt:RawByteString;
begin
  Inc(Peremohy);
  if RiznytsiaOdynBait(A,B,Poz,BA,BB) and (BA=OchikA) and (BB=OchikB) then
    WriteLn('ok ',Nazva,' -> ',SlovoPozytsiia,Poz,' ',OchikA,'->',OchikB)
  else begin
    Dec(Peremohy); Inc(Zboi);
    Fakt:=SlovoFormyNeOdynBait+OchikA+'->'+OchikB;
    WriteLn(PrefiksZboiu,Nazva,PrefiksOchik,
      SlovoOdynBaitTila,OchikA,'->',OchikB,PrefiksFakt,Fakt);
  end;
end;

var
  V:TNativeEvaluator;
  I:SizeInt;
  Uspih:Boolean;
  Tekst,Fakt,Riadok:RawByteString;
  Rez1,Rez2,Rez3,Rez4:RawByteString;
  Usp1,Usp2,Usp3,Usp4:Boolean;
begin
  if ParamCount<>0 then begin
    WriteLn(StdErr,PrefiksVnutrishnoi+TekstBezArhumentiv);
    Halt(2);
  end;
  if not DirectoryExists('external/sens') then begin
    WriteLn(StdErr,PrefiksVnutrishnoi+TekstBezDomeniv);
    Halt(2);
  end;

  SetLength(Vypadky,0);
  Dodaty('zamykannia-zakhopliuie-otochemnia',F1,'1',False);
  Dodaty('negatyvnyi-bez-zakhoplennia',F2,'0',False);
  Dodaty('zakhoplene-znachennia-dvichi-rizni-arhumenty',F3,'(1 . 1)',False);
  Dodaty('negatyvnyi-dvichi-bez-zakhoplennia',F4,'(1 . 0)',False);
  Dodaty('zakhoplene-znachennia-ide-za-otochemniam',F5,'(0 . 0)',False);
  Dodaty('mitka-D5-00100-vyklyk-za-imenem',F6,'1',False);
  Dodaty('negatyvnyi-mitka-bez-zakhoplennia',F7,'0',False);
  Dodaty('appq-pairlis-zamalo-arhumentiv',F8,'ARITY: TOO-FEW-ARGUMENTS',True);
  Dodaty('appq-pairlis-zabahato-arhumentiv',F9,'ARITY: TOO-MANY-ARGUMENTS',True);
  { Спільна комірка: те саме питання, але про комірку, не про значення. }
  Dodaty('spilna-komirka-bachyt-nove-znachennia',F10,'0',False);
  Dodaty('negatyvnyi-kopiia-ne-bachyt-novoho-znachennia',F11,'1',False);
  Dodaty('kontrol-bez-prysvoiennia-bachyt-zakhoplene',F12,'1',False);
  Dodaty('vstanovyty-imia-nove-imia-stvoriuie-zv-iazuvannia',F13,'1',False);
  Dodaty('spilna-komirka-bachyt-prysvoiennia-z-inshoho-zamykannia',F14,'0',False);

  Peremohy:=0; Zboi:=0;
  V:=TNativeEvaluator.Create('external/sens');
  try
    for I:=0 to High(Vypadky) do begin
      Vyikonaty(V,Vypadky[I].Forma,Uspih,Tekst);
      { Машинний рядок для .sh: незалежна модель звіряє те саме. }
      if Uspih then Riadok:=PrefiksSvidok+Vypadky[I].Nazva+TAb+'OK'+TAb+
        Vypadky[I].Forma+TAb+Tekst
      else
        Riadok:=PrefiksSvidok+Vypadky[I].Nazva+TAb+'ERR'+TAb+
          Vypadky[I].Forma+TAb+Tekst;
      WriteLn(Riadok);
      if Vypadky[I].Vidmova then
        Rez1:=BoolToStr((not Uspih) and (Pos(Vypadky[I].Ochikuvane,Tekst)>0),True)
      else
        Rez1:=BoolToStr(Uspih and (Tekst=Vypadky[I].Ochikuvane),True);
      if Rez1='True' then begin
        Inc(Peremohy);
        WriteLn('ok ',Vypadky[I].Nazva,' -> ',Tekst);
      end
      else begin
        Inc(Zboi);
        Fakt:=Tekst;
        WriteLn(PrefiksZboiu,Vypadky[I].Nazva,PrefiksOchik,
          Vypadky[I].Ochikuvane,PrefiksFakt,Fakt);
      end;
    end;

    { --- Негативний свідок: захоплення відрізняється від не-захоплення --- }
    Vyikonaty(V,F1,Usp1,Rez1);
    Vyikonaty(V,F2,Usp2,Rez2);
    Inc(Peremohy);
    if Usp1 and Usp2 and (Rez1<>Rez2) then
      WriteLn('ok negatyvnyi-svidok-rozrizniaie-zakhoplennia -> ',
        SlovoZakhoplennia,Rez1,SlovoBezZakhoplennia,Rez2)
    else begin
      Dec(Peremohy); Inc(Zboi);
      WriteLn(PrefiksZboiu,'negatyvnyi-svidok-rozrizniaie-zakhoplennia',
        PrefiksOchik,SlovoRizniRezultaty,
        PrefiksFakt,Rez1,' / ',Rez2);
    end;
    Vyikonaty(V,F3,Usp3,Rez3);
    Vyikonaty(V,F4,Usp4,Rez4);
    Inc(Peremohy);
    if Usp3 and Usp4 and (Rez3<>Rez4) then
      WriteLn('ok negatyvnyi-svidok-dvichi-rozrizniaie -> ',
        SlovoZakhoplennia,Rez3,SlovoBezZakhoplennia,Rez4)
    else begin
      Dec(Peremohy); Inc(Zboi);
      WriteLn(PrefiksZboiu,'negatyvnyi-svidok-dvichi-rozrizniaie',
        PrefiksOchik,SlovoRizniRezultaty,
        PrefiksFakt,Rez3,' / ',Rez4);
    end;
    { Форми мусять відрізнятися рівно тілом: інакше це різні питання. }
    PerevirytyRiznytsiu('negatyvnyi-vidrizniaietsia-lyshe-tilom-x-y',F1,F2,'x','y');
    PerevirytyRiznytsiu('negatyvnyi-dvichi-vidrizniaietsia-lyshe-tilom-x-y',F3,F4,'x','y');
    PerevirytyRiznytsiu('negatyvnyi-mitka-vidrizniaietsia-lyshe-tilom-x-y',F6,F7,'x','y');

    { --- Негативний свідок СПІЛЬНОЇ КОМІРКИ (обовʼязковий) ---
      Знімок і спільна комірка мусять дати РІЗНІ результати на одній
      і тій самій формі. F10 (спільна комірка) і F11 (знімок, виражений
      копіюванням у нове звʼязування) — це те саме питання з різними
      устроями оточення; збіг результатів означав би, що свідок нічого
      не доводить. }
    Vyikonaty(V,F10,Usp1,Rez1);
    Vyikonaty(V,F11,Usp2,Rez2);
    Inc(Peremohy);
    if Usp1 and Usp2 and (Rez1<>Rez2) then
      WriteLn('ok negatyvnyi-spilna-komirka-proty-znimka -> ',
        SlovoKomirka,Rez1,SlovoZnimok,Rez2)
    else begin
      Dec(Peremohy); Inc(Zboi);
      WriteLn(PrefiksZboiu,'negatyvnyi-spilna-komirka-proty-znimka',
        PrefiksOchik,SlovoRizniRezultatyKomirky,
        PrefiksFakt,Rez1,' / ',Rez2);
    end;
    { Та сама форма без присвоєння мусить дати СТАРЕ значення: інакше
      F10 давала б 0 не через присвоєння, і різниця нічого не доводила. }
    Vyikonaty(V,F12,Usp3,Rez3);
    Inc(Peremohy);
    if Usp3 and (Rez3=Rez2) and (Rez3<>Rez1) then
      WriteLn('ok kontrol-bez-prysvoiennia-dorivniuie-znimku -> ',
        SlovoKomirka,Rez1,SlovoBezPrysvoiennia,Rez3)
    else begin
      Dec(Peremohy); Inc(Zboi);
      WriteLn(PrefiksZboiu,'kontrol-bez-prysvoiennia-dorivniuie-znimku',
        PrefiksOchik,'старе значення без присвоєння',
        PrefiksFakt,Rez3,' комірка=',Rez1,' знімок=',Rez2);
    end;
  finally
    V.Free;
  end;

  WriteLn(PrefiksPidsumku,RawByteString(IntToStr(Peremohy+Zboi)),
    PrefiksPidsumku2,RawByteString(IntToStr(Zboi)));
  if Zboi>0 then Halt(1);
end.
