{ G3.49 — справжнє Lazarus/LCL вікно над ОДНИМ фізичним Core1 сеансом.
  Увесь виклик виконує вже злитий senscore1seans / pinned core1.sens.
  u32le/status — лише приватний host транспорт, НЕ мова SENS чи D1.
  Українська .lisp — людська укр проєкція; вхід тільки packed .sens.
  Це не загальний Core1 REPL, GC або нове визначення мовного закону. }
program sens_core1_seans_okno;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Dialogs,
  Grids, Process, wsm.t5m;

const MaxFrame = 65536;

type
  TSeansWindow = class(TForm)
  private
    FWorker:TProcess;                    { owned; ОДИН дочірній процес }
    FPath:TEdit;
    FChoose,FExecute:TButton;
    FFiles:TOpenDialog;
    FGrid:TStringGrid;
    FDetail:TMemo;
    FState:TLabel;
    FLastAnswer:RawByteString;          { owned canonical packed T5M }
    FRows,FSuccess,FReject,FRemoteReject:SizeInt;
    procedure Need(Condition:Boolean;const Why:String);
    procedure PathChanged(Sender:TObject);
    procedure ChooseClick(Sender:TObject);
    procedure ExecuteClick(Sender:TObject);
    procedure AddRow(const StateText,WordText:String);
    function ReadPhysical(const FileName:String):RawByteString;
    procedure WriteFrame(const Physical:RawByteString);
    function ReadExact(var Dest;Count:SizeInt):Boolean;
    function ReadReply(out Physical:RawByteString;
      out Diagnostic:RawByteString):Boolean;
    function RunCurrent:Boolean;
    procedure CheckFixture(const FileName:String;ShouldSucceed:Boolean;
      const Expected:RawByteString);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure Connect(const ExecutablePath,WorkspaceRoot:String);
    procedure SelfCheck(const Fixtures:String);
  end;

var Window:TSeansWindow;

constructor TSeansWindow.Create(AOwner:TComponent);
var L:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — довгоживучий фізичний сеанс Core1';
  Width:=1100;Height:=720;Position:=poScreenCenter;
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(12,8,1060,25);
  L.Caption:='Канон — двійковий .sens (T5M); .lisp — тільки українська укр проєкція.';
  FPath:=TEdit.Create(Self);FPath.Parent:=Self;FPath.SetBounds(12,45,745,30);
  FChoose:=TButton.Create(Self);FChoose.Parent:=Self;
  FChoose.SetBounds(770,45,130,30);FChoose.Caption:='Обрати .sens';
  FChoose.OnClick:=@ChooseClick;
  FExecute:=TButton.Create(Self);FExecute.Parent:=Self;
  FExecute.SetBounds(910,45,175,30);FExecute.Caption:='Виконати в сеансі';
  FExecute.Enabled:=False;FExecute.OnClick:=@ExecuteClick;
  FState:=TLabel.Create(Self);FState.Parent:=Self;FState.SetBounds(12,90,1060,27);
  FState.Caption:='Ще немає з’єднання з нативним Core1';
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;
  FGrid.SetBounds(12,130,1072,318);FGrid.ColCount:=3;
  FGrid.FixedCols:=0;FGrid.FixedRows:=1;FGrid.RowCount:=2;
  FGrid.ColWidths[0]:=80;FGrid.ColWidths[1]:=180;
  FGrid.ColWidths[2]:=800;
  FGrid.Cells[0,0]:='Запит';FGrid.Cells[1,0]:='Статус';
  FGrid.Cells[2,0]:='Фізичний результат';
  L:=TLabel.Create(Self);L.Parent:=Self;L.SetBounds(12,463,1000,24);
  L.Caption:='Остання відповідь: точні Wn-слова; байти зберігаються без змін';
  FDetail:=TMemo.Create(Self);FDetail.Parent:=Self;
  FDetail.SetBounds(12,490,1072,178);FDetail.ReadOnly:=True;
  FDetail.ScrollBars:=ssBoth;FDetail.WordWrap:=False;
  FFiles:=TOpenDialog.Create(Self);
  FFiles.Filter:='Двійковий фізичний SENS|*.sens';
  FFiles.Options:=FFiles.Options+[ofFileMustExist];
  FPath.OnChange:=@PathChanged;
end;

destructor TSeansWindow.Destroy;
begin
  { Дочірній процес власний тільки вікну; жодних фізичних байтів
    чи TD2Node pointers після звільнення не лишається. }
  if FWorker<>nil then begin
    try
      if FWorker.Running then FWorker.Terminate(0);
    except end;
    FWorker.Free;
  end;
  inherited Destroy;
end;

procedure TSeansWindow.Need(Condition:Boolean;const Why:String);
begin if not Condition then raise Exception.Create(Why) end;

