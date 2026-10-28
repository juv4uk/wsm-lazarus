{ Справжнє вікно Lazarus/LCL: ТІЛЬКИ структурний допуск pinned Core4.
  Законів SENS, двійкового dispatch та виконання бібліотеки тут НЕМАЄ.
  SIR1 — приватний структурний формат, не канонічний .sens. }
program core4_dopusk;
{$mode objfpc}{$H+}{$codepage utf8}

uses
  Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls,
  ExtCtrls, Graphics, wsm.core4source, wsm.compiler;

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
    procedure CheckClicked(Sender: TObject);
    procedure PaintDiagram(Sender: TObject);
    procedure ClearEvidence;
    procedure ShowError(const MessageText: String;
      Offset, Line, Column: SizeInt);
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadRoot(const RepoRoot: String);
    procedure SmokeTest(const MissingRoot, BadBytesRoot,
      BadSyntaxRoot: String);
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
  Header, StatsPanel, Footer: TPanel;
  I: Integer;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — допуск джерела Core4';
  Width := 1000;
  Height := 610;
  Position := poScreenCenter;
  FReady := False;
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
  FState.Caption := 'Джерело ще не перевірено. Виконання Core4: НІ.';
  FState.AutoSize := True;

  FDiagram := TPaintBox.Create(Self);
  FDiagram.Parent := Self;
  FDiagram.Align := alClient;
  FDiagram.OnPaint := @PaintDiagram;
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
        ' Канонічний .sens: НІ.';
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
  BadSyntaxRoot: String);
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
  WriteLn('LCL-CORE4-ДОПУСК-ГАРАЗД вікно=справжнє ',
    'діаграма=справжня pinned=так структура=так ',
    'негативні=3 очищення=так відновлення=так ',
    'Core4-виконання=НІ');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — структурний допуск Core4';
    Application.CreateForm(TCore4Window, Window);
    if (ParamCount >= 1) and
      (ParamStr(1)='--самоперевірка') then begin
      if ParamCount <> 4 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SmokeTest(ParamStr(2), ParamStr(3), ParamStr(4));
      Window.Free;
      Halt(0);
    end;
    if ParamCount <> 0 then
      raise EVisualCheckError.Create(
        'використання: core4-dopusk [--самоперевірка відсутній погані-байти незакритий]');
    Application.Run;
  except
    on E: Exception do begin
      WriteLn(StdErr,'LCL-CORE4-ДОПУСК-ПОМИЛКА: ', E.Message);
      Halt(2);
    end;
  end;
end.
