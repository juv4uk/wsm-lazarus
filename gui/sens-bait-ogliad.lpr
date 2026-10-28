{ Графічний фізичний оглядач байтів SENS. Це транспорт, не семантика. }
program sens_bait_ogliad;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids,
  Dialogs, wsm.t5m;
const MaxVisibleBytes = 4096;
type
  TBaitWindow = class(TForm)
  private
    FGrid: TStringGrid;
    FStatus: TLabel;
    FOpen: TButton;
    FDialog: TOpenDialog;
    FPhysical: RawByteString;
    procedure ClearView;
    procedure OpenClicked(Sender: TObject);
    procedure Require(Condition: Boolean; const Reason: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadPhysical(const Path: String): Boolean;
    procedure SelfCheck(const GoodFile, BadFile, EmptyFile: String);
  end;
var Window: TBaitWindow;

constructor TBaitWindow.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — фізичні байти';
  Width := 690; Height := 640; Position := poScreenCenter;
  FOpen := TButton.Create(Self);
  FOpen.Parent := Self;
  FOpen.SetBounds(12, 12, 270, 36);
  FOpen.Caption := 'Відкрити двійковий файл .sens';
  FOpen.OnClick := @OpenClicked;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Title := 'Виберіть фізичний файл SENS';
  FDialog.Filter := 'Фізична SENS (*.sens)|*.sens';
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(12, 56, 640, 28);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.SetBounds(12, 88, 650, 490);
  FGrid.ColCount := 3;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 2;
  FGrid.ColWidths[0] := 160;
  FGrid.ColWidths[1] := 160;
  FGrid.ColWidths[2] := 220;
  FGrid.Cells[0, 0] := 'Адреса байта (0-based)';
  FGrid.Cells[1, 0] := 'Байт (hex)';
  FGrid.Cells[2, 0] := 'Байт (десятковий)';
  ClearView;
end;

procedure TBaitWindow.Require(Condition: Boolean; const Reason: String);
begin
  if not Condition then raise Exception.Create('перевірка вікна: ' + Reason);
end;

procedure TBaitWindow.ClearView;
var I: Integer;
begin
  FPhysical := '';
  FGrid.RowCount := 2;
  for I := 0 to 2 do FGrid.Cells[I, 1] := '';
  FStatus.Caption := 'Тільки фізичні байти; виконання та мовна викличність не визначаються.';
end;

function TBaitWindow.LoadPhysical(const Path: String): Boolean;
var
  Stream: TFileStream;
  Physical: RawByteString;
  Words: TExactWords;
  I: SizeInt;
begin
  Result := False;
  ClearView;
  try
    if LowerCase(ExtractFileExt(Path)) <> '.sens' then
      raise Exception.Create('потрібен фізичний .sens');
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size < 1) or (Stream.Size > MaxVisibleBytes) then
        raise Exception.Create('фізичний файл порожній або більший за 4096 байтів');
      SetLength(Physical, SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1], Length(Physical));
    finally Stream.Free end;
    DecodeT5M(Physical, Words);
    { Звірено байтову канонічність чинним T5M, до публікації таблиці. }
    if EncodeT5M(Words) <> Physical then
      raise Exception.Create('не канонічне фізичне подання');
    FGrid.RowCount := Length(Physical) + 1;
    for I := 0 to Length(Physical)-1 do begin
      FGrid.Cells[0, I+1] := IntToStr(I);
      FGrid.Cells[1, I+1] := IntToHex(Ord(Physical[I+1]), 2);
      FGrid.Cells[2, I+1] := IntToStr(Ord(Physical[I+1]));
    end;
    FPhysical := Physical;
    FStatus.Caption := 'Перевірено байтів: ' + IntToStr(Length(Physical)) +
      '; точних двійкових слів: ' + IntToStr(Length(Words)) +
      '; семантика не перевірялася.';
    Result := True;
  except on E: Exception do begin
    ClearView;
    FStatus.Caption := 'Помилка: ' + E.Message;
  end end;
end;

procedure TBaitWindow.OpenClicked(Sender: TObject);
begin
  if FDialog.Execute then LoadPhysical(FDialog.FileName);
end;

procedure TBaitWindow.SelfCheck(const GoodFile, BadFile, EmptyFile: String);
begin
  Require(LoadPhysical(GoodFile), 'допуск канонічного T5M');
  Require(Length(FPhysical) = 4, 'чотири фізичних байти');
  Require(FGrid.RowCount = 5, 'чотири рядки байтів');
  Require((FGrid.Cells[0, 1] = '0') and
    (FGrid.Cells[0, 4] = '3'), 'точні фізичні адреси');
  Require((FGrid.Cells[1, 1] = IntToHex(Ord(FPhysical[1]),2)) and
    (FGrid.Cells[2, 4] = IntToStr(Ord(FPhysical[4]))), 'показ реальних байтів');
  Require(not LoadPhysical(BadFile), 'відхилити байт 243');
  Require((FPhysical = '') and (FGrid.RowCount = 2) and
    (FGrid.Cells[0, 1] = ''), 'очистити таблицю на помилці');
  Require(not LoadPhysical(EmptyFile), 'відхилити порожній файл');
  Require((FPhysical = '') and (FGrid.Cells[1, 1] = ''), 'очистити порожній ввід');
  Require(not LoadPhysical('відсутній-файл.sens'), 'відхилити відсутній файл');
  Require(FPhysical = '', 'очистити відсутній файл');
  WriteLn('LCL-БАЙТИ-ГАРАЗД Lazarus=GTK2 фізичних-байтів=4 ',
    'адреси=точні T5M=перевірено помилки=очищено семантика=ні');
end;

begin
  Application.Initialize;
  Application.Title := 'SENS — фізичні байти';
  Application.CreateForm(TBaitWindow, Window);
  if (ParamCount > 0) and (ParamStr(1) = '--самоперевірка') then begin
    if ParamCount <> 4 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2), ParamStr(3), ParamStr(4));
    except on E: Exception do begin
      WriteLn(StdErr, 'LCL-БАЙТИ-ПОМИЛКА ', E.Message);
      Halt(1);
    end end;
  end else begin
    if ParamCount = 1 then Window.LoadPhysical(ParamStr(1));
    Application.Run;
  end;
end.
