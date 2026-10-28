{ G6.9: фізичні байти машинного ELF64 з чинного pinned D1 backend.
  Лише графічний огляд, не інша семантика та не другий компілятор. }
program sens_elf_inspector;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Graphics, Dialogs, Types, wsm.elfd1, wsm.t5m;
const
  ELFSize = 155;
  HeaderEnd = 64;
  ProgramEnd = 120;
  NativeEnd = 153;
  BarTop = 35;
  BarBottom = 95;
type
  TELFWindow = class(TForm)
  private
    FChart: TPaintBox;
    FGrid: TStringGrid;
    FState, FChoice: TLabel;
    FOpen: TButton;
    FDialog: TOpenDialog;
    FImage: RawByteString;
    FSelected: SizeInt;
    procedure ClearView;
    procedure ShowError(const Why: String);
    procedure OpenClicked(Sender: TObject);
    function Kind(At: SizeInt): String;
    function ColorAt(At: SizeInt): TColor;
    function LE(At, Count: SizeInt): QWord;
    procedure VerifyImage;
    procedure DrawChart(Target: TCanvas; CanvasWidth, CanvasHeight: Integer);
    procedure PaintChart(Sender: TObject);
    procedure ClickChart(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure SelectByte(At: SizeInt);
    procedure Check(Condition: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function OpenPhysical(const FilePath: String): Boolean;
    procedure SelfCheck(const ZeroFile, OneFile, BadFile, D3File,
      EmptyFile: String);
  end;
var Window: TELFWindow;

constructor TELFWindow.Create(AOwner: TComponent);
var TopBar, Bottom: TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption := 'SENS — оглядач машинного ELF64';
  Width := 980; Height := 670; Position := poScreenCenter;
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self; TopBar.Align := alTop;
  TopBar.Height := 54; TopBar.BevelOuter := bvNone;
  FOpen := TButton.Create(Self);
  FOpen.Parent := TopBar;
  FOpen.SetBounds(12,10,300,32);
  FOpen.Caption := 'Породити ELF із фізичного D1 .sens';
  FOpen.OnClick := @OpenClicked;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Filter := 'Фізичний SENS (*.sens)|*.sens';
  FDialog.Title := 'Виберіть двійковий літерал D1';
  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self; Bottom.Align := alBottom;
  Bottom.Height := 60;
  FState := TLabel.Create(Self);
  FState.Parent := Bottom; FState.SetBounds(12,8,945,23);
  FChoice := TLabel.Create(Self);
  FChoice.Parent := Bottom; FChoice.SetBounds(12,34,945,23);
  FChart := TPaintBox.Create(Self);
  FChart.Parent := Self; FChart.Align := alTop;
  FChart.Height := 150;
  FChart.OnPaint := @PaintChart;
  FChart.OnMouseDown := @ClickChart;
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self; FGrid.Align := alClient;
  FGrid.ColCount := 3; FGrid.FixedRows := 1; FGrid.RowCount := 2;
  FGrid.ColWidths[0] := 190; FGrid.ColWidths[1] := 190;
  FGrid.ColWidths[2] := 530;
  FGrid.Cells[0,0] := 'Адреса байта (0-based)';
  FGrid.Cells[1,0] := 'Байт ELF (hex)';
  FGrid.Cells[2,0] := 'Машинний інтервал (не SENS law)';
  ClearView;
end;

procedure TELFWindow.ClearView;
var I: Integer;
begin
  FImage := ''; FSelected := -1;
  FGrid.RowCount := 2;
  for I := 0 to 2 do FGrid.Cells[I,1] := '';
  FState.Caption := 'Фізичний .sens → pinned D1 → наявний нативний backend.';
  FChoice.Caption := 'Машинний ELF64 — не канонічний файл SENS.';
  FChart.Invalidate;
end;

procedure TELFWindow.ShowError(const Why: String);
begin
  ClearView;
  FState.Caption := 'Відхилено: ' + Why;
end;

function TELFWindow.Kind(At: SizeInt): String;
begin
  if At < HeaderEnd then Result := 'Заголовок ELF64'
  else if At < ProgramEnd then Result := 'Програмний заголовок PT_LOAD'
  else if At < NativeEnd then Result := 'Код машини x86-64'
  else Result := 'Байти результату D1 та LF';
end;

function TELFWindow.ColorAt(At: SizeInt): TColor;
begin
  if At < HeaderEnd then Result := clNavy
  else if At < ProgramEnd then Result := clTeal
  else if At < NativeEnd then Result := clPurple
  else Result := clOlive;
end;

function TELFWindow.LE(At, Count: SizeInt): QWord;
var I: SizeInt;
begin
  if (Count<1) or (Count>8) or (At<0) or
     (At>Length(FImage)-Count) then
    raise Exception.Create('поза фізичними межами ELF');
  Result := 0;
  for I := Count-1 downto 0 do
    Result := (Result shl 8) or Ord(FImage[At+I+1]);
end;

procedure TELFWindow.VerifyImage;
begin
  if Length(FImage)<>ELFSize then
    raise Exception.Create('невідома машинна довжина ELF');
  if (Ord(FImage[1])<>$7F) or (Copy(FImage,2,3)<>'ELF') or
     (Ord(FImage[5])<>2) or (Ord(FImage[6])<>1) then
    raise Exception.Create('очікується ELF64 little-endian');
  if (LE(16,2)<>2) or (LE(18,2)<>62) or
     (LE(24,8)<>$400000+ProgramEnd) or
     (LE(32,8)<>HeaderEnd) or
     (LE(52,2)<>HeaderEnd) or (LE(54,2)<>56) or
     (LE(56,2)<>1) then
    raise Exception.Create('невірний ELF64 entry/PHDR/машинний тип');
  if (LE(64,4)<>1) or (LE(68,4)<>5) or
     (LE(96,8)<>ELFSize) or (LE(104,8)<>ELFSize) or
     (LE(112,8)<>$1000) then
    raise Exception.Create('невірний RX PT_LOAD');
  if not (FImage[NativeEnd+1] in ['0','1']) or
     (FImage[ELFSize]<>#10) then
    raise Exception.Create('невірні байти D1/LF');
end;

procedure TELFWindow.DrawChart(Target: TCanvas;
  CanvasWidth, CanvasHeight: Integer);
var I, X1, X2, SX: Integer;
begin
  Target.Brush.Color := clWhite;
  Target.FillRect(Rect(0,0,CanvasWidth,CanvasHeight));
  if (Length(FImage)<>ELFSize) or (CanvasWidth<310) or
     (CanvasHeight<110) then Exit;
  Target.Pen.Style := psClear;
  for I := 0 to ELFSize-1 do begin
    X1 := (I*CanvasWidth) div ELFSize;
    X2 := ((I+1)*CanvasWidth) div ELFSize;
    Target.Brush.Color := ColorAt(I);
    Target.FillRect(Rect(X1,BarTop,X2,BarBottom));
  end;
  Target.Pen.Style := psSolid;
  Target.Font.Color := clBlack;
  Target.TextOut(4,5,'0–63: ELF');
  Target.TextOut((HeaderEnd*CanvasWidth) div ELFSize+3,5,'64–119: PT_LOAD');
  Target.TextOut((ProgramEnd*CanvasWidth) div ELFSize+3,5,'120–152: код');
  Target.TextOut(4,BarBottom+6,
    '153–154: D1 і LF · натисніть байт на кольоровій стрічці');
  if FSelected>=0 then begin
    SX := (FSelected*CanvasWidth) div ELFSize;
    Target.Pen.Color := clRed;
    Target.Pen.Width := 3;
    Target.Line(SX,BarTop-3,SX,BarBottom+3);
    Target.Pen.Width := 1;
  end;
end;

procedure TELFWindow.PaintChart(Sender: TObject);
begin
  DrawChart(FChart.Canvas,FChart.Width,FChart.Height);
end;

procedure TELFWindow.SelectByte(At: SizeInt);
begin
  if (At<0) or (At>=Length(FImage)) then Exit;
  FSelected := At;
  FGrid.Row := At+1;
  FChoice.Caption := 'Байт № ' + IntToStr(At) + ': ' +
    IntToHex(Ord(FImage[At+1]),2) + ' · ' + Kind(At);
  FChart.Invalidate;
end;

procedure TELFWindow.ClickChart(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var At: SizeInt;
begin
  if (Button<>mbLeft) or (Y<BarTop) or (Y>=BarBottom) or
     (X<0) or (X>=FChart.Width) or
     (Length(FImage)<>ELFSize) then Exit;
  At := (Int64(X)*ELFSize) div FChart.Width;
  SelectByte(At);
end;

procedure TELFWindow.OpenClicked(Sender: TObject);
begin
  if FDialog.Execute then OpenPhysical(FDialog.FileName);
end;

function TELFWindow.OpenPhysical(const FilePath: String): Boolean;
var Stream: TFileStream; Source, Candidate: RawByteString; I: SizeInt;
begin
  Result := False;
  ClearView;
  try
    if LowerCase(ExtractFileExt(FilePath))<>'.sens' then
      raise Exception.Create('допускається тільки фізичний .sens');
    Stream := TFileStream.Create(FilePath,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create('фізичний .sens порожній або понад 4 МіБ');
      SetLength(Source,SizeInt(Stream.Size));
      Stream.ReadBuffer(Source[1],Length(Source));
    finally Stream.Free; end;
    { BuildD1ELF перевіряє T5M/D2, pinned координати й existing D3 runtime. }
    Candidate := BuildD1ELF(Source,'external/sens');
    FImage := Candidate; { локальний staged масив, без UI до VerifyImage }
    try VerifyImage;
    except FImage := ''; raise; end;
    FGrid.RowCount := ELFSize+1;
    for I := 0 to ELFSize-1 do begin
      FGrid.Cells[0,I+1] := IntToStr(I);
      FGrid.Cells[1,I+1] := IntToHex(Ord(Candidate[I+1]),2);
      FGrid.Cells[2,I+1] := Kind(I);
    end;
    FState.Caption := 'ELF64 x86-64, 155 байтів; фізичний D1=' +
      String(Candidate[NativeEnd+1]) + '; машинний вихід не є .sens';
    FChart.Invalidate;
    Result := True;
  except
    on E: Exception do ShowError(E.Message);
  end;
end;

procedure TELFWindow.Check(Condition: Boolean; const Why: String);
begin
  if not Condition then
    raise Exception.Create('LCL-ELF-перевірка: ' + Why);
end;

procedure TELFWindow.SelfCheck(const ZeroFile, OneFile, BadFile, D3File,
  EmptyFile: String);
var Bitmap: TBitmap; PixelX: Integer;
begin
  Check((FChart.Parent=Self) and (FGrid.Parent=Self),
    'Lazarus віджети не створено');
  Check(OpenPhysical(ZeroFile),'D1:0 не породив ELF');
  Check((Length(FImage)=ELFSize) and (FGrid.RowCount=ELFSize+1),
    'неповна таблиця машинних байтів');
  Check((FGrid.Cells[0,154]='153') and
    (FGrid.Cells[1,154]='30') and (FGrid.Cells[1,155]='0A'),
    'байти D1:0/LF спотворено');
  Check((FGrid.Cells[2,1]='Заголовок ELF64') and
    (FGrid.Cells[2,121]='Код машини x86-64'),
    'помилкові інтервали ELF');
  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(FChart.Width,FChart.Height);
    DrawChart(Bitmap.Canvas,Bitmap.Width,Bitmap.Height);
    PixelX := (140*Bitmap.Width) div ELFSize;
    Check(Bitmap.Canvas.Pixels[PixelX,BarTop+15]=clPurple,
      'немає справжнього Canvas відображення машинного коду');
  finally Bitmap.Free; end;
  PixelX := (153*FChart.Width) div ELFSize + 2;
  ClickChart(FChart,mbLeft,[],PixelX,BarTop+20);
  Check((FSelected=153) and (FGrid.Row=154) and
    (Pos('30',FChoice.Caption)>0),
    'натискання мишею не обрало машинний байт D1:0');
  Check(OpenPhysical(OneFile),'D1:1 не породив ELF');
  Check((FGrid.Cells[1,154]='31') and (FImage[154]='1'),
    'D1:0 та D1:1 переплутано');
  Check(not OpenPhysical(BadFile),'зіпсований T5M прийнято');
  Check((FImage='') and (FSelected=-1) and
    (FGrid.RowCount=2) and (FGrid.Cells[1,1]=''),
    'помилка T5M залишила ELF');
  Check(Pos('Відхилено:',FState.Caption)=1,
    'немає українського статусу помилки');
  Check(not OpenPhysical(D3File),'D3 видано за D1');
  Check((FImage='') and (FGrid.Cells[0,1]=''),
    'D3 залишив попередній машинний результат');
  Check(not OpenPhysical(EmptyFile),'порожній файл прийнято');
  Check((FImage='') and (FGrid.Cells[0,1]=''),
    'порожній файл залишив граф');
  Check(not OpenPhysical('відсутній-файл.sens'),'відсутній файл прийнято');
  Check((FImage='') and (FSelected=-1),
    'відсутній файл залишив вибір');
  WriteLn('LCL-МАШИННИЙ-ELF-ГАРАЗД Lazarus=справжній',
    ' Canvas=намальовано байти=155 click=точний D1=0,1',
    ' пошкоджені=відхилено семантика=тільки-pinned');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — машинний ELF64';
    Application.CreateForm(TELFWindow,Window);
    if (ParamCount=0) then Application.Run
    else if (ParamCount=1) then begin
      Window.OpenPhysical(ParamStr(1));
      Application.Run;
    end else if (ParamCount=6) and
      (RawByteString(ParamStr(1))=RawByteString('--самоперевірка')) then begin
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6));
    end else raise Exception.Create('некоректні аргументи інспектора ELF64');
  except
    on E: Exception do begin
      WriteLn(StdErr,'LCL-МАШИННИЙ-ELF-ПОМИЛКА: ',E.Message);
      ExitCode := 2;
    end;
  end;
end.
