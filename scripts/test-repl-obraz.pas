{ Свідок образу середовища: ДВА РІЗНІ ПРОЦЕСИ.
  Це власна програма, яка кличе сам механізм; її вивід — спостереження,
  а не доказ правильності (той самий підхід, що й у
  scripts/test-repl-seredovyshche.pas).

  Ролі (argv[1]), кожна — окремий запуск, тобто окремий процес:
    zberegty   — процес А: визначити імена, зберегти образ у файл, вийти;
    zavanty    — процес Б: завантажити образ, прочитати імʼя;
    bez-obrazu — негативний свідок: БЕЗ завантаження образу те саме імʼя
                 мусить дати 'unknown native binding';
    zipsovany  — образ зіпсовано: завантаження мусить відмовити.

  Нічого не вимикається заради зеленого: будь-який збій — код 1.
  Порівняння значень між А і Б робить скрипт, а не ця програма: інакше
  доказ був би переказом, а не спостереженням ззовні. }
program test_repl_obraz;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, BaseUnix, wsm.nativeeval, wsm.source;

function B(const U:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(U)); end;

var
  Zghoda,Zboi:SizeInt;

{ Вивід — суто RawByteString: інакше RTL перекодовує кирилицю в системну
  кодову сторінку термінала й у лог CI потрапляють знаки питання. }
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

function TryForm(E:TNativeEvaluator; const Source:RawByteString;
  out Value:RawByteString; out ErrorText:RawByteString):Boolean;
begin
  Value:=''; ErrorText:='';
  try
    Value:=E.EvaluateSessionSource(Source);
    Result:=True;
  except
    on X:Exception do begin
      ErrorText:=RawByteString(X.Message);
      Result:=False;
    end;
  end;
end;

{ Розмір файлу образу. Не плутати з системною FileSize(var f): тут
  потрібен саме розмір на диску, бо «образ записано» без байтів — не факт. }
function RozmirFailu(const Path:RawByteString):Int64;
var G:File of Byte; N:Int64;
begin
  Result:=0;
  if not FileExists(Path) then Exit;
  Assign(G,Path); Reset(G); N:=System.FileSize(G); Close(G); Result:=N;
end;

const
  FORM_X        = '(встановити-ім''я число так)';
  FORM_PERELIK  = '(встановити-ім''я перелік (як-є (а б)))';
  FORM_MITKA    = '(мітка ід (створити-лямбда-замикання (y) y))';
  FORM_X_CHYT   = 'число';
  FORM_PER_CHYT = 'перелік';
  FORM_ID_CHYT  = 'ід';

var
  Rol,Shliakh:RawByteString;
  E:TNativeEvaluator;
  V,VD,ErrText:RawByteString;
  OkForm:Boolean;
  N:SizeInt;
  F:File of Byte;
  Dany:RawByteString;
  I:SizeInt;
  Bt:Byte;
