{ G3.44 — ЛКЛ-налагодження справжнього фізичного D1/D3 виконавця.
  ЄДИНИЙ runtime = wsm.gcexecution / wsm.binaryexec; збирач = wsm.gc.
  D7 є даними, D12+ тут не тлумачаться; Core1 DEFINE не виконується.
  Видимий Wn означає тільки ширину фізичного слова, НЕ його закон. }
program sens_gc_vykon_ogliad;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Dialogs,
  Grids, wsm.gcexecution, wsm.gc, wsm.t5m;

type
  TPhysicalGCWindow = class(TForm)
  private
    FExec: TGCExecution;
    FToken: TGCFrameToken;
    FRootActive: Boolean;
    FLast: TGCHandle;
    FLastPhysical: RawByteString;
    FInput: TEdit;
    FPicker: TOpenDialog;
    FGrid: TStringGrid;
    FStats, FStatus: TLabel;
    FRun, FRelease: TButton;
    procedure InputChanged(Sender: TObject);
    procedure SelectClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure ReleaseClick(Sender: TObject);
    function LoadPacked: RawByteString;
    procedure ClearResult;
    procedure RefreshCounts;
    procedure DisplayPhysical(const Physical: RawByteString);
    procedure Require(Condition: Boolean; const Detail: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure SelfTest(const AtomFile, PairFile, CorruptFile,
      UnsupportedFile: String);
  end;

var Window: TPhysicalGCWindow;

constructor TPhysicalGCWindow.Create(AOwner: TComponent);
var L: TLabel; Pick: TButton;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — фізичний виконавець і корені GC';
  Width := 1040; Height := 660; Position := poScreenCenter;
  { Сеанс володіє єдиним TGCExecution до Destroy, не копіює ні
    evaluator, ні фізичні закони. TForm володіє всіма віджетами. }
  FExec := TGCExecution.Create('external/sens');
  FRootActive := False;
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 12, 1000, 40);
  L.Caption := 'Виконується лише вже підтримана фізична D1/D3 форма .sens.'+
    LineEnding+'Core1/замикання/REPL тут НЕ підтримуються. Wn не надає викличності.';
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 62, 840, 20);
  L.Caption := 'Вхід: ОДНА канонічна T5M форма (.sens), не .lisp';
  FInput := TEdit.Create(Self); FInput.Parent := Self;
  FInput.SetBounds(16, 86, 800, 30);
  FInput.OnChange := @InputChanged;
  Pick := TButton.Create(Self); Pick.Parent := Self;
  Pick.SetBounds(830, 86, 180, 30); Pick.Caption := 'Вибрати фізичний файл';
  Pick.OnClick := @SelectClick;
  FRun := TButton.Create(Self); FRun.Parent := Self;
  FRun.SetBounds(16, 130, 270, 40);
  FRun.Caption := 'Виконати фізичну форму'; FRun.OnClick := @RunClick;
  FRelease := TButton.Create(Self); FRelease.Parent := Self;
  FRelease.SetBounds(300, 130, 270, 40);
  FRelease.Caption := 'Зняти корінь і зібрати'; FRelease.OnClick := @ReleaseClick;
  FStats := TLabel.Create(Self); FStats.Parent := Self;
  FStats.SetBounds(16, 184, 995, 27);
  FGrid := TStringGrid.Create(Self); FGrid.Parent := Self;
  FGrid.SetBounds(16, 220, 995, 340);
  FGrid.ColCount := 3; FGrid.RowCount := 2;
  FGrid.FixedCols := 0; FGrid.FixedRows := 1;
  FGrid.ColWidths[0] := 140;
  FGrid.ColWidths[1] := 165;
  FGrid.ColWidths[2] := 670;
  FGrid.Options := FGrid.Options - [goEditing];
  FGrid.Cells[0,0] := 'Фізичне слово';
  FGrid.Cells[1,0] := 'Точна ширина';
  FGrid.Cells[2,0] := 'Біти (не назва, не закон)';
  FStatus := TLabel.Create(Self); FStatus.Parent := Self;
  FStatus.SetBounds(16, 573, 995, 60);
  FPicker := TOpenDialog.Create(Self);
  FPicker.Filter := 'Канонічний SENS (*.sens)|*.sens';
  FPicker.Options := FPicker.Options + [ofFileMustExist];
  ClearResult;
