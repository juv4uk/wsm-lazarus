{ Issue #490 — дві голови драбини, які досі відмовляли.

  ЩО ПЕРЕВІРЯЄТЬСЯ (лише те, що є в src/wsm.nativeeval.pas):
    1. D5:00110 «встановити» (pinned lib/domains/d5.lisp:15). Відміна від
       встановити-ім'я (00111) рівно одна й названа в pinned core1.lisp:1360-1363:
       НАЗВА обчислюється, а не береться з написання. Тому свідок вимагає:
         * запис приймається і повертає ЗАПИСАНЕ значення;
         * імʼя справді звʼязане в оточенні (читання наступною формою);
         * назва, обчислена з D7-даних (перше (як-є (х у))), а не написана
           атомом, дає те саме звʼязування — інакше «обчислювана назва» не
           доведена;
         * повторний запис змінює НАЯВНУ пару (FindBinding), а не додає другу:
           кількість звʼязань у сесії не росте.
    2. D10:0101100010 «зв'язати-параметри» (pinned lib/domains/d10.lisp:365,
       закон core1.lisp:193-207). Вимагається:
         * результат — нова аліста, а не відмова;
         * cons іде з голови, тому ОСТАННІЙ параметр стоїть першим
           (перевіряється структурно: імʼя першої пари дорівнює імені
           останнього параметра, а не першого);
         * дві РІЗНІ помилки арності: TOO-MANY-ARGUMENTS і TOO-FEW-ARGUMENTS;
         * передане оточення продовжується, а не затирається;
         * у FGlobalEnv нічого не пишеться — на відміну від встановити.

  НЕГАТИВНІ СВІДКИ. Кожен позитив має пару, без якої він нічого не доводив би:
    * те саме читання без сесії мусить ВІДМОВИТИ (інакше звʼязування не
      доведене — його могло не бути);
    * у жодному збої не сміє зʼявитися давня відмова: 'unsupported D5
      callable' або 'bind-params: not implemented yet'. Якщо зʼявиться —
      голова не виконалася, і це збій, а не зелено.

  ЦЕЙ СВІДОК НЕ ПІДГАНЯЄТЬСЯ ПІД КОД: очікування сформульовані за pinned
  законами, а не за спостереженим виводом. Будь-який збій — код 1. }
program test_vstanovyty_zviazaty;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.nativeeval, wsm.source;

var
  Zghoda,Zboi:SizeInt;

{ Вивід — суто RawByteString: інакше RTL перекодовує кирилицю в системну
  кодову сторінку термінала, і скрипт звіряв би не ті байти. }
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
  if Condition then Ok(Name,Actual) else Zbii(Name,Expected,Actual);
end;

