{ G5.56 — Lazarus/LCL оболонка над уже злитим обмеженим D3-сеансом.
  Редактор приймає ЯВНО компактну українську проєкцію «ук».
  Це не канонічна фізична .sens і не повний SENS REPL.
  Один TNativeSession живе разом із TForm; виконує лише pinned D3 executor.
  Жодної семантики за людськими назвами у вікні немає. }
program sens_seans_d3;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, ExtCtrls, Dialogs,
  wsm.session, wsm.sessiond3;

type
  TSeansWindow = class(TForm)
  private
    FSession: TNativeSession;
    InputMemo, Journal: TMemo;
    RunButton, LoadButton: TButton;
    OpenSource: TOpenDialog;
    Status: TLabel;
    procedure RenderReplies(const Replies: TSessionReplies);
    procedure RunClick(Sender: TObject);
    procedure LoadClick(Sender: TObject);
    procedure LoadPath(const Path: String);
    procedure Check(Condition: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ConnectPinned(const Root: RawByteString);
    procedure SelfTest(const TempDir: String);
  end;

var
  Window: TSeansWindow;

constructor TSeansWindow.Create(AOwner: TComponent);
var Panel: TPanel; LabelText: TLabel;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — обмежений сеанс Д3 (ук, не .sens)';
  Width := 950;
  Height := 740;
  Position := poScreenCenter;
  FSession := nil;

  LabelText := TLabel.Create(Self);
  LabelText.Parent := Self;
  LabelText.Align := alTop;
  LabelText.Height := 30;
  LabelText.Caption := 'Тільки явна коротка проєкція «ук»; числа Д12+ і Core4 тут не виконуються.';

  Panel := TPanel.Create(Self);
  Panel.Parent := Self;
  Panel.Align := alTop;
  Panel.Height := 43;
  RunButton := TButton.Create(Self);
  RunButton.Parent := Panel;
  RunButton.SetBounds(8, 6, 180, 31);
  RunButton.Caption := 'Виконати форми ук';
  RunButton.Enabled := False;
  RunButton.OnClick := @RunClick;
  LoadButton := TButton.Create(Self);
  LoadButton.Parent := Panel;
  LoadButton.SetBounds(204, 6, 275, 31);
  LoadButton.Caption := 'Завантажити файл ук (.lisp)';
  LoadButton.Enabled := False;
  LoadButton.OnClick := @LoadClick;

  InputMemo := TMemo.Create(Self);
  InputMemo.Parent := Self;
  InputMemo.Align := alTop;
  InputMemo.Height := 205;
  InputMemo.ScrollBars := ssBoth;
  InputMemo.WordWrap := False;
  InputMemo.Text := 'так ні (сполучити так ())';

  Status := TLabel.Create(Self);
  Status.Parent := Self;
  Status.Align := alBottom;
  Status.Height := 28;
  Status.Caption := 'Не підключено pinned D3.';

  Journal := TMemo.Create(Self);
  Journal.Parent := Self;
  Journal.Align := alClient;
  Journal.ScrollBars := ssBoth;
  Journal.WordWrap := False;
  Journal.ReadOnly := True;
  Journal.Lines.Add('Відповіді реального D3-оцінювача (це не повний REPL SENS).');

  OpenSource := TOpenDialog.Create(Self);
  OpenSource.Title := 'Оберіть текстовий файл короткої проєкції ук';
  OpenSource.Filter := 'Проєкція ук (*.lisp)|*.lisp';
  OpenSource.Options := OpenSource.Options + [ofFileMustExist];
end;

destructor TSeansWindow.Destroy;
begin
  FSession.Free;
  inherited Destroy;
end;

procedure TSeansWindow.ConnectPinned(const Root: RawByteString);
begin
  if FSession <> nil then
    raise ESessionError.Create('повторна ініціалізація сеансу заборонена');
  FSession := TNativeSession.Create(NewNativeD3Executor(Root));
  RunButton.Enabled := True;
  LoadButton.Enabled := True;
  Status.Caption := 'Підключено pinned виконавець Д3; оброблено форм: 0';
end;

{ Replies — тимчасовий керований масив структур TSessionReply.
  TNativeSession володіє своїм лексичним кадром до Destroy;
  Journal копіює лише UTF-8 байти текстового host-представлення.
  FormNumber — лічильник форм host-сесії, НЕ доменний числовий атом. }
procedure TSeansWindow.RenderReplies(const Replies: TSessionReplies);
var
  I: SizeInt;
  R: TSessionReply;
  Note: String;
begin
  for I := 0 to High(Replies) do begin
    R := Replies[I];
    if R.Ok then
      Note := 'Результат'
    else
      Note := 'Відмова';
    Journal.Lines.Add(Note + ' №' + IntToStr(R.FormNumber) +
      ' [рядок ' + IntToStr(R.Line) + ', стовпець ' +
      IntToStr(R.ByteColumn) + ', байт ' + IntToStr(R.ByteOffset) + ']: ' +
      String(R.Output) + String(R.Diagnostic));
  end;
  Status.Caption := 'Оброблено форм: ' + IntToStr(FSession.FormsSeen) +
    '; відповідей на останній запит: ' + IntToStr(Length(Replies));
end;

procedure TSeansWindow.RunClick(Sender: TObject);
var Replies: TSessionReplies;
begin
  if FSession = nil then Exit;
  RunButton.Enabled := False;
  try
    { Введені LCL рядки — UTF-8 «ук», не прихований binary reader. }
    Replies := FSession.Submit(RawByteString(InputMemo.Text));
    RenderReplies(Replies);
  except
    on E: Exception do
      Journal.Lines.Add('Помилка host-сеансу: ' + E.Message);
  end;
  RunButton.Enabled := True;
end;

procedure TSeansWindow.LoadPath(const Path: String);
var Replies: TSessionReplies;
begin
  if FSession = nil then Exit;
  { .sens ніколи не читаємо як текстову проєкцію. }
  if LowerCase(ExtractFileExt(Path)) <> '.lisp' then begin
    Journal.Lines.Add('Відмова: дозволено лише явний текстовий файл .lisp (ук).');
    Exit;
  end;
  Replies := FSession.LoadFile(Path);
  RenderReplies(Replies);
end;

procedure TSeansWindow.LoadClick(Sender: TObject);
begin
  if not OpenSource.Execute then Exit;
  try
    LoadPath(OpenSource.FileName);
  except
    on E: Exception do
      Journal.Lines.Add('Помилка host-файлу: ' + E.Message);
  end;
end;

procedure TSeansWindow.Check(Condition: Boolean; const Why: String);
begin
  if not Condition then
    raise Exception.Create('ЛКЛ-СЕАНС-Д3-ПОМИЛКА: ' + Why);
end;

procedure TSeansWindow.SelfTest(const TempDir: String);
var Path,Physical: String; Data: RawByteString; OutFile: TFileStream;
    BeforeCount: QWord;
begin
  Check((FSession <> nil) and RunButton.Enabled and LoadButton.Enabled,
    'вікно не підключене до справжнього D3-сеансу');
  InputMemo.Text := 'так ні (сполучити так ())';
  RunButton.Click;
  Check((FSession.FormsSeen = 3) and
    (Pos('Результат №1', Journal.Text) > 0) and
    (Pos('Результат №2', Journal.Text) > 0) and
    (Pos('Результат №3', Journal.Text) > 0) and
    (Pos('(1)', Journal.Text) > 0), 'не виконано перші три реальні форми');

  InputMemo.Text := '(перше (сполучити ні ()))';
  RunButton.Click;
  Check((FSession.FormsSeen = 4) and
    (Pos('Результат №4', Journal.Text) > 0),
    'другий клік не використав той самий живий сеанс');

  InputMemo.Text := '(невідома ()) ні';
  RunButton.Click;
  Check((FSession.FormsSeen = 6) and
    (Pos('Відмова №5 [рядок 1, стовпець 2, байт 2]', Journal.Text) > 0) and
    (Pos('Результат №6', Journal.Text) > 0),
    'відмова не зберегла точну позицію або наступну форму');

  InputMemo.Text := '(перше';
  RunButton.Click;
  Check((FSession.FormsSeen = 6) and (Pos('Відмова №6', Journal.Text) > 0),
    'помилка синтаксису не була відхилена без збільшення лічильника');
  InputMemo.Text := 'так';
  RunButton.Click;
  Check((FSession.FormsSeen = 7) and (Pos('Результат №7', Journal.Text) > 0),
    'сеанс не відновився після синтаксичної відмови');

  Path := IncludeTrailingPathDelimiter(TempDir) + 'сеанс-ук.lisp';
  Data := RawByteString('ні (атом? ())');
  OutFile := TFileStream.Create(Path, fmCreate);
  try
    OutFile.WriteBuffer(Data[1], Length(Data));
  finally
    OutFile.Free;
  end;
  LoadPath(Path);
  Check((FSession.FormsSeen = 9) and
    (Pos('Результат №8', Journal.Text) > 0) and
    (Pos('Результат №9', Journal.Text) > 0),
    'файловий текст не виконався у тому самому сеансі');

  BeforeCount := FSession.FormsSeen;
  Physical := IncludeTrailingPathDelimiter(TempDir) + 'машина.sens';
  LoadPath(Physical);
  Check((FSession.FormsSeen = BeforeCount) and
    (Pos('Відмова: дозволено лише явний текстовий файл .lisp', Journal.Text) > 0),
    'машинний .sens помилково допущено як текст');
  LoadPath(IncludeTrailingPathDelimiter(TempDir) + 'відсутній.lisp');
  Check((FSession.FormsSeen = BeforeCount) and
    (Pos('Відмова №9', Journal.Text) > 0),
    'відсутній файл порушив сеанс або створив значення');
  InputMemo.Text := 'ні';
  RunButton.Click;
  Check((FSession.FormsSeen = 10) and
    (Pos('Результат №10', Journal.Text) > 0),
    'не відновлено роботу після відмови файлової операції');

  WriteLn('ЛКЛ-СЕАНС-Д3-ГАРАЗД Lazarus=GTK2 реальні-кліки=6',
    ' D1/D3=виконано форми=10 точні-позиції=так',
    ' файл-ук=так .sens=відхилено відновлення=так',
    ' Core4=НЕ_ВИКОНУЄТЬСЯ повний-REPL=НЕ_РЕАЛІЗОВАНО');
end;

begin
  Application.Initialize;
  Window := TSeansWindow.Create(Application);
  try
    if (ParamCount = 3) and (ParamStr(1) = '--самоперевірка') then begin
      Window.ConnectPinned(RawByteString(ParamStr(2)));
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(3));
    end else if ParamCount = 0 then begin
      Window.ConnectPinned('external/sens');
      Window.Show;
      Application.Run;
    end else
      raise Exception.Create(
        'Виклик: sens-seans-d3 [--самоперевірка pinned-каталог тимчасова-тека]');
  finally
    Window.Free;
  end;
end.