end;

destructor TPhysicalGCWindow.Destroy;
begin
  { Вивільнити root ще до звільнення heap. Віджети належать TForm. }
  ClearResult;
  FExec.Free;
  inherited Destroy;
end;

procedure TPhysicalGCWindow.RefreshCounts;
begin
  FStats.Caption := 'Реальний GC: живих=' + IntToStr(FExec.LiveCount) +
    ' | комірок=' + IntToStr(FExec.SlotCount) +
    ' | коренів стеку=' + IntToStr(FExec.ScopedRoots) +
    ' | областей=' + IntToStr(FExec.ScopeDepth);
end;

procedure TPhysicalGCWindow.ClearResult;
var I, J: Integer;
begin
  if FRootActive then begin
    FExec.EndScope(FToken);
    FRootActive := False;
  end;
  FExec.Collect;
  FLast := Default(TGCHandle);
  FLastPhysical := '';
  FGrid.RowCount := 2;
  for I:=1 to FGrid.RowCount-1 do
    for J:=0 to FGrid.ColCount-1 do FGrid.Cells[J,I]:='';
  FStatus.Caption := 'Немає активної фізичної відповіді. Стан Core1 не визначено.';
  RefreshCounts;
end;

procedure TPhysicalGCWindow.InputChanged(Sender: TObject);
begin
  { Змінений файл негайно знімає root старої відповіді: stale view=0. }
  ClearResult;
end;

procedure TPhysicalGCWindow.SelectClick(Sender: TObject);
begin if FPicker.Execute then FInput.Text := FPicker.FileName; end;

function TPhysicalGCWindow.LoadPacked: RawByteString;
var F: TFileStream;
begin
  if (FInput.Text = '') or
     (LowerCase(ExtractFileExt(FInput.Text)) <> '.sens') then
    raise Exception.Create('потрібен явно вибраний фізичний .sens');
  F := TFileStream.Create(FInput.Text, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size < 1) or (F.Size > MAX_T5M_FILE_BYTES) then
      raise Exception.Create('фізичний T5M порожній або перевищує межу');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1], Length(Result));
  finally F.Free; end;
end;

{ Вхід/вихід — одна канонічна packed T5M послідовність.
  DecodeT5M — наявний фізичний codec, лише для показу; не створює
  доменних законів. Масив exact words живе лише протягом DisplayPhysical.
  Відповідь FLastPhysical живе під GC root до зміни вводу або Release. }
procedure TPhysicalGCWindow.DisplayPhysical(const Physical: RawByteString);
var Words: TExactWords; I: SizeInt;
begin
  DecodeT5M(Physical, Words);
  if EncodeT5M(Words) <> Physical then
    raise Exception.Create('необоротна фізична відповідь');
  if Length(Words) > 4096 then
    raise Exception.Create('надто багато фізичних слів для вікна');
  FGrid.RowCount := Length(Words)+1;
  for I:=0 to High(Words) do begin
    FGrid.Cells[0,I+1] := IntToStr(I+1);
    FGrid.Cells[1,I+1] := 'W'+IntToStr(Length(Words[I]));
    FGrid.Cells[2,I+1] := String(Words[I]);
  end;
end;

procedure TPhysicalGCWindow.RunClick(Sender: TObject);
var Input, Answer: RawByteString;
begin
  ClearResult;
  try
    Input := LoadPacked;
    { Саме штатний TGCExecution виконує фізичний D3 і створює root. }
    FToken := FExec.BeginScope;
    FRootActive := True;
    FLast := FExec.ExecutePhysical(Input, FToken);
    Answer := FExec.PhysicalOf(FLast);
    DisplayPhysical(Answer);
    FLastPhysical := Answer;
    FStatus.Caption := 'Фізична відповідь підтверджена; Wn — лише ширина.'+
      ' Поки активний корінь, GC зберігає байти.';
    RefreshCounts;
  except
    on E: Exception do begin
      ClearResult;
      FStatus.Caption := 'ВІДМОВА: '+E.Message+
        '. Результат очищено, попередній корінь звільнено.';
    end;
  end;
end;

procedure TPhysicalGCWindow.ReleaseClick(Sender: TObject);
begin
  ClearResult;
  FStatus.Caption := 'Корінь знято; штатний GC виконав mark-and-sweep.';
