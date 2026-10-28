{ Графічна проєкція вже збережених фізичних кадрів SENS.
  Жодних мовних законів, dispatch, Core4 чи обчислення форм у LCL. }
unit wsm.tracegrid;
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Grids, Dialogs,
  wsm.debugtrace, wsm.domain;

type
  ETraceGridError = class(Exception);

  TTraceGrid = class(TPanel)
  private
    FTable: TStringGrid;
    FCount: SizeInt;
  public
    constructor Create(AOwner: TComponent); override;
    procedure ShowFrames(const Frames: TDebugFrames);
    function Cell(Column, Row: Integer): String;
    function FrameCount: SizeInt;
    function Evidence: RawByteString;
  end;

  TTraceViewerForm = class(TForm)
  private
    FTraceGrid: TTraceGrid;
    FStatus: TLabel;
    procedure ExportClicked(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrames(const Frames: TDebugFrames);
    property TraceGrid: TTraceGrid read FTraceGrid;
  end;

implementation

constructor TTraceGrid.Create(AOwner: TComponent);
var I: Integer;
begin
  inherited Create(AOwner);
  Caption := '';
  FCount := 0;
  FTable := TStringGrid.Create(Self);
  FTable.Parent := Self;
  FTable.Align := alClient;
  FTable.ColCount := 6;
  FTable.FixedCols := 0;
  FTable.FixedRows := 1;
  FTable.RowCount := 2;
  FTable.Options := FTable.Options - [goEditing];
  FTable.Options := FTable.Options + [goRowSelect];
  FTable.ColWidths[0] := 75;
  FTable.ColWidths[1] := 110;
  FTable.ColWidths[2] := 180;
  for I := 3 to 5 do FTable.ColWidths[I] := 110;
  FTable.Cells[0,0] := 'Кадр';
  FTable.Cells[1,0] := 'Домен';
  FTable.Cells[2,0] := 'Точне слово';
  FTable.Cells[3,0] := 'Байт';
  FTable.Cells[4,0] := 'Рядок';
  FTable.Cells[5,0] := 'Стовпець';
end;

procedure TTraceGrid.ShowFrames(const Frames: TDebugFrames);
type
  TRow = array[0..5] of String;
var
  Rows: array of TRow;
  I, J, Index: SizeInt;
  F: TDebugFrame;
  Bits: RawByteString;
begin
  if (Length(Frames) < 1) or (Length(Frames) > MaxTraceDepth) then
    raise ETraceGridError.Create('кількість кадрів має бути від 1 до 128');
  SetLength(Rows, Length(Frames));
  { Перевірити всі дані ДО зміни таблиці: помилкові кадри не
    пошкоджують попереднє фізичне свідчення. }
  for I := 0 to High(Frames) do begin
    Index := High(Frames) - I; { найглибший кадр перший }
    F := Frames[Index];
    try
      Bits := KeyBits(F.Key);
    except
      on E: EDomainError do
        raise ETraceGridError.Create('некоректна двійкова координата кадру');
    end;
    if (F.ByteOffset < 1) or (F.Line < 1) or (F.ByteColumn < 1) then
      raise ETraceGridError.Create('фізичні позиції повинні бути додатними');
    Rows[I][0] := IntToStr(I);
    Rows[I][1] := 'D' + IntToStr(F.Key.Width);
    Rows[I][2] := String(Bits);
    Rows[I][3] := IntToStr(F.ByteOffset);
    Rows[I][4] := IntToStr(F.Line);
    Rows[I][5] := IntToStr(F.ByteColumn);
  end;
  FTable.BeginUpdate;
  try
    FTable.RowCount := Length(Frames) + 1;
    for I := 0 to High(Rows) do
      for J := 0 to 5 do
        FTable.Cells[J, I+1] := Rows[I][J];
    FCount := Length(Frames);
  finally
    FTable.EndUpdate;
  end;
end;

function TTraceGrid.Cell(Column, Row: Integer): String;
begin
  if (Column < 0) or (Column >= 6) or
     (Row < 1) or (Row > FCount) then
    raise ETraceGridError.Create('індекс комірки поза фізичним стеком');
  Result := FTable.Cells[Column, Row];
end;

function TTraceGrid.FrameCount: SizeInt;
begin
  Result := FCount;
end;

function TTraceGrid.Evidence: RawByteString;
var I: SizeInt;
begin
  Result := 'Фізичний стек SENS (найглибший кадр перший)' + #10 +
    'Не є виконанням або джерелом мовної семантики' + #10;
  for I := 1 to FCount do
    Result := Result + 'кадр ' + FTable.Cells[0,I] +
      ': домен ' + FTable.Cells[1,I] +
      ', слово ' + FTable.Cells[2,I] +
      ', байт ' + FTable.Cells[3,I] +
      ', рядок ' + FTable.Cells[4,I] +
      ', стовпець ' + FTable.Cells[5,I] + #10;
end;

constructor TTraceViewerForm.Create(AOwner: TComponent);
var
  Toolbar: TPanel;
  SaveButton: TButton;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — нативний фізичний стек';
  Width := 900;
  Height := 520;
  Position := poScreenCenter;
  Toolbar := TPanel.Create(Self);
  Toolbar.Parent := Self;
  Toolbar.Align := alTop;
  Toolbar.Height := 82;
  SaveButton := TButton.Create(Self);
  SaveButton.Parent := Toolbar;
  SaveButton.Caption := 'Зберегти фізичне свідчення';
  SaveButton.SetBounds(12, 12, 260, 30);
  SaveButton.OnClick := @ExportClicked;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Toolbar;
  FStatus.Caption := 'Очікується знімок фізичних кадрів. Виконання немає.';
  FStatus.SetBounds(12, 52, 760, 24);
  FStatus.AutoSize := True;
  FTraceGrid := TTraceGrid.Create(Self);
  FTraceGrid.Parent := Self;
  FTraceGrid.Align := alClient;
end;

procedure TTraceViewerForm.LoadFrames(const Frames: TDebugFrames);
begin
  FTraceGrid.ShowFrames(Frames);
  FStatus.Caption := 'Допущено кадрів: ' +
    IntToStr(FTraceGrid.FrameCount) + '; точні домени; виконання: немає';
end;

procedure TTraceViewerForm.ExportClicked(Sender: TObject);
var
  Dialog: TSaveDialog;
  EvidenceText: RawByteString;
  Stream: TFileStream;
begin
  if FTraceGrid.FrameCount = 0 then begin
    MessageDlg('Немає перевірених фізичних кадрів', mtInformation, [mbOK], 0);
    Exit;
  end;
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Title := 'Експортувати фізичне свідчення';
    Dialog.Filter := 'Текст UTF-8|*.txt';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if Dialog.Execute then
      try
        EvidenceText := FTraceGrid.Evidence;
        Stream := TFileStream.Create(Dialog.FileName, fmCreate);
        try
          if Length(EvidenceText) > 0 then
            Stream.WriteBuffer(EvidenceText[1], Length(EvidenceText));
        finally
          Stream.Free;
        end;
      except
        on E: Exception do
          MessageDlg('Помилка експорту: ' + E.Message, mtError, [mbOK], 0);
      end;
  finally
    Dialog.Free;
  end;
end;

end.
