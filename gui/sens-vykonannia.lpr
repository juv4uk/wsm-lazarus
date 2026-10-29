{ Справжня графічна оболонка Lazarus для обмеженого виконання SENS.
  Джерело законів: pinned external/sens; тут ЖОДНОГО dispatch.
  Українська «ук» — людиночитаний вхід окремої TNativeSession.
  Канонічний двійковий .sens — ОКРЕМИЙ прямий вхід фізичного D3
  executor. Обидва механізми вже існували до цього GUI-зрізу. }
program sens_vykonannia;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, wsm.source, wsm.session, wsm.sessiond3,
  wsm.t5m, wsm.binaryexec;

const
  MaxVisualInput = 65536;
  MaxVisualForms = 256;
type
  EVisualError = class(Exception);

  TVykonanniaForm = class(TForm)
  private
    FSession: TNativeSession;
    FPhysicalExecutor: TBinaryExecutor;
    FLastPhysicalAnswer: RawByteString;
    FInput: TMemo;
    FGrid: TStringGrid;
    FStatus: TLabel;
    FRunButton, FFileButton, FPhysicalButton: TButton;
    FDialog, FPhysicalDialog: TOpenDialog;
    procedure RunClicked(Sender: TObject);
    procedure FileClicked(Sender: TObject);
    procedure PhysicalClicked(Sender: TObject);
    procedure ClearResults;
    procedure ShowReplies(const Replies: TSessionReplies);
    procedure ShowFailure(const MessageText: String);
    procedure CheckInputBudget(const TextBytes: RawByteString);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure RunBytes(const TextBytes: RawByteString);
    procedure RunFile(const FileName: String);
    function RunPhysicalFile(const FileName: String): Boolean;
    procedure SmokeTest(const FileName, D1File, QuoteFile, BlockedFile,
      BadT5MFile, MultiFile: String);
  end;

var Window: TVykonanniaForm;

procedure Require(Yes: Boolean; const MessageText: String);
begin
  if not Yes then raise EVisualError.Create(MessageText);
end;

function UkrainianBytes(const Value: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(Value));
end;