begin
  Zghoda:=0; Zboi:=0;
  if ParamCount<2 then begin
    WriteLn(RawByteString('ВЖИВАННЯ: test-repl-obraz <zberegty|zavanty|bez-obrazu|zipsovany> <файл образу>'));
    Halt(2);
  end;
  Rol:=RawByteString(ParamStr(1));
  Shliakh:=RawByteString(ParamStr(2));
  WriteLn(RawByteString('ОБРАЗ-СВІДОК роль=')+Rol+
    RawByteString(' pid=')+RawByteString(IntToStr(FpGetPid)));

  if Rol='zberegty' then begin
    { ---------------------------------------------- ПРОЦЕС А: зберегти
      Звичайні визначення — дані. Замикання визначене НАВМИСНО: воно
      мусить не потрапити в образ, і це мусить бути названо, а не
      замовчане. }
    E:=TNativeEvaluator.Create('external/sens',65536);
    try
      E.BeginSession;
      OkForm:=TryForm(E,FORM_X,V,ErrText);
      Check('a-vyznachennia-chyslo',OkForm and (V='1'),'прийнято зі значенням 1',V+' '+ErrText);
      OkForm:=TryForm(E,FORM_PERELIK,V,ErrText);
      Check('a-vyznachennia-perelik',OkForm and (Length(V)>0),
        'прийнято структуру',V+' '+ErrText);
      OkForm:=TryForm(E,FORM_MITKA,VD,ErrText);
      Check('a-vyznachennia-zamykannia',
        OkForm and (Length(VD)>0) and (VD[1]='<'),
        'прийнято замикання',VD+' '+ErrText);
      Check('a-zv-yazuvan-u-sesii',E.SessionBindings=3,'3 звʼязання',
        RawByteString(IntToStr(E.SessionBindings)));
      N:=E.SaveImage(Shliakh);
      Check('a-obraz-zberezheno',(N=2) and (E.ImageSkippedBindings=1),
        'у файл пішло 2 звʼязування, замикання назване як пропущене',
        RawByteString('записано=')+RawByteString(IntToStr(N))+
        RawByteString(' пропущено=')+
        RawByteString(IntToStr(E.ImageSkippedBindings)));
      Check('a-obraz-ne-porozhnii',RozmirFailu(Shliakh)>0,
        'файл образу не порожній',
        RawByteString(IntToStr(RozmirFailu(Shliakh)))+RawByteString(' байтів'));
      { Значення, яке процес Б мусить дістати з образу. Друкуються саме
        ті рядки, які скрипт потім порівнює між процесами. }
      OkForm:=TryForm(E,FORM_PER_CHYT,V,ErrText);
      Ok('a-perelik-dosi',V);
      E.EndSession;
    finally
      E.Free;
    end;
  end
  else if Rol='zavanty' then begin
    { ---------------------------------------------- ПРОЦЕС Б: відновити
      Жодного визначення тут не робиться: усе, що програма прочитає,
      прийшло з файлу, а не з цього процесу. }
    E:=TNativeEvaluator.Create('external/sens',65536);
    try
      E.BeginSession;
      Check('b-sesiia-na-start-porozhnia',E.SessionBindings=0,
        '0 звʼязань до завантаження',
        RawByteString(IntToStr(E.SessionBindings)));
      N:=E.LoadImage(Shliakh);
      Check('b-obraz-zavantazheno',N=2,'2 звʼязання з образу',
        RawByteString(IntToStr(N)));
      Check('b-zv-yazuvan-pislia-zavantazhennia',E.SessionBindings=2,
        '2 звʼязання в сесії',
        RawByteString(IntToStr(E.SessionBindings)));
      OkForm:=TryForm(E,FORM_X_CHYT,V,ErrText);
      Check('b-chytannia-chysla-z-obrazu',OkForm and (V='1'),
        'збережене значення 1',V+' '+ErrText);
      Ok('b-chyslo',V);
      OkForm:=TryForm(E,FORM_PER_CHYT,V,ErrText);
      Check('b-chytannia-perelik-z-obrazu',OkForm and (Length(V)>0),
        'відновлена структура',V+' '+ErrText);
      Ok('b-perelik',V);
      { Межа зрізу, названа прямо: тіло замикання не пережило процес,
        тому його імʼя мусить бути невидимим, а не «приблизно робочим». }
      OkForm:=TryForm(E,FORM_ID_CHYT,V,ErrText);
      Check('b-tilo-zamykannia-ne-perezhylo',not OkForm,
        B('помилка замість значення'),
        B('значення=')+V+B(' помилка=')+ErrText);
      Ok('b-id-pomylka',ErrText);
      E.EndSession;
    finally
      E.Free;
    end;
  end
  else if Rol='bez-obrazu' then begin
    { ------------------------------- НЕГАТИВНИЙ СВІДОК: без завантаження
      Той самий свіжий обчислювач, та сама форма читання, але образ не
      завантажений. Якщо тут теж було б 1 — образ нічого не додає. }
    E:=TNativeEvaluator.Create('external/sens',65536);
    try
      E.BeginSession;
      Check('n-bez-obrazu-sesiia-porozhnia',E.SessionBindings=0,
        '0 звʼязань',RawByteString(IntToStr(E.SessionBindings)));
      OkForm:=TryForm(E,FORM_X_CHYT,V,ErrText);
      Check('n-bez-obrazu-im-ia-nevydyme',not OkForm,
        B('помилка замість значення'),
        B('значення=')+V+B(' помилка=')+ErrText);
      Ok('n-chyslo-pomylka',ErrText);
      E.EndSession;
    finally
      E.Free;
    end;
  end
  else if Rol='zipsovany' then begin
    { ------------------------------- ЗІПСОВАНИЙ ОБРАЗ: відмова, не здогад
      Пишемо не-T5M байти й вимагаємо відмови: інакше «відновлення»
      означало б тлумачення чого завгодно як середовища. }
    Assign(F,Shliakh);
    Rewrite(F);
    Dany:=RawByteString(#$FF#$00#$FF#$13#$37);
    for I:=1 to 3 do begin
      Bt:=Ord(Dany[I]);
      Write(F,Bt);
    end;
    Close(F);
    E:=TNativeEvaluator.Create('external/sens',65536);
    try
      E.BeginSession;
      OkForm:=False; ErrText:='';
      try
        E.LoadImage(Shliakh);
      except
        on X:Exception do begin OkForm:=True; ErrText:=RawByteString(X.Message); end;
      end;
      Check('z-zipsovanyi-obraz-vidmovliaie',OkForm,
        B('відмова замість середовища'),
        B('відмова: ')+ErrText);
      Ok('z-pomylka',ErrText);
      E.EndSession;
    finally
      E.Free;
    end;
  end
  else begin
    WriteLn(RawByteString('НЕВІДОМА РОЛЬ: ')+Rol);
    Halt(2);
  end;

  WriteLn(RawByteString('ОБРАЗ-ПІДСУМОК роль=')+Rol+
    RawByteString(' перевірок=')+RawByteString(IntToStr(Zghoda+Zboi))+
    RawByteString(' ok=')+RawByteString(IntToStr(Zghoda))+
    RawByteString(' збоїв=')+RawByteString(IntToStr(Zboi)));
  if Zboi>0 then Halt(1);
end.
