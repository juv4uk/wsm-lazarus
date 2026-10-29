{ G5.64 — справжня Lazarus/LCL таблиця кількох ВИКОНАНИХ .sens файлів.
  Файловий FPC клієнт sensfizfaily → один sensfizseans → D3 runtime.
  Фізичний T5M залишається байтами; статус host ≠ D1.
  Шість D7 проєкцій лише читаються з pinned authority, не dispatch.
  Це НЕ повний SENS REPL, не Core4 і не арифметика D12+. }
program sens_fiz_faily_ogliad;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Dialogs,
  Grids, Process, Pipes, wsm.t5m, wsm.proektsii, wsm.domain;

const
  MaxFiles = 16;
  MaxPhysical = 65536;
  MaxOutput = 16 * (65536 + 9);
  MaxErrors = 8192;
type
  TPhysicalResult = record
    Status: Byte; { 0=успіх, 1=відмова; приватний host status, не D1 }
    AtWord: QWord; { 1-based; 0 — пошкоджений T5M }
    Bytes: RawByteString; { оригінальні виконані T5M або UTF-8 помилка }
    Words: String; { лише відображення фізичного результату }
    Surfaces: String; { pinned D7 дані, не семантичні назви }
  end;
  TResultRows = array of TPhysicalResult;

  TFilesWindow = class(TForm)
  private
    FClient, FServer: String;
    FCatalog: TProektsiiCatalog;
    FPaths: array of String;
    FRows: TResultRows;
    FList: TListBox;
    FGrid: TStringGrid;
    FDetails: TMemo;
    FState: TLabel;
    FRun, FChoose: TButton;
    FDialog: TOpenDialog;
    procedure Demand(Condition: Boolean; const Why: String);
    procedure ClearSnapshot;
    procedure PaintRows;
    procedure ChooseClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure SelectRow(Sender: TObject; Col, Row: LongInt;
      var CanSelect: Boolean);
    function ExecuteFiles: Boolean;
    function ReceiveFrames(const Data: RawByteString;
      ChildCode: Integer): TResultRows;
    function RunClient(out Data, Errors: RawByteString): Integer;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Connect(const Client, Server: String);
    procedure SetPaths(const Paths: array of String);
    procedure SelfCheck(const Good, D7, Bad, Missing, TextPath,
      FakeClient: String);
  end;
var Window: TFilesWindow;

constructor TFilesWindow.Create(AOwner: TComponent);
var L: TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption := 'SENS — фізичні файли в одному сеансі Lazarus';
  Width := 1140; Height := 760; Position := poScreenCenter;
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(12,8,1110,26);
  L.Caption := 'Канонічні фізичні .sens; українська .lisp — лише проєкція. D12+ тут не обчислюється.';
  FChoose := TButton.Create(Self);
  FChoose.Parent := Self; FChoose.SetBounds(12,40,220,33);
  FChoose.Caption := 'Обрати файли .sens'; FChoose.OnClick := @ChooseClick;
  FRun := TButton.Create(Self);
  FRun.Parent := Self; FRun.SetBounds(242,40,290,33);
  FRun.Caption := 'Виконати разом (один сеанс)';
  FRun.Enabled := False; FRun.OnClick := @RunClick;
  FState := TLabel.Create(Self); FState.Parent := Self;
  FState.SetBounds(542,44,560,28);
  FState.Caption := 'Не підключено фізичний клієнт';
  FList := TListBox.Create(Self); FList.Parent := Self;
  FList.SetBounds(12,85,1110,116);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self; FGrid.SetBounds(12,215,1110,295);
  FGrid.ColCount := 5; FGrid.FixedCols := 0;
  FGrid.RowCount := 2; FGrid.FixedRows := 1;
  FGrid.ColWidths[0] := 52; FGrid.ColWidths[1] := 350;
  FGrid.ColWidths[2] := 112; FGrid.ColWidths[3] := 85;
  FGrid.ColWidths[4] := 460;
  FGrid.OnSelectCell := @SelectRow;
  FDetails := TMemo.Create(Self); FDetails.Parent := Self;
  FDetails.SetBounds(12,521,1110,205);
  FDetails.ReadOnly := True; FDetails.WordWrap := False;
  FDetails.ScrollBars := ssBoth;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Filter := 'Канонічні двійкові файли SENS|*.sens';
  FDialog.Options := FDialog.Options + [ofAllowMultiSelect,ofFileMustExist];
  ClearSnapshot;
