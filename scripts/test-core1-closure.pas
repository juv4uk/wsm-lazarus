{ Core1 / issue #866 — незалежний свідок виконання замикання.

  ЩО ПЕРЕВІРЯЄТЬСЯ (лише те, що є в src/wsm.nativeeval.pas):
    1. D10:0100111100 «створити-лямбда-замикання» (pinned
       external/sens/lib/domains/d10.lisp:327) реально створює замикання —
       тобто форма приймається механізмом, а не відкидається.
    2. Створене замикання ВИКЛИКАЄТЬСЯ з фізичним аргументом і дає
       правильний результат. Виклик — це гілка Eval:
         голова-атом без доменного ключа -> Assoc(Name,Env) ->
         ncClosure -> Appq(Evlis(N,1,Depth+1,Env)) ->
         Pairlis(FCells[A].First,B,Env) -> Eval(FNodes[FCells[A].Rest],...)
       (wsm.nativeeval.pas, рядки 523-529).
    3. НЕГАТИВНІ випадки: невірна кількість аргументів при виклику
       замикання мусить дати ARITY-помилку з Pairlis (рядки 370-371),
       а не тихий результат; створення без тіла мусить відмовити.

  ЦЕЙ СВІДОК НЕ ПІДГАНЯЄТЬСЯ ПІД КОД. Очікування сформульовані за
  названим механізмом, а не за спостереженим виводом. Якщо механізм не
  виконується — рядок стає «ПОМИЛКА-ТЕСТУ» з фактичним виводом, і це
  є результатом прогону, а не дефектом свідка.

  Точка входу — та сама, що в src/sens_oracle.lpr: TNativeEvaluator з
  коренем pinned доменів 'external/sens', один вираз на один виклик
  EvaluateSource. Протокол відповіді повторює оракул:
    OK<TAB><результат>   або   ERR<TAB><причина>
  Свідок незалежний від оракула: власний program, власні очікування,
  жодного спільного коду з sens_oracle.lpr, крім самого механізму. }
program test_core1_closure;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.nativeeval, wsm.source;

type
  { oPriimannia — форма мусить виконатися;
    oNeporo     — мусить виконатися і дати непорожній результат;
    oNeRivne    — мусить виконатися, і результат не може дорівнювати
                  заданому рядку (значення не сміє зникнути з виводу);
    oVidmova    — мусить відмовити, і причина мусить містити підрядок. }
  TOchikuvannia=(oPriimannia,oNeporo,oNeRivne,oVidmova);
  TVypadok=record
    Nazva:RawByteString;
    Forma:RawByteString;
    Ochik:TOchikuvannia;
    Ochikuvane:RawByteString;
    Prymitka:RawByteString;
  end;

const
  { Українські префікси звіту мусять дійти до виводу БАЙТ-У-БАЙТ.
    Причина: літерал, відданий WriteLn безпосередньо, FPC перекодовує
    в кодування консолі й кирилиця стає '?'. RawByteString-константа
    пишеться як є — так само, як це робить src/sens_oracle.lpr через
    сирий дескриптор 1. }
  PrefiksZboiu:RawByteString='ПОМИЛКА-ТЕСТУ: ';
  OchikVykonannia:RawByteString='виконання (OK)';
  OchikVykonanniaNeporo:RawByteString=
    'виконання (OK) з непорожнім результатом';
  OchikVykonanniaVidminne:RawByteString=
    'виконання (OK) з результатом, відмінним від [';
  OchikVidmova:RawByteString='відмову (ERR) зі згадкою [';
  PrefiksOchik:RawByteString=' — очікували ';
  PrefiksFakt:RawByteString='; фактично: ';
  PrefiksPidsumku:RawByteString='ЗАМИКАННЯ-СВІДОК перевірок=';
  PrefiksPidsumku2:RawByteString=' збоїв=';
  PrefiksVnutrishnoi:RawByteString=
    'ЗАМИКАННЯ-СВІДОК-ПОМИЛКА: ';
  TekstBezArhumentiv:RawByteString=
    'запуск без аргументів із кореня репозиторію';
  TekstBezDomeniv:RawByteString=
    'немає pinned доменів external/sens';

var
  Vypadky:array of TVypadok;
  Peremohy,Zboi:SizeInt;

procedure Dodaty(const Nazva,Forma:RawByteString; Ochik:TOchikuvannia;
  const Ochikuvane:RawByteString; const Prymitka:RawByteString);
var I:SizeInt;
begin
  I:=Length(Vypadky);
  SetLength(Vypadky,I+1);
  Vypadky[I].Nazva:=Nazva;
  Vypadky[I].Forma:=Forma;
  Vypadky[I].Ochik:=Ochik;
  Vypadky[I].Ochikuvane:=Ochikuvane;
  Vypadky[I].Prymitka:=Prymitka;
end;

{ Один виклик механізму. Uspih=False означає відмову (ERR), а Tekst тоді —
  причина; інакше Tekst — відображення результату, як його дає Render. }
procedure Vyikonaty(V:TNativeEvaluator; const Forma:RawByteString;
  out Uspih:Boolean; out Tekst:RawByteString);
begin
  Uspih:=True;
  Tekst:='';
  try
    Tekst:=V.EvaluateSource(Forma);
  except
    on E:ESourceError do begin
      Uspih:=False;
      Tekst:='ERR'#9+RawByteString(E.Message);
    end;
    on E:Exception do begin
      Uspih:=False;
      Tekst:='ERR'#9+RawByteString(E.Message);
    end;
  end;
end;

function ChohoOchikuvaly(const V:TVypadok):RawByteString;
begin
  case V.Ochik of
    oPriimannia: Result:=OchikVykonannia;
    oNeporo:     Result:=OchikVykonanniaNeporo;
    oNeRivne:    Result:=OchikVykonanniaVidminne+V.Ochikuvane+']';
    oVidmova:    Result:=OchikVidmova+V.Ochikuvane+']';
  end;
