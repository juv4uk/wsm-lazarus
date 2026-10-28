{ Справжнє Lazarus-вікно для незалежних фізичних файлів SENS.
  Тільки наявний TBinaryExecutor; жодного другого мовного runtime. }
program sens_batch;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, wsm.batchpanel;
var Window:TBatchForm;

procedure Require(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('пакетний GUI: '+Why);
end;

procedure SelfTest;
var
  Files:array of String;
  Expected1,Expected2,Proof:RawByteString;
  Refused:Boolean;
begin
  Require(Window.HasWidgets,'немає реального вибору кількох файлів або таблиці');
  Expected1:=RawByteString(ParamStr(6));
  Expected2:=RawByteString(ParamStr(7));
  SetLength(Files,2);
  Files[0]:=ParamStr(2); Files[1]:=ParamStr(3);
  Require(Window.ExecuteFiles(Files),'не виконано двох фізичних .sens');
  Require(Window.ResultCount=2,'число підтверджених файлів');
  Require(Window.ResultAt(0)=Expected1,'результат першого файлу відмінний від CLI');
  Require(Window.ResultAt(1)=Expected2,'результат другого файлу відмінний від CLI');
  Proof:=Window.Evidence;
  Require(Pos('Результат D1/D3',Proof)>0,'втрачено заголовок TSV');
  Require(Pos('1'#9,Proof)>0,'відсутній перший фізичний рядок');
  Require(Pos('2'#9,Proof)>0,'відсутній другий фізичний рядок');

  Files[1]:=ParamStr(4); { невідома двійкова цитата після валідного файлу }
  Require(not Window.ExecuteFiles(Files),'непідтверджений D3 допущено');
  Require((Window.Evidence='') and (Window.ResultCount=0),
    'частковий результат першого файлу видно після відмови другого');
  Require(Pos('файл №2',Window.StatusText)>0,
    'відмова втратила номер фізичного файлу');
  Require(Pos('слово 2',Window.StatusText)>0,
    'відмова втратила точний номер D3-слова');

  Files[1]:=ParamStr(5); { T5M invalid byte 243 }
  Require(not Window.ExecuteFiles(Files),'неканонічний T5M допущено');
  Require((Window.ResultCount=0) and (Window.Evidence=''),
    'пошкоджений T5M опублікував попередній результат');
  Require(Pos('слово 0',Window.StatusText)>0,
    'пошкоджені байти втратили свій код фізичної позиції');

  Files[1]:='немає-програми.sens';
  Require(not Window.ExecuteFiles(Files),'відсутній файл допущено');
  Require((Window.ResultCount=0) and (Window.Evidence=''),
    'відсутній файл залишив результати');
  Files[1]:='текст.lisp';
  Require(not Window.ExecuteFiles(Files),'людську .lisp прийнято за фізичну .sens');
  Require(Window.ResultCount=0,'текстова проєкція породила бінарний результат');

  SetLength(Files,0);
  Require(not Window.ExecuteFiles(Files),'нуль файлів допущено');
  SetLength(Files,MaxBatchFiles+1);
  Require(not Window.ExecuteFiles(Files),'17 файлів прийнято');
  Require(Window.ResultCount=0,'кількісна відмова не очищає таблицю');

  Refused:=False;
  try Window.ResultAt(0);
  except on E:Exception do Refused:=True; end;
  Require(Refused,'індекс порожньої таблиці допускається');

  SetLength(Files,2);
  Files[0]:=ParamStr(2); Files[1]:=ParamStr(3);
  Require(Window.ExecuteFiles(Files),'після негативних спроб GUI не відновився');
  Require(Window.Evidence=Proof,'повторна фізична програма дала інший TSV');
  Window.Show;
  Window.Repaint;
  Application.ProcessMessages;
  WriteLn('LCL-ПАКЕТ-ГАРАЗД GTK2=так фізичних-файлів=2 ',
    'окремі-D1-D3=CLI-паритет розділення-stdin=не-використано ',
    'заборонений-T5M=відхилено quote=відхилено ',
    'часткових-рядків=0 відновлення=так Core4=ні REPL=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — декілька фізичних програм';
    Application.CreateForm(TBatchForm,Window);
    if (ParamCount=7) and (ParamStr(1)='--самоперевірка') then
      SelfTest
    else if ParamCount=0 then Application.Run
    else begin
      WriteLn(StdErr,'Використання: sens-batch [--самоперевірка параметри]');
      Halt(64);
    end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-ПАКЕТ-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
