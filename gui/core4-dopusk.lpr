{ Справжнє вікно Lazarus/LCL: ТІЛЬКИ структурний допуск pinned Core4.
  Законів SENS, двійкового dispatch та виконання бібліотеки тут НЕМАЄ.
  SIR1 — приватний структурний формат, не канонічний .sens. }
program core4_dopusk;
{$mode objfpc}{$H+}{$codepage utf8}

uses
  Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls,
  ExtCtrls, Graphics, Grids, wsm.t5m, wsm.core4runtime,
  wsm.core4source, wsm.compiler;

type
  EVisualCheckError = class(Exception);
  TCore4Window = class(TForm)
  private
    FButton: TButton;
    FPath, FState: TLabel;
    FCounts: array[0..5] of TLabel;
    FDiagram: TPaintBox;
    FStats: TSIR1Stats;
    FReady: Boolean;
    FBinary: TCore4Runtime;
    FChoice: TComboBox;
    FRunButton: TButton;
    FBinaryStatus: TLabel;
    FGrid: TStringGrid;
    FResultBits: RawByteString;
    procedure ResetBinaryEvidence;
    procedure LoadPhysicalRoot(const RepoRoot: String);
    procedure RunClicked(Sender: TObject);
    procedure ExecuteSelected;
    procedure CheckClicked(Sender: TObject);
    procedure PaintDiagram(Sender: TObject);
    procedure ClearEvidence;
    procedure ShowError(const MessageText: String;
      Offset, Line, Column: SizeInt);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadRoot(const RepoRoot: String);
    procedure SmokeTest(const MissingRoot, BadBytesRoot,
      BadSyntaxRoot, BadBinaryRoot: String);
  end;

var
  Window: TCore4Window;

procedure Demand(Condition: Boolean; const Problem: String);
begin
  if not Condition then raise EVisualCheckError.Create(Problem);
end;

constructor TCore4Window.Create(AOwner: TComponent);
const
  Titles: array[0..5] of String =
    ('Відкриті списки', 'Атоми', 'Рядки', 'Усі токени',
     'Найбільша глибина', 'Байти лексем');