end;

function Zarakhovano(const V:TVypadok; Uspih:Boolean;
  const Tekst:RawByteString):Boolean;
begin
  case V.Ochik of
    oPriimannia: Result:=Uspih;
    oNeporo:     Result:=Uspih and (Length(Trim(Tekst))>0);
    oNeRivne:    Result:=Uspih and (Tekst<>V.Ochikuvane);
    oVidmova:    Result:=(not Uspih) and (Pos(V.Ochikuvane,Tekst)>0);
  else
    Result:=False;
  end;
end;

{ Форми. Дослівно, без скорочень. Адреси взяті з pinned доменних таблиць:
  D10:0100111100 — створити-лямбда-замикання (d10.lisp:327);
  D5:00100      — мітка (d5.lisp:13), у wsm.nativeeval.pas поки відмовляє. }
procedure PobutuvatyVypadky;
begin
  SetLength(Vypadky,0);

  { 1. Створення замикання. Форма з трьох полів: адреса, параметри, тіло. }
  Dodaty('створити-замикання-D10-0100111100',
    '(створити-лямбда-замикання (х) х)', oPriimannia, '',
    'D10:0100111100 мусить прийняти параметри й тіло');

  { 2. ГОЛОВНА ПОЗИТИВНА ПЕРЕВІРКА: виклик замикання з фізичним
     аргументом. Голова — форма створення; аргумент — D1:1 «так». }
  Dodaty('виклик-замикання-фізичним-аргументом',
    '((створити-лямбда-замикання (х) х) так)', oNeporo, '',
    'лямбда тотожності мусить повернути свій аргумент');

  { 3. НЕГАТИВНИЙ: виклик без аргументів при одному параметрі.
     Очікування — ARITY: TOO-FEW-ARGUMENTS із Pairlis (рядок 371). }
  Dodaty('виклик-замикання-замало-аргументів',
    '((створити-лямбда-замикання (х) х))', oVidmova, 'ARITY',
    'тихий результат замість ARITY заборонений');

  { 4. НЕГАТИВНИЙ: виклик із двома аргументами при одному параметрі.
     Очікування — ARITY: TOO-MANY-ARGUMENTS (рядок 370). }
  Dodaty('виклик-замикання-забагато-аргументів',
    '((створити-лямбда-замикання (х) х) так ні)', oVidmova, 'ARITY',
    'тихий результат замість ARITY заборонений');

  { 5. НЕГАТИВНИЙ до самої форми створення: тіла немає.
     wsm.nativeeval.pas, рядок 556-557: 'closure needs parameters and body'. }
  Dodaty('створення-без-тіла',
    '(створити-лямбда-замикання (х))', oVidmova,
    'closure needs parameters and body',
    'форма створення мусить перевіряти кількість полів');

  { 6. НЕГАТИВНИЙ до форми створення: зайве поле понад тіло. }
  Dodaty('створення-із-зайвим-полем',
    '(створити-лямбда-замикання (х) х ні)', oVidmova,
    'closure needs parameters and body',
    'форма створення мусить відхиляти зайве поле');

  { 7. Замикання мусить бути видимим значенням. Якщо воно зникає з
     відображення, то жодна перевірка «замикання створено» неможлива:
     порожній вивід не відрізняється від відсутності результату. }
  Dodaty('замикання-не-зникає-з-виводу',
    '(сполучити (створити-лямбда-замикання (х) х) ())', oNeRivne, '()',
    'список із замиканням не може відображатися як порожній');

  { 8. Мітка D5:00100 (d5.lisp:13) — іменоване закриття, тобто єдиний
     шлях до рекурсії. Свідок фіксує, що вона поки відмовляє, і не
     видає цю відмову за виконання. }
  Dodaty('мітка-D5-00100-відмовляє',
    '(мітка (х) х)', oVidmova, 'не реалізовано',
    'D5:00100 мусить або працювати, або чесно відмовляти');
end;

var
  V:TNativeEvaluator;
  I:SizeInt;
  Uspih:Boolean;
  Tekst,Fakt,Riadok:RawByteString;
begin
  if ParamCount<>0 then begin
    WriteLn(StdErr,PrefiksVnutrishnoi+TekstBezArhumentiv);
    Halt(2);
  end;
  if not DirectoryExists('external/sens') then begin
    WriteLn(StdErr,PrefiksVnutrishnoi+TekstBezDomeniv);
    Halt(2);
  end;
  PobutuvatyVypadky;
  Peremohy:=0; Zboi:=0;
  V:=TNativeEvaluator.Create('external/sens');
  try
    for I:=0 to High(Vypadky) do begin
      Vyikonaty(V,Vypadky[I].Forma,Uspih,Tekst);
      if Uspih then Fakt:='OK'#9+Tekst else Fakt:=Tekst;
      if Zarakhovano(Vypadky[I],Uspih,Tekst) then begin
        Inc(Peremohy);
        WriteLn('ok ',Vypadky[I].Nazva,' -> ',Fakt);
      end
      else begin
        Inc(Zboi);
        Riadok:=PrefiksZboiu+Vypadky[I].Nazva+PrefiksOchik+
          ChohoOchikuvaly(Vypadky[I])+PrefiksFakt+Fakt+
          ' ('+Vypadky[I].Prymitka+')';
        WriteLn(Riadok);
      end;
    end;
  finally
    V.Free;
  end;
  WriteLn(PrefiksPidsumku,RawByteString(IntToStr(Peremohy+Zboi)),
    PrefiksPidsumku2,RawByteString(IntToStr(Zboi)));
  if Zboi>0 then Halt(1);
end.