{ Один шлях для позитивного й негативного свідка: інакше різниця могла б
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

{ Давні відмови обох голів. Якщо вони зʼявляються — голова не виконалася. }
function StaraVidmova(const ErrorText:RawByteString):Boolean;
begin
  Result:=(Pos('unsupported D5 callable',ErrorText)>0) or
          (Pos('bind-params: not implemented',ErrorText)>0);
end;

const
  { встановити (D5:00110). Назва — D7-дані, значення — обчислюваний вираз. }
  F_VSTANOVYTY      = '(встановити (як-є х) так)';
  F_VSTANOVYTY_NI   = '(встановити (як-є х) ні)';
  { Назва ОБЧИСЛЮЄТЬСЯ з даних: перше з (як-є (х у)) — це D7-ланцюг «х». }
  F_VSTANOVYTY_OBS  = '(встановити (перше (як-є (х у))) ні)';
  F_VSTANOVYTY_2ARG = '(встановити (як-є х))';
  F_VSTANOVYTY_NEMA = '(встановити () так)';
  F_CHYTATY_H       = 'х';

  { зв'язати-параметри (D10:0101100010). Параметри — D7-дані, тобто список
    ІМЕН; аргументи — обчислений список значень; оточення — аліста або (). }
  F_BIND_1   = '(зв''язати-параметри (як-є (х)) (сполучити так ()) ())';
  { імʼя першої пари при параметрах (х у): мусить бути «у», не «х» }
  F_BIND_IMIA2 =
    '(перше (перше (зв''язати-параметри (як-є (х у)) '+
    '(сполучити так (сполучити ні ())) ())))';
  { те саме імʼя, здобуте незалежно — з одного параметра «у» }
  F_BIND_IMIA_U =
    '(перше (перше (зв''язати-параметри (як-є (у)) '+
    '(сполучити так ()) ())))';
  F_BIND_2ARG =
    '(зв''язати-параметри (як-є (х)) (сполучити так ()))';
  F_BIND_MALO  = '(зв''язати-параметри (як-є (х)) () ())';
  F_BIND_BAHATO= '(зв''язати-параметри (як-є ()) (сполучити так ()) ())';
  { оточення продовжується: друга пара мусить існувати }
  F_BIND_OTOCHE =
    '(перше (решта (зв''язати-параметри (як-є (х)) (сполучити так ()) '+
    '(зв''язати-параметри (як-є (у)) (сполучити ні ()) ()))))';
  { зв'язати-параметри НЕ пише в FGlobalEnv — імʼя «ц» лишається вільним }
  F_BIND_NEPYSHE =
    '(зв''язати-параметри (як-є (ц)) (сполучити так ()) ())';
  F_CHYTATY_C = 'ц';

var
  E,E2:TNativeEvaluator;
  V,V2,VObs,VImia2,VImiaU,VOTO,VNepyshe,ErrText,Err2,ErrObs,ErrNepyshe:RawByteString;
  OkForm,OkObs:Boolean;
  Zviazan,Bulo:SizeInt;
begin
  Zghoda:=0; Zboi:=0;
  WriteLn(RawByteString('ВСТАНОВИТИ-ЗВЯЗАТИ-СВІДОК початок'));

  { ======================================================= D5:00110 встановити }
  E:=TNativeEvaluator.Create('external/sens',65536);
  try
    E.BeginSession;
    Bulo:=E.SessionBindings;

    OkForm:=TryForm(E,F_VSTANOVYTY,True,V,ErrText);
    Check('vstanovyty-pryiniato',OkForm and (V='1') and not StaraVidmova(ErrText),
      'прийнято зі значенням 1 (записане значення і є результатом)',
      V+' '+ErrText);

    Zviazan:=E.SessionBindings;
    Check('vstanovyty-zv-iazalo-im-ia',Zviazan=Bulo+1,
      'рівно одне нове звʼязування',
      RawByteString(IntToStr(Zviazan))+' (bulo '+RawByteString(IntToStr(Bulo))+')');

    { ОКРЕМЕ обчислення в тій самій сесії: читання мусить дістати записане. }
    OkForm:=TryForm(E,F_CHYTATY_H,True,V2,ErrText);
    Check('vstanovyty-chytannia-bachyt-zapys',OkForm and (V2=V),
      'те саме значення, що повернув запис',
      RawByteString('запис=')+V+RawByteString(' читання=')+V2+' '+ErrText);

    { НЕГАТИВНИЙ СВІДОК: та сама форма читання на СВІЖОМУ обчислювачі без
      сесії мусить відмовити. Окремий обʼєкт, а не той самий: у відкритій
      сесії EvaluateSource відмовляє з іншої причини, і така відмова нічого
      не доводила б про звʼязування. }
    E2:=TNativeEvaluator.Create('external/sens',65536);
    try
      OkForm:=TryForm(E2,F_CHYTATY_H,False,V2,Err2);
      Check('negatyvnyi-bez-sesii-chytannia-vidmovliaie',
        (not OkForm) and (Pos('оточенн',Err2)=0),
        'відмову через відсутнє звʼязування, не через режим сесії',
        V2+' '+Err2);
    finally
      E2.Free;
    end;

    { Назва ОБЧИСЛЮЄТЬСЯ: та сама комірка «х» адресується D7-даними, а не
      написанням атома. }
    OkObs:=TryForm(E,F_VSTANOVYTY_OBS,True,VObs,ErrObs);
    Check('vstanovyty-nazva-obchysliuietsia',OkObs and (VObs='0') and
      not StaraVidmova(ErrObs),'прийнято зі значенням 0',
      VObs+' '+ErrObs);
    OkForm:=TryForm(E,F_CHYTATY_H,True,V2,ErrText);
    Check('vstanovyty-obchyslena-nazva-pishe-tu-samu-komirku',
      OkForm and (V2=VObs) and (V2<>V),
      'обчислена назва змінила те саме звʼязування',
      RawByteString('було=')+V+RawByteString(' стало=')+V2);

    { СПІЛЬНА КОМІРКА: другий запис змінює наявну пару, а не додає другу. }
    OkForm:=TryForm(E,F_VSTANOVYTY_NI,True,V,ErrText);
    Check('vstanovyty-povtornyi-zapys-pryiniato',OkForm and (V='0'),
      'прийнято зі значенням 0',V+' '+ErrText);
    Check('vstanovyty-spilna-komirka-bez-druhoi-pary',E.SessionBindings=Zviazan,
      'та сама кількість звʼязань (FindBinding, не нова пара)',
      RawByteString(IntToStr(E.SessionBindings)));

    { Відмови: форма без виразу і форма без обчислюваної назви. }
    OkForm:=TryForm(E,F_VSTANOVYTY_2ARG,True,V,ErrText);
    Check('vstanovyty-bez-vyrazu-vidmovliaie',(not OkForm) and
      (Pos('D5:00110',ErrText)>0) and not StaraVidmova(ErrText),
      'відмову зі згадкою D5:00110',V+' '+ErrText);
    OkForm:=TryForm(E,F_VSTANOVYTY_NEMA,True,V,ErrText);
    Check('vstanovyty-bez-nazvy-vidmovliaie',(not OkForm) and
      not StaraVidmova(ErrText),'відмову (назва не є значенням)',V+' '+ErrText);

    { ====================================== D10:0101100010 зв'язати-параметри }
    OkForm:=TryForm(E,F_BIND_1,True,V,ErrText);
    Check('zviazaty-parametry-pryiniato',OkForm and (Length(V)>0) and
      (V<>'()') and (V<>'0') and (V<>'1') and not StaraVidmova(ErrText),
      'прийнято непорожню алісту',V+' '+ErrText);

    OkForm:=TryForm(E,F_BIND_IMIA2,True,VImia2,ErrText);
    OkForm:=TryForm(E,F_BIND_IMIA_U,True,VImiaU,Err2);
    Check('zviazaty-parametry-ostannii-parametr-pershyi',
      (VImia2<>'') and (VImia2=VImiaU),
      'імʼя першої пари = імʼя ОСТАННЬОГО параметра (у), не першого (х)',
      RawByteString('перша-пара=')+VImia2+RawByteString(' імʼя-у=')+VImiaU+' '+
      ErrText+' '+Err2);

    OkForm:=TryForm(E,F_BIND_OTOCHE,True,VOTO,ErrText);
    Check('zviazaty-parametry-prodovzhuie-otochemnia',
      OkForm and (Length(VOTO)>0) and (VOTO<>'0'),
      'другу пару в переданому оточенні',VOTO+' '+ErrText);

    OkForm:=TryForm(E,F_BIND_MALO,True,V,ErrText);
    Check('zviazaty-parametry-arnist-zamalo',(not OkForm) and
      (Pos('ARITY: TOO-FEW-ARGUMENTS',ErrText)>0) and not StaraVidmova(ErrText),
      'ARITY: TOO-FEW-ARGUMENTS',V+' '+ErrText);

    OkForm:=TryForm(E,F_BIND_BAHATO,True,V,ErrText);
    Check('zviazaty-parametry-arnist-zabahato',(not OkForm) and
      (Pos('ARITY: TOO-MANY-ARGUMENTS',ErrText)>0) and not StaraVidmova(ErrText),
      'ARITY: TOO-MANY-ARGUMENTS',V+' '+ErrText);

    OkForm:=TryForm(E,F_BIND_2ARG,True,V,ErrText);
    Check('zviazaty-parametry-try-argumenty-obov-iazkovi',(not OkForm) and
      (Pos('D10:0101100010',ErrText)>0) and not StaraVidmova(ErrText),
      'відмову зі згадкою D10:0101100010',V+' '+ErrText);

    { НЕГАТИВНИЙ СВІДОК: зв'язати-параметри не пише в FGlobalEnv. }
    Bulo:=E.SessionBindings;
    OkForm:=TryForm(E,F_BIND_NEPYSHE,True,VNepyshe,ErrText);
    OkForm:=TryForm(E,F_CHYTATY_C,True,V,ErrNepyshe);
    Check('negatyvnyi-zviazaty-parametry-ne-pyshe-v-hlobalne',
      (not OkForm) and (E.SessionBindings=Bulo) and not StaraVidmova(ErrNepyshe),
      'вільне імʼя «ц» і незмінну кількість звʼязань у сесії',
      VNepyshe+' '+ErrNepyshe+' zviazan='+RawByteString(IntToStr(E.SessionBindings)));

    E.EndSession;
  finally
    E.Free;
  end;

  WriteLn(RawByteString('ВСТАНОВИТИ-ЗВЯЗАТИ-ПІДСУМОК перевірок=')+
    RawByteString(IntToStr(Zghoda+Zboi))+RawByteString(' ok=')+
    RawByteString(IntToStr(Zghoda))+RawByteString(' збоїв=')+
    RawByteString(IntToStr(Zboi)));
  if Zboi>0 then begin
    WriteLn(RawByteString('ВИСНОВОК: голови встановити (D5:00110) і ')+
      RawByteString('зв''язати-параметри (D10:0101100010) НЕ виконуються ')+
      RawByteString('на поверхні (див. збої вище).'));
    Halt(1);
  end;
  WriteLn(RawByteString('ВИСНОВОК: обидві голови виконані фактичним виводом: ')+
    RawByteString('запис за обчисленою назвою і звʼязування параметрів.'));
end.

