{ Lazarus/LCL: фізичний спектр точних двійкових доменів SENS.
  Лише візуалізація вже допущених wsm.t5m / wsm.d2source / wsm.binarybind.
  Частота слова не дає мовного закону, викличності або значення. }
program domain_spectrum;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Dialogs, Graphics, Types,
  wsm.t5m, wsm.d2source, wsm.domain, wsm.bind, wsm.binarybind;

const
  MaxVisibleWords = 16384;
  LeftInset = 32;
  BottomInset = 38;
type
  TSpectrumForm = class(TForm)
  private
    Graph: TPaintBox;
    Details: TListBox;
    Status: TLabel;
    OpenButton: TButton;
    Dialog: TOpenDialog;
    Words: TBinaryWords;
    Counts: array[1..9] of SizeInt;
    Selected: Integer;
    procedure ResetData;
    procedure Failure(const Reason: String);
    procedure OpenClick(Sender: TObject);
    procedure GraphPaint(Sender: TObject);
    procedure GraphMouse(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure PickDomain(Domain: Integer);
    function DomainAt(X, AWidth: Integer): Integer;
    procedure PaintSpectrum(Target: TCanvas; AWidth, AHeight: Integer);
    procedure Demand(TestOK: Boolean; const Reason: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadPhysical(const FileName: String): Boolean;
    procedure SelfTest(const GoodFile, BadT5M, BadD2: String);
  end;

var Window: TSpectrumForm;

constructor TSpectrumForm.Create(AOwner: TComponent);
var TopBar, BottomBar: TPanel;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — спектр точних двійкових доменів';
  Width := 1000;
  Height := 700;
  Position := poScreenCenter;

  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 48;
  TopBar.BevelOuter := bvNone;
  OpenButton := TButton.Create(Self);
  OpenButton.Parent := TopBar;
  OpenButton.SetBounds(12, 8, 220, 32);
  OpenButton.Caption := 'Відкрити двійковий .sens…';
  OpenButton.OnClick := @OpenClick;
  Dialog := TOpenDialog.Create(Self);
  Dialog.Title := 'Виберіть фізичний SENS';
  Dialog.Filter := 'Двійковий SENS (*.sens)|*.sens';

  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 40;
  Status := TLabel.Create(Self);
  Status.Parent := BottomBar;
  Status.SetBounds(12, 10, 950, 24);

  Graph := TPaintBox.Create(Self);
  Graph.Parent := Self;
  Graph.Align := alTop;
  Graph.Height := 320;
  Graph.OnPaint := @GraphPaint;
  Graph.OnMouseDown := @GraphMouse;

  Details := TListBox.Create(Self);
  Details.Parent := Self;
  Details.Align := alClient;
  Details.IntegralHeight := False;

  ResetData;
end;

procedure TSpectrumForm.ResetData;
var D: Integer;
begin
  SetLength(Words, 0);
  for D := 1 to 9 do Counts[D] := 0;
  Selected := 0;
  Details.Items.Clear;
  Status.Caption := 'Виберіть фізичний .sens. Графік показує кількість слів, а не семантику.';
  Graph.Invalidate;
end;

procedure TSpectrumForm.Failure(const Reason: String);
begin
  ResetData;
  Status.Caption := 'Помилка: ' + Reason;
end;

function TSpectrumForm.LoadPhysical(const FileName: String): Boolean;
var
  F: TFileStream;
  Physical: RawByteString;
  Tables: TDomainSet;
  Candidate: TBinaryWords;
  TempCounts: array[1..9] of SizeInt;
  I, D: SizeInt;
begin
  Result := False;
  ResetData;
  try
    if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
      raise Exception.Create('потрібен фізичний двійковий файл .sens');
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create('файл порожній або перевищує 4 МіБ');
      SetLength(Physical, SizeInt(F.Size));
      F.ReadBuffer(Physical[1], Length(Physical));
    finally
      F.Free;
    end;
    LoadPinnedDomains('external/sens', Tables);
    BindT5MBinary(Physical, Tables, Candidate);
    if (Length(Candidate) = 0) or (Length(Candidate) > MaxVisibleWords) then
      raise Exception.Create('перевищена межа 16384 фізичних слів або немає даних');

    for D := 1 to 9 do TempCounts[D] := 0;
    for I := 0 to High(Candidate) do begin
      D := Candidate[I].Key.Width;
      if (D < 1) or (D > 9) or (D = 2) then
        raise Exception.Create('недопущена ширина фізичного слова');
      { D1:0 і D3:000 навмисно належать різним стовпчикам. }
      Inc(TempCounts[D]);
    end;

    { Атомарно публікуємо результат лише після повного допуску. }
    Words := Candidate;
    for D := 1 to 9 do Counts[D] := TempCounts[D];
    Status.Caption := 'Допущено слів: ' + IntToStr(Length(Words)) +
      ' · натисніть D1–D9 · викличність не доведено';
    Graph.Invalidate;
    Result := True;
  except
    on E: ED2SourceError do
      Failure('фізичне слово ' + IntToStr(E.WordIndex) + ': ' + E.Message);
    on E: Exception do Failure(E.Message);
  end;
end;

function TSpectrumForm.DomainAt(X, AWidth: Integer): Integer;
var Step, D: Integer;
begin
  Result := 0;
  if AWidth < 180 then Exit;
  Step := (AWidth - LeftInset - 16) div 9;
  for D := 1 to 9 do
    if (X >= LeftInset + (D-1)*Step + Step div 4) and
       (X < LeftInset + (D-1)*Step + 3*Step div 4) then
      Exit(D);
end;

procedure TSpectrumForm.PickDomain(Domain: Integer);
var
  I: SizeInt;
  Row, Surface: RawByteString;
begin
  if (Domain < 1) or (Domain > 9) then Exit;
  Selected := Domain;
  Details.Items.Clear;
  for I := 0 to High(Words) do
    if Words[I].Key.Width = Domain then begin
      Surface := Words[I].Ukrainian;
      if Surface = '' then Surface := '—';
      Row := '№ ' + IntToStr(Words[I].WordIndex) +
        ' · D' + IntToStr(Domain) + ' · ' +
        KeyBits(Words[I].Key) + ' · ' + Surface;
      Details.Items.Add(String(Row));
    end;
  Status.Caption := 'D' + IntToStr(Domain) +
    ': фізичних слів ' + IntToStr(Counts[Domain]) +
    ' · точні біти та проєкція ук; не семантичний закон';
  Graph.Invalidate;
end;

procedure TSpectrumForm.PaintSpectrum(Target: TCanvas; AWidth, AHeight: Integer);
var
  D, Step, X, TopY, PlotBottom, MaxCount, PlotHeight, BarHeight: Integer;
begin
  Target.Brush.Color := clWhite;
  Target.FillRect(Rect(0, 0, AWidth, AHeight));
  if (Length(Words) = 0) or (AWidth < 180) or (AHeight < 100) then Exit;

  MaxCount := 1;
  for D := 1 to 9 do
    if Counts[D] > MaxCount then MaxCount := Counts[D];
  Step := (AWidth - LeftInset - 16) div 9;
  PlotBottom := AHeight - BottomInset;
  PlotHeight := PlotBottom - 28;
  Target.Font.Color := clBlack;
  Target.Font.Size := 10;
  Target.Pen.Style := psClear;
  for D := 1 to 9 do begin
    X := LeftInset + (D-1)*Step + Step div 4;
    BarHeight := Trunc((Int64(PlotHeight) * Counts[D]) div MaxCount);
    TopY := PlotBottom - BarHeight;
    if Counts[D] > 0 then begin
      if Selected = D then Target.Brush.Color := clRed
      else Target.Brush.Color := clNavy;
      Target.FillRect(Rect(X, TopY, X + Step div 2, PlotBottom));
    end;
    Target.Brush.Color := clWhite;
    Target.TextOut(X, PlotBottom + 5, 'D' + IntToStr(D));
    Target.TextOut(X, 8, IntToStr(Counts[D]));
  end;
  Target.Pen.Style := psSolid;
end;

procedure TSpectrumForm.GraphPaint(Sender: TObject);
begin
  PaintSpectrum(Graph.Canvas, Graph.Width, Graph.Height);
end;

procedure TSpectrumForm.GraphMouse(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var D: Integer;
begin
  if Button <> mbLeft then Exit;
  if (Y < 0) or (Y > Graph.Height) then Exit;
  D := DomainAt(X, Graph.Width);
  if D > 0 then PickDomain(D);
end;

procedure TSpectrumForm.OpenClick(Sender: TObject);
begin
  if Dialog.Execute then LoadPhysical(Dialog.FileName);
end;

procedure TSpectrumForm.Demand(TestOK: Boolean; const Reason: String);
begin
  if not TestOK then raise Exception.Create('фізична перевірка LCL: ' + Reason);
end;

procedure TSpectrumForm.SelfTest(const GoodFile, BadT5M, BadD2: String);
var Bitmap: TBitmap; Step, X3: Integer;
begin
  Demand((Graph.Parent = Self) and (Details.Parent = Self),
    'справжні LCL віджети не створено');
  Demand(LoadPhysical(GoodFile), 'позитивний T5M не допущено');
  Demand(Length(Words) = 3, 'потрібні три точні слова');
  Demand((Counts[1] = 1) and (Counts[3] = 2) and (Counts[2] = 0),
    'точні D1/D3 домени змішані');

  Step := (Graph.Width - LeftInset - 16) div 9;
  X3 := LeftInset + 2*Step + Step div 2;
  GraphMouse(Graph, mbLeft, [], X3, Graph.Height div 2);
  Demand(Selected = 3, 'миша не обрала D3');
  Demand(Details.Items.Count = 2, 'D3 не містить двох фізичних слів');
  Demand((Pos('111', Details.Items[0]) > 0) and
         (Pos('000', Details.Items[1]) > 0),
    'утрачено точні біти D3 або порядок фізичних слів');
  Demand(Pos('сполучити', Details.Items[0]) > 0,
    'утрачено pinned українську проєкцію ук для D3:111');

  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(Graph.Width, Graph.Height);
    PaintSpectrum(Bitmap.Canvas, Bitmap.Width, Bitmap.Height);
    Demand(Bitmap.Canvas.Pixels[X3, Bitmap.Height - BottomInset - 12] = clRed,
      'справжній Canvas не зафарбував вибраний стовпчик D3');
  finally Bitmap.Free; end;

  GraphMouse(Graph, mbLeft, [],
    LeftInset + Step div 2, Graph.Height div 2);
  Demand((Selected = 1) and (Details.Items.Count = 1) and
    (Pos('D1', Details.Items[0]) > 0) and
    (Pos('1', Details.Items[0]) > 0) and
    (Pos('так', Details.Items[0]) > 0),
    'D1 помилково змішано з D3');

  Demand(not LoadPhysical(BadT5M), 'поганий T5M пройшов');
  Demand((Length(Words) = 0) and (Details.Items.Count = 0) and
    (Counts[1] = 0) and (Counts[3] = 0) and (Selected = 0),
    'після T5M-помилки залишились дані');
  Demand(Pos('Помилка:', Status.Caption) = 1,
    'немає статусу фізичної помилки');
  Demand(not LoadPhysical(BadD2), 'незакрита D2 форма пройшла');
  Demand((Length(Words) = 0) and (Details.Items.Count = 0),
    'після D2-помилки залишився граф');
  Demand(not LoadPhysical('немає-такого-файлу.sens'),
    'відсутній файл пройшов');
  Demand((Length(Words) = 0) and (Details.Items.Count = 0),
    'відсутній файл залишив попередні слова');

  WriteLn('LCL-СПЕКТР-ГАРАЗД Lazarus=справжній Canvas=намальовано',
    ' вибір-мишею=так D1_не_дорівнює_D3=так UTF8=проєкція',
    ' пошкоджені=відхилено виконання=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — спектр двійкових доменів';
    Application.CreateForm(TSpectrumForm, Window);
    if (ParamCount >= 1) and (ParamStr(1) = '--selftest') then begin
      if ParamCount <> 4 then
        raise Exception.Create('самоперевірка потребує три фізичні файли');
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(2), ParamStr(3), ParamStr(4));
    end else if (ParamCount = 0) then
      Application.Run
    else if ParamCount = 1 then begin
      Window.LoadPhysical(ParamStr(1));
      Application.Run;
    end else
      raise Exception.Create('некоректна кількість аргументів');
  except
    on E: Exception do begin
      WriteLn(StdErr, 'LCL-СПЕКТР-ПОМИЛКА: ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
