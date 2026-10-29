{ G6.21: фізичні байти машинного ELF64 з уже наявних D1/EQ/COND backend.
  Один справжній Lazarus/LCL інспектор, без власної семантики. }
program sens_elf_inspector;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Graphics, Dialogs, Types, wsm.elfd1, wsm.elfeq,
  wsm.elfcond, wsm.elfcondt5m, wsm.binaryexec, wsm.t5m, wsm.elfprobe;
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
    FOpen, FOpenEQ, FOpenCond, FOpenPhysicalCond, FExecuteELF: TButton;
    FEQMode, FCondMode, FPhysicalCondMode: Boolean;
    FPhysicalAnswer, FPhysicalSource, FMachineAnswer: RawByteString;
    FDialog: TOpenDialog;
    FImage: RawByteString;
    FSelected: SizeInt;
    procedure ClearView;
    procedure ShowError(const Why: String);
    procedure OpenClicked(Sender: TObject);
    procedure OpenEQClicked(Sender: TObject);
    procedure OpenCondClicked(Sender: TObject);
    procedure OpenPhysicalCondClicked(Sender: TObject);
    procedure ExecuteELFClicked(Sender: TObject);
    function ExecuteMachine: Boolean;
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
    function OpenPhysical(const FilePath: String;
      AsEQ: Boolean = False; AsCond: Boolean = False;
      AsPhysicalCond: Boolean = False): Boolean;
    procedure SelfCheck(const ZeroFile, OneFile, BadFile, D3File,
      EmptyFile: String);
    procedure SelfCheckEQ(const EqualFile, DifferentFile, D1File,
      BadFile: String);
    procedure SelfCheckCond(const TrueFile, EqualFile, DifferentFile,
      ManyFile, StandaloneEQ, StandaloneD1, BadFile: String);
    procedure SelfCheckPhysicalCond(const YesFile, NoFile, EmptyFile,
      EqFile, BadFile, ForeignFile, D12File: String);
    procedure SelfCheckMachine(const YesFile, NoFile, EmptyFile,
      EqFile, BadFile, ForeignFile, D12File: String);
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
  TopBar.Height := 138; TopBar.BevelOuter := bvNone;
  FOpen := TButton.Create(Self);
  FOpen.Parent := TopBar;
  FOpen.SetBounds(12,10,250,32);
  FOpen.Caption := 'Породити ELF із фізичного D1 .sens';
  FOpen.OnClick := @OpenClicked;
  FOpenEQ := TButton.Create(Self);
  FOpenEQ.Parent := TopBar;
  FOpenEQ.SetBounds(272,10,318,32);
  FOpenEQ.Caption := 'Оглянути машинний D3:101 (тотожне?)';
  FOpenEQ.OnClick := @OpenEQClicked;
  FOpenCond := TButton.Create(Self);
  FOpenCond.Parent := TopBar;
  FOpenCond.SetBounds(600,10,365,32);
  FOpenCond.Caption := 'Оглянути D3:110 (за-умовою)';
  FOpenCond.OnClick := @OpenCondClicked;
  { Четвертий режим — лише фізичний stdout з вже перевіреного backend.
    Немає нового емітера, D7-парсера або викличного диспетчера. }
  FOpenPhysicalCond := TButton.Create(Self);
  FOpenPhysicalCond.Parent := TopBar;
  FOpenPhysicalCond.SetBounds(12,54,953,32);
  FOpenPhysicalCond.Caption := 'Оглянути D3:110 · фізичний результат T5M (.sens)';
  FOpenPhysicalCond.OnClick := @OpenPhysicalCondClicked;
  FExecuteELF := TButton.Create(Self);
  FExecuteELF.Parent := TopBar;
  FExecuteELF.SetBounds(12,96,953,32);
  FExecuteELF.Caption := 'Виконати перевірену машинну D3:110 та звірити фізичний T5M';
  FExecuteELF.OnClick := @ExecuteELFClicked;
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
  FImage := ''; FPhysicalAnswer := ''; FPhysicalSource := '';
  FMachineAnswer := ''; FExecuteELF.Enabled := False; FSelected := -1;
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
  else if FPhysicalCondMode then Result := 'D3:110 · CMP/JNE · фізичний T5M stdout'
  else if FCondMode then Result := 'Машинна D3:110, CMP/JNE x86-64'
  else if FEQMode then Result := 'Машинна D3:101, CMP/SETE x86-64'
  else if At < NativeEnd then Result := 'Код машини x86-64'
  else Result := 'Байти результату D1 та LF';