constructor TVykonanniaForm.Create(AOwner: TComponent);
var Toolbar, Footer: TPanel;
    Instruction: TLabel;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — нативне виконання, українська проєкція';
  Width := 1050;
  Height := 660;
  Position := poScreenCenter;

  Toolbar := TPanel.Create(Self);
  Toolbar.Parent := Self;
  Toolbar.Align := alTop;
  Toolbar.Height := 78;
  Toolbar.BevelOuter := bvNone;

  Instruction := TLabel.Create(Self);
  Instruction.Parent := Toolbar;
  Instruction.SetBounds(12, 8, 1000, 20);
  Instruction.Caption :=
    'Введіть проєкцію «ук». Виконуються лише підтримані D1/D3-форми SENS.';
  Instruction.AutoSize := True;

  FRunButton := TButton.Create(Self);
  FRunButton.Parent := Toolbar;
  FRunButton.Caption := 'Виконати форми';
  FRunButton.SetBounds(12, 35, 190, 32);
  FRunButton.OnClick := @RunClicked;

  FFileButton := TButton.Create(Self);
  FFileButton.Parent := Toolbar;
  FFileButton.Caption := 'Відкрити проєкцію .lisp…';
  FFileButton.SetBounds(216, 35, 260, 32);
  FFileButton.OnClick := @FileClicked;

  FPhysicalButton := TButton.Create(Self);
  FPhysicalButton.Parent := Toolbar;
  FPhysicalButton.Caption := 'Виконати двійковий .sens…';
  FPhysicalButton.SetBounds(490, 35, 285, 32);
  FPhysicalButton.OnClick := @PhysicalClicked;

  FPhysicalDialog := TOpenDialog.Create(Self);
  FPhysicalDialog.Title := 'Оберіть канонічну фізичну програму .sens';
  FPhysicalDialog.Filter := 'Двійкова програма SENS (*.sens)|*.sens';

  FDialog := TOpenDialog.Create(Self);
  FDialog.Title := 'Оберіть українську проєкцію SENS';
  FDialog.Filter := 'Українська проєкція (*.lisp)|*.lisp';

  FInput := TMemo.Create(Self);
  FInput.Parent := Self;
  FInput.Align := alTop;
  FInput.Height := 150;
  FInput.ScrollBars := ssVertical;
  FInput.Text := '(сполучити так ())';

  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 62;
  Footer.BevelOuter := bvNone;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Footer;
  FStatus.SetBounds(12, 10, 1010, 44);
  FStatus.Caption :=
    'Лише підтверджена частина D3. Немає повного REPL або Core4.';
  FStatus.AutoSize := True;

  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.FixedCols := 0;
  FGrid.FixedRows := 1;
  FGrid.ColCount := 6;
  FGrid.RowCount := 2;
  FGrid.Options := (FGrid.Options - [goEditing]) + [goColSizing, goRowSelect];
  FGrid.Cells[0,0] := 'Форма / слово №';
  FGrid.Cells[1,0] := 'Стан механізму';
  FGrid.Cells[2,0] := 'Двійковий результат';
  FGrid.Cells[3,0] := 'Діагностика';
  FGrid.Cells[4,0] := 'Байт';
  FGrid.Cells[5,0] := 'Рядок:стовпець';
  FGrid.ColWidths[0] := 90;
  FGrid.ColWidths[1] := 155;
  FGrid.ColWidths[2] := 245;
  FGrid.ColWidths[3] := 260;
  FGrid.ColWidths[4] := 75;
  FGrid.ColWidths[5] := 145;
  ClearResults;

  { Два НЕЗАЛЕЖНІ вже перевірені механізми D3:
    текстова сесія з постійним станом та фізичний exact executor.
    Один не конвертує неявно вхід іншого. }
  FSession := nil;
  FPhysicalExecutor := nil;
  try
    FSession := TNativeSession.Create(NewNativeD3Executor('external/sens'));
    FPhysicalExecutor := TBinaryExecutor.Create('external/sens');
  except
    FreeAndNil(FSession);
    FreeAndNil(FPhysicalExecutor);
    raise;
  end;
end;

destructor TVykonanniaForm.Destroy;
begin
  FPhysicalExecutor.Free;
  FSession.Free;
  inherited Destroy;
end;

procedure TVykonanniaForm.ClearResults;
var I: Integer;
begin
  FLastPhysicalAnswer := '';
  FGrid.RowCount := 2;
  for I := 0 to FGrid.ColCount - 1 do FGrid.Cells[I,1] := '';
end;

procedure TVykonanniaForm.ShowFailure(const MessageText: String);
begin
  ClearResults;
  FStatus.Caption := 'Помилка графічного вводу: ' + MessageText;
end;

procedure TVykonanniaForm.ShowReplies(const Replies: TSessionReplies);
var I: SizeInt;
begin
  ClearResults;
  if Length(Replies) > MaxVisualForms then
    raise EVisualError.Create('забагато результатів для візуальної таблиці');
  FGrid.RowCount := Length(Replies)+1;
  if FGrid.RowCount < 2 then FGrid.RowCount := 2;
  for I := 0 to High(Replies) do begin
    FGrid.Cells[0,I+1] := IntToStr(Replies[I].FormNumber);
    if Replies[I].Ok then FGrid.Cells[1,I+1] := 'ВИКОНАНО'
    else FGrid.Cells[1,I+1] := 'ПОМИЛКА';
    FGrid.Cells[2,I+1] := String(Replies[I].Output);
    FGrid.Cells[3,I+1] := String(Replies[I].Diagnostic);
    FGrid.Cells[4,I+1] := IntToStr(Replies[I].ByteOffset);
    FGrid.Cells[5,I+1] := IntToStr(Replies[I].Line)+
      ':'+IntToStr(Replies[I].ByteColumn);
  end;
  FStatus.Caption := 'Оброблено форм/відповідей: '+
    IntToStr(Length(Replies))+
    '; стан — властивість хост-механізму, НЕ D1-істина; Core4 не виконується.';
