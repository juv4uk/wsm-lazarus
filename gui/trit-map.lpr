{ Фізична стрічка тритів SENS. Візуалізація не встановлює мовних законів.
  Усі слова й тритові адреси бере з чинного wsm.physloc (pinned T5M). }
program sens_trit_map;
{$mode objfpc}{$H+}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Graphics, Dialogs, wsm.t5m, wsm.physloc;

const
  MaxVisibleTrits = 1020;
  PerRow = 25;
  CellWidth = 30;
  CellHeight = 40;

type
  TTritWindow = class(TForm)
  private
    FScroll: TScrollBox;
    FPaint: TPaintBox;
    FInfo: TMemo;
    FStatus: TLabel;
    FDialog: TOpenDialog;
    FTrits: RawByteString;
    FWords: TExactWords;
    FSpans: TPhysicalWordSpans;
    FSelected: SizeInt;
    procedure OpenClicked(Sender: TObject);
    procedure PaintTrits(Sender: TObject);
    procedure MouseTrit(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ClearView;
    procedure SelectTrit(Index: SizeInt);
    procedure Demand(Condition: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadPhysicalFile(const Path: String): Boolean;
    procedure SelfCheck(const GoodFile, BadFile, BigFile: String);
  end;

var Window: TTritWindow;

constructor TTritWindow.Create(AOwner: TComponent);
var
  Bar, Bottom: TPanel;
  OpenButton: TButton;
begin
  inherited CreateNew(AOwner,1);
  Caption := 'SENS — фізична тритова стрічка';
  Width := 930;
  Height := 710;
  Position := poScreenCenter;
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 54;
  Bar.BevelOuter := bvNone;
  OpenButton := TButton.Create(Self);
  OpenButton.Parent := Bar;
  OpenButton.Caption := 'Відкрити двійковий .sens…';
  OpenButton.SetBounds(12, 9, 250, 35);
  OpenButton.OnClick := @OpenClicked;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Filter := 'Двійковий SENS (*.sens)|*.sens';
  FDialog.Title := 'Виберіть фізичний двійковий файл';
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 32;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Bottom;
  FStatus.SetBounds(12, 8, 900, 20);
  FInfo := TMemo.Create(Self);
  FInfo.Parent := Self;
  FInfo.Align := alBottom;
  FInfo.Height := 140;
  FInfo.ReadOnly := True;
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.AutoScroll := True;
  FPaint := TPaintBox.Create(Self);
  FPaint.Parent := FScroll;
  FPaint.SetBounds(0, 0, PerRow*CellWidth, CellHeight);
  FPaint.OnPaint := @PaintTrits;
  FPaint.OnMouseDown := @MouseTrit;
  ClearView;
end;

procedure TTritWindow.Demand(Condition: Boolean; const Why: String);
begin
  if not Condition then
    raise Exception.Create('графічна перевірка: ' + Why);
end;

procedure TTritWindow.ClearView;
begin
  FTrits := '';
  SetLength(FWords, 0);
  SetLength(FSpans, 0);
  FSelected := -1;
  FInfo.Clear;
  FPaint.Height := CellHeight;
  FPaint.Invalidate;
  FStatus.Caption := '0/1 — двійкові біти; 2 — фізичний роздільник або заповнення.';
end;

procedure TTritWindow.SelectTrit(Index: SizeInt);
var
  I, Found: SizeInt;
  Role: String;
begin
  if (Index < 0) or (Index >= Length(FTrits)) then
    raise Exception.Create('поза фізичною тритовою стрічкою');
  FSelected := Index;
  Found := -1;
  for I := 0 to High(FSpans) do begin
    if (Index >= FSpans[I].TritStart) and
       (Index < FSpans[I].TritEnd) then begin Found := I; Break; end;
  end;
  FInfo.Clear;
  FInfo.Lines.Add('Трит №: ' + IntToStr(Index));
  FInfo.Lines.Add('Фізичний байт №: ' + IntToStr(Index div 5));
  FInfo.Lines.Add('Місце в байті: ' + IntToStr(Index mod 5));
  FInfo.Lines.Add('Значення трита: ' + String(FTrits[Index+1]));
  if Found >= 0 then begin
    Role := 'двійковий біт слова';
    FInfo.Lines.Add('Роль: ' + Role);
    FInfo.Lines.Add('Слово №: ' + IntToStr(FSpans[Found].WordIndex));
    FInfo.Lines.Add('Точні біти: ' + String(FWords[Found]));
    FInfo.Lines.Add('Точна ширина: ' + IntToStr(Length(FWords[Found])));
    FInfo.Lines.Add('Трити слова [початок,кінець): ' +
      IntToStr(FSpans[Found].TritStart) + ', ' +
      IntToStr(FSpans[Found].TritEnd));
  end else begin
    if Index > FSpans[High(FSpans)].TritEnd then
      Role := 'кінцеве заповнення'
    else if Index = FSpans[High(FSpans)].TritEnd then
      Role := 'кінцеве заповнення'
    else
      Role := 'фізичний роздільник';
    FInfo.Lines.Add('Роль: ' + Role);
    FInfo.Lines.Add('Власного двійкового слова немає');
  end;
  FInfo.Lines.Add('Мовна викличність: не визначається інтерфейсом');
  FPaint.Invalidate;
end;

procedure TTritWindow.MouseTrit(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var Index: SizeInt;
begin
  if Button <> mbLeft then Exit;
  if (X < 0) or (Y < 0) or (X >= PerRow*CellWidth) then Exit;
  Index := (Y div CellHeight)*PerRow + (X div CellWidth);
  if Index < Length(FTrits) then SelectTrit(Index);
end;

procedure TTritWindow.PaintTrits(Sender: TObject);
var
  I, X, Y: SizeInt;
  C: TColor;
begin
  FPaint.Canvas.Brush.Color := clWhite;
  FPaint.Canvas.FillRect(0,0,FPaint.Width,FPaint.Height);
  for I := 0 to Length(FTrits)-1 do begin
    X := (I mod PerRow)*CellWidth;
    Y := (I div PerRow)*CellHeight;
    case FTrits[I+1] of
      '0': C := clTeal;
      '1': C := clNavy;
      else C := clGray;
    end;
    if I = FSelected then C := clMaroon;
    FPaint.Canvas.Brush.Color := C;
    FPaint.Canvas.Pen.Color := clWhite;
    FPaint.Canvas.Rectangle(X+1,Y+1,X+CellWidth-1,Y+CellHeight-8);
    FPaint.Canvas.Font.Color := clWhite;
    FPaint.Canvas.TextOut(X+10,Y+8,FTrits[I+1]);
    FPaint.Canvas.Font.Color := clBlack;
    FPaint.Canvas.TextOut(X+2,Y+CellHeight-8,IntToStr(I div 5));
    if (I mod 5) = 4 then begin
      FPaint.Canvas.Pen.Color := clRed;
      FPaint.Canvas.Line(X+CellWidth-1,Y,X+CellWidth-1,Y+CellHeight-6);
    end;
  end;
end;

function TTritWindow.LoadPhysicalFile(const Path: String): Boolean;
var
  Stream: TFileStream;
  Physical, Trits: RawByteString;
  Words: TExactWords;
  Spans: TPhysicalWordSpans;
  I, J: SizeInt;
begin
  Result := False;
  ClearView;
  try
    if LowerCase(ExtractFileExt(Path)) <> '.sens' then
      raise Exception.Create('потрібен фізичний файл .sens');
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size <= 0) or (Stream.Size*5 > MaxVisibleTrits) then
        raise Exception.Create('фізичний файл перевищує 1020 видимих тритів');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free; end;
    DecodeT5MWithLocations(Physical,Words,Spans);
    { Розташування вже перевірене чинним reader. Не декодуємо байти вдруге:
      заповнюємо тільки видимі позиції точними словами та фізичними 2. }
    SetLength(Trits,Length(Physical)*5);
    for I:=1 to Length(Trits) do Trits[I]:='2';
    for I:=0 to High(Words) do
      for J:=1 to Length(Words[I]) do
        Trits[Spans[I].TritStart+J] := Words[I][J];
    FTrits := Trits;
    FWords := Words;
    FSpans := Spans;
    FPaint.Height := ((Length(FTrits)+PerRow-1) div PerRow)*CellHeight;
    FStatus.Caption := 'Фізичних тритів: '+IntToStr(Length(FTrits))+
      '; слів: '+IntToStr(Length(FWords))+
      '; межа байта — п’ять тритів; виконання відсутнє.';
    FPaint.Invalidate;
    Result := True;
  except on E: Exception do begin
    ClearView;
    FStatus.Caption := 'Помилка: '+E.Message;
  end; end;
end;

procedure TTritWindow.OpenClicked(Sender: TObject);
begin
  if FDialog.Execute then LoadPhysicalFile(FDialog.FileName);
end;

procedure TTritWindow.SelfCheck(const GoodFile, BadFile, BigFile: String);
begin
  Demand(LoadPhysicalFile(GoodFile),'вхід з точними словами');
  Demand(Length(FTrits)=20,'4 байти дають рівно 20 тритів');
  Demand((FTrits[1]='1') and (FTrits[2]='0') and
    (FTrits[3]='2') and (FTrits[4]='1') and (FTrits[7]='2'),
    'початкові біти та роздільники');
  Demand((FTrits[19]='2') and (FTrits[20]='2'),
    'завершальне заповнення');
  Demand((Length(FWords)=6) and (FWords[1]='111') and
    (FSpans[1].TritStart=3) and (FSpans[1].TritEnd=6),
    'точні координати другого слова');
  SelectTrit(3);
  Demand((Pos('Слово №: 2',FInfo.Text)>0) and
    (Pos('Точні біти: 111',FInfo.Text)>0), 'вибраний біт слова');
  SelectTrit(2);
  Demand(Pos('Роль: фізичний роздільник',FInfo.Text)>0,
    'роздільник не маскується двійковим бітом');
  SelectTrit(19);
  Demand(Pos('Роль: кінцеве заповнення',FInfo.Text)>0,
    'кінцеве заповнення не є словом');
  Demand(not LoadPhysicalFile(BadFile),'пошкоджений T5M');
  Demand((FTrits='') and (FInfo.Lines.Count=0) and
    (Pos('Помилка:',FStatus.Caption)=1), 'старий екран після помилки');
  Demand(not LoadPhysicalFile('неіснуючий.sens'),'немає файлу');
  Demand((FTrits='') and (FInfo.Lines.Count=0),'старий стан після відсутнього файла');
  Demand(not LoadPhysicalFile(BigFile),'ліміт видимих тритів');
  Demand(FTrits='','часткова стрічка після ліміту');
  WriteLn('LCL-ТРИТИ-ГАРАЗД GTK2=так TPaintBox=справжній ',
    'тритів=20 байтів=4 біт=точний роздільник=2 заповнення=2 ',
    'вибір=фізичний помилки=очищено семантика=ні');
end;

begin
  Application.Initialize;
  Application.Title := 'SENS — фізична тритова стрічка';
  Application.CreateForm(TTritWindow,Window);
  if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
    if ParamCount<>4 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4));
    except on E:Exception do begin
      WriteLn(StdErr,'LCL-ТРИТИ-ПОМИЛКА ',E.Message);
      Halt(1);
    end; end;
  end else begin
    if ParamCount=1 then Window.LoadPhysicalFile(ParamStr(1));
    Application.Run;
  end;
end.
