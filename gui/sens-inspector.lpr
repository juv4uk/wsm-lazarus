{ Візуальний механічний інспектор SENS на Lazarus/LCL, без мовних законів. }
program sensinspector;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, wsm.t5m, wsm.d2source, wsm.domain, wsm.bind, wsm.binarybind;

const MaxVisibleWords = 16384;
type
  TInspectorForm = class(TForm)
  private
    Grid: TStringGrid;
    Status: TLabel;
    OpenButton: TButton;
    Dialog: TOpenDialog;
    procedure OpenClick(Sender: TObject);
    procedure ClearData;
    procedure Fail(const Reason: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const FileName: String): Boolean;
    procedure SmokeTest(const GoodFile, BadFile: String);
  end;
var
  Window: TInspectorForm;

constructor TInspectorForm.Create(AOwner: TComponent);
var TopBar, BottomBar: TPanel;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — двійковий інспектор';
  Width := 990;
  Height := 560;
  Position := poScreenCenter;
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 48;
  TopBar.BevelOuter := bvNone;
  OpenButton := TButton.Create(Self);
  OpenButton.Parent := TopBar;
  OpenButton.SetBounds(12, 8, 190, 32);
  OpenButton.Caption := 'Відкрити файл .sens…';
  OpenButton.OnClick := @OpenClick;
  Dialog := TOpenDialog.Create(Self);
  Dialog.Title := 'Оберіть двійковий файл SENS';
  Dialog.Filter := 'Двійкові файли SENS (*.sens)|*.sens';
  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 42;
  BottomBar.BevelOuter := bvNone;
  Status := TLabel.Create(Self);
  Status.Parent := BottomBar;
  Status.SetBounds(12, 10, 900, 24);
  Status.Caption := 'Двійкова програма SENS. Викличність не перевіряється.';
  Grid := TStringGrid.Create(Self);
  Grid.Parent := Self;
  Grid.Align := alClient;
  Grid.ColCount := 6;
  Grid.FixedCols := 0;
  Grid.RowCount := 2;
  Grid.FixedRows := 1;
  Grid.Options := Grid.Options + [goColSizing, goRowSelect];
  Grid.Cells[0,0] := 'Слово №';
  Grid.Cells[1,0] := 'Форма №';
  Grid.Cells[2,0] := 'Домен';
  Grid.Cells[3,0] := 'Точні біти';
  Grid.Cells[4,0] := 'Порожнє';
  Grid.Cells[5,0] := 'Українська (ук)';
  Grid.ColWidths[0] := 100;
  Grid.ColWidths[1] := 100;
  Grid.ColWidths[2] := 80;
  Grid.ColWidths[3] := 190;
  Grid.ColWidths[4] := 90;
  Grid.ColWidths[5] := 260;
  ClearData;
end;

procedure TInspectorForm.ClearData;
var J: Integer;
begin
  Grid.RowCount := 2;
  for J := 0 to Grid.ColCount - 1 do Grid.Cells[J,1] := '';
end;

procedure TInspectorForm.Fail(const Reason: String);
begin
  ClearData;
  Status.Caption := 'Помилка: ' + Reason;
end;

function TInspectorForm.LoadFile(const FileName: String): Boolean;
var
  F: TFileStream;
  Physical, Surface: RawByteString;
  Tables: TDomainSet;
  Bound: TBinaryWords;
  I: SizeInt;
begin
  Result := False;
  ClearData;
  Status.Caption := 'Перевірка фізичного файлу…';
  try
    if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
      raise Exception.Create('очікується двійковий файл .sens');
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або надто великий файл');
      SetLength(Physical, SizeInt(F.Size));
      F.ReadBuffer(Physical[1], Length(Physical));
    finally
      F.Free;
    end;
    LoadPinnedDomains('external/sens', Tables);
    BindT5MBinary(Physical, Tables, Bound);
    if Length(Bound) > MaxVisibleWords then
      raise Exception.Create('перевищено межу рядків вікна');
    { Жодна клітинка не оновлюється до повної перевірки вхідних даних. }
    Grid.RowCount := Length(Bound)+1;
    if Grid.RowCount < 2 then Grid.RowCount := 2;
    for I := 0 to High(Bound) do begin
      Grid.Cells[0,I+1] := IntToStr(Bound[I].WordIndex);
      Grid.Cells[1,I+1] := IntToStr(Bound[I].RootIndex);
      Grid.Cells[2,I+1] := 'D'+IntToStr(Bound[I].Key.Width);
      Grid.Cells[3,I+1] := String(KeyBits(Bound[I].Key));
      if Bound[I].IsEmpty then Grid.Cells[4,I+1] := 'так'
      else Grid.Cells[4,I+1] := 'ні';
      Surface := Bound[I].Ukrainian;
      if Surface = '' then Surface := '—';
      Grid.Cells[5,I+1] := String(Surface);
    end;
    Status.Caption := 'Перевірено слів: '+IntToStr(Length(Bound))+
      ' · pinned SENS · викличність не доведено';
    Result := True;
  except
    on E: ED2SourceError do
      Fail('слово '+IntToStr(E.WordIndex)+': '+E.Message);
    on E: Exception do Fail(E.Message);
  end;
end;

procedure TInspectorForm.OpenClick(Sender: TObject);
begin
  if Dialog.Execute then LoadFile(Dialog.FileName);
end;

procedure TInspectorForm.SmokeTest(const GoodFile, BadFile: String);
begin
  if not LoadFile(GoodFile) then
    raise Exception.Create('позитивний вхід: '+Status.Caption);
  if (Grid.RowCount <> 4) or
     (Grid.Cells[2,1] <> 'D3') or (Grid.Cells[3,1] <> '111') or
     (Grid.Cells[5,1] <> 'сполучити') or
     (Grid.Cells[3,2] <> '1') or (Grid.Cells[5,2] <> 'так') or
     (Grid.Cells[3,3] <> '000') or (Grid.Cells[4,3] <> 'так') then
    raise Exception.Create('розбіжність справжніх LCL-клітинок');
  if LoadFile(BadFile) then
    raise Exception.Create('некоректний T5M прийнято');
  if (Grid.RowCount <> 2) or (Grid.Cells[0,1] <> '') or
     (Pos('Помилка:', Status.Caption) <> 1) then
    raise Exception.Create('помилка залишила часткові результати');
  if LoadFile('відсутній.sens') then
    raise Exception.Create('відсутній файл прийнято');
  if (Grid.Cells[0,1] <> '') or (Pos('Помилка:', Status.Caption) <> 1) then
    raise Exception.Create('відсутній файл залишив старі клітинки');
  WriteLn('LCL-ІНСПЕКТОР-ГАРАЗД форма=створена віджети=справжні точні-домени=так відмови=очищають');
end;

begin
  Application.Initialize;
  Application.CreateForm(TInspectorForm, Window);
  if (ParamCount >= 1) and (ParamStr(1) = '--самоперевірка') then begin
    if ParamCount <> 3 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SmokeTest(ParamStr(2), ParamStr(3));
      Window.Free;
      Halt(0);
    except on E: Exception do begin
      WriteLn(StdErr, 'LCL-ІНСПЕКТОР-ПОМИЛКА ', E.Message);
      Halt(1);
    end; end;
  end;
  if ParamCount = 1 then Window.LoadFile(ParamStr(1));
  Application.Run;
end.
