{ G5.12: справжня візуалізація виконаних верхніх форм одного .sens.
  Лише Lazarus/LCL; жодних локальних законів чи мовного evaluator. }
program sens_formas;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, wsm.formpanel;
var Window:TFormWindow;

procedure Require(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('вікно форм: '+Why);
end;

procedure SelfTest;
var
  Proof:RawByteString;
  Rejected:Boolean;
begin
  Require(Window.HasWidgets,'LCL не створив справжні віджети');
  Require(Window.ExecuteFile(ParamStr(2)),'три фізичні корені не прийнято');
  Require(Window.ResultCount=3,'відсутні три рядки');
  Require(Window.ValueAt(0)=RawByteString(ParamStr(6)),'перший результат відрізняється від CLI');
  Require(Window.ValueAt(1)=RawByteString(ParamStr(7)),'другий результат відрізняється від CLI');
  Require(Window.ValueAt(2)=RawByteString(ParamStr(8)),'третій результат відрізняється від CLI');
  Require((Window.RootWordAt(0)=1) and (Window.RootWordAt(1)=2) and
    (Window.RootWordAt(2)=8),'втрачені фізичні номери слів');
  Require((Window.CoordinateAt(0)='D1:1') and
    (Window.CoordinateAt(1)='D2:10') and
    (Window.CoordinateAt(2)='D1:0'),'ширина та фізичний бітовий рисунок кореня');
  Require((Window.TritStartAt(0)=0) and (Window.TritStartAt(1)=2) and
    (Window.TritStartAt(2)=21),'втрачені точні тритові позиції');
  Proof:=Window.Evidence;
  Require(Pos('1'#9'1'#9'D1:1'#9'[0,1)'#9'[0,1)'#9'1'#10,Proof)=1,
    'втрачено фізичну адресу D1:1');
  Require(Pos('3'#9'8'#9'D1:0'#9'[21,22)'#9'[4,5)'#9'0'#10,Proof)>0,
    'фізична адреса останньої форми помилкова');

  Require(not Window.ExecuteFile(ParamStr(3)),
    'непідтверджена D3 цитата в другій формі прийнята');
  Require((Window.ResultCount=0) and (Window.Evidence=''),
    'відмова другої форми опублікувала першу');
  Require(Pos('форму №2',Window.StatusText)>0,
    'помилка втратила номер другої форми');
  Require(Pos('слово 3',Window.StatusText)>0,
    'помилка втратила глобальний номер фізичного слова');

  Require(not Window.ExecuteFile(ParamStr(4)),
    'незакритий D2 після валідного кореня прийнято');
  Require((Window.ResultCount=0) and (Window.Evidence=''),
    'після D2 відмови залишився старий результат');
  Require(Pos('слово 4',Window.StatusText)>0,
    'помилка D2 втратила позицію EOF');

  Require(not Window.ExecuteFile(ParamStr(5)),'байт 243 прийнято за T5M');
  Require((Window.ResultCount=0) and (Window.Evidence=''),
    'після зіпсованого T5M залишився рядок');
  Require(not Window.ExecuteFile('фізично-відсутній.sens'),
    'неіснуючий файл прийнято');
  Require((Window.ResultCount=0) and (Window.Evidence=''),
    'неіснуючий файл залишив попередню таблицю');
  Require(not Window.ExecuteFile('проєкція.lisp'),
    'текстову проєкцію прийнято як канонічний файл');
  Require(Window.ResultCount=0,'текстова проєкція змінила таблицю');

  Rejected:=False;
  try Window.ValueAt(0);
  except on E:Exception do Rejected:=True; end;
  Require(Rejected,'читання неіснуючого рядка дозволено');

  Require(Window.ExecuteFile(ParamStr(2)),
    'відновлення після помилок не працює');
  Require(Window.Evidence=Proof,'повторне виконання не є детермінованим');
  Window.Show; Window.Repaint; Application.ProcessMessages;
  WriteLn('LCL-ФОРМИ-ГАРАЗД GTK2=так коренів=3 ',
    'один-фізичний-файл=так точні-трити=так точні-байти=так ',
    'CLI-паритет=так негативні=відхилено таблиця=атомарна');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — форми двійкового файлу';
    Application.CreateForm(TFormWindow,Window);
    if (ParamCount=8) and
       (ParamStr(1)=#$2D#$2D#$D1#$81#$D0#$B0#$D0#$BC#$D0#$BE#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$BA#$D0#$B0) then
      SelfTest
    else if ParamCount=0 then Application.Run
    else begin
      WriteLn(StdErr,'Використання: sens-formas [--самоперевірка файли та результати]');
      Halt(64);
    end;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-ФОРМИ-ПОМИЛКА: ',E.Message);
    Halt(2);
  end; end;
end.
