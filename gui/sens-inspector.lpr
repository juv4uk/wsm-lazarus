{ Графічний інспектор фізичного потоку SENS — окремий LCL клієнт.
  Тільки верифікований T5M/D2, не REPL та не виконавець семантики. }
program sens_inspector;
{$mode objfpc}{$H+}

uses
  Interfaces, Forms, SysUtils, wsm.inspectorform, wsm.d2source, wsm.t5m;

var
  Inspector: TInspectorForm;

procedure Check(Condition: Boolean; const MessageText: String);
begin
  if not Condition then
    raise Exception.Create('перевірка інтерфейсу: ' + MessageText);
end;

procedure SelfTest;
var
  BeforePath, BeforeEvidence: String;
  BeforeWords: Integer;
  Rejected: Boolean;
begin
  Check(ParamCount = 5, 'потрібні 4 фізичні тестові файли');
  Inspector.InspectFile(ParamStr(2));
  Check(Inspector.WordCount = 3, 'кількість точних слів');
  Check(Pos('D1:0', Inspector.WordCaption(0)) > 0, 'втрачено D1:0');
  Check(Pos('D2:00', Inspector.WordCaption(1)) > 0, 'втрачено D2:00');
  Check(Pos('D3:000', Inspector.WordCaption(2)) > 0, 'втрачено D3:000');
  Check(Inspector.RootCount = 2, 'потрібно дві різні структури');
  Check(Pos('D3:000', Inspector.Evidence) > 0, 'звіту бракує D3');
  Inspector.InspectFile(ParamStr(4));
  Check(Inspector.WordCount = 3, 'D2 список: кількість фізичних слів');
  Check(Inspector.RootCount = 2, 'D2 список: корінь та елемент');
  BeforePath := Inspector.CurrentPath;
  BeforeWords := Inspector.WordCount;
  BeforeEvidence := Inspector.Evidence;

  Rejected := False;
  try Inspector.InspectFile(ParamStr(3));
  except on E: ET5MError do Rejected := True; end;
  Check(Rejected, 'пошкоджений T5M мав бути відхилений');
  Check(Inspector.CurrentPath = BeforePath, 'змінено шлях після T5M-помилки');
  Check(Inspector.WordCount = BeforeWords, 'змінено слова після T5M-помилки');
  Check(Inspector.Evidence = BeforeEvidence, 'змінено звіт після T5M-помилки');

  Rejected := False;
  try Inspector.InspectFile(ParamStr(5));
  except on E: ED2SourceError do Rejected := True; end;
  Check(Rejected, 'пошкоджений D2 мав бути відхилений');
  Check(Inspector.CurrentPath = BeforePath, 'змінено шлях після D2-помилки');
  Check(Inspector.Evidence = BeforeEvidence, 'змінено звіт після D2-помилки');
  WriteLn('LCL-ІНСПЕКТОР-ГАРАЗД вікно=GTK2 слова=D1,D2,D3 дерево=D2 ',
    'помилки=відхилено стан=збережено виконання=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — фізичний інспектор';
    Application.CreateForm(TInspectorForm, Inspector);
    if (ParamCount > 0) and (ParamStr(1) = '--самоперевірка') then begin
      SelfTest;
      Inspector.Free;
    end else begin
      if ParamCount = 1 then Inspector.InspectFile(ParamStr(1))
      else if ParamCount > 1 then
        raise Exception.Create('використання: інспектор [файл.sens]');
      Application.Run;
    end;
  except
    on E: Exception do begin
      WriteLn(StdErr, 'LCL-ІНСПЕКТОР-ПОМИЛКА: ', E.Message);
      Halt(2);
    end;
  end;
end.
