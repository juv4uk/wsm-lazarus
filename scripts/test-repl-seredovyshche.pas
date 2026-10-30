{ Задача — постійне середовище REPL: визначення переживають ОДНЕ обчислення.
  Це власна програма, яка кличе сам механізм; її вивід — спостереження, а не
  доказ правильності (див. коментар у scripts/test-zamykannia-svidok.sh).

  Два свідки, навмисно не змішані:
    ПОЗИТИВНИЙ — із сесією: форма 1 визначає імʼя, форма 2 (ОКРЕМЕ
      обчислення) читає його й дістає збережене значення.
    НЕГАТИВНИЙ — без сесії: ТА САМА форма 2 на тому самому оточенні й на
      свіжому оточенні мусить дати ПОМИЛКУ. Інакше свідок не доводив би,
      що додає саме сесія.

  Нічого не вимикається заради зеленого: будь-який збій — код 1. }
program test_repl_seredovyshche;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.nativeeval, wsm.source;

function B(const U:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(U)); end;

var
  Zghoda,Zboi:SizeInt;

{ Вивід — суто RawByteString: інакше RTL перекодовує кирилицю в системну
  кодову сторінку термінала й у лог CI потрапляють знаки питання замість
  слів. Це не косметика: скрипт звіряє саме ці рядки. }
procedure Ok(const Name,Value:RawByteString);
begin
  Inc(Zghoda);
  WriteLn(RawByteString('ok ')+Name+RawByteString(' -> ')+Value);
end;

procedure Zbii(const Name,Expected,Actual:RawByteString);
begin
  Inc(Zboi);
  WriteLn(RawByteString('ПОМИЛКА-ТЕСТУ: ')+Name+RawByteString(' — очікували ')+
    Expected+RawByteString('; фактично: ')+Actual);
end;

procedure Check(const Name:RawByteString; Condition:Boolean;
  const Expected,Actual:RawByteString);
begin
  if Condition then Ok(Name,Actual)
  else Zbii(Name,Expected,Actual);
end;

{ Обчислити форму, повернувши або результат, або позначку помилки.
  Один шлях для позитивного й негативного свідка: інакше різниця могла б
  походити від різного коду, а не від наявності сесії. }
function TryForm(E:TNativeEvaluator; const Source:RawByteString;
  UseSession:Boolean; out Value:RawByteString; out ErrorText:RawByteString):Boolean;
begin
  Value:=''; ErrorText:='';
  try
    if UseSession then Value:=E.EvaluateSessionSource(Source)
    else Value:=E.EvaluateSource(Source);
    Result:=True;
  except
    on X:Exception do begin
      ErrorText:=RawByteString(X.Message);
      Result:=False;
    end;
  end;
end;

const
  FORM_VYSNACHYTY = '(встановити-ім''я x так)';
  FORM_CHYTATY    = 'x';
  FORM_PEREVYSN   = '(встановити-ім''я x ні)';
  FORM_MITKA      = '(мітка ід (створити-лямбда-замикання (y) y))';
  FORM_VYKLYK     = '(ід ні)';

var
  E:TNativeEvaluator;
  V1,V2,V3,V4,VD,VC,ErrText,NegSame,ErrFresh,PosChytannia:RawByteString;
  OkForm:Boolean;
  NegSameOk,NegFreshOk:Boolean;
  Vidmova:Boolean;