var
  Header, StatsPanel, Footer, BinaryPanel: TPanel;
  I: Integer;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — допуск джерела Core4';
  Width := 1000;
  Height := 770;
  Position := poScreenCenter;
  FReady := False;
  FBinary := nil;
  FResultBits := '';
  FillChar(FStats, SizeOf(FStats), 0);

  Header := TPanel.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := 100;
  Header.BevelOuter := bvNone;
  FButton := TButton.Create(Self);
  FButton.Parent := Header;
  FButton.SetBounds(12, 9, 270, 35);
  FButton.Caption := 'Перевірити закріплений Core4';
  FButton.OnClick := @CheckClicked;
  FPath := TLabel.Create(Self);
  FPath.Parent := Header;
  FPath.SetBounds(12, 58, 970, 32);
  FPath.Caption := 'Джерело: external/sens/lib/core4.lisp';
  FPath.AutoSize := True;

  StatsPanel := TPanel.Create(Self);
  StatsPanel.Parent := Self;
  StatsPanel.Align := alTop;
  StatsPanel.Height := 122;
  StatsPanel.BevelOuter := bvNone;
  for I := 0 to High(FCounts) do begin
    FCounts[I] := TLabel.Create(Self);
    FCounts[I].Parent := StatsPanel;
    FCounts[I].SetBounds(12+(I mod 3)*322, 12+(I div 3)*47,
      315, 28);
    FCounts[I].Caption := Titles[I] + ': —';
    FCounts[I].AutoSize := True;
  end;

  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 76;
  Footer.BevelOuter := bvNone;
  FState := TLabel.Create(Self);
  FState.Parent := Footer;
  FState.SetBounds(12, 12, 950, 55);
  FState.Caption := 'Джерело .lisp ще не перевірено; .sens виконання окреме.';
  FState.AutoSize := True;

  { Справжня візуальна панель виконання pinned фізичного Core4 .sens.
    Вона незалежна від статистики української .lisp проєкції. }
  BinaryPanel := TPanel.Create(Self);
  BinaryPanel.Parent := Self;
  BinaryPanel.Align := alBottom;
  BinaryPanel.Height := 172;
  BinaryPanel.BevelOuter := bvNone;
  FChoice := TComboBox.Create(Self);
  FChoice.Parent := BinaryPanel;
  FChoice.Style := csDropDownList;
  FChoice.SetBounds(12,8,177,32);
  FChoice.Items.Add('D1:0');
  FChoice.Items.Add('D1:1');
  FChoice.Items.Add('D24:0 (дані)');
  FChoice.Items.Add('D24:1 (дані)');
  FChoice.ItemIndex := 0;
  FRunButton := TButton.Create(Self);
  FRunButton.Parent := BinaryPanel;
  FRunButton.SetBounds(200,7,283,34);
  FRunButton.Caption := 'Виконати визначення Core4 .sens';
  FRunButton.OnClick := @RunClicked;
  FBinaryStatus := TLabel.Create(Self);
  FBinaryStatus.Parent := BinaryPanel;
  FBinaryStatus.SetBounds(12,48,954,30);
  FBinaryStatus.AutoSize := True;
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := BinaryPanel;
  FGrid.SetBounds(12,81,956,85);
  FGrid.ColCount := 3;
  FGrid.RowCount := 3;
  FGrid.FixedRows := 1;
  FGrid.ColWidths[0] := 168;
  FGrid.ColWidths[1] := 84;
  FGrid.ColWidths[2] := 668;
  FGrid.Cells[0,0] := 'Фізичний свідок';
  FGrid.Cells[1,0] := 'Ширина';
  FGrid.Cells[2,0] := 'Точні двійкові біти';
  ResetBinaryEvidence;

  FDiagram := TPaintBox.Create(Self);
  FDiagram.Parent := Self;
  FDiagram.Align := alClient;
  FDiagram.OnPaint := @PaintDiagram;
end;


destructor TCore4Window.Destroy;
begin
  FBinary.Free;
  inherited Destroy;
end;

procedure TCore4Window.ResetBinaryEvidence;
var Row: Integer;
begin
  FreeAndNil(FBinary);
  FResultBits := '';
  for Row := 1 to 2 do begin
    FGrid.Cells[0,Row] := '';
    FGrid.Cells[1,Row] := '';
    FGrid.Cells[2,Row] := '';
  end;
  FBinaryStatus.Caption := 'Фізичний Core4 .sens ще не завантажено';
end;

procedure TCore4Window.LoadPhysicalRoot(const RepoRoot: String);
begin
  ResetBinaryEvidence;
  try
    FBinary := TCore4Runtime.Create(RepoRoot);
    if FBinary.BindingCount <> 3 then
      raise EVisualCheckError.Create('очікувалися три початкові визначення');
    FBinaryStatus.Caption :=
      'Фізичний Core4 .sens: допущено 3 початкові DEFINE; '+
      'виконуване лише перше замикання';
  except
    on E:Exception do begin
      ResetBinaryEvidence;
      FBinaryStatus.Caption := 'ВІДХИЛЕНО фізичний Core4: '+E.Message;
    end;
  end;
end;

procedure TCore4Window.ExecuteSelected;
var
  Identifier, ArgBits, Answer: RawByteString;
  Words, ResultWords: TExactWords;
  I, N, Glyphs: SizeInt;
