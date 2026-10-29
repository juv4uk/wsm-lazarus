{ Окремий справжній Lazarus/LCL оглядач перевірених host-лічильників RAPL.
  Власна арифметика енергії ЗАБОРОНЕНА: тільки stdout чинного sensrapl.
  SENS .sens/.lisp, D7, D12+ чи Core4 тут не читаються й не виконуються. }
program sens_enerhiia;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Dialogs,
  Grids, ExtCtrls, Graphics, Process;

type
  TZoneView = record
    Key, NameText: String;
    BeforeEnergy, AfterEnergy, RangeEnergy, DeltaEnergy: QWord;
  end;
  TZoneViews = array of TZoneView;

  TEnergyWindow = class(TForm)
  private
    FCli, FBefore, FAfter, FTime, FPower: TEdit;
    FGrid: TStringGrid;
    FGraph: TPaintBox;
    FStatus: TLabel;
    FPicker: TOpenDialog;
    FRows: TZoneViews;
    FRun: TButton;
    procedure Changed(Sender: TObject);
    procedure SelectBefore(Sender: TObject);
    procedure SelectAfter(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure DrawGraph(Sender: TObject);
    procedure ClearView;
    function CaptureDifference: RawByteString;
    function DecodeReport(const Data: RawByteString): TZoneViews;
    procedure DisplayRows(const Rows: TZoneViews);
    procedure Check(OK: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SelfTest(const CliPath, FirstPath, SecondPath, BadPath: String);
  end;

var Window: TEnergyWindow;

function StrictUnsigned(const S: String): QWord;
var I: SizeInt;
begin
  if S = '' then raise Exception.Create('Порожнє значення RAPL');
  for I := 1 to Length(S) do
    if (S[I] < '0') or (S[I] > '9') then
      raise Exception.Create('Неканонічне число RAPL');
  if not TryStrToQWord(S, Result) then
    raise Exception.Create('Число RAPL поза QWord');
end;

function Fields(const Line: String; Needed: Integer): TStringList;
var I, Start: SizeInt;
begin
  Result := TStringList.Create;
  Start := 1;
  for I := 1 to Length(Line) do
    if Line[I] = #9 then begin
      Result.Add(Copy(Line, Start, I - Start));
      Start := I + 1;
    end;
  Result.Add(Copy(Line, Start, MaxInt));
  if Result.Count <> Needed then begin
    Result.Free;
    raise Exception.Create('Пошкоджена кількість TSV полів');
  end;
end;

constructor TEnergyWindow.Create(AOwner: TComponent);
var L: TLabel; Pick: TButton;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — фізична енергія Linux RAPL';
  Width := 1110; Height := 680; Position := poScreenCenter;
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 10, 1050, 42);
  L.Caption := 'Фізичні зони package/core/dram НЕ підсумовуються. Джоулі процесу SENS тут НЕ виміряно.'+
    LineEnding+'Порівнюються лише два знімки RAPL1 через перевірений нативний FPC sensrapl.';
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 60, 330, 20); L.Caption := 'Перевірений виконуваний sensrapl';
  FCli := TEdit.Create(Self); FCli.Parent := Self;
  FCli.SetBounds(16, 82, 1055, 29);
  FCli.Text := ExpandFileName('build/m0.2/bin/sensrapl');
  FCli.OnChange := @Changed;
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 118, 360, 20); L.Caption := 'Перший фізичний знімок RAPL1';
  FBefore := TEdit.Create(Self); FBefore.Parent := Self;
  FBefore.SetBounds(16, 140, 890, 29); FBefore.OnChange := @Changed;
  Pick := TButton.Create(Self); Pick.Parent := Self;
  Pick.SetBounds(915, 140, 155, 29); Pick.Caption := 'Відкрити перший';
  Pick.OnClick := @SelectBefore;
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 177, 360, 20); L.Caption := 'Другий фізичний знімок RAPL1';
  FAfter := TEdit.Create(Self); FAfter.Parent := Self;
  FAfter.SetBounds(16, 199, 890, 29); FAfter.OnChange := @Changed;
  Pick := TButton.Create(Self); Pick.Parent := Self;
  Pick.SetBounds(915, 199, 155, 29); Pick.Caption := 'Відкрити другий';
  Pick.OnClick := @SelectAfter;
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 237, 250, 20); L.Caption := 'Виміряна тривалість (мкс)';
  FTime := TEdit.Create(Self); FTime.Parent := Self;
  FTime.SetBounds(16, 260, 220, 29); FTime.Text := '';
  FTime.OnChange := @Changed;
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(255, 237, 330, 20); L.Caption := 'Обґрунтована верхня межа (Вт)';
  FPower := TEdit.Create(Self); FPower.Parent := Self;
  FPower.SetBounds(255, 260, 220, 29); FPower.Text := '';
  FPower.OnChange := @Changed;
  FRun := TButton.Create(Self); FRun.Parent := Self;
  FRun.SetBounds(520, 255, 270, 40);
  FRun.Caption := 'Перевірити й порівняти'; FRun.OnClick := @RunClick;
  FPicker := TOpenDialog.Create(Self);
  FPicker.Title := 'Вибрати знімок, створений sensrapl';
  FPicker.Filter := 'Знімки RAPL (*.tsv)|*.tsv';
  FPicker.Options := FPicker.Options + [ofFileMustExist];
  FGrid := TStringGrid.Create(Self); FGrid.Parent := Self;
  FGrid.SetBounds(16, 310, 1055, 183);
  FGrid.ColCount := 6; FGrid.RowCount := 2;
  FGrid.FixedRows := 1; FGrid.FixedCols := 0;
  FGrid.Options := FGrid.Options - [goEditing];
  FGrid.ColWidths[0] := 235; FGrid.ColWidths[1] := 160;
  FGrid.ColWidths[2] := 148; FGrid.ColWidths[3] := 148;
  FGrid.ColWidths[4] := 170; FGrid.ColWidths[5] := 165;
  FGrid.Cells[0, 0] := 'Фізична зона';
  FGrid.Cells[1, 0] := 'Назва зони';
  FGrid.Cells[2, 0] := 'До (мкДж)';
  FGrid.Cells[3, 0] := 'Після (мкДж)';
  FGrid.Cells[4, 0] := 'Діапазон (мкДж)';
  FGrid.Cells[5, 0] := 'Різниця (мкДж)';
  L := TLabel.Create(Self); L.Parent := Self;
  L.SetBounds(16, 503, 980, 24);
  L.Caption := 'Відносні стовпчики різниць за зонами — НЕ сумарна енергія та НЕ джоулі процесу:';
  FGraph := TPaintBox.Create(Self); FGraph.Parent := Self;
  FGraph.SetBounds(16, 532, 1055, 86); FGraph.OnPaint := @DrawGraph;
  FStatus := TLabel.Create(Self); FStatus.Parent := Self;
  FStatus.SetBounds(16, 625, 1050, 35);
  ClearView;
