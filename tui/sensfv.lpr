{ SENS / Free Vision. Вікно над чинним Core1 REPL, не новий runtime.
  Канонічний .sens тут не читається: ввід — українська проєкція. }
program sensfv;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, Objects, Drivers, Views, Menus, Dialogs, App,
     sensfvbridge;
const
  cmSensEval = 1101;
  MaxHistoryRows = 150;
type
  PSensInput = ^TSensInput;
  TSensInput = object(TInputLine)
    procedure HandleEvent(var Event: TEvent); virtual;
  end;
  PSensWindow = ^TSensWindow;
  TSensWindow = object(TWindow)
    Input: PSensInput;
    HistoryView: PListBox;
    History: Classes.TStringList;
    constructor Init(var Bounds: TRect);
    destructor Done; virtual;
    procedure AppendLine(const Text: RawByteString);
    procedure HandleEvent(var Event:TEvent); virtual;
  end;
  TSensApp = object(TApplication)
    Window: PSensWindow;
    constructor Init;
    procedure InitMenuBar; virtual;
    procedure InitStatusLine; virtual;
    procedure Idle; virtual;
  end;
var
  Bridge: TSensFVBridge;
  ConsoleApp: TSensApp;

procedure TSensInput.HandleEvent(var Event:TEvent);
begin
  if (Event.What=evKeyDown) and (Event.KeyCode=kbEnter) then begin
    Message(Owner,evCommand,cmSensEval,nil);
    ClearEvent(Event);
    Exit;
  end;
  inherited HandleEvent(Event);
end;

constructor TSensWindow.Init(var Bounds:TRect);
var R:TRect;
begin
  inherited Init(Bounds,'SENS — Free Vision / Core1',wnNoNumber);
  Options := Options or ofTileable;
  History := Classes.TStringList.Create;
  R.Assign(2,1,Size.X-2,Size.Y-4);
  HistoryView := New(PListBox,Init(R,1,nil));
  Insert(HistoryView);
  R.Assign(2,Size.Y-3,Size.X-2,Size.Y-2);
  Input := New(PSensInput,Init(R,240));
  Insert(Input);
  Input^.Select;
  AppendLine('SENS: існуючий Core1 REPL, D24, pinned Contract 12');
  AppendLine('Ввід — UTF-8 проєкція, до 240 байтів. Alt+X — вихід.');
end;

destructor TSensWindow.Done;
begin
  History.Free;
  inherited Done;
end;

procedure TSensWindow.AppendLine(const Text:RawByteString);
var I:Integer; Items:PUnSortedStrCollection; Line:RawByteString;
begin
  if History.Count>=MaxHistoryRows then History.Delete(0);
  { Рендеринг Unicode на SSH перевіряється окремим PTY smoke. }
  Line := SafeTerminalText(Text);
  if Length(Line)>220 then Line:=Copy(Line,1,220);
  History.Add(String(Line));
  Items:=New(PUnSortedStrCollection,Init(32,16));
  for I:=0 to History.Count-1 do Items^.Insert(NewStr(History[I]));
  HistoryView^.NewList(Items);
  HistoryView^.FocusItem(History.Count-1);
end;

procedure TSensWindow.HandleEvent(var Event:TEvent);
var Command:RawByteString;
begin
  inherited HandleEvent(Event);
  if (Event.What=evCommand) and (Event.Command=cmSensEval) then begin
    Command:=RawByteString(Input^.Data^);
    Input^.Data^:='';
    Input^.CurPos:=0;
    Input^.FirstPos:=0;
    Input^.SelStart:=0;
    Input^.SelEnd:=0;
    Input^.DrawView;
    if Command<>'' then begin
      try
        Bridge.Send(Command);
        AppendLine('> '+Command);
      except
        on E:Exception do AppendLine('; помилка вводу: '+RawByteString(E.Message));
      end;
    end;
    ClearEvent(Event);
  end;
end;

constructor TSensApp.Init;
var R:TRect;
begin
  inherited Init;
  Desktop^.GetExtent(R);
  Window:=New(PSensWindow,Init(R));
  Desktop^.Insert(Window);
end;

procedure TSensApp.InitMenuBar;
var R:TRect;
begin
  GetExtent(R);
  R.B.Y:=R.A.Y+1;
  MenuBar:=New(PMenuBar,Init(R,NewMenu(
    NewSubMenu('~S~ENS',hcNoContext,NewMenu(
      NewItem('~В~ихід','Alt+X',kbAltX,cmQuit,hcNoContext,nil)
    ),nil)
  )));
end;