end;

procedure TPhysicalGCWindow.Require(Condition:Boolean; const Detail:String);
begin
  if not Condition then raise Exception.Create('ЛКЛ-GC-ПРОВАЛ: '+Detail);
end;

function AtomOne: RawByteString;
var Words: TExactWords;
begin
  SetLength(Words,1);
  Words[0]:='1';
  Result:=EncodeT5M(Words);
end;

procedure TPhysicalGCWindow.SelfTest(
  const AtomFile, PairFile, CorruptFile, UnsupportedFile: String);
var Old: TGCHandle;
begin
  { Натискання й реальні TStringGrid/TLabel/LCL, а не headless echo. }
  FInput.Text := AtomFile;
  FRun.Click;
  Require((FLastPhysical <> '') and (FLastPhysical = AtomOne) and (FGrid.RowCount=2) and
    (FGrid.Cells[1,1]='W1') and (FGrid.Cells[2,1]='1') and
    (FExec.LiveCount=1) and (FExec.ScopedRoots=1),
    'дійсний D1 результат не збережений у видимому GC');
  Old := FLast;
  FInput.Text := PairFile;
  Require((FExec.LiveCount=0) and (FGrid.Cells[2,1]='') and
    (not FExec.IsAlive(Old)), 'зміна вводу не очищає попередній корінь');
  FRun.Click;
  Require((FGrid.RowCount=6) and (FGrid.Cells[2,1]='10') and
    (FGrid.Cells[2,2]='0') and (FGrid.Cells[2,3]='11') and
    (FGrid.Cells[2,4]='1') and (FGrid.Cells[2,5]='01') and
    (FExec.LiveCount=1) and (FExec.ScopedRoots=1),
    'фізична D3 цитата пари не виконалась або змінила слова');
  Old := FLast;
  FRelease.Click;
  Require((FGrid.RowCount=2) and (FGrid.Cells[2,1]='') and
    (FExec.LiveCount=0) and (FExec.ScopedRoots=0) and
    (not FExec.IsAlive(Old)), 'зняття кореня не звільнило фізичну пам’ять');
  FInput.Text := CorruptFile;
  FRun.Click;
  Require((Pos('ВІДМОВА',FStatus.Caption)>0) and
    (FGrid.Cells[2,1]='') and (FExec.LiveCount=0) and
    (FExec.ScopeDepth=0), 'зіпсовану фізичну відповідь прийнято');
  FInput.Text := UnsupportedFile;
  FRun.Click;
  Require((Pos('ВІДМОВА',FStatus.Caption)>0) and
    (FGrid.Cells[2,1]='') and (FExec.LiveCount=0),
    'невикличний D7 атом прийнято');
  FInput.Text := AtomFile;
  FRun.Click;
  Require((FGrid.Cells[2,1]='1') and (FExec.LiveCount=1),
    'відновлення після негативів не працює');
  FRelease.Click;
  Require((FExec.LiveCount=0) and (FExec.ScopeDepth=0) and
    (FExec.SlotCount=1), 'повторне використання GC комірки не обмежене');
  WriteLn('ЛКЛ-ФІЗИЧНИЙ-GC-ГАРАЗД LCL=GTK2 D1=виконано D3=виконано '+
    'roots=знято stale=очищено negatives=2 Core1=НЕ_ВИКОНАНО');
end;

begin
  Application.Initialize;
  Window := TPhysicalGCWindow.Create(nil);
  try
    if (ParamCount=5) and (ParamStr(1)='--самоперевірка') then begin
      try
        Window.Show;
        Application.ProcessMessages;
        Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5));
      except
        on E:Exception do begin
          WriteLn(StdErr,'ЛКЛ-ФІЗИЧНИЙ-GC-ПРОВАЛ: ',E.Message);
          Halt(1);
        end;
      end;
    end else Application.Run;
  finally Window.Free; end;
end.
{ Питання: (1) Чому W7 сам по собі не є викличним кодом?
  (2) Чому новий ввід спочатку знімає корінь?
  (3) Який саме TGCHeap переживає кілька натискань?
  (4) Чому GUI показує exact bits без текстової реконструкції?
  (5) Чого бракує до debugger замикань Core1? }