end;

procedure TVykonanniaForm.CheckInputBudget(const TextBytes: RawByteString);
var Doc: TSourceDocument;
begin
  if Length(TextBytes) > MaxVisualInput then
    raise EVisualError.Create('ввід перевищує фізичні 64 КіБ');
  Doc := nil;
  try
    try
      Doc := ReadUkrainianSource(TextBytes);
    except
      on E: ESourceError do Exit; { помилку з позицією поверне session }
    end;
    if Length(Doc.Forms) > MaxVisualForms then
      raise EVisualError.Create('ввід перевищує 256 форм');
  finally
    Doc.Free;
  end;
end;

procedure TVykonanniaForm.RunBytes(const TextBytes: RawByteString);
begin
  ClearResults;
  try
    CheckInputBudget(TextBytes);
    ShowReplies(FSession.Submit(TextBytes));
  except
    on E: Exception do ShowFailure(E.Message);
  end;
end;

procedure TVykonanniaForm.RunFile(const FileName: String);
var Stream: TFileStream; Bytes: RawByteString;
begin
  ClearResults;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size < 0) or (Stream.Size > MaxVisualInput) then
        raise EVisualError.Create('файл перевищує фізичні 64 КіБ');
      SetLength(Bytes, SizeInt(Stream.Size));
      if Length(Bytes) > 0 then Stream.ReadBuffer(Bytes[1], Length(Bytes));
    finally
      Stream.Free;
    end;
    { Та сама сесія: порядок виконання та лічильник форм збережені. }
    CheckInputBudget(Bytes);
    ShowReplies(FSession.Submit(Bytes));
  except
    on E: Exception do ShowFailure(E.Message);
  end;
end;

{ Виключно HOST-операція: з фізичного T5M -> уже наявний
  TBinaryExecutor.ExecutePhysicalT5M -> канонічний T5M-відгук.
  Boolean повідомляє успіх UI, не SENS D1. FileName — шлях host,
  не українська проєкція. RawByteString і TExactWords є керованими
  FPC значеннями та звільняються після виклику. Вікно тримає лише
  точно перевірену відповідь FLastPhysicalAnswer до нового запуску.
  Усі рядки публікуються ПІСЛЯ перевірки кожного фізичного слова. }
function TVykonanniaForm.RunPhysicalFile(const FileName: String): Boolean;
var
  Stream: TFileStream;
  Physical, Answer: RawByteString;
  Words: TExactWords;
  I: SizeInt;
begin
  Result := False;
  ClearResults;
  try
    if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
      raise EVisualError.Create('фізична програма повинна мати .sens');
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size < 1) or (Stream.Size > MaxVisualInput) then
        raise EVisualError.Create('фізичний .sens порожній або перевищує 64 КіБ');
      SetLength(Physical, SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1], Length(Physical));
    finally
      Stream.Free;
    end;
    Answer := FPhysicalExecutor.ExecutePhysicalT5M(Physical);
    if (Length(Answer) < 1) or (Length(Answer) > MaxVisualInput) then
      raise EVisualError.Create('надмірна фізична відповідь');
    DecodeT5M(Answer, Words);
    if EncodeT5M(Words) <> Answer then
      raise EVisualError.Create('неканонічна фізична відповідь');
    if (Length(Words) < 1) or (Length(Words) > MaxVisualForms) then
      raise EVisualError.Create('фізичних слів відповіді понад межу 256');

    { Атомарна публікація: до цієї точки немає часткової таблиці. }
    FGrid.RowCount := Length(Words) + 1;
    if FGrid.RowCount < 2 then FGrid.RowCount := 2;
    for I := 0 to High(Words) do begin
      FGrid.Cells[0,I+1] := 'слово ' + IntToStr(I+1);
      FGrid.Cells[1,I+1] := 'ФІЗИЧНО ВИКОНАНО';
      FGrid.Cells[2,I+1] := 'W'+IntToStr(Length(Words[I]))+
        ':'+String(Words[I]);
      FGrid.Cells[3,I+1] := 'виконаний фізичний D3, не текст';
      FGrid.Cells[4,I+1] := IntToStr(Length(Answer));
      FGrid.Cells[5,I+1] := '—';
    end;
    FLastPhysicalAnswer := Answer;
    FStatus.Caption := 'РЕАЛЬНО виконано канонічний .sens: '+
      IntToStr(Length(Words))+' фізичних слів результату; '+
      IntToStr(Length(Answer))+' байтів T5M; D12+/Core4 не заявлені.';
    Result := True;
  except
    on E: EBinaryExecutionError do
      ShowFailure('фізична форма, слово №'+IntToStr(E.WordIndex)+': '+E.Message);
    on E: Exception do ShowFailure('двійковий .sens: '+E.Message);
  end;