procedure TSensApp.InitStatusLine;
var R:TRect;
begin
  GetExtent(R);
  R.A.Y:=R.B.Y-1;
  StatusLine:=New(PStatusLine,Init(R,
    NewStatusDef(0,$FFFF,
      NewStatusKey('~F10~ меню',kbF10,cmMenu,
      NewStatusKey('~Enter~ виконати',kbEnter,cmSensEval,
      NewStatusKey('~Alt+X~ вихід',kbAltX,cmQuit,nil))),nil)));
end;

procedure TSensApp.Idle;
var Line:RawByteString; IsError:Boolean;
begin
  inherited Idle;
  Bridge.Poll;
  while Bridge.PopLine(Line,IsError) do begin
    if IsError then Window^.AppendLine('! '+Line)
    else Window^.AppendLine(Line);
  end;
end;

function WaitForLine(const Expected:RawByteString; MaxMillis:QWord):Boolean;
var Since:QWord; Line:RawByteString; Err:Boolean;
begin
  Result:=False;
  Since:=GetTickCount64;
  repeat
    Bridge.Poll;
    while Bridge.PopLine(Line,Err) do
      if (not Err) and (Line=Expected) then Exit(True);
    if Bridge.Finished then Exit(False);
    Sleep(5);
  until GetTickCount64-Since>=MaxMillis;
end;

function WaitForError(MaxMillis:QWord):Boolean;
var Since:QWord; Line:RawByteString; Err:Boolean;
begin
  Result:=False;
  Since:=GetTickCount64;
  repeat
    Bridge.Poll;
    while Bridge.PopLine(Line,Err) do begin
      WriteLn(StdErr,'FV-RESPONSE-',Ord(Err),' ',Line);
      if Err and (Pos('; помилка:',String(Line))>0) then Exit(True);
    end;
    if Bridge.Finished then Exit(False);
    Sleep(5);
  until GetTickCount64-Since>=MaxMillis;
end;

function WaitUntilReady(MaxMillis:QWord):Boolean;
var Since:QWord; Line:RawByteString; Err:Boolean;
begin
  Result:=False;
  Since:=GetTickCount64;
  repeat
    Bridge.Poll;
    while Bridge.PopLine(Line,Err) do
      WriteLn(StdErr,'FV-STARTUP-',Ord(Err),' ',Line);
    if Bridge.Ready then Exit(True);
    if Bridge.Finished then Exit(False);
    Sleep(5);
  until GetTickCount64-Since>=MaxMillis;
end;

procedure SelfTest;
begin
  if ValidInputUTF8(#$C0#$AF) then
    raise Exception.Create('помилково прийнято overlong UTF-8');
  if ValidInputUTF8(#$D0) then
    raise Exception.Create('помилково прийнято обрізаний UTF-8');
  if ValidInputUTF8(#27+'[31m') then
    raise Exception.Create('помилково прийнято ANSI escape');
  if not ValidInputUTF8('(додати 2 3)') then
    raise Exception.Create('відхилено коректний вхід');
  if not WaitUntilReady(20000) then
    raise Exception.Create('Core1 REPL не дав завершеного початкового світу');
  Bridge.Send('(додати 2 3)');
  if not WaitForLine('5',7000) then
    raise Exception.Create('перший обчислений результат не дорівнює 5');
  Bridge.Send('(додати 2 3)');
  if not WaitForLine('5',7000) then
    raise Exception.Create('повторний результат не дорівнює 5');
  Bridge.Send('(додати 2)');
  if not WaitForError(15000) then
    raise Exception.Create('недопустима арність не викликала діагностики');
  Bridge.Send('(додати 2 3)');
  if not WaitForLine('5',7000) then
    raise Exception.Create('сесія не відновилася після помилки');
  WriteLn('FREEVISION-CORE1-SMOKE-OK checks=8 backend=real-Core1',
    ' input=utf8-bounded fv=link-only terminal-unicode=NOT_VERIFIED');
end;

begin
  if ParamCount < 2 then begin
    WriteLn(StdErr,'Використання: sensfv [--selftest] <шлях-repl> <корінь-проєкту>');
    Halt(2);
  end;
  try
    if ParamStr(1)='--selftest' then begin
      if ParamCount<>3 then raise Exception.Create('selftest потребує 2 шляхи');
      Bridge:=TSensFVBridge.Create(ParamStr(2),ParamStr(3));
      try SelfTest; finally Bridge.Free; end;
    end else begin
      if ParamCount<>2 then raise Exception.Create('потрібно 2 шляхи');
      Bridge:=TSensFVBridge.Create(ParamStr(1),ParamStr(2));
      try
        ConsoleApp.Init;
        ConsoleApp.Run;
        ConsoleApp.Done;
      finally Bridge.Free; end;
    end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'FREEVISION-CORE1-FAIL ',E.Message);
      Halt(1);
    end;
  end;
end.