begin
  FResultBits := '';
  for I := 1 to 2 do begin
    FGrid.Cells[0,I] := '';
    FGrid.Cells[1,I] := '';
    FGrid.Cells[2,I] := '';
  end;
  if FBinary=nil then LoadPhysicalRoot('.');
  if FBinary=nil then Exit;
  try
    { Це ФІЗИЧНІ біти UI-свідків, а не D12+ host-арифметика.
      Callable ідентифікатор береться лише із pinned core4.sens. }
    case FChoice.ItemIndex of
      0: ArgBits := '0';
      1: ArgBits := '1';
      2: ArgBits := '000000000000000000000000';
      3: ArgBits := '000000000000000000000001';
      else raise EVisualCheckError.Create('недопустимий вибір аргументу');
    end;
    Identifier := FBinary.FirstDefinitionIdentifier;
    if (Length(Identifier)<7) or (Length(Identifier) mod 7<>0) then
      raise EVisualCheckError.Create('зіпсований pinned D7 ключ');
    Glyphs := Length(Identifier) div 7;
    SetLength(Words,Glyphs+5);
    N:=0; Words[N]:='10';Inc(N); Words[N]:='10';Inc(N);
    for I:=0 to Glyphs-1 do begin
      Words[N]:=Copy(Identifier,I*7+1,7); Inc(N);
    end;
    Words[N]:='01';Inc(N);
    Words[N]:=ArgBits;Inc(N);
    Words[N]:='01';Inc(N);
    SetLength(Words,N);
    Answer := FBinary.ExecutePhysicalCall(EncodeT5M(Words));
    DecodeT5M(Answer,ResultWords);
    if (Length(ResultWords)<>1) or (ResultWords[0]<>ArgBits) then
      raise EVisualCheckError.Create('втрачені точні біти замикання');
    FGrid.Cells[0,1] := 'Аргумент';
    FGrid.Cells[1,1] := IntToStr(Length(ArgBits));
    FGrid.Cells[2,1] := String(ArgBits);
    FGrid.Cells[0,2] := 'Результат виконання';
    FGrid.Cells[1,2] := IntToStr(Length(ResultWords[0]));
    FGrid.Cells[2,2] := String(ResultWords[0]);
    FResultBits := ResultWords[0];
    FBinaryStatus.Caption := 'ВИКОНАНО початкове замикання pinned Core4 .sens; '+
      'бітів='+IntToStr(Length(FResultBits));
  except
    on E:Exception do begin
      FResultBits := '';
      FBinaryStatus.Caption := 'ВІДХИЛЕНО виклик Core4: '+E.Message;
    end;
  end;
end;

procedure TCore4Window.RunClicked(Sender: TObject);
begin
  ExecuteSelected;
end;

procedure TCore4Window.ClearEvidence;
const
  Titles: array[0..5] of String =
    ('Відкриті списки', 'Атоми', 'Рядки', 'Усі токени',
     'Найбільша глибина', 'Байти лексем');
var I: Integer;
begin
  FReady := False;
  FillChar(FStats, SizeOf(FStats), 0);
  for I := 0 to High(FCounts) do
    FCounts[I].Caption := Titles[I] + ': —';
  FPath.Caption := 'Джерело: не допущене';
  FDiagram.Invalidate;
end;

procedure TCore4Window.ShowError(const MessageText: String;
  Offset, Line, Column: SizeInt);
begin
  ClearEvidence;
  FState.Caption := 'ВІДХИЛЕНО: ' + MessageText;
  if Offset > 0 then
    FState.Caption := FState.Caption +
      ' | байт=' + IntToStr(Offset) +
      ', рядок=' + IntToStr(Line) +
      ', стовпець=' + IntToStr(Column);
end;

procedure TCore4Window.LoadRoot(const RepoRoot: String);
var
  Scratch: TMemoryStream;
  Stats: TSIR1Stats;