end;

{ Знімки не утримуємо: поля TEdit — позичені шляхи; FRows — керований
  FPC-масив host QWord із життям лише до зміни вводу. TForm є власником
  усіх LCL віджетів, FGraph лише перемальовує FRows. }
procedure TEnergyWindow.ClearView;
var I, J: Integer;
begin
  SetLength(FRows, 0);
  FGrid.RowCount := 2;
  for I := 1 to FGrid.RowCount - 1 do
    for J := 0 to FGrid.ColCount - 1 do FGrid.Cells[J, I] := '';
  FStatus.Caption := 'Немає перевірених даних; енергію SENS не виміряно.';
  FGraph.Invalidate;
end;

procedure TEnergyWindow.Changed(Sender: TObject);
begin
  ClearView;
end;

procedure TEnergyWindow.SelectBefore(Sender: TObject);
begin if FPicker.Execute then FBefore.Text := FPicker.FileName; end;
procedure TEnergyWindow.SelectAfter(Sender: TObject);
begin if FPicker.Execute then FAfter.Text := FPicker.FileName; end;

{ Тільки готовий sensrapl має право виконувати фізичне modulo/обмеження
  wrap. TProcess НЕ викликає shell; stdout/stderr bounded 64 KiB;
  повний nonzero exit не допускає часткового графічного результату. }
function TEnergyWindow.CaptureDifference: RawByteString;
var P: TProcess; B: array[0..4095] of Byte; N: LongInt;
begin
  Result := '';
  if not FileExists(FCli.Text) then
    raise Exception.Create('Не знайдено виконуваний sensrapl');
  if not FileExists(FBefore.Text) or not FileExists(FAfter.Text) then
    raise Exception.Create('Не знайдено фізичні знімки RAPL1');
  P := TProcess.Create(nil);
  try
    P.Executable := FCli.Text;
    P.Parameters.Add('--різниця');
    P.Parameters.Add(FBefore.Text);
    P.Parameters.Add(FAfter.Text);
    P.Parameters.Add(FTime.Text);
    P.Parameters.Add(FPower.Text);
    P.Options := [poUsePipes, poStderrToOutPut];
    P.Execute;
    repeat
      N := P.Output.Read(B, SizeOf(B));
      if N > 0 then begin
        if Length(Result) + N > 65536 then
          raise Exception.Create('Вивід sensrapl завеликий');
        SetLength(Result, Length(Result) + N);
        Move(B[0], Result[Length(Result) - N + 1], N);
      end;
    until N <= 0;
    P.WaitOnExit;
    if P.ExitStatus <> 0 then
      raise Exception.Create('Нативний sensrapl відхилив пару знімків');
  finally
    P.Free;
  end;
