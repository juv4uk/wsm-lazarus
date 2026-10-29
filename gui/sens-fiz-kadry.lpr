{ G5.61 — Lazarus/LCL клієнт ЖИВОГО фізичного двійкового сеансу.
  Процес sensfizseans є єдиним виконавцем D3. Це приватний host
  протокол, НЕ нова форма SENS і НЕ загальний REPL/Core4. }
program sens_fiz_kadry;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls,
  Dialogs, Process, wsm.t5m, wsm.proektsii, wsm.domain;

const MaxPacket=65536;
type
  TFizWindow=class(TForm)
  private
    FWorker:TProcess;
    FPath:TEdit;
    FRun:TButton;
    FJournal:TMemo;
    FState:TLabel;
    FDialog:TOpenDialog;
    FCatalog:TProektsiiCatalog;
    FSuccess,FRefused:SizeInt;
    FLast:RawByteString;
    procedure RunClicked(Sender:TObject);
    procedure BrowseClicked(Sender:TObject);
    function ReadExact(Count:SizeInt):RawByteString;
    procedure Demand(OK:Boolean;const Reason:String);
    procedure ShowExact(const ResultWords:TExactWords);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure Connect(const Executable:String);
    procedure ExecuteFile(const Path:String);
    procedure SelfCheck(const Good,Bad,D7,TextFile:String);
  end;
var W:TFizWindow;

constructor TFizWindow.Create(AOwner:TComponent);
var Choose:TButton;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — живий фізичний сеанс у Lazarus';
  Width:=1070; Height:=670; Position:=poScreenCenter;
  FWorker:=nil; FSuccess:=0; FRefused:=0;FLast:='';
  FPath:=TEdit.Create(Self);
  FPath.Parent:=Self; FPath.SetBounds(12,14,760,30);
  FPath.Text:='програма.sens';
  FRun:=TButton.Create(Self);
  FRun.Parent:=Self; FRun.SetBounds(784,12,255,34);
  FRun.Caption:='Виконати канонічний .sens';
  FRun.Enabled:=False;
  FRun.OnClick:=@RunClicked;
  Choose:=TButton.Create(Self);
  Choose.Parent:=Self;Choose.SetBounds(12,52,250,32);
  Choose.Caption:='Вибрати фізичний файл';
  Choose.OnClick:=@BrowseClicked;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Двійкові SENS|*.sens';
  FState:=TLabel.Create(Self);
  FState.Parent:=Self;FState.SetBounds(274,58,760,25);
  FState.Caption:='Виконавець не підключений';
  FJournal:=TMemo.Create(Self);
  FJournal.Parent:=Self;FJournal.SetBounds(12,96,1026,520);
  FJournal.ReadOnly:=True;FJournal.WordWrap:=False;
  FJournal.ScrollBars:=ssBoth;
end;

destructor TFizWindow.Destroy;
begin
  if FWorker<>nil then begin
    if FWorker.Running then begin
      FWorker.Terminate(1);
      FWorker.WaitOnExit;
    end;
    FWorker.Free;
  end;
  inherited Destroy;
end;

procedure TFizWindow.Demand(OK:Boolean;const Reason:String);
begin
  if not OK then raise Exception.Create('ЛКЛ-ФІЗИЧНА-ПЕРЕВІРКА: '+Reason);
end;