begin
  Zghoda:=0; Zboi:=0;
  WriteLn(RawByteString('REPL-СЕРЕДОВИЩЕ-СВІДОК початок'));

  { ---------------------------------------------------- 1. ПОЗИТИВНИЙ СВІДОК
    Визначення в першому обчисленні, читання — в ОКРЕМОМУ. }
  E:=TNativeEvaluator.Create('external/sens',65536);
  try
    E.BeginSession;
    Check('sesiia-vidkryta',E.SessionBindings=0,'0 звʼязань на старті',
      RawByteString(IntToStr(E.SessionBindings)));

    OkForm:=TryForm(E,FORM_VYSNACHYTY,True,V1,ErrText);
    Check('vyznachennia-v-pershomu-obchyslenni',OkForm and (V1='1'),
      'прийнято зі значенням 1',V1+' '+ErrText);

    Check('im-ia-zviazane-u-sesii',E.SessionBindings=1,'1 звʼязання після форми 1',
      RawByteString(IntToStr(E.SessionBindings)));

    { ОКРЕМЕ обчислення — новий виклик, новий бюджет кроків, та сама сесія. }
    OkForm:=TryForm(E,FORM_CHYTATY,True,V2,ErrText);
    Check('chytannia-v-okremomu-obchyslenni',OkForm and (V2='1'),
      'збережене значення 1',V2+' '+ErrText);
    Check('chytannia-baivt-v-baivt-z-vyznachenniam',V2=V1,'те саме значення, що дало визначення',
      B('визначення=')+V1+B(' читання=')+V2);
    PosChytannia:=V2; { значення, яке дало успішне читання в сесії }

    { Спільна комірка: присвоєння в третьому обчисленні видно в четвертому. }
    OkForm:=TryForm(E,FORM_PEREVYSN,True,V3,ErrText);
    Check('perevyznachennia-pryiniato',OkForm and (V3='0'),'прийнято зі значенням 0',
      V3+' '+ErrText);
    OkForm:=TryForm(E,FORM_CHYTATY,True,V4,ErrText);
    Check('spilna-komirka-mizh-obchyslenniamy',OkForm and (V4='0') and (V4<>V2),
      'нове значення 0, не старий знімок 1',V4+' '+ErrText);

    { Замикання: тіло — вузол AST попередньої форми. Якщо сесія не тримає
      документ, цей виклик читав би звільнену памʼять. }
    OkForm:=TryForm(E,FORM_MITKA,True,VD,ErrText);
    { Маркер замикання починається з '<'. Pos() із кириличною голкою тут
      зайвий: RTL перекодовує аргументи, і звірка стала б неточною. }
    Check('mitka-zamkannia-pryiniata',
      OkForm and (Length(VD)>0) and (VD[1]='<'),
      'прийнято замикання',VD+' '+ErrText);
    OkForm:=TryForm(E,FORM_VYKLYK,True,VC,ErrText);
    Check('zamykannia-vyklykaietsia-z-inshoho-obchyslennia',OkForm and (VC='0'),
      'значення 0 з тіла попередньої форми',VC+' '+ErrText);

    { Семантика одного обчислення не змінена: EvaluateNode під час сесії
      відмовляє явно, а не мовчки скидає оточення. }
    Vidmova:=False;
    try
      E.EvaluateSource(B('x'));
    except
      on X:Exception do Vidmova:=True;
    end;
    Check('odnorazovyi-vhid-vidmovliaie-pid-chas-sesii',Vidmova,'явна відмова',
      'без відмови (оточення було б скинуто)');

    E.EndSession;
    OkForm:=TryForm(E,FORM_CHYTATY,True,V2,ErrText);
    Check('pislia-zakryttia-sesii-im-ia-nevydyme',(not OkForm) and (V2=''),
      'відмова без значення',V2+' '+ErrText);
  finally
    E.Free;
  end;

  { -------------------------------------------------- 2. НЕГАТИВНИЙ СВІДОК
    ТА САМА форма читання БЕЗ сесії. Два варіанти: те саме оточення двічі
    (обчислювач одного виразу) і свіже оточення. }
  E:=TNativeEvaluator.Create('external/sens',65536);
  try
    OkForm:=TryForm(E,FORM_VYSNACHYTY,False,V1,ErrText);
    Check('bez-sesii-vyznachennia-obchysleno',OkForm and (V1='1'),
      'форма 1 обчислюється й без сесії',V1+' '+ErrText);
    Check('bez-sesii-im-ia-ni-z-chym-ne-zviazane',E.SessionBindings=0,
      '0 звʼязань: сесія не відкрита',RawByteString(IntToStr(E.SessionBindings)));
    NegSameOk:=TryForm(E,FORM_CHYTATY,False,NegSame,ErrText);
    Check('negatyvnyi-bez-sesii-te-same-otochemnia',not NegSameOk,
      B('помилка замість значення'),B('значення=')+NegSame+B(' помилка=')+ErrText);
  finally
    E.Free;
  end;

  E:=TNativeEvaluator.Create('external/sens',65536);
  try
    NegFreshOk:=TryForm(E,FORM_CHYTATY,False,ErrFresh,ErrText);
    Check('negatyvnyi-bez-sesii-svizhe-otochemnia',not NegFreshOk,
      B('помилка замість значення'),B('значення=')+ErrFresh+B(' помилка=')+ErrText);
  finally
    E.Free;
  end;

  { Головна умова негативного свідка: та сама форма, різний результат.
    Якщо без сесії теж поверталося б 1 — сесія не додавала б нічого. }
  Check('negatyvnyi-vidrizniaietsia-vid-pozytyvnoho',
    (not NegSameOk) and (not NegFreshOk) and (PosChytannia='1'),
    B('без сесії — помилка, із сесією — значення'),
    B('без сесії ok=')+B(BoolToStr(NegSameOk,True))+B('/')+
    B(BoolToStr(NegFreshOk,True))+B('; із сесією ')+PosChytannia);

  WriteLn(RawByteString('REPL-СЕРЕДОВИЩЕ-ПІДСУМОК перевірок=')+
    RawByteString(IntToStr(Zghoda+Zboi))+RawByteString(' ok=')+
    RawByteString(IntToStr(Zghoda))+RawByteString(' збоїв=')+
    RawByteString(IntToStr(Zboi)));
  if Zboi>0 then begin
    WriteLn(RawByteString('ВИСНОВОК: постійного середовища НЕМАЄ — визначення не переживають обчислення.'));
    Halt(1);
  end;
  WriteLn(RawByteString('ВИСНОВОК: визначення переживають обчислення в сесії, і без сесії те саме імʼя не видно.'));
end.