procedure TSeansWindow.Connect(const ExecutablePath,WorkspaceRoot:String);
begin
  Need(FWorker=nil,'підключення вже існує');
  Need(FileExists(ExecutablePath),'немає справжнього FPC виконавця Core1');
  Need(FileExists(IncludeTrailingPathDelimiter(WorkspaceRoot)+
    'external/sens/lib/core1.sens'),'немає pinned core1.sens');
  FWorker:=TProcess.Create(Self);
  try
    FWorker.Executable:=ExpandFileName(ExecutablePath);
    FWorker.Parameters.Add('--сеанс-core1');
    FWorker.Parameters.Add(ExpandFileName(WorkspaceRoot));
    FWorker.Options:=[poUsePipes];
    FWorker.Execute;
    Need(FWorker.Running,'довгоживучий FPC Core1 не запущений');
    FExecute.Enabled:=True;
    FState.Caption:='З’єднано з одним FPC Core1 процесом; це не повний REPL';
  except
    FreeAndNil(FWorker);
    raise;
  end;
end;

procedure TSeansWindow.PathChanged(Sender:TObject);
begin
  { OnChange робить попередню відповідь НЕАКТУАЛЬНОЮ.
    RawByteString — FPC-managed, стан сеансу залишається живим. }
  FLastAnswer:='';FDetail.Clear;
  FState.Caption:='Новий шлях ще не виконано; попередній T5M snapshot очищено';
end;

procedure TSeansWindow.ChooseClick(Sender:TObject);
begin
  if FFiles.Execute then begin
    FPath.Text:=FFiles.FileName;
    PathChanged(FPath);
  end;
end;

function TSeansWindow.ReadPhysical(const FileName:String):RawByteString;
var F:TFileStream;Words:TExactWords;
begin
  Need(LowerCase(ExtractFileExt(FileName))='.sens',
    'відхилено .lisp: потрібен канонічний фізичний .sens');
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>=1) and (F.Size<=MaxFrame),
      'фізичний вхід поза межею 1..65536 байтів');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
  DecodeT5M(Result,Words);
  Need(EncodeT5M(Words)=Result,'вхід не канонічний T5M');
end;

{ Указуємо лише довжину host-кадру у чотирьох little-endian байтах.
  Physical — позичені packed T5M байти; числа тут не D12+.
  Вхід — один валідований RawByteString, вихід — байти pipe без
  перекодування; lifetime належить викликачеві до завершення запису.
  Питання: чому довжина не є мовним числом D12?
  Чому UTF-8 .lisp заборонений? Чому pipe живе між викликами? }
procedure TSeansWindow.WriteFrame(const Physical:RawByteString);
var Header:array[0..3] of Byte; I:SizeInt;N:QWord;
begin
  Need((Length(Physical)>=1) and (Length(Physical)<=MaxFrame),
    'недопустима довжина фізичного кадру');
  Need((FWorker<>nil) and FWorker.Running,'сеанс завершився');
  N:=Length(Physical);
  for I:=0 to 3 do Header[I]:=Byte((N shr (8*I)) and $FF);
  FWorker.Input.WriteBuffer(Header,SizeOf(Header));
  FWorker.Input.WriteBuffer(Physical[1],Length(Physical));
end;

function TSeansWindow.ReadExact(var Dest;Count:SizeInt):Boolean;
var P:PByte;Done,Got:SizeInt;
begin
  Need(Count>=1,'некоректний розмір відповіді');
  P:=@Dest;Done:=0;
  while Done<Count do begin
    Got:=FWorker.Output.Read(P[Done],Count-Done);
    Need(Got>0,'обірвано відповідь дочірнього Core1 процесу');
    Inc(Done,Got);
  end;
  Result:=True;
end;

{ Reply status — приватний host байт (0 успіх / 1 діагностика),
  ніколи не D1:0/D1:1. Result — власні канонічні байти, якщо true;
  Diagnostic — власні host UTF-8 байти, якщо false. }
function TSeansWindow.ReadReply(out Physical:RawByteString;
  out Diagnostic:RawByteString):Boolean;
var Status:Byte;Header:array[0..3] of Byte;N:QWord;I:SizeInt;
    Raw:RawByteString;Words:TExactWords;
begin
  Physical:='';Diagnostic:='';
  ReadExact(Status,1);
  ReadExact(Header,4);
  N:=0;
  for I:=0 to 3 do N:=N or (QWord(Header[I]) shl (8*I));
  Need((Status=0) or (Status=1),'неправильний host статус відповіді');
  Need((N>=1) and (N<=MaxFrame),'розмір відповіді поза межею');
  SetLength(Raw,SizeInt(N));
  ReadExact(Raw[1],Length(Raw));
  if Status=1 then begin
    Diagnostic:=Raw;
    Exit(False);
  end;
  DecodeT5M(Raw,Words);
  Need((Length(Words)=1) and (EncodeT5M(Words)=Raw),
    'відповідь не є одним канонічним фізичним словом');
  Physical:=Raw;
  Result:=True;
end;

procedure TSeansWindow.AddRow(const StateText,WordText:String);
var Row:SizeInt;
begin
  Inc(FRows);Row:=FRows;
  if FGrid.RowCount<=Row then FGrid.RowCount:=Row+1;
  FGrid.Cells[0,Row]:=IntToStr(Row);
  FGrid.Cells[1,Row]:=StateText;
  FGrid.Cells[2,Row]:=WordText;
  FGrid.Row:=Row;