end;

procedure TVykonanniaForm.PhysicalClicked(Sender: TObject);
begin
  if FPhysicalDialog.Execute then RunPhysicalFile(FPhysicalDialog.FileName);
end;

procedure TVykonanniaForm.RunClicked(Sender: TObject);
begin
  { LCL вже повертає UTF-8; не перекодовуємо її в іншу code page. }
  RunBytes(RawByteString(FInput.Text));
end;

procedure TVykonanniaForm.FileClicked(Sender: TObject);
begin
  if FDialog.Execute then RunFile(FDialog.FileName);
end;

procedure TVykonanniaForm.SmokeTest(const FileName, D1File, QuoteFile,
  BlockedFile, BadT5MFile, MultiFile: String);
var
  Bad: RawByteString;
  Words: TExactWords;
begin
  FInput.Text := 'так ні () (сполучити так ())';
  FRunButton.Click; { справжній LCL event, а не прямий виклик evaluator }
  Require(FGrid.RowCount=5, 'чотири результати не показані');
  Require((FGrid.Cells[2,1]='1') and (FGrid.Cells[2,2]='0') and
    (FGrid.Cells[2,3]='()') and (FGrid.Cells[2,4]='(1)'),
    'точна відмінність D1:0 та D3:000 втрачена');
  Require(FGrid.Cells[0,4]='4', 'порядок фізичних форм');
  RunBytes(UkrainianBytes('(перше ()) так'));
  Require(FGrid.RowCount=3, 'помилка і наступна форма не показані');
  Require((FGrid.Cells[1,1]='ПОМИЛКА') and
          (FGrid.Cells[1,2]='ВИКОНАНО') and
          (FGrid.Cells[2,2]='1'), 'помилка заблокувала наступний виклик');
  RunFile(FileName);
  Require(FGrid.RowCount=3, 'дві форми з файлу не прийнято');
  Require((FGrid.Cells[2,1]='0') and
          (FGrid.Cells[2,2]='1') and
          (FGrid.Cells[0,1]='7'), 'файл не виконався в тій самій сесії');
  Bad := #$FF;
  RunBytes(Bad);
  Require((FGrid.RowCount=2) and (FGrid.Cells[1,1]='ПОМИЛКА') and
          (FGrid.Cells[2,1]='') and
          (FGrid.Cells[3,1]<>''),
          'неправильний UTF-8 не відхилено або залишено старий результат');
  RunFile('відсутня-проєкція.lisp');
  Require((FGrid.Cells[2,1]='') and
          (Pos('Помилка графічного вводу',FStatus.Caption)=1),
          'відсутній файл залишив старі клітинки');
  RunBytes(UkrainianBytes('ні'));
  Require((FGrid.Cells[0,1]='9') and (FGrid.Cells[2,1]='0'),
          'сесія не відновилась після помилки');
  { G3.15: два реальні фізичні .sens із чинного senst5m CLI.
    ЖОДЕН текст попередньої ук-сесії не використано для їх виконання. }
  Require(Assigned(FPhysicalButton.OnClick),
    'справжній графічний двійковий режим не підключено');
  Require(RunPhysicalFile(D1File), 'фізичне D1:1 не виконалося');
  Require((FGrid.RowCount=2) and (FGrid.Cells[0,1]='слово 1') and
    (FGrid.Cells[1,1]='ФІЗИЧНО ВИКОНАНО') and
    (FGrid.Cells[2,1]='W1:1') and
    (Pos('РЕАЛЬНО виконано канонічний .sens:',FStatus.Caption)=1),
    'результат D1:1 не є фізичним словом у справжній таблиці');
  DecodeT5M(FLastPhysicalAnswer,Words);
  Require((Length(Words)=1) and (Words[0]='1') and
    (EncodeT5M(Words)=FLastPhysicalAnswer),
    'двійковий результат D1:1 не має канонічних T5M-байтів');

  Require(RunPhysicalFile(QuoteFile),'фізична D3:001 цитата не виконалася');
  Require((FGrid.RowCount=5) and
    (FGrid.Cells[2,1]='W2:10') and
    (FGrid.Cells[2,2]='W1:1') and
    (FGrid.Cells[2,3]='W1:0') and
    (FGrid.Cells[2,4]='W2:01'),
    'фізичні слова цитованого списку втратили точну ширину/порядок');
  DecodeT5M(FLastPhysicalAnswer,Words);
  Require((Length(Words)=4) and
    (EncodeT5M(Words)=FLastPhysicalAnswer),
    'цитований список не повернув канонічний фізичний T5M');

  Require(not RunPhysicalFile(BlockedFile),'непідтриману D4 голову прийнято');
  Require((FGrid.RowCount=2) and (FGrid.Cells[2,1]='') and
    (FLastPhysicalAnswer='') and
    (Pos('Помилка графічного вводу:',FStatus.Caption)=1),
    'після відмови D4 залишився попередній фізичний результат');
  Require(not RunPhysicalFile(MultiFile),'два корені прийнято за одну форму');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer=''),
    'після багатокореневої форми залишилася часткова відповідь');
  Require(not RunPhysicalFile(BadT5MFile),'неканонічний T5M прийнято');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer=''),
    'після пошкодженого T5M залишився результат');
  Require(not RunPhysicalFile(FileName),'.lisp прийнято за фізичний .sens');
  Require(not RunPhysicalFile('відсутній-фізичний.sens'),
    'відсутній фізичний файл прийнято');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer=''),
    'після помилки host-шляху лишився фізичний результат');

  Require(RunPhysicalFile(D1File),'фізичний D3 executor не відновився');
  Require(FGrid.Cells[2,1]='W1:1',
    'повторний канонічний D1 не виконався');
  RunBytes(UkrainianBytes('так'));
  Require((FGrid.RowCount=2) and (FGrid.Cells[0,1]='10') and
    (FGrid.Cells[2,1]='1') and (FLastPhysicalAnswer=''),
    'двійковий режим змінив попередній стан української сесії');
  WriteLn('LCL-ФІЗИЧНЕ-D3-ГАРАЗД T5M=канонічний',
    ' D1=1 цитата=4-слова D4=відхилено',
    ' багато-коренів=відхилено пізня-помилка=очищено',
    ' текстова-сесія=форма-10 D12+=ні Core4=ні');

  WriteLn('LCL-ВИКОНАННЯ-ГАРАЗД форми=9 двійкові=так ',
    'LCL-кнопка=натиснута файл=виконаний помилки=відхилені ',
    'старі-клітинки=очищено повний-REPL=ні Core4=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — двійкове виконання, проєкція ук';
    Application.CreateForm(TVykonanniaForm, Window);
    if (ParamCount>=1) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>7 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SmokeTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;
      Halt(0);
    end;
    if ParamCount<>0 then
      raise EVisualError.Create('використання: sens-vykonannia [--самоперевірка файл.lisp]');
    Application.Run;
  except
    on E: Exception do begin
      WriteLn(StdErr,'LCL-ВИКОНАННЯ-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