end;

procedure TFilesWindow.Demand(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create(Why);
end;

procedure TFilesWindow.ClearSnapshot;
begin
  SetLength(FRows,0);
  FGrid.RowCount := 2;
  FGrid.Cells[0,0] := '№';
  FGrid.Cells[1,0] := 'Фізичний файл';
  FGrid.Cells[2,0] := 'Host-стан';
  FGrid.Cells[3,0] := 'Слово';
  FGrid.Cells[4,0] := 'Точна T5M відповідь / відмова';
  FGrid.Rows[1].Clear;
  FDetails.Clear;
end;

procedure TFilesWindow.Connect(const Client,Server:String);
begin
  Demand((FClient='') and (FServer=''),'повторне підключення заборонено');
  Demand((Client<>'') and (Server<>''),'потрібні два FPC виконувані файли');
  LoadPinnedProjections('external/sens',FCatalog);
  FClient := Client; FServer := Server;
  FRun.Enabled := True;
  FState.Caption := 'Підключено фізичний FPC клієнт; не повний REPL';
end;

procedure TFilesWindow.SetPaths(const Paths:array of String);
var I:SizeInt;
begin
  ClearSnapshot;
  SetLength(FPaths,Length(Paths));
  FList.Clear;
  for I:=0 to High(Paths) do begin
    FPaths[I] := Paths[I];
    FList.Items.Add(Paths[I]);
  end;
  FState.Caption := 'Фізичних файлів у черзі: '+IntToStr(Length(FPaths));
end;

procedure TFilesWindow.ChooseClick(Sender:TObject);
var Paths:array of String; I:SizeInt;
begin
  if not FDialog.Execute then Exit;
  SetLength(Paths,FDialog.Files.Count);
  for I:=0 to High(Paths) do Paths[I]:=FDialog.Files[I];
  SetPaths(Paths);
end;

{ Один FPC TProcess, оригінальні stdout/stderr з pipe. Обидва канали
  зчитуємо до EOF, щоби не блокуватись на повному stderr.
  Межа 16*(65536+9) — HOST ресурс, а НЕ числова D12+ семантика.
  Життєвий цикл TProcess/TMemoryStream строго обмежений викликом;
  на timeout або overflow процес завершується, без часткових рядків.
  Питання: чому не можна WaitOnExit перед читанням pipe?
  Чому обидва потоки треба дренувати?
  Чому host статус 1 не є D1:1?
  Як зупиняємо зіпсованого дочірнього клієнта? }
function TFilesWindow.RunClient(out Data,Errors:RawByteString):Integer;
var P:TProcess; OutBuf,ErrBuf:TMemoryStream;
    Block:array[0..4095] of Byte; Got,Avail:SizeInt;
    I:SizeInt; UntilMs:QWord;
  procedure Drain(Pipe:TInputPipeStream;Target:TMemoryStream;Max:SizeInt);
  begin
    Avail:=Pipe.NumBytesAvailable;
    while Avail>0 do begin
      if Avail>SizeOf(Block) then Avail:=SizeOf(Block);
      Got:=Pipe.Read(Block,Avail);
      if Got<=0 then Break;
      Demand(Target.Size<=Max-Got,'переповнено фізичний host-буфер');
      Target.WriteBuffer(Block,Got);
      Avail:=Pipe.NumBytesAvailable;
    end;
  end;
  function Dump(S:TMemoryStream):RawByteString;
  begin
    SetLength(Result,SizeInt(S.Size));
    if S.Size>0 then begin
      S.Position:=0;
      S.ReadBuffer(Result[1],Length(Result));
    end;
  end;
begin
  Data:=''; Errors:='';
  P:=TProcess.Create(nil);
  OutBuf:=TMemoryStream.Create; ErrBuf:=TMemoryStream.Create;
  try
    P.Executable:=FClient;
    P.Parameters.Add('--файли');
    P.Parameters.Add(FServer);
    for I:=0 to High(FPaths) do P.Parameters.Add(FPaths[I]);
    P.Options:=[poUsePipes];
    P.Execute;
    UntilMs:=GetTickCount64+30000;
    repeat
      Drain(P.Output,OutBuf,MaxOutput);
      Drain(P.Stderr,ErrBuf,MaxErrors);
      if not P.Running then begin
        Drain(P.Output,OutBuf,MaxOutput);
        Drain(P.Stderr,ErrBuf,MaxErrors);
        Break;
      end;
      Demand(GetTickCount64<UntilMs,'дочірній FPC клієнт не відповів за 30 с');
      Sleep(5);
    until False;
    P.WaitOnExit;
    { На Unix FPC TProcess.ExitStatus може бути RAW waitpid-status:
      512 означає exit(2), а НЕ код 512 від SENS. Сигнал
      завершує host-канал як пошкоджений; не маскуємо його під
      допустиму відмову окремої форми.
      Питання: чому status waitpid не є кодом SENS?
      Чому сигнал не можна вважати відмовою D3?
      Чому вихідний код 2 треба нормалізувати до frame-перевірки? }
    {$IFDEF UNIX}
    if (P.ExitStatus and $7F) <> 0 then Result:=-1
    else Result:=(P.ExitStatus shr 8) and $FF;
    {$ELSE}
    Result:=P.ExitStatus;
    {$ENDIF}
    Data:=Dump(OutBuf); Errors:=Dump(ErrBuf);
  finally
    if P.Running then begin
      P.Terminate(2); P.WaitOnExit;
    end;
    P.Free; OutBuf.Free; ErrBuf.Free;
  end;
end;

function ReadLE(const Data:RawByteString;At:SizeInt):QWord;
begin
  Result:=QWord(Ord(Data[At])) or (QWord(Ord(Data[At+1])) shl 8) or
    (QWord(Ord(Data[At+2])) shl 16) or
    (QWord(Ord(Data[At+3])) shl 24);
end;

{ Декодування HOST-кадрів після ПОВНОГО виконання. Rows тимчасові:
  FRows не отримує даних до останнього перевіреного байта.
  TExactWords — короткоживучий буфер чинного T5M, D7 таблиця з pin.
  Відмови — UTF-8 діагностика, ніколи не SENS слова.
  Питання: чому навіть частково правильна відповідь не публікується?
  Чому W7 не виконується за текстом «укр»?
  Чому нульовий код без кадрів є збоєм?
  Де доводиться точна тотожність packed T5M? }
function TFilesWindow.ReceiveFrames(const Data:RawByteString;
  ChildCode:Integer):TResultRows;
const Names:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var I,J,K,PosByte,N:SizeInt; Size,Index:QWord;
    Words:TExactWords; Key:TDomainKey;
    S:String; Rejected:Boolean;
begin
  Demand((ChildCode=0) or (ChildCode=2),
    'неправильний код файлового клієнта='+IntToStr(ChildCode));
  SetLength(Result,Length(FPaths));
  PosByte:=1; Rejected:=False;
  for I:=0 to High(Result) do begin
    Demand(PosByte+8<=Length(Data),'обірваний заголовок host-кадру');
    Demand(Ord(Data[PosByte])<=1,'невідомий статус host-кадру');
    Result[I].Status:=Ord(Data[PosByte]);
    Index:=ReadLE(Data,PosByte+1);
    Size:=ReadLE(Data,PosByte+5);
    Demand((Size>=1) and (Size<=MaxPhysical),'недопустима довжина відповіді');
    Inc(PosByte,9);
    Demand(Size<=QWord(Length(Data)-PosByte+1),
      'обірваний payload host-кадру');
    N:=SizeInt(Size);
    Result[I].AtWord:=Index;
    Result[I].Bytes:=Copy(Data,PosByte,N);
    Inc(PosByte,N);
    if Result[I].Status=1 then begin
      Rejected:=True;
      Result[I].Words:='відхилено';
    end else begin
      Demand(Index=0,'ненульовий індекс успішної відповіді');
      DecodeT5M(Result[I].Bytes,Words);
      Demand((Length(Words)>0) and
        (EncodeT5M(Words)=Result[I].Bytes),
        'відповідь не є канонічним фізичним T5M');
      S:='';
      for J:=0 to High(Words) do begin
        if J<>0 then S:=S+' ';
        S:=S+'W'+IntToStr(Length(Words[J]))+':'+String(Words[J]);
        if Length(Words[J])=7 then begin
          Key:=ExactKey(Words[J]);K:=Key.Bits;
          Demand((K>=0) and (K<Length(FCatalog[7])) and
            SameKey(FCatalog[7][K].Key,Key),
            'D7 поза pinned шістьма проєкціями');
          for K:=0 to 5 do
            Result[I].Surfaces:=Result[I].Surfaces+
              Names[K]+'='+SurfaceForDisplay(FCatalog[7][Key.Bits].Surface[K])+#10;
        end;
      end;
      Result[I].Words:=S;
    end;
  end;
  Demand(PosByte=Length(Data)+1,'зайві байти фізичного host stdout');
  Demand((ChildCode=2)=Rejected,'host код не збігається з відмовами');
end;

procedure TFilesWindow.PaintRows;
var I:SizeInt;
begin
  FGrid.RowCount:=Length(FRows)+1;
  for I:=0 to High(FRows) do begin
    FGrid.Cells[0,I+1]:=IntToStr(I+1);
    FGrid.Cells[1,I+1]:=FPaths[I];
    if FRows[I].Status=0 then FGrid.Cells[2,I+1]:='Виконано'
    else FGrid.Cells[2,I+1]:='Відхилено';
    FGrid.Cells[3,I+1]:=IntToStr(FRows[I].AtWord);
    if FRows[I].Status=0 then
      FGrid.Cells[4,I+1]:=FRows[I].Words
    else FGrid.Cells[4,I+1]:=String(FRows[I].Bytes);
  end;
  if Length(FRows)>0 then begin
    FGrid.Row:=1;
    FDetails.Text:=FRows[0].Words+#10+FRows[0].Surfaces;
  end;
end;

procedure TFilesWindow.SelectRow(Sender:TObject;Col,Row:LongInt;
  var CanSelect:Boolean);
begin
  if (Row>0) and (Row<=Length(FRows)) then
    if FRows[Row-1].Status=0 then
      FDetails.Text:=FRows[Row-1].Words+#10+FRows[Row-1].Surfaces
    else FDetails.Text:='Відмова; фізичне слово='+
      IntToStr(FRows[Row-1].AtWord)+': '+String(FRows[Row-1].Bytes);
end;

function TFilesWindow.ExecuteFiles:Boolean;
var Data,Errors:RawByteString; Code:Integer; Fresh:TResultRows;
    I,Refusals:SizeInt;
begin
  Result:=False;
  ClearSnapshot;
  try
    Demand((Length(FPaths)>=1) and (Length(FPaths)<=MaxFiles),
      'потрібно 1..16 фізичних файлів');
    for I:=0 to High(FPaths) do
      Demand(LowerCase(ExtractFileExt(FPaths[I]))='.sens',
        'людську .lisp не можна виконувати як фізичну .sens');
    Code:=RunClient(Data,Errors);
    Demand((Errors='') and (Data<>''),'дочірній клієнт не повернув повних кадрів: '+String(Errors));
    Fresh:=ReceiveFrames(Data,Code);
    FRows:=Fresh; { єдиний commit після перевірки ВСІХ кадрів }
    PaintRows;
    Refusals:=0;
    for I:=0 to High(FRows) do if FRows[I].Status=1 then Inc(Refusals);
    FState.Caption:='Один фізичний сеанс: файлів='+
      IntToStr(Length(FRows))+' відмов='+IntToStr(Refusals);
    Result:=True;
  except on E:Exception do begin
    ClearSnapshot;
    FState.Caption:='ФІЗИЧНА ВІДМОВА: '+E.Message;
  end end;
end;

procedure TFilesWindow.RunClick(Sender:TObject);
begin
  if not FRun.Enabled then Exit;
  FRun.Enabled:=False;
  try ExecuteFiles; finally FRun.Enabled:=True end;
end;

procedure TFilesWindow.SelfCheck(const Good,D7,Bad,Missing,TextPath,
  FakeClient:String);
var Paths:array of String; OriginalClient:String;
begin
  Demand(FRun.Enabled and (FGrid.ColCount=5),'немає реального LCL вікна');
  SetLength(Paths,3);
  Paths[0]:=Good; Paths[1]:=D7; Paths[2]:=Bad;
  SetPaths(Paths); FRun.Click;
  if Length(FRows)<>3 then
    WriteLn(StdErr,'ЛКЛ-ДІАГНОСТИКА: рядків=',Length(FRows),
      ' стан=',FState.Caption)
  else begin
    WriteLn(StdErr,'ЛКЛ-ДІАГНОСТИКА: W1=',FRows[0].Words,
      ' статус=',FRows[0].Status,' W7=',FRows[1].Words,
      ' ук=',FRows[1].Surfaces,' відмова=',FRows[2].Status,
      ' фізичне-слово=',FRows[2].AtWord);
  end;
  Demand((Length(FRows)=3) and
    (FRows[0].Status=0) and (FRows[0].Words='W1:1') and
    (FRows[1].Status=0) and
    (Pos('W7:0010110',FRows[1].Words)>0) and
    (Pos('ук=(відсутня)',FRows[1].Surfaces)>0) and
    (Pos('LISP=(відсутня)',FRows[1].Surfaces)>0) and
    (FRows[2].Status=1) and (FRows[2].AtWord=0),
    'кліки GUI не відобразили реальні D1/D7 та T5M-відмову');
  Demand((FGrid.RowCount=4) and
    (FGrid.Cells[2,3]='Відхилено'),
    'таблиця втрачає точну третю форму');
  SetLength(Paths,2); Paths[0]:=Good; Paths[1]:=Missing;
  SetPaths(Paths);FRun.Click;
  Demand((Length(FRows)=0) and (FGrid.RowCount=2) and
    (Pos('ВІДМОВА',FState.Caption)>0),
    'пізня відсутність файла залишила часткові результати');
  Paths[1]:=TextPath;SetPaths(Paths);FRun.Click;
  Demand((Length(FRows)=0) and (FGrid.RowCount=2),
    'людський .lisp прийнято за фізичний T5M');
  OriginalClient:=FClient;FClient:=FakeClient;
  try
    Paths[1]:=D7;SetPaths(Paths);FRun.Click;
    Demand((Length(FRows)=0) and (FGrid.RowCount=2),
      'обрізаний host-кадр намалював частковий результат');
  finally FClient:=OriginalClient end;
  SetPaths(Paths);FRun.Click;
  Demand((Length(FRows)=2) and (FRows[0].Words='W1:1') and
    (Pos('W7:0010110',FRows[1].Words)>0),
    'після host-пошкодження не відновилися фізичні відповіді');
  Show;Repaint;Application.ProcessMessages;
  WriteLn('ЛКЛ-ФІЗИЧНІ-ФАЙЛИ-ГАРАЗД Lazarus=GTK2 файлових=3',
    ' D1=виконано D7=шість-pinned T5M=точно',
    ' відмова=позиційна host-розрив=відхилено',
    ' пізній-файл=атомарно відновлення=так',
    ' REPL=НЕ-ГОТОВИЙ Core4=НЕ-ДОВЕДЕНО');
end;

begin
  Application.Initialize;
  Window:=TFilesWindow.Create(nil);
  try
    if (ParamCount=9) and
      (ParamStr(1)='--самоперевірка') then begin
      Window.Connect(ParamStr(2),ParamStr(3));
      Window.SelfCheck(ParamStr(4),ParamStr(5),ParamStr(6),
        ParamStr(7),ParamStr(8),
        ParamStr(9));
    end else if ParamCount=0 then begin
      Window.Connect('build/m0.2/fiz-faily-bin/sensfizfaily',
        'build/m0.2/fiz-faily-bin/sensfizseans');
      Window.Show;Application.Run;
    end else raise Exception.Create('використання: --самоперевірка клієнт сервер добре.sens d7.sens погано.sens немає.sens текст.lisp підроблений-клієнт');
  except on E:Exception do begin
    WriteLn(StdErr,'ЛКЛ-ФІЗИЧНІ-ФАЙЛИ-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end end;
  Window.Free;
end.