begin
  ClearEvidence;
  FState.Caption := 'Перевіряється закріплене джерело Core4…';
  Scratch := TMemoryStream.Create;
  try
    try
      { Це ЄДИНИЙ допуск: строгий pinned UTF-8/AST + SIR1 verifier,
        уже реалізований у headless компонентах. }
      CompilePinnedCore4Structure(RepoRoot, Scratch);
      Scratch.Position := 0;
      InspectSIR1(Scratch, Stats);
      FStats := Stats;
      FReady := True;
      FCounts[0].Caption := 'Відкриті списки: ' + IntToStr(FStats.ListOpens);
      FCounts[1].Caption := 'Атоми: ' + IntToStr(FStats.Atoms);
      FCounts[2].Caption := 'Рядки: ' + IntToStr(FStats.Strings);
      FCounts[3].Caption := 'Усі токени: ' + IntToStr(FStats.Tokens);
      FCounts[4].Caption := 'Найбільша глибина: ' + IntToStr(FStats.MaxDepth);
      FCounts[5].Caption := 'Байти лексем: ' + IntToStr(FStats.PayloadBytes);
      FPath.Caption := 'Джерело: ' + Core4PinnedPath(RepoRoot);
      FState.Caption := 'ДОПУЩЕНО структуру SIR1 ('+
        IntToStr(Scratch.Size) + ' байтів); виконання Core4: НІ.' +
        ' Це лише людська .lisp-проєкція.';
      FDiagram.Invalidate;
    except
      on E: ECore4SourceError do
        ShowError(E.Message, E.ByteOffset, E.Line, E.ByteColumn);
      on E: Exception do ShowError(E.Message, 0, 0, 0);
    end;
  finally
    Scratch.Free;
  end;
end;

procedure TCore4Window.PaintDiagram(Sender: TObject);
const
  Bars: array[0..2] of String =
    ('Списки', 'Атоми', 'Рядки');
  BarColors: array[0..2] of TColor =
    (clNavy, clTeal, clOlive);
var
  Counts: array[0..2] of Int64;
  Biggest: Int64;
  I, BarWidth, MaxBarWidth, Y: Integer;
begin
  FDiagram.Canvas.Brush.Color := clWhite;
  FDiagram.Canvas.FillRect(FDiagram.ClientRect);
  if not FReady then begin
    FDiagram.Canvas.Font.Color := clGray;
    FDiagram.Canvas.TextOut(16, 22,
      'Немає допущеної структури для візуалізації');
    Exit;
  end;
  Counts[0] := FStats.ListOpens;
  Counts[1] := FStats.Atoms;
  Counts[2] := FStats.Strings;
  Biggest := 1;
  for I := 0 to High(Counts) do
    if Counts[I] > Biggest then Biggest := Counts[I];
  MaxBarWidth := FDiagram.ClientWidth - 230;
  if MaxBarWidth < 0 then MaxBarWidth := 0;
  for I := 0 to 2 do begin
    Y := 24+I*72;
    FDiagram.Canvas.Font.Color := clBlack;
    FDiagram.Canvas.TextOut(12, Y+6,
      Bars[I]+' ('+IntToStr(Counts[I])+')');
    BarWidth := Trunc((Counts[I] / Biggest) * MaxBarWidth);
    FDiagram.Canvas.Brush.Color := BarColors[I];
    FDiagram.Canvas.FillRect(Rect(170, Y, 170+BarWidth, Y+34));
  end;
  FDiagram.Canvas.Font.Color := clGray;
  FDiagram.Canvas.TextOut(12, 250,
    'Лише статистика структурних токенів. Не профіль виконання.');
end;

procedure TCore4Window.CheckClicked(Sender: TObject);
begin
  LoadRoot('.');
end;

procedure TCore4Window.SmokeTest(const MissingRoot, BadBytesRoot,
  BadSyntaxRoot, BadBinaryRoot: String);