end;

function TEnergyWindow.DecodeReport(const Data: RawByteString): TZoneViews;
var Lines, Columns, Header: TStringList; I: Integer;
    Z: TZoneView;
begin
  SetLength(Result, 0);
  Lines := TStringList.Create;
  try
    Lines.Text := String(Data);
    if (Lines.Count < 2) or (Lines.Count > 257) then
      raise Exception.Create('Некоректна кількість рядків RAPL');
    Header := Fields(Lines[0], 3);
    try
      if (Header[0] <> 'RAPL-DELTA1') or
         (Header[1] <> 'elapsed_us=' + FTime.Text) or
         (Header[2] <> 'max_watts=' + FPower.Text) then
        raise Exception.Create('Заголовок не відповідає явним параметрам');
    finally Header.Free; end;
    for I := 1 to Lines.Count - 1 do begin
      Columns := Fields(Lines[I], 6);
      try
        Z.Key := Columns[0]; Z.NameText := Columns[1];
        if (Z.Key = '') or (Z.NameText = '') or
           (Pos('intel-rapl:', Z.Key) = 0) or
           (Length(Z.Key) > 240) or (Length(Z.NameText) > 128) then
          raise Exception.Create('Некоректна ідентичність зони');
        Z.BeforeEnergy := StrictUnsigned(Columns[2]);
        Z.AfterEnergy := StrictUnsigned(Columns[3]);
        Z.RangeEnergy := StrictUnsigned(Columns[4]);
        Z.DeltaEnergy := StrictUnsigned(Columns[5]);
        if (Z.RangeEnergy = 0) or
           (Z.BeforeEnergy >= Z.RangeEnergy) or
           (Z.AfterEnergy >= Z.RangeEnergy) or
           (Z.DeltaEnergy >= Z.RangeEnergy) then
          raise Exception.Create('Недопустима точна зона');
        if (I > 1) and (CompareStr(Result[I - 2].Key, Z.Key) >= 0) then
          raise Exception.Create('Повторення або несортована зона');
        SetLength(Result, I);
        Result[I - 1] := Z;
      finally Columns.Free; end;
    end;
  finally Lines.Free; end;
end;

procedure TEnergyWindow.DisplayRows(const Rows: TZoneViews);
var I: Integer;
begin
  FRows := Rows;
  FGrid.RowCount := Length(FRows) + 1;
  for I := 0 to High(FRows) do begin
    FGrid.Cells[0, I + 1] := FRows[I].Key;
    FGrid.Cells[1, I + 1] := FRows[I].NameText;
    FGrid.Cells[2, I + 1] := UIntToStr(FRows[I].BeforeEnergy);
    FGrid.Cells[3, I + 1] := UIntToStr(FRows[I].AfterEnergy);
    FGrid.Cells[4, I + 1] := UIntToStr(FRows[I].RangeEnergy);
    FGrid.Cells[5, I + 1] := UIntToStr(FRows[I].DeltaEnergy);
  end;
  FStatus.Caption := 'Пара перевірена нативним FPC; зон=' +
    IntToStr(Length(FRows)) +
    '. Енергія SENS/процесу не встановлена; зони не підсумовано.';
  FGraph.Invalidate;
end;

procedure TEnergyWindow.RunClick(Sender: TObject);
var Rows: TZoneViews;
begin
  ClearView;
  try
    { Не інтерпретувати текст як мовні атоми чи числа D12+: це host TSV. }
    Rows := DecodeReport(CaptureDifference);
    DisplayRows(Rows);
  except
    on E: Exception do begin
      ClearView;
      FStatus.Caption := 'ВІДМОВА: ' + E.Message +
        ' — попередні дані скинуто; енергію не виміряно.';
    end;
  end;
end;

