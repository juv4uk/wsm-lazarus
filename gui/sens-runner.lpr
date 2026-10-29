{ Справжня графічна Lazarus-програма для перевіреного нативного D3.
  Без текстового перекодування фізичного .sens на вході та власного eval. }
program sens_runner;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, wsm.runpanel;
var Window: TSensRunForm;
begin
  try
    Application.Initialize;
    Application.Title := 'SENS — нативне виконання';
    Application.CreateForm(TSensRunForm,Window);
    if (ParamCount=7) and (ParamStr(1)='--самоперевірка') then begin
      Window.Show;
      Application.ProcessMessages;
      Window.SmokeTest(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5),
        ParamStr(6),ParamStr(7));
      Window.Free;
    end else if (ParamCount=14) and
      (ParamStr(1)='--самоперевірка-пакета') then begin
      Window.SmokeTestBatch(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9),
        ParamStr(10),ParamStr(11),ParamStr(12),ParamStr(13),
        ParamStr(14));
      Window.Free;
    end else if (ParamCount=9) and
      (ParamStr(1)='--самоперевірка-проєкцій') then begin
      Window.SmokeTestProjections(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9));
      Window.Free;
    end else if (ParamCount=7) and
      (ParamStr(1)='--самоперевірка-збереження') then begin
      Window.SmokeTestSave(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;
    end else if (ParamCount=9) and
      (ParamStr(1)='--самоперевірка-канал') then begin
      Window.SmokeTestChannel(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9));
      Window.Free;
    end else if (ParamCount=9) and
      (ParamStr(1)='--самоперевірка-укр') then begin
      Window.SmokeTestUkr(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9));
      Window.Free;
    end else if (ParamCount=3) and (ParamStr(1)='--канал') then begin
      Window.ConnectChannel(ParamStr(2),ParamStr(3));
      Application.Run;
    end else if ParamCount=0 then begin
      Application.Run;
    end else if ParamCount=1 then begin
      Window.ExecuteFile(ParamStr(1));
      Application.Run;
    end else begin
      WriteLn(StdErr,'Використання: sens-runner [файл.sens] ', 
        'або sens-runner --канал ROOT шлях-до-senspotikd3');
      Halt(64);
    end;
  except
    on E: Exception do begin
      WriteLn(StdErr,'LCL-ВИКОНАННЯ-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
