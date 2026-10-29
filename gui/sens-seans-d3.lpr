{ G5.56 — Lazarus/LCL оболонка над уже злитим обмеженим D3-сеансом.
  Редактор приймає ЯВНО компактну українську проєкцію «ук».
  Це не канонічна фізична .sens і не повний SENS REPL.
  Один TNativeSession живе разом із TForm; виконує лише pinned D3 executor.
  Жодної семантики за людськими назвами у вікні немає. }
program sens_seans_d3;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, ExtCtrls, Dialogs,
  wsm.session, wsm.sessiond3, wsm.binaryexec, wsm.t5m;

type
  TSeansWindow = class(TForm)
  private
    FSession: TNativeSession;
    FPhysicalExecutor: TBinaryExecutor;
    InputMemo, Journal: TMemo;
    RunButton, LoadButton, PhysicalButton: TButton;
    PhysicalPath: TEdit;
    OpenSource: TOpenDialog;
    Status: TLabel;
    procedure RenderReplies(const Replies: TSessionReplies);
    procedure RunClick(Sender: TObject);
    procedure LoadClick(Sender: TObject);
    procedure PhysicalClick(Sender: TObject);
    procedure ExecutePhysicalPath(const Path: String);
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
  FPhysicalExecutor := nil;

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
  PhysicalPath := TEdit.Create(Self);
  PhysicalPath.Parent := Panel;
  PhysicalPath.SetBounds(490, 8, 240, 27);
  PhysicalPath.Text := 'program.sens';
  PhysicalButton := TButton.Create(Self);
  PhysicalButton.Parent := Panel;
  PhysicalButton.SetBounds(738, 6, 195, 31);
  PhysicalButton.Caption := 'Виконати фізичний .sens';
  PhysicalButton.Enabled := False;
  PhysicalButton.OnClick := @PhysicalClick;

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
  FPhysicalExecutor.Free;
  inherited Destroy;
end;

procedure TSeansWindow.ConnectPinned(const Root: RawByteString);
begin
  if FSession <> nil then
    raise ESessionError.Create('повторна ініціалізація сеансу заборонена');
  FSession := TNativeSession.Create(NewNativeD3Executor(Root));
  FPhysicalExecutor := TBinaryExecutor.Create(Root);
  RunButton.Enabled := True;
  LoadButton.Enabled := True;
  PhysicalButton.Enabled := True;
  Status.Caption := 'Підключено pinned виконавець Д3; оброблено форм: 0';
end;

{ Фізичне джерело — обмежені байти pinned T5M. Повертається окремий
  T5M-вихід D3; файл ніколи не перетворюється в .lisp чи текст «ук».
  Кількість байтів перевіряється до читання, executor володіє тільки
  власним станом, а результат DecodeT5M володіє тимчасовим списком слів. }
procedure TSeansWindow.ExecutePhysicalPath(const Path: String);
var Stream: TFileStream; Physical, Reply: RawByteString;
    Words: TExactWords; I: SizeInt; Display: String;
begin
  if FPhysicalExecutor = nil then Exit;
  if LowerCase(ExtractFileExt(Path)) <> '.sens' then begin
    Journal.Lines.Add('Фізична відмова: потрібен канонічний двійковий .sens файл.');
    Exit;
  end;
  Stream := nil;
  try
    Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    if (Stream.Size < 1) or (Stream.Size > MAX_T5M_FILE_BYTES) then
      raise ET5MError.Create('фізичний файл поза межею T5M');
    SetLength(Physical, Stream.Size);
    Stream.ReadBuffer(Physical[1], Length(Physical));
    Reply := FPhysicalExecutor.ExecutePhysicalT5M(Physical);
    DecodeT5M(Reply, Words);
    Display := '';
    for I := 0 to High(Words) do begin
      if I <> 0 then Display := Display + ' ';
      Display := Display + String(Words[I]);
    end;
    Journal.Lines.Add('Фізичний T5M: ' + Display);
    Status.Caption := 'Фізичний .sens виконано; постійний сеанс форм: ' +
      IntToStr(FSession.FormsSeen);
  except
    on E: EBinaryExecutionError do
      Journal.Lines.Add('Фізична відмова слово=' + IntToStr(E.WordIndex) +
        ': ' + E.Message);
    on E: Exception do
      Journal.Lines.Add('Фізична відмова: ' + E.Message);
  end;
  Stream.Free;
end;

procedure TSeansWindow.PhysicalClick(Sender: TObject);
begin
  if PhysicalPath.Text <> '' then ExecutePhysicalPath(PhysicalPath.Text);
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
      UTF8String(R.Output) + UTF8String(R.Diagnostic));
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
    PhysicalWords: TExactWords;
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

  { D7: точна машинна текстова послідовність із pinned reader,
    а не Unicode-об'єкт у runtime та не нова функція Pascal. }
  InputMemo.Text := '(як-є кіт)';
  RunButton.Click;
  Check((FSession.FormsSeen = 11) and
    (Pos('Результат №11', Journal.Text) > 0) and
    (Pos('(1110010 1110011 1101110)', Journal.Text) > 0),
    'D7 втратило точні 7-бітні слова в реальному LCL журналі');

  { Доказ прямого канонічного шляху: ця T5M форма походить тільки з
    бінарних слів, результат теж показаний як точні біти, не проєкція. }
  SetLength(PhysicalWords, 4);
  PhysicalWords[0] := '10'; PhysicalWords[1] := '001';
  PhysicalWords[2] := '1'; PhysicalWords[3] := '01';
  Data := EncodeT5M(PhysicalWords);
  Physical := IncludeTrailingPathDelimiter(TempDir) + 'цитата.sens';
  OutFile := TFileStream.Create(Physical, fmCreate);
  try OutFile.WriteBuffer(Data[1], Length(Data)); finally OutFile.Free; end;
  BeforeCount := FSession.FormsSeen;
  PhysicalPath.Text := Physical;
  PhysicalButton.Click;
  Check((Pos('Фізичний T5M: 1', Journal.Text) > 0) and
    (FSession.FormsSeen = BeforeCount),
    'канонічний .sens не виконався окремо від постійного сеансу');

  Physical := IncludeTrailingPathDelimiter(TempDir) + 'помилка.sens';
  Data := #243;
  OutFile := TFileStream.Create(Physical, fmCreate);
  try OutFile.WriteBuffer(Data[1], Length(Data)); finally OutFile.Free; end;
  PhysicalPath.Text := Physical;
  PhysicalButton.Click;
  Check((Pos('Фізична відмова слово=0', Journal.Text) > 0) and
    (FSession.FormsSeen = BeforeCount),
    'помилка T5M не зберегла позиційну відмову або змінила сеанс');

  WriteLn('ЛКЛ-СЕАНС-Д3-ГАРАЗД Lazarus=GTK2 реальні-кліки=7',
    ' D1/D3/D7=виконано форми=11 точні-позиції=так',
    ' файл-ук=так .sens=відхилено відновлення=так',
    ' Core4=НЕ_ВИКОНУЄТЬСЯ повний-REPL=НЕ_РЕАЛІЗОВАНО');
  WriteLn('ФІЗИЧНИЙ-SENS-LCL-ГАРАЗД T5M=точний відмова=позиційна');
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