procedure TEnergyWindow.DrawGraph(Sender: TObject);
var I, Count, BarSize, MaxBars, X, Y: Integer; MaxEnergy: QWord; Ratio: Extended;
begin
  FGraph.Canvas.Brush.Color := clWhite;
  FGraph.Canvas.FillRect(FGraph.ClientRect);
  Count := Length(FRows);
  if Count = 0 then Exit;
  MaxEnergy := 0;
  for I := 0 to High(FRows) do
    if FRows[I].DeltaEnergy > MaxEnergy then MaxEnergy := FRows[I].DeltaEnergy;
  if MaxEnergy = 0 then Exit; { нуль не є ENERGY_NOT_MEASURED }
  MaxBars := FGraph.ClientWidth - 18;
  if MaxBars < 1 then Exit;
  for I := 0 to High(FRows) do begin
    Y := 4 + (I * 76 div Count);
    if I >= 16 then Break;
    Ratio := Extended(FRows[I].DeltaEnergy) / Extended(MaxEnergy);
    BarSize := Trunc(Ratio * MaxBars);
    X := 5;
    FGraph.Canvas.Brush.Color := clTeal;
    FGraph.Canvas.FillRect(Rect(X, Y, X + BarSize, Y + 3));
  end;
end;

procedure TEnergyWindow.Check(OK: Boolean; const Why: String);
begin
  if not OK then raise Exception.Create('ЛКЛ-ЕНЕРГІЯ: ' + Why);
end;

procedure TEnergyWindow.SelfTest(const CliPath, FirstPath, SecondPath, BadPath: String);
begin
  FCli.Text := CliPath;
  FBefore.Text := FirstPath;
  FAfter.Text := SecondPath;
  FTime.Text := '50000'; FPower.Text := '1000';
  FRun.Click; Application.ProcessMessages;
  Check((Length(FRows) = 2) and
    (FGrid.Cells[0,1] = 'intel-rapl:0') and
    (FGrid.Cells[5,1] = '30') and
    (FGrid.Cells[5,2] = '21') and
    (FRows[0].BeforeEnergy = 99999990) and
    (FRows[0].DeltaEnergy = 30) and
    (FRows[1].DeltaEnergy = 21) and
    (FGraph.Visible), 'пара двох зон або справжній віджет не працює');
  FGraph.Repaint;
  FAfter.Text := BadPath;
  Check((Length(FRows) = 0) and (FGrid.Cells[5,1] = ''),
    'зміна знімка зберігає старі значення');
  FRun.Click;
  Check((Length(FRows) = 0) and
    (Pos('ВІДМОВА', FStatus.Caption) > 0) and
    (FGrid.Cells[5,1] = ''), 'пошкоджений фізичний знімок прийнято');
  FAfter.Text := SecondPath;
  FRun.Click;
  Check((Length(FRows) = 2) and (FGrid.Cells[5,1] = '30'),
    'відновлення після відмови не працює');
  FTime.Text := '100000';
  FRun.Click;
  Check((Length(FRows) = 0) and (FGrid.RowCount = 2) and
    (FGrid.Cells[5,1] = '') and (Pos('ВІДМОВА', FStatus.Caption) > 0),
    'двозначне переповнення не відхилено');
  FTime.Text := '50000';
  FRun.Click;
  Check((Length(FRows) = 2) and (FGrid.Cells[5,2] = '21'),
    'повторна перевірка втратила фізичну різницю');
  FPower.Text := '0';
  FRun.Click;
  Check((Length(FRows) = 0) and (FGrid.Cells[5,1] = ''),
    'нульову межу потужності прийнято');
  FPower.Text := '1000';
  FRun.Click;
  Check(Length(FRows) = 2, 'нативне відновлення після помилки неможливе');
  WriteLn('ЛКЛ-ЕНЕРГІЯ-ГАРАЗД Lazarus=GTK2 FPC=sensrapl '+
    'зони=2 wrap=30 stale=очищено відмови=відхилено');
end;

begin
  Application.Initialize;
  Window := TEnergyWindow.Create(nil);
  try
    if (ParamCount = 5) and (ParamStr(1) = '--самоперевірка') then begin
      try
        Window.Show;
        Application.ProcessMessages;
        Window.SelfTest(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5));
      except
        on E: Exception do begin
          WriteLn(StdErr, 'ЛКЛ-ЕНЕРГІЯ-ВІДМОВА: ', E.Message);
          Halt(1);
        end;
      end;
    end else
      Application.Run;
  finally
    Window.Free;
  end;
end.
{ Питання: 1) Чому GUI не рахує modulo? 2) Як захищено від stale view?
  3) Чому вкладені зони окремі? 4) Хто відповідає за FRows lifetime?
  5) Чому відносна графіка не є енергією SENS-процесу? }
