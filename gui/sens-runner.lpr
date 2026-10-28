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
    end else if ParamCount=0 then begin
      Application.Run;
    end else if ParamCount=1 then begin
      Window.ExecuteFile(ParamStr(1));
      Application.Run;
    end else begin
      WriteLn(StdErr,'Використання: sens-runner [файл.sens]');
      Halt(64);
    end;
  except
    on E: Exception do begin
      WriteLn(StdErr,'LCL-ВИКОНАННЯ-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