end;

function TSeansWindow.RunCurrent:Boolean;
var InBytes,OutBytes,Diagnostic:RawByteString;Words:TExactWords;
    TextValue:String;
begin
  Result:=False;FLastAnswer:='';FDetail.Clear;
  try
    Need((FWorker<>nil) and FWorker.Running,'немає живого Core1 сеансу');
    InBytes:=ReadPhysical(FPath.Text);
    WriteFrame(InBytes);
    if not ReadReply(OutBytes,Diagnostic) then begin
      Inc(FRemoteReject);
      raise Exception.Create('Core1 відхилив форму: '+String(Diagnostic));
    end;
    DecodeT5M(OutBytes,Words);
    TextValue:='W'+IntToStr(Length(Words[0]))+':'+String(Words[0]);
    FLastAnswer:=OutBytes;
    FDetail.Text:=TextValue+LineEnding+'Фізичний T5M: '+IntToStr(Length(OutBytes))+
      ' байтів; текст не є семантикою числа чи D1';
    Inc(FSuccess);AddRow('виконано',TextValue);
    FState.Caption:='Фізичний Core1 виконано; той самий дочірній процес';
    Result:=True;
  except on E:Exception do begin
    FLastAnswer:='';FDetail.Clear;
    Inc(FReject);AddRow('відмова',E.Message);
    FState.Caption:='ВІДМОВА: '+E.Message;
  end end;
end;

procedure TSeansWindow.ExecuteClick(Sender:TObject);
begin RunCurrent end;

procedure TSeansWindow.CheckFixture(const FileName:String;
  ShouldSucceed:Boolean;const Expected:RawByteString);
var OK:Boolean;
begin
  FPath.Text:=FileName;
  FExecute.Click; { ДІЙСНА графічна GTK2 кнопка }
  OK:=FLastAnswer<>'';
  Need(OK=ShouldSucceed,'помилкова оцінка виконання '+FileName);
  if ShouldSucceed then begin
    Need(FLastAnswer=Expected,'не побайтовий pinned фізичний результат');
    Need(Pos('W',FDetail.Text)=1,'UI не показав точну ширину');
  end else Need((FLastAnswer='') and (FDetail.Lines.Count=0) and
    (Pos('ВІДМОВА',FState.Caption)=1),
    'застарілі фізичні байти після відмови');
end;

procedure TSeansWindow.SelfCheck(const Fixtures:String);
var Base:String;Expected:RawByteString;Pid:PtrInt;
begin
  Need((FWorker<>nil) and FWorker.Running,'не відкрито справжній сеанс');
  Pid:=PtrInt(FWorker.ProcessID);
  Base:=IncludeTrailingPathDelimiter(Fixtures);
  Expected:=ReadPhysical(Base+'one.expected.sens');
  CheckFixture(Base+'one.sens',True,Expected);
  { Без нового виконавця: відмова у вже існуючому FPC child. }
  CheckFixture(Base+'known-blocked.sens',False,'');
  CheckFixture(Base+'one.sens',True,Expected);
  CheckFixture(Base+'broken-d2.sens',False,'');
  CheckFixture(Base+'one.sens',True,Expected);
  CheckFixture(Base+'three.sens',False,'');
  CheckFixture(Base+'one.sens',True,Expected);
  CheckFixture(Base+'не-канон.lisp',False,'');
  CheckFixture(Base+'one.sens',True,Expected);
  Need((FSuccess=5) and (FReject=4) and (FRemoteReject=3) and
    (FRows=9),'не всі реальні кліки/відмови виконані');
  Need((FWorker<>nil) and FWorker.Running and
    (PtrInt(FWorker.ProcessID)=Pid),'дочірній Core1 PID змінився');
  Show;Repaint;Application.ProcessMessages;
  WriteLn('ЛКЛ-CORE1-СЕАНС-ГАРАЗД GTK2=так FPC=справжній',
    ' кліки=9 успіхи=5 відмови=4 remote-відмови=3',
    ' pid=незмінний physical-T5M=побайтово',
    ' відновлення=так stale=очищено',
    ' REPL=НЕ-ПОВНИЙ GC=НЕ-ІНТЕГРОВАНО');
end;

begin
  Application.Initialize;
  try
    Window:=TSeansWindow.Create(nil);
    try
      if (ParamCount=4) and (ParamStr(1)='--самоперевірка') then begin
        Window.Connect(ParamStr(4),ParamStr(2));
        Window.SelfCheck(ParamStr(3));
      end else if ParamCount=0 then begin
        Window.Connect(ExtractFilePath(ParamStr(0))+'senscore1seans','.');
        Window.Show;
        Application.Run;
      end else
        raise Exception.Create(
          'використання: --самоперевірка workspace-root fixtures-dir fpc-binary');
    finally Window.Free end;
  except on E:Exception do begin
    WriteLn(ErrOutput,'ЛКЛ-CORE1-СЕАНС-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end end;
end.