procedure TFizWindow.Connect(const Executable:String);
begin
  Demand(FWorker=nil,'повторний запуск виконавця');
  LoadPinnedProjections('external/sens',FCatalog);
  FWorker:=TProcess.Create(nil);
  try
    FWorker.Executable:=Executable;
    FWorker.CurrentDirectory:=GetCurrentDir;
    FWorker.Parameters.Add(
      #$2D#$2D#$D1#$81#$D0#$B5#$D0#$B0#$D0#$BD#$D1#$81);
    FWorker.Options:=[poUsePipes];
    FWorker.Execute;
    Demand(FWorker.Running,'дочірній процес не запустився');
  except
    FreeAndNil(FWorker);
    raise;
  end;
  FRun.Enabled:=True;
  FState.Caption:='Підключено фізичний виконавець PID='+
    IntToStr(FWorker.ProcessID);
end;

procedure TFizWindow.RunClicked(Sender:TObject);
begin
  ExecuteFile(FPath.Text);
end;

procedure TFizWindow.BrowseClicked(Sender:TObject);
begin
  if FDialog.Execute then FPath.Text:=FDialog.FileName;
end;

{ Pipe читається у власну RawByteString; перевіряються точна довжина,
  живий PID і часовий бюджет, не припускається один Read = один кадр.
  Блокування UI обмежено 8 с; це ще не асинхронний debugger.
  Питання: чому NumBytesAvailable? Де межа кадру? Хто володіє
  рядком? Чому time limit не визначає закон SENS? }
function TFizWindow.ReadExact(Count:SizeInt):RawByteString;
var Used,Available,Take,Got:SizeInt; Deadline:QWord;
begin
  Demand((Count>0) and (Count<=MaxPacket),'порушено квоту відповіді');
  SetLength(Result,Count);
  Used:=0; Deadline:=GetTickCount64+8000;
  while Used<Count do begin
    Available:=FWorker.Output.NumBytesAvailable;
    if Available>0 then begin
      Take:=Count-Used;
      if Take>Available then Take:=Available;
      Got:=FWorker.Output.Read(Result[Used+1],Take);
      Demand(Got>0,'обірвано фізичну відповідь');
      Inc(Used,Got);
    end else begin
      Demand(FWorker.Running,'виконавець завершився до кінця кадру');
      Demand(GetTickCount64<Deadline,'перевищено час host-відповіді');
      Sleep(5);
    end;
  end;
end;

procedure TFizWindow.ShowExact(const ResultWords:TExactWords);
const Names:array[0..5] of String=
  ('ук','укр','san','en','LISP','sym');
var I,J,K:SizeInt;S:String;Key:TDomainKey;
begin
  S:='';
  for I:=0 to High(ResultWords) do begin
    if S<>'' then S:=S+' ';
    S:=S+String(ResultWords[I]);
  end;
  FJournal.Lines.Add('Точні фізичні слова: '+S);
  for I:=0 to High(ResultWords) do if Length(ResultWords[I])=7 then begin
    Key:=ExactKey(ResultWords[I]);
    K:=Key.Bits;
    Demand((K>=0) and (K<Length(FCatalog[7])) and
      SameKey(FCatalog[7][K].Key,Key),'D7 поза pinned таблицею');
    FJournal.Lines.Add('D7:'+String(ResultWords[I])+' — тільки дані');
    for J:=0 to 5 do
      FJournal.Lines.Add(Names[J]+'='+
        SurfaceForDisplay(FCatalog[7][K].Surface[J]));
  end;
end;

{ Механічна host-рамка не додає семантики: FWorker виконує
  лише чинний TBinaryExecutor; status byte НЕ є значенням D1.
  Фізичні байти фізичної відповіді FLast належать формі до
  наступного натискання. На відмові очищаються перед рендером.
  Питання: чому .lisp не приймається? Що гарантує D7 таблиця?
  Чому діагностика не є D3:000? Хто виконує реальну форму? }
procedure TFizWindow.ExecuteFile(const Path:String);
var Stream:TFileStream; Physical,Frame,Head,Payload:RawByteString;
    Size:QWord; WordAt:QWord; Status:Byte; Words:TExactWords; I:SizeInt;
begin
  FLast:='';
  if (FWorker=nil) or not FWorker.Running then begin
    FJournal.Lines.Add('Відмова: немає живого фізичного виконавця');
    Exit;
  end;
  if LowerCase(ExtractFileExt(Path))<>'.sens' then begin
    FJournal.Lines.Add('Відмова: .lisp — лише проєкція; потрібен .sens');
    Exit;
  end;
  try
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      Demand((Stream.Size>0) and (Stream.Size<=MaxPacket),
        'фізичний файл поза бюджетом');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free;end;
    Size:=Length(Physical);
    SetLength(Frame,SizeInt(Size)+4);
    for I:=0 to 3 do Frame[I+1]:=AnsiChar(Byte((Size shr (I*8)) and $FF));
    Move(Physical[1],Frame[5],SizeInt(Size));
    FWorker.Input.WriteBuffer(Frame[1],Length(Frame));
    Head:=ReadExact(9);
    Status:=Ord(Head[1]);
    WordAt:=0; Size:=0;
    for I:=0 to 3 do begin
      WordAt:=WordAt or (QWord(Ord(Head[2+I])) shl (I*8));
      Size:=Size or (QWord(Ord(Head[6+I])) shl (I*8));
    end;
    Demand((Status<=1) and (Size>0) and (Size<=MaxPacket),
      'пошкоджений заголовок host-відповіді');
    Payload:=ReadExact(SizeInt(Size));
    if Status=0 then begin
      Demand(WordAt=0,'неправильний індекс успішної відповіді');
      DecodeT5M(Payload,Words);
      FLast:=Payload;
      Inc(FSuccess);
      FJournal.Lines.Add('Виконано: канонічний T5M, байтів='+
        IntToStr(Length(Payload)));
      ShowExact(Words);
    end else begin
      Inc(FRefused);
      FJournal.Lines.Add('Відхилено слово='+IntToStr(WordAt)+
        ': '+String(Payload));
    end;
    FState.Caption:='Один живий PID='+IntToStr(FWorker.ProcessID)+
      '; виконано='+IntToStr(FSuccess)+
      '; відхилено='+IntToStr(FRefused);
  except on E:Exception do begin
    FLast:='';
    FJournal.Lines.Add('Пошкодження host-кадру/входу: '+E.Message);
    { Відновлювати довіру до розсинхронізованого pipe заборонено. }
    FRun.Enabled:=False;
    if FWorker<>nil then if FWorker.Running then FWorker.Terminate(1);
  end;end;
end;

procedure TFizWindow.SelfCheck(const Good,Bad,D7,TextFile:String);
var PID:TProcessID; First,ResultD7:RawByteString;
begin
  Demand((FWorker<>nil) and FWorker.Running,'немає живого PID');
  PID:=FWorker.ProcessID;
  FPath.Text:=Good; FRun.Click;
  Demand((FSuccess=1) and (FRefused=0) and
    (Pos('Точні фізичні слова: 1',FJournal.Text)>0),
    'перша реальна D3 цитата не виконана');
  First:=FLast;
  Demand((First<>'') and FWorker.Running,'немає фізичної відповіді');
  FPath.Text:=Bad; FRun.Click;
  Demand((FSuccess=1) and (FRefused=1) and (FLast='') and
    (Pos('Відхилено слово=0',FJournal.Text)>0),
    'некоректний T5M не дав позиційної відмови');
  FPath.Text:=D7;FRun.Click;
  ResultD7:=FLast;
  Demand((FSuccess=2) and (FRefused=1) and
    (Pos('D7:0010110',FJournal.Text)>0) and
    (Pos('ук=(відсутня)',FJournal.Text)>0) and
    (Pos('LISP=(відсутня)',FJournal.Text)>0),
    'точний D7 SYN не відображено як pinned дані');
  FPath.Text:=TextFile;FRun.Click;
  Demand((FSuccess=2) and (FRefused=1) and
    (FLast='') and (Pos('.lisp — лише проєкція',FJournal.Text)>0),
    '.lisp помилково прийнято як фізичну програму');
  FPath.Text:=Good;FRun.Click;
  Demand((FSuccess=3) and (FRefused=1) and
    (FLast=First) and (ResultD7<>First) and
    (FWorker.ProcessID=PID) and FWorker.Running,
    'не збережено живий PID і точну відновлену відповідь');
  WriteLn('ЛКЛ-ФІЗИЧНІ-КАДРИ-ГАРАЗД PID=той-самий',
    ' GUI-кліків=5 виконано=3 відмов=1',
    ' D7=SYN pinned-проєкцій=6 byte-exact=так',
    ' .lisp=відхилено REPL=НЕ-ГОТОВИЙ');
end;

begin
  Application.Initialize;
  W:=TFizWindow.Create(nil);
  try
    if (ParamCount=6) and
       (RawByteString(ParamStr(1))=
         #$2D#$2D#$D1#$81#$D0#$B0#$D0#$BC#$D0#$BE#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B2#$D1#$96#$D1#$80#$D0#$BA#$D0#$B0) then begin
      W.Connect(ParamStr(2));
      W.SelfCheck(ParamStr(3),ParamStr(4),ParamStr(5),ParamStr(6));
    end else if ParamCount=0 then begin
      W.Connect('build/m0.2/fizseans-bin/sensfizseans');
      W.Show;
      Application.Run;
    end else raise Exception.Create('використання: --самоперевірка виконавець добрий.sens поганий.sens d7.sens текст.lisp');
  except
    on E:Exception do begin
      WriteLn(StdErr,'ЛКЛ-ФІЗИЧНІ-КАДРИ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
  W.Free;
end.
