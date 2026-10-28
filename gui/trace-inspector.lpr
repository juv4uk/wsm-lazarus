{ Демонстраційний справжній LCL-клієнт фізичного snapshot стека.
  Програма не запускає жодного виклику або визначення SENS. }
program sens_trace_viewer;
{$mode objfpc}{$H+}
uses
  Interfaces, Forms, SysUtils, wsm.tracegrid, wsm.debugtrace, wsm.domain;

var
  Window: TTraceViewerForm;
  Snapshot: TDebugFrames;

procedure Demand(Condition: Boolean; const Details: String);
begin
  if not Condition then
    raise Exception.Create('фізична GUI-перевірка: ' + Details);
end;

procedure CheckViewer;
var
  Prior: RawByteString;
  Invalid: TDebugFrames;
  Rejected: Boolean;
begin
  Demand(Window.TraceGrid.FrameCount = 2, 'повинно бути два кадри');
  Demand(Window.TraceGrid.Cell(1,1) = 'D3', 'порядок D3');
  Demand(Window.TraceGrid.Cell(2,1) = '000', 'точне D3:000');
  Demand(Window.TraceGrid.Cell(1,2) = 'D1', 'порядок D1');
  Demand(Window.TraceGrid.Cell(2,2) = '0', 'точне D1:0');
  Demand(Window.TraceGrid.Cell(3,1) = '11', 'байтовий зсув кадру');
  Demand(Window.TraceGrid.Cell(4,1) = '2', 'рядок кадру');
  Demand(Window.TraceGrid.Cell(5,1) = '5', 'стовпець кадру');
  Prior := Window.TraceGrid.Evidence;
  Demand(Pos('домен D3, слово 000', Prior) > 0, 'експорт точного слова');
  Invalid := Copy(Snapshot, 0, Length(Snapshot));
  Invalid[1].Key.Width := 0;
  Rejected := False;
  try Window.LoadFrames(Invalid);
  except on E: ETraceGridError do Rejected := True; end;
  Demand(Rejected, 'нульову ширину домену не відхилено');
  Demand(Window.TraceGrid.Evidence = Prior, 'змінено таблицю після поганого домену');
  Invalid := Copy(Snapshot, 0, Length(Snapshot));
  Invalid[0].ByteColumn := 0;
  Rejected := False;
  try Window.LoadFrames(Invalid);
  except on E: ETraceGridError do Rejected := True; end;
  Demand(Rejected, 'нульовий стовпець не відхилено');
  Demand(Window.TraceGrid.Evidence = Prior, 'змінено таблицю після поганої позиції');
  SetLength(Invalid, MaxTraceDepth + 1);
  Rejected := False;
  try Window.LoadFrames(Invalid);
  except on E: ETraceGridError do Rejected := True; end;
  Demand(Rejected, 'завеликий стек не відхилено');
  Demand(Window.TraceGrid.Evidence = Prior, 'змінено таблицю після переповнення');
  SetLength(Invalid, 0);
  Rejected := False;
  try Window.LoadFrames(Invalid);
  except on E: ETraceGridError do Rejected := True; end;
  Demand(Rejected, 'порожній стек не відхилено');
  Demand(Window.TraceGrid.Evidence = Prior, 'змінено таблицю після порожнього стека');
  WriteLn('LCL-СТЕК-ГАРАЗД GTK2=так D1:0_не_дорівнює_D3:000 ',
    'top-first=так snapshot=незалежний негативні=відхилено виконання=ні');
end;

procedure InitializeSnapshot;
var
  Physical: TDebugTrace;
  FirstToken, SecondToken: TDebugToken;
begin
  Physical := TDebugTrace.Create;
  try
    FirstToken := Physical.Push(ExactKey('0'), 3, 1, 3);
    SecondToken := Physical.Push(ExactKey('000'), 11, 2, 5);
    Snapshot := Physical.Snapshot;
    Physical.Pop(SecondToken);
    Physical.Pop(FirstToken);
  finally
    Physical.Free;
  end;
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — візуальний фізичний стек';
    Application.CreateForm(TTraceViewerForm, Window);
    InitializeSnapshot;
    Window.LoadFrames(Snapshot);
    if (ParamCount = 1) and (ParamStr(1) = '--самоперевірка') then
      CheckViewer
    else if ParamCount = 0 then
      Application.Run
    else
      raise Exception.Create('використання: trace-inspector [--самоперевірка]');
  except
    on E: Exception do begin
      WriteLn(StdErr, 'LCL-СТЕК-ПОМИЛКА: ', E.Message);
      Halt(2);
    end;
  end;
end.