end;

function TELFWindow.ColorAt(At: SizeInt): TColor;
begin
  if At < HeaderEnd then Result := clNavy
  else if At < ProgramEnd then Result := clTeal
  else if FCondMode or FEQMode or (At < NativeEnd) then Result := clPurple
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
  if FCondMode then begin
    if (Length(FImage)<=160) or (Length(FImage)>ProgramEnd+4096) then
      raise Exception.Create('невідома довжина машинної D3:110 програми');
  end else if FEQMode then begin
    if (Length(FImage)<150) or (Length(FImage)>ProgramEnd+256) then
      raise Exception.Create('невідома довжина машинної D3:101 програми');
  end else if Length(FImage)<>ELFSize then
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
     (LE(96,8)<>QWord(Length(FImage))) or
     (LE(104,8)<>QWord(Length(FImage))) or
     (LE(112,8)<>$1000) then
    raise Exception.Create('невірний RX PT_LOAD');
  if FCondMode then begin
    { Чинний BuildCondELF спочатку допускає точні pinned ключі й
      обчислює фізичну форму лише наявним D3 evaluator.
      Тут перевіряємо ELF-контейнер і x86-64 машинну геометрію,
      а не робимо нове обчислення або людський semantic dispatch. }
    if (LE(80,8)<>$400000) or (LE(88,8)<>$400000) or
       (Copy(FImage,Length(FImage)-3,4)<>#$31#$FF#$0F#$05) then
      raise Exception.Create('змінена геометрія або завершення D3:110 ELF');
    if FPhysicalCondMode and
       (Pos(#$BA#$01#0#0#0+#$0F#$05,FImage)=0) then
      raise Exception.Create('не знайдено фізичний write(1) у ELF64');
    if Ord(FImage[ProgramEnd+1])=$B8 then begin
      if Pos(#$83#$F8#$01#$75,FImage)=0 then
        raise Exception.Create('не знайдено справжнього CMP/JNE для D3:110');
    end else if Copy(FImage,ProgramEnd+1,4)<>#$48#$83#$EC#$08 then
      raise Exception.Create('невідомий машинний початок D3:110');
  end else if FEQMode then begin
    { GUI не виконує EQ і не виводить істинність з його вхідних бітів.
      Довірена функція BuildEqELF передала машинну програму тільки після
      фізичного T5M, точного pinned binder і реального D3 evaluator.
      Тут перевіряємо відмінність machine-контейнера від D1-шаблону. }
    if (Ord(FImage[121])<>$B8) or
       (Ord(FImage[126])<>$B9) or
       not (FImage[122] in [#0,#1]) or
       not (FImage[127] in [#0,#1]) or
       (Pos(#$39#$C8#$0F#$94#$C0,FImage)=0) or
       (Pos(#$0F#$B6#$C0#$04#$30,FImage)=0) then
      raise Exception.Create('немає підтвердженої машинної D3:101 CMP/SETE');
  end else if not (FImage[NativeEnd+1] in ['0','1']) or
     (FImage[ELFSize]<>#10) then
    raise Exception.Create('невірні байти D1/LF');
end;

procedure TELFWindow.DrawChart(Target: TCanvas;
  CanvasWidth, CanvasHeight: Integer);
var I, X1, X2, SX, N: Integer;
begin
  Target.Brush.Color := clWhite;
  Target.FillRect(Rect(0,0,CanvasWidth,CanvasHeight));
  N := Length(FImage);
  if (N<ProgramEnd) or (CanvasWidth<310) or
     (CanvasHeight<110) then Exit;
  Target.Pen.Style := psClear;
  for I := 0 to N-1 do begin
    X1 := (I*CanvasWidth) div N;
    X2 := ((I+1)*CanvasWidth) div N;
    Target.Brush.Color := ColorAt(I);
    Target.FillRect(Rect(X1,BarTop,X2,BarBottom));
  end;
  Target.Pen.Style := psSolid;
  Target.Font.Color := clBlack;
  Target.TextOut(4,5,'0–63: ELF');
  Target.TextOut((HeaderEnd*CanvasWidth) div N+3,5,'64–119: PT_LOAD');
  if FCondMode then begin
    Target.TextOut((ProgramEnd*CanvasWidth) div N+3,5,'120+: CMP/JNE');
    Target.TextOut(4,BarBottom+6,
      'Машинна D3:110 · фізичний T5M при явному режимі; не новий закон');
  end else if FEQMode then begin
    Target.TextOut((ProgramEnd*CanvasWidth) div N+3,5,'120+: CMP/SETE');
    Target.TextOut(4,BarBottom+6,
      'Машинна D3:101 · виконання перевіряє окремий нативний тест');
  end else begin
    Target.TextOut((ProgramEnd*CanvasWidth) div N+3,5,'120–152: код');
    Target.TextOut(4,BarBottom+6,
      '153–154: D1 і LF · натисніть байт на кольоровій стрічці');
  end;
  if FSelected>=0 then begin
    SX := (FSelected*CanvasWidth) div N;
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
     (Length(FImage)<ProgramEnd) then Exit;
  At := (Int64(X)*Length(FImage)) div FChart.Width;
  SelectByte(At);
end;

procedure TELFWindow.OpenClicked(Sender: TObject);
begin
  FDialog.Title := 'Виберіть двійковий літерал D1';
  if FDialog.Execute then OpenPhysical(FDialog.FileName,False);
end;

procedure TELFWindow.OpenEQClicked(Sender: TObject);
begin
  FDialog.Title := 'Виберіть фізичний виклик D3:101';
  if FDialog.Execute then OpenPhysical(FDialog.FileName,True);
end;

procedure TELFWindow.OpenCondClicked(Sender: TObject);
begin
  FDialog.Title := 'Виберіть фізичну форму D3:110';
  if FDialog.Execute then OpenPhysical(FDialog.FileName,False,True);
end;

procedure TELFWindow.OpenPhysicalCondClicked(Sender: TObject);
begin
  FDialog.Title := 'Виберіть двійкову форму D3:110 для T5M';
  if FDialog.Execute then OpenPhysical(FDialog.FileName,False,False,True);
end;

procedure TELFWindow.ExecuteELFClicked(Sender: TObject);
begin
  ExecuteMachine;
end;

{ G6.34: кнопка справді запускає знову згенерований із pinned .sens
  Linux ELF, а не лише показує результат обчислення на Pascal. }
function TELFWindow.ExecuteMachine:Boolean;
var Actual:RawByteString;
begin
  Result:=False;
  FMachineAnswer:='';
  try
    if (not FExecuteELF.Enabled) or (not FPhysicalCondMode) or
       (FPhysicalSource='') or (FPhysicalAnswer='') or (FImage='') then
      raise Exception.Create('спочатку потрібна допущена фізична D3:110');
    ExecutePinnedCondELF(FPhysicalSource,'external/sens',Actual);
    if Actual<>FPhysicalAnswer then
      raise Exception.Create('машинна відповідь не збігається з допущеною');
    FMachineAnswer:=Actual;
    FChoice.Caption:=FChoice.Caption+' · виконаний x86-64 = FPC T5M';
    FState.Caption:='Виконано справжній ELF64: exit=0, T5M побайтово рівні';
    Result:=True;
  except
    on E:Exception do ShowError(E.Message);
  end;
end;

function TELFWindow.OpenPhysical(const FilePath: String;
  AsEQ: Boolean; AsCond, AsPhysicalCond: Boolean): Boolean;
var Stream: TFileStream; Source, Candidate, Answer: RawByteString;
    I: SizeInt; Engine: TBinaryExecutor; AnswerWords: TExactWords;
begin
  Result := False;
  ClearView;
  FEQMode := AsEQ;
  FCondMode := AsCond or AsPhysicalCond;
  FPhysicalCondMode := AsPhysicalCond;
  try
    if (AsEQ and AsCond) or (AsPhysicalCond and (AsEQ or AsCond)) then
      raise Exception.Create('два машинні режими одночасно недопустимі');
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
    if AsPhysicalCond then begin
      Candidate := BuildCondT5MELF(Source,'external/sens');
      { Незалежний чинний нативний D3 evaluator повертає фізичні
        байти. UI не робить з них власної мовної арифметики. }
      Engine := TBinaryExecutor.Create('external/sens');
      try Answer := Engine.ExecutePhysicalT5M(Source);
      finally Engine.Free end;
      DecodeT5M(Answer,AnswerWords);
      if (EncodeT5M(AnswerWords)<>Answer) or
         (Length(AnswerWords)<>1) or
         ((AnswerWords[0]<>'0') and (AnswerWords[0]<>'1') and
          (AnswerWords[0]<>'000')) then
        raise Exception.Create('неканонічний або чужий фізичний результат D3');
    end else if AsCond then Candidate := BuildCondELF(Source,'external/sens')
    else if AsEQ then Candidate := BuildEqELF(Source,'external/sens')
    else Candidate := BuildD1ELF(Source,'external/sens');
    FImage := Candidate; { локальний staged масив, без UI до VerifyImage }
    try VerifyImage;
    except FImage := ''; raise; end;
    FGrid.RowCount := Length(Candidate)+1;
    for I := 0 to Length(Candidate)-1 do begin
      FGrid.Cells[0,I+1] := IntToStr(I);
      FGrid.Cells[1,I+1] := IntToHex(Ord(Candidate[I+1]),2);
      FGrid.Cells[2,I+1] := Kind(I);
    end;
    if AsPhysicalCond then begin
      FPhysicalAnswer := Answer;
      FPhysicalSource := Source;
      FExecuteELF.Enabled := True;
      FState.Caption := 'ELF64 x86-64 · D3:110 → T5M, ' +
        IntToStr(Length(Candidate)) + ' машинних байтів';
      FChoice.Caption := 'Точна відповідь D' +
        IntToStr(Length(AnswerWords[0])) + ':' + String(AnswerWords[0])+
        ' · фізичний T5M байт 0x' + IntToHex(Ord(Answer[1]),2);
    end else if AsCond then
      FState.Caption := 'ELF64 x86-64, ' + IntToStr(Length(Candidate)) +
        ' байтів; фізичний D3:110, CMP/JNE (можливий CMP/SETE)'
    else if AsEQ then
      FState.Caption := 'ELF64 x86-64, ' + IntToStr(Length(Candidate)) +
        ' байтів; D3:101 CMP/SETE, значення визначає лише машинне виконання'
    else
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

procedure TELFWindow.SelfCheckEQ(const EqualFile, DifferentFile,
  D1File, BadFile: String);
var B: TBitmap; PixelX: Integer; EqualBytes: RawByteString;
begin
  Check((FOpenEQ.Parent<>nil) and (FChart.Parent=Self),
    'кнопку та Canvas D3:101 не створено');
  Check(OpenPhysical(EqualFile,True),'точний EQ(0,0) не породив ELF');
  Check(FEQMode and (Length(FImage)>150) and
    (FGrid.RowCount=Length(FImage)+1) and
    (FGrid.Cells[2,121]='Машинна D3:101, CMP/SETE x86-64'),
    'машинний інтервал D3:101 помилковий');
  Check((Ord(FImage[122])=0) and (Ord(FImage[127])=0),
    'точні два D1:0 аргументи не збережено');
  EqualBytes:=FImage;
  B:=TBitmap.Create;
  try
    B.SetSize(FChart.Width,FChart.Height);
    DrawChart(B.Canvas,B.Width,B.Height);
    PixelX:=(130*B.Width) div Length(FImage);
    Check(B.Canvas.Pixels[PixelX,BarTop+15]=clPurple,
      'машинний CMP/SETE не намальовано Canvas');
  finally B.Free; end;
  Check(OpenPhysical(DifferentFile,True),'точний EQ(0,1) не породив ELF');
  Check((Ord(FImage[122])=0) and (Ord(FImage[127])=1) and
    (EqualBytes<>FImage),'різні EQ аргументи дали той самий ELF');
  Check(not OpenPhysical(D1File,True),
    'самостійний D1 помилково допущено як D3:101');
  Check((FImage='') and (FGrid.RowCount=2) and (FSelected=-1),
    'неуспішний EQ залишив машинні байти');
  Check(not OpenPhysical(BadFile,True),'зіпсований EQ T5M прийнято');
  Check((FImage='') and (FGrid.Cells[0,1]=''),
    'зіпсований T5M залишив GUI результат');
  Check(OpenPhysical(D1File,False),'повернення в D1 режим зіпсоване');
  Check((not FEQMode) and (Length(FImage)=ELFSize) and
    (FGrid.Cells[1,154]='30'), 'перемикання EQ→D1 не відновило D1');
  WriteLn('LCL-ELF-EQ-ГАРАЗД Lazarus=GTK2 Canvas=машинний',
    ' D3:101=CMP/SETE точні-аргументи=0,0;0,1',
    ' негативні=відхилено D1=збережено');
end;

{ Самоперевірка самого GTK2/LCL інспектора, не окремий SENS oracle.
  Перевіряє, що 32 гілки, справжня машинна EQ і відмови не залишають
  на екрані попередніх точних даних. }
procedure TELFWindow.SelfCheckCond(const TrueFile, EqualFile,
  DifferentFile, ManyFile, StandaloneEQ, StandaloneD1,
  BadFile: String);
var B:TBitmap; PixelX:Integer; PreviousBytes:RawByteString;
begin
  Check((FOpenCond.Parent<>nil) and (FGrid.Parent=Self) and
    (FChart.Parent=Self), 'LCL кнопка/таблиця/Canvas умови не створені');
  Check(OpenPhysical(TrueFile,False,True),
    'фізична істинна гілка D3:110 не породила ELF');
  Check(FCondMode and not FEQMode and
    (FGrid.RowCount=Length(FImage)+1) and
    (FGrid.Cells[2,121]='Машинна D3:110, CMP/JNE x86-64') and
    (Pos(#$83#$F8#$01#$75,FImage)>0),
    'відсутній реальний CMP/JNE або точний рядок інтервалу');
  PreviousBytes:=FImage;
  B:=TBitmap.Create;
  try
    B.SetSize(FChart.Width,FChart.Height);
    DrawChart(B.Canvas,B.Width,B.Height);
    PixelX:=(145*B.Width) div Length(FImage);
    Check(B.Canvas.Pixels[PixelX,BarTop+15]=clPurple,
      'немає справжнього Lazarus Canvas для D3:110');
  finally B.Free; end;
  Check(OpenPhysical(EqualFile,False,True),
    'вкладений EQ(0,0) у D3:110 не породив ELF');
  Check((FImage<>PreviousBytes) and
    (Pos(#$39#$C8#$0F#$94#$C0#$0F#$B6#$C0,FImage)>0),
    'немає машинного CMP/SETE/MOVZX вкладеної тотожності');
  PreviousBytes:=FImage;
  Check(OpenPhysical(DifferentFile,False,True),
    'вкладений EQ(0,1) у D3:110 не породив ELF');
  Check((FImage<>PreviousBytes) and
    (Pos(#$39#$C8#$0F#$94#$C0,FImage)>0),
    'різні фізичні EQ дали однаковий ELF');
  Check(OpenPhysical(ManyFile,False,True),
    '32 вкладені рівності не породили ELF');
  Check((Length(FImage)>1000) and
    (FGrid.RowCount=Length(FImage)+1) and
    (FGrid.Cells[2,Length(FImage)]='Машинна D3:110, CMP/JNE x86-64'),
    'не відображено всі байти машинних 32 гілок');
  Check(not OpenPhysical(StandaloneEQ,False,True),
    'D3:101 видано за фізичну D3:110');
  Check((FImage='') and (FSelected=-1) and
    (FGrid.RowCount=2) and (FGrid.Cells[1,1]='') and
    (Pos('Відхилено:',FState.Caption)=1),
    'неправильна голова залишила попередню умову в GUI');
  Check(not OpenPhysical(StandaloneD1,False,True),
    'самостійний D1 помилково допущений як D3:110');
  Check((FImage='') and (FGrid.Cells[0,1]=''),
    'D1 залишив байти машинного ELF умови');
  Check(not OpenPhysical(BadFile,False,True),
    'зіпсований T5M допущений у D3:110');
  Check((FImage='') and (FGrid.RowCount=2),
    'зіпсований T5M не очистив граф і таблицю');
  Check(OpenPhysical(StandaloneEQ,True) and FEQMode and not FCondMode,
    'перемикання з D3:110 у D3:101 не працює');
  Check(OpenPhysical(StandaloneD1) and not FEQMode and not FCondMode
    and (Length(FImage)=ELFSize),
    'перемикання з D3:101 у D1 не працює');
  WriteLn('LCL-ELF-УМОВА-ГАРАЗД Lazarus=GTK2 Canvas=намальовано',
    ' D3:110=CMP/JNE D3:101=CMP/SETE/MOVZX',
    ' гілок=32 відмови=очищено D1/EQ=збережено');
end;

{ G6.31: справжня LCL сітка + Canvas; семантичне виконання робить
  чинний TBinaryExecutor, а дев'ять машинних ELF запускає CI окремо.
  Всі входи — фізичні pinned .sens, не український текст як код. }
procedure TELFWindow.SelfCheckPhysicalCond(const YesFile, NoFile,
  EmptyFile, EqFile, BadFile, ForeignFile, D12File: String);
var
  B:TBitmap; X:Integer; OldBytes:RawByteString;
  Words:TExactWords;
  function Expected(const Bits:RawByteString):RawByteString;
  begin
    SetLength(Words,1);Words[0]:=Bits;
    Result:=EncodeT5M(Words);
  end;
begin
  Check((FOpenPhysicalCond.Parent<>nil) and (FGrid.Parent=Self) and
    (FChart.Parent=Self),'Lazarus-кнопка чи справжні віджети відсутні');
  Check(OpenPhysical(YesFile,False,False,True),'не допущено D3:110 → D1:1');
  Check(FPhysicalCondMode and FCondMode and (not FEQMode) and
    (FPhysicalAnswer=Expected('1')) and
    (FGrid.RowCount=Length(FImage)+1) and
    (FGrid.Cells[2,121]='D3:110 · CMP/JNE · фізичний T5M stdout') and
    (Pos('D1:1',FChoice.Caption)>0),'фізична D1:1 відповідь і сітка');
  Check(Pos(#$83#$F8#$01#$75,FImage)>0,
    'відсутній фізичний машинний CMP/JNE');
  OldBytes:=FImage;
  B:=TBitmap.Create;
  try
    B.SetSize(FChart.Width,FChart.Height);
    DrawChart(B.Canvas,B.Width,B.Height);
    X:=(140*B.Width) div Length(FImage);
    Check(B.Canvas.Pixels[X,BarTop+15]=clPurple,
      'справжній Lazarus Canvas не показує машинні байти');
  finally B.Free end;
  Check(OpenPhysical(NoFile,False,False,True),
    'не допущено D3:110 → D1:0');
  Check((FPhysicalAnswer=Expected('0')) and (OldBytes<>FImage) and
    (Pos('D1:0',FChoice.Caption)>0),'D1:0 не тотожне D1:1');
  Check(OpenPhysical(EmptyFile,False,False,True),
    'не допущено вичерпання D3:110');
  Check((FPhysicalAnswer=Expected('000')) and
    (Pos('D3:000',FChoice.Caption)>0),
    'D3:000 не може зливатися з D1:0');
  Check(OpenPhysical(EqFile,False,False,True),
    'машинний EQ expression D3:110 не допущений');
  Check((FPhysicalAnswer=Expected('0')) and
    (Pos(#$0F#$94#$C0#$6B#$C0,FImage)>0),
    'EQ expression не лишив machine SETE/IMUL');
  Check(not OpenPhysical(BadFile,False,False,True),
    'пошкоджений T5M допущений');
  Check((FImage='') and (FPhysicalAnswer='') and
    (FGrid.RowCount=2) and (FSelected=-1) and
    (Pos('Відхилено:',FState.Caption)=1),
    'відмова залишила stale ELF або T5M');
  Check(not OpenPhysical(ForeignFile,False,False,True),
    'самостійний D1 виданий за D3:110');
  Check((FImage='') and (FPhysicalAnswer=''),
    'чужа голова залишила старий фізичний результат');
  Check(not OpenPhysical(D12File,False,False,True),
    'D12 число потрапило в предикат D1');
  Check((FImage='') and (FPhysicalAnswer=''),
    'D12 відмова залишила stale результат');
  Check(OpenPhysical(YesFile,False,True) and not FPhysicalCondMode and
    (FPhysicalAnswer=''),'старий ASCII D3:110 режим зламано');
  Check(OpenPhysical(YesFile,False,False,True) and FPhysicalCondMode and
    (FPhysicalAnswer=Expected('1')),
    'після відмови T5M-режим не відновився');
  WriteLn('LCL-ELF-ФІЗИЧНА-УМОВА-ГАРАЗД Lazarus=GTK2 ',
    'Canvas=так TStringGrid=байти D1:0/1-окремо ',
    'D3:000=окремо EQ=машинний T5M=канонічний ',
    'помилки=очищено відновлення=так');
end;

{ Справжній gtk2-selftest: натискання кнопки без допущеного D3,
  три відмінні T5M результати, machine EQ, відмови й відновлення. }
procedure TELFWindow.SelfCheckMachine(const YesFile,NoFile,EmptyFile,
  EqFile,BadFile,ForeignFile,D12File:String);
var
  Words:TExactWords;
  function Enc(const Bits:RawByteString):RawByteString;
  begin SetLength(Words,1);Words[0]:=Bits;Result:=EncodeT5M(Words) end;
begin
  Check(not FExecuteELF.Enabled,'машинна кнопка до admission дозволена');
  Check(not ExecuteMachine,'машинне виконання без вхідної форми');
  Check((FImage='') and (FMachineAnswer=''),'примарне машинне значення');
  Check(OpenPhysical(YesFile,False,False,True) and FExecuteELF.Enabled,
    'не завантажено чинний D3:110');
  FExecuteELF.Click;
  Check((FMachineAnswer=Enc('1')) and
    (Pos('Виконано справжній ELF64',FState.Caption)=1),
    'не виконався x86-64 або не збігся D1:1');
  Check(OpenPhysical(NoFile,False,False,True),'не завантажено D1:0');
  Check(FMachineAnswer='','старий D1:1 лишився після відкриття нового');
  FExecuteELF.Click;
  Check(FMachineAnswer=Enc('0'),'машинна D1:0 не збіглася');
  Check(OpenPhysical(EmptyFile,False,False,True),'вичерпання D3');
  FExecuteELF.Click;
  Check(FMachineAnswer=Enc('000'),'D3:000 помилково дорівняно D1:0');
  Check(OpenPhysical(EqFile,False,False,True),'машинна EQ гілка');
  FExecuteELF.Click;
  Check((FMachineAnswer=Enc('0')) and
    (Pos(#$0F#$94#$C0#$6B#$C0,FImage)>0),
    'справжня SETE/IMUL EQ не обчислена');
  Check(not OpenPhysical(BadFile,False,False,True),
    'неканонічний T5M допущено');
  Check((not FExecuteELF.Enabled) and (FImage='') and
    (FPhysicalAnswer='') and (FMachineAnswer=''),
    'пізня T5M відмова не очистила GUI');
  Check(not OpenPhysical(ForeignFile,False,False,True),
    'самостійний D1 помилково callable D3');
  Check((not FExecuteELF.Enabled) and (FMachineAnswer=''),
    'залишилися старі bytes');
  Check(not OpenPhysical(D12File,False,False,True),
    'числовий D12 не є D1 предикатом');
  Check((not FExecuteELF.Enabled) and (FMachineAnswer=''),
    'D12 відмова залишила результат');
  Check(OpenPhysical(YesFile,False,True) and not FExecuteELF.Enabled,
    'старий ASCII ELF режим зламано');
  Check(not ExecuteMachine,'ASCII режим виконався як канонічний T5M');
  Check(OpenPhysical(YesFile,False,False,True),'повторний admission');
  FExecuteELF.Click;
  Check(FMachineAnswer=Enc('1'),'відновлення машинної D3 форми');
  WriteLn('LCL-ELF-ВИКОНАННЯ-ГАРАЗД GTK2=так кнопка=справжня',
    ' ELF64=дочірній x86-64 T5M=byte-exact',
    ' D1:0/1=D3:000-окремо EQ=SETE/IMUL',
    ' негативи=відхилено старий-режим=збережено',
    ' відновлення=так');
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
    end else if (ParamCount=2) and
      (RawByteString(ParamStr(1))=RawByteString('--тотожне')) then begin
      Window.OpenPhysical(ParamStr(2),True);
      Application.Run;
    end else if (ParamCount=8) and
      (RawByteString(ParamStr(1))=RawByteString('--самоперевірка-машина')) then begin
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheckMachine(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8));
    end else if (ParamCount=8) and
      (RawByteString(ParamStr(1))=RawByteString('--самоперевірка-фізична-умова')) then begin
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheckPhysicalCond(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8));
    end else if (ParamCount=8) and
      (RawByteString(ParamStr(1))=RawByteString('--самоперевірка-умова')) then begin
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheckCond(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8));
    end else if (ParamCount=2) and
      (RawByteString(ParamStr(1))=RawByteString('--за-умовою')) then begin
      Window.OpenPhysical(ParamStr(2),False,True);
      Application.Run;
    end else if (ParamCount=5) and
      (RawByteString(ParamStr(1))=RawByteString('--самоперевірка-eq')) then begin
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheckEQ(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5));
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