var First: Int64;
begin
  FButton.Click; { фізична LCL-подія, а не підміна допуску }
  Demand(FReady, 'реальне закріплене Core4 не допущене');
  Demand(FStats.ListOpens > 0, 'немає списків Core4');
  Demand(FStats.Atoms > 0, 'немає атомів Core4');
  Demand(FDiagram.Width > 0, 'не створено діаграму');
  First := FStats.ListOpens;

  LoadRoot(MissingRoot);
  Demand((not FReady) and (FStats.ListOpens=0) and
    (Pos('ВІДХИЛЕНО:',FState.Caption)=1) and
    (Pos('—', FCounts[0].Caption)>0),
    'після відсутнього файлу залишено попередні показники');
  Demand(Pos('байт=', FState.Caption)=0,
    'придумано фізичний байт помилки вводу/виводу');

  LoadRoot(BadBytesRoot);
  Demand((not FReady) and (FStats.Atoms=0) and
    (Pos('байт=',FState.Caption)>0),
    'некоректний UTF-8 допущено або втрачено позицію');

  LoadRoot(BadSyntaxRoot);
  Demand((not FReady) and (FStats.Tokens=0) and
    (Pos('байт=',FState.Caption)>0),
    'незакриту форму допущено або втрачено позицію');

  FButton.Click;
  Demand(FReady and (FStats.ListOpens=First),
    'відновлення після негативних випадків не детерміноване');

  { Реальний LCL-клік викликає pinned binary Core4 у тій самій формі. }
  LoadPhysicalRoot('.');
  Demand((FBinary<>nil) and (FBinary.BindingCount=3),
    'не завантажено фізичний Core4.sens');
  FChoice.ItemIndex:=0; FRunButton.Click;
  Demand((FResultBits='0') and (FGrid.Cells[1,2]='1'),
    'D1:0 замикання не виконалося');
  FChoice.ItemIndex:=1; FRunButton.Click;
  Demand((FResultBits='1') and (FGrid.Cells[1,2]='1'),
    'D1:1 замикання не виконалося у тій самій сесії');
  FChoice.ItemIndex:=2; FRunButton.Click;
  Demand((FResultBits='000000000000000000000000') and
    (FGrid.Cells[1,2]='24'),'opaque D24:0 втратило біти');
  FChoice.ItemIndex:=3; FRunButton.Click;
  Demand((FResultBits='000000000000000000000001') and
    (FGrid.Cells[1,2]='24'),'opaque D24:1 втратило біти');

  LoadPhysicalRoot(MissingRoot);
  Demand((FBinary=nil) and (FResultBits='') and
    (FGrid.Cells[2,2]='') and
    (Pos('ВІДХИЛЕНО',FBinaryStatus.Caption)=1),
    'відсутній binary Core4 залишив стару відповідь');
  LoadPhysicalRoot(BadBinaryRoot);
  Demand((FBinary=nil) and (FResultBits='') and
    (FGrid.Cells[2,2]='') and
    (Pos('ВІДХИЛЕНО',FBinaryStatus.Caption)=1),
    'пошкоджений T5M Core4 залишив стару відповідь');
  LoadPhysicalRoot('.');
  Demand(FBinary<>nil,'Core4 не відновився після помилки');
  FChoice.ItemIndex:=1; FRunButton.Click;
  Demand(FResultBits='1','повторний виклик після відмови');

  WriteLn('LCL-CORE4-ДОПУСК-ГАРАЗД вікно=справжнє ',
    'діаграма=справжня pinned=так структура=так ',
    'негативні=3 очищення=так відновлення=так ',
    'Core4-виконання=початкове D1=2 D24=2 ',
    'binary-відмови=2 відновлення=так');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — структурний допуск Core4';
    Application.CreateForm(TCore4Window, Window);
    if (ParamCount >= 1) and
      (ParamStr(1)='--самоперевірка') then begin
      if ParamCount <> 5 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SmokeTest(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5));
      Window.Free;
      Halt(0);
    end;
    if ParamCount <> 0 then
      raise EVisualCheckError.Create(
        'використання: core4-dopusk [--самоперевірка відсутній погані-байти незакритий поганий-t5m]');
    Application.Run;
  except
    on E: Exception do begin
      WriteLn(StdErr,'LCL-CORE4-ДОПУСК-ПОМИЛКА: ', E.Message);
      Halt(2);
    end;
  end;
end.
