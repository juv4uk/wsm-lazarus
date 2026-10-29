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
  wsm.t5m, wsm.binaryexec, wsm.d3batch, wsm.d2source,
  wsm.bind, wsm.ukroundtrip;

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
    FRunButton, FFileButton, FPhysicalButton, FBatchButton: TButton;
    FUkrButton, FUkrFileButton, FPairButton: TButton;
    FDialog, FPhysicalDialog, FBatchDialog, FUkrDialog, FPairDialog: TOpenDialog;
    procedure RunClicked(Sender: TObject);
    procedure FileClicked(Sender: TObject);
    procedure PhysicalClicked(Sender: TObject);
    procedure BatchClicked(Sender: TObject);
    procedure UkrClicked(Sender: TObject);
    procedure UkrFileClicked(Sender: TObject);
    procedure PairClicked(Sender: TObject);
    function RunPhysicalBatchBytes(const Physical: RawByteString): Boolean;
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
    function RunPhysicalBatchFile(const FileName: String): Boolean;
    function RunUkrPhysicalBytes(const Input: RawByteString): Boolean;
    function RunUkrPhysicalFile(const FileName: String): Boolean;
    function RunPinnedPairFile(const FileName: String): Boolean;
    procedure SmokeTest(const FileName, D1File, QuoteFile, BlockedFile,
      BadT5MFile, MultiFile, BatchFile, BadBatchFile, UkrFile: String);
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
  Toolbar.Height := 120;
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

  { Новий режим лише в існуючому LCL-вікні; не дублюємо evaluator. }
  FBatchButton := TButton.Create(Self);
  FBatchButton.Parent := Toolbar;
  FBatchButton.Caption := 'Виконати пакет .sens…';
  FBatchButton.SetBounds(790, 35, 228, 32);
  FBatchButton.OnClick := @BatchClicked;

  { Окремий явний шлях ПОВНОЇ укр-проєкції через pinned T5M;
    звичайний короткий ук-режим і фізичний .sens не підміняємо. }
  FUkrButton := TButton.Create(Self);
  FUkrButton.Parent := Toolbar;
  FUkrButton.Caption := 'Виконати укр фізично';
  FUkrButton.SetBounds(12, 78, 230, 32);
  FUkrButton.OnClick := @UkrClicked;

  FUkrFileButton := TButton.Create(Self);
  FUkrFileButton.Parent := Toolbar;
  FUkrFileButton.Caption := 'Відкрити повну укр .lisp…';
  FUkrFileButton.SetBounds(255, 78, 275, 32);
  FUkrFileButton.OnClick := @UkrFileClicked;

  { G5.42: явний paired admission — тут .sens є реальним машинним
    входом, а .lisp лише pinned ukr-проєкцією для точної звірки. }
  FPairButton := TButton.Create(Self);
  FPairButton.Parent := Toolbar;
  FPairButton.Caption := 'Виконати пару .lisp + .sens…';
  FPairButton.SetBounds(542, 78, 315, 32);
  FPairButton.OnClick := @PairClicked;

  FPairDialog := TOpenDialog.Create(Self);
  FPairDialog.Title := 'Оберіть український .lisp із однойменним .sens';
  FPairDialog.Filter := 'Повна проєкція укр (*.lisp)|*.lisp';

  FUkrDialog := TOpenDialog.Create(Self);
  FUkrDialog.Title := 'Оберіть повну українську проєкцію укр (.lisp)';
  FUkrDialog.Filter := 'Повна українська проєкція (*.lisp)|*.lisp';

  FBatchDialog := TOpenDialog.Create(Self);
  FBatchDialog.Title := 'Оберіть фізичний пакет D3 .sens';
  FBatchDialog.Filter := 'Двійковий пакет SENS (*.sens)|*.sens';

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

{ G3.20: новий режим ВЖЕ НАЯВНОГО Lazarus вікна, а не новий
  D3 evaluator. Вхід — host шлях до 1..64 незалежних canonical T5M форм;
  їх виконує чинний pinned ExecutePhysicalD3Batch. Значення D12+ не
  декодуємо і мовних законів із написання .lisp не створюємо.
  Doc/Words/Answer — короткочасні керовані FPC значення. Вікно зберігає
  лише FLastPhysicalAnswer після ПОВНОЇ перевірки всього пакета. }
{ Один спільний механізм фізичного показу: ввід уже є канонічними
  T5M-байтами; D2/T5M та 1..64 справжні відповіді перевіряємо до UI.
  Doc і Words — приватні FPC-керовані значення одного виклику.
  FLastPhysicalAnswer переходить у стан вікна лише після успіху. }
function TVykonanniaForm.RunPhysicalBatchBytes(
  const Physical: RawByteString): Boolean;
var
  Answer, Detail: RawByteString;
  Words: TExactWords;
  Doc: TD2Document;
  Forms, I, J, First, Last: SizeInt;
begin
  Result := False;
  ClearResults;
  Doc := nil;
  try
    ExecutePhysicalD3Batch(Physical, 'external/sens', Answer, Forms);
    if (Length(Answer)<1) or (Length(Answer)>MaxVisualInput) then
      raise EVisualError.Create('надмірна фізична відповідь пакета');
    DecodeT5M(Answer, Words);
    if EncodeT5M(Words)<>Answer then
      raise EVisualError.Create('неканонічна фізична відповідь пакета');
    if (Forms<1) or (Forms>64) or
       (Length(Words)<1) or (Length(Words)>MaxVisualForms) then
      raise EVisualError.Create('пакет перевищив межу візуальних форм/слів');
    Doc := ReadD2T5M(Answer);
    if Length(Doc.Roots)<>Forms then
      raise EVisualError.Create('число D2 відповідей не збігається з формами');
    for I:=0 to Forms-1 do begin
      First := Doc.Roots[I].WordIndex-1;
      Last := Doc.Roots[I].EndWordIndexExclusive-1;
      if (First<0) or (Last<=First) or (Last>Length(Words)) then
        raise EVisualError.Create('некоректні фізичні межі D2 відповіді');
    end;

    FGrid.RowCount := Forms+1;
    for I:=0 to Forms-1 do begin
      First := Doc.Roots[I].WordIndex-1;
      Last := Doc.Roots[I].EndWordIndexExclusive-1;
      Detail := '';
      for J:=First to Last-1 do begin
        if J<>First then Detail:=Detail+' ';
        Detail:=Detail+'W'+IntToStr(Length(Words[J]))+':'+Words[J];
      end;
      FGrid.Cells[0,I+1] := 'форма '+IntToStr(I+1);
      FGrid.Cells[1,I+1] := 'ПАКЕТ ВИКОНАНО';
      FGrid.Cells[2,I+1] := String(Detail);
      FGrid.Cells[3,I+1] := 'перевірена фізична D2 відповідь';
      FGrid.Cells[4,I+1] := IntToStr(Length(Answer));
      FGrid.Cells[5,I+1] := '—';
    end;
    FLastPhysicalAnswer := Answer;
    FStatus.Caption := 'ФІЗИЧНИЙ ПАКЕТ: виконано '+IntToStr(Forms)+
      ' D3 форм, '+IntToStr(Length(Words))+' exact слів / '+
      IntToStr(Length(Answer))+' байтів T5M; Core4/D12+ не заявлені.';
    Result := True;
  except
    on E: ED3BatchError do
      ShowFailure('пакет, форма='+IntToStr(E.FormIndex)+
        ' слово='+IntToStr(E.WordIndex)+': '+E.Message);
    on E: Exception do ShowFailure('фізичний пакет .sens: '+E.Message);
  end;
  Doc.Free;
end;

{ Файловий .sens залишається ОКРЕМИМ режимом, який передає
  тільки сирі фізичні байти у той самий спільний renderer. }
function TVykonanniaForm.RunPhysicalBatchFile(
  const FileName: String): Boolean;
var
  Stream: TFileStream;
  Physical: RawByteString;
begin
  Result := False;
  ClearResults;
  try
    if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
      raise EVisualError.Create('фізичний пакет повинен мати .sens');
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size < 1) or (Stream.Size > MaxVisualInput) then
        raise EVisualError.Create('фізичний пакет порожній або перевищує 64 КіБ');
      SetLength(Physical, SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1], Length(Physical));
    finally
      Stream.Free;
    end;
    Result := RunPhysicalBatchBytes(Physical);
  except
    on E: Exception do ShowFailure('двійковий пакет .sens: '+E.Message);
  end;
end;

{ Людський укр вхід НЕ канон. Його pinned D1..D9 координати
  перетворює злитий перевірений модуль ukroundtrip; D7 — дані.
  Після фізичного round-trip виконує лише чинний D3 executor.
  Вихідний Boolean — стан host GUI, а не мовна істина D1. }
function TVykonanniaForm.RunUkrPhysicalBytes(
  const Input: RawByteString): Boolean;
var
  Tables: TDomainSet;
  Longs: TLongProjection;
  Physical, Printed, Again: RawByteString;
begin
  Result := False;
  ClearResults;
  try
    if (Length(Input)<1) or (Length(Input)>MaxVisualInput) then
      raise EVisualError.Create('укр-проєкція порожня або понад 64 КіБ');
    LoadPinnedDomains('external/sens',Tables);
    LoadPinnedLongProjection('external/sens',Tables,Longs);
    Physical:=UkrainianToPhysical(Input,Tables,Longs);
    Printed:=PhysicalToUkrainian(Physical,Tables,Longs);
    Again:=UkrainianToPhysical(Printed,Tables,Longs);
    if Again<>Physical then
      raise EVisualError.Create('побайтовий укр/T5M round-trip не збігся');
    if not RunPhysicalBatchBytes(Physical) then Exit;
    FStatus.Caption:='УКР → ФІЗИЧНИЙ D3: точний T5M, '+
      IntToStr(FGrid.RowCount-1)+
      ' виконаних форм; D7 лише дані, Core4/D12+ не заявлені.';
    Result:=True;
  except
    on E: Exception do ShowFailure('проєкція укр: '+E.Message);
  end;
end;

function TVykonanniaForm.RunUkrPhysicalFile(
  const FileName: String): Boolean;
var
  Stream: TFileStream;
  Data: RawByteString;
begin
  Result:=False;
  ClearResults;
  try
    if LowerCase(ExtractFileExt(FileName))<>'.lisp' then
      raise EVisualError.Create('українська проєкція повинна мати .lisp');
    Stream:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxVisualInput) then
        raise EVisualError.Create('укр-файл порожній або понад 64 КіБ');
      SetLength(Data,SizeInt(Stream.Size));
      Stream.ReadBuffer(Data[1],Length(Data));
    finally
      Stream.Free;
    end;
    Result:=RunUkrPhysicalBytes(Data);
  except
    on E:Exception do ShowFailure('файл укр .lisp: '+E.Message);
  end;
end;

{ G5.42. FileName — позичений host-шлях до .lisp; відповідний
  .sens має те саме ім'я до розширення. Немає автоматичного створення
  .sens із людського тексту. Обидва файли читаємо окремо в обмежені
  RawByteString, які FPC звільнить після цього виклику. Ключі/написи
  належать pinned SENS; єдиний виконавець — ExecutePhysicalD3Batch.
  Відповідь та host Boolean стають публічними тільки після повного
  byte-exact admission і успішного фізичного D3 виконання. }
function TVykonanniaForm.RunPinnedPairFile(
  const FileName: String): Boolean;
var
  Source, Expected, Printed, Again, Paired: RawByteString;
  Tables: TDomainSet;
  Longs: TLongProjection;
  Words: TExactWords;
  PhysicalPath: String;

  function ReadBounded(const Path: String): RawByteString;
  var Stream: TFileStream;
  begin
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxVisualInput) then
        raise EVisualError.Create('файл пари порожній або понад 64 КіБ');
      SetLength(Result,SizeInt(Stream.Size));
      Stream.ReadBuffer(Result[1],Length(Result));
    finally
      Stream.Free;
    end;
  end;

begin
  Result:=False;
  ClearResults;
  try
    if LowerCase(ExtractFileExt(FileName))<>'.lisp' then
      raise EVisualError.Create('пара починається з українського .lisp');
    PhysicalPath:=ChangeFileExt(FileName,'.sens');
    { Тільки звичайна повна укр-проєкція; ані D7, ані текстове
      написання не присвоюють викличність чи D12+ значення. }
    Source:=ReadBounded(FileName);
    LoadPinnedDomains('external/sens',Tables);
    LoadPinnedLongProjection('external/sens',Tables,Longs);
    Expected:=UkrainianToPhysical(Source,Tables,Longs);
    Printed:=PhysicalToUkrainian(Expected,Tables,Longs);
    Again:=UkrainianToPhysical(Printed,Tables,Longs);
    if Again<>Expected then
      raise EVisualError.Create('необернена pinned укр/T5M проєкція');

    { Фактичний ввід виконавця — лише ФАЙЛОВІ байти; текстовий
      Expected слугує незалежним byte-exact підтвердженням пари. }
    Paired:=ReadBounded(PhysicalPath);
    DecodeT5M(Paired,Words);
    if EncodeT5M(Words)<>Paired then
      raise EVisualError.Create('неканонічний фізичний T5M пари');
    if Paired<>Expected then
      raise EVisualError.Create('не збігаються точні байти укр та .sens');

    if not RunPhysicalBatchBytes(Paired) then Exit;
    FStatus.Caption:='ПАРА УКР/.SENS: перевірено побайтово, виконано '+
      IntToStr(FGrid.RowCount-1)+
      ' фізичних D3 форм; D7 — дані, D12+/Core4 не заявлені.';
    Result:=True;
  except
    on E:Exception do ShowFailure('точна пара укр/.sens: '+E.Message);
  end;
end;

procedure TVykonanniaForm.PairClicked(Sender: TObject);
begin
  if FPairDialog.Execute then RunPinnedPairFile(FPairDialog.FileName);
end;

procedure TVykonanniaForm.UkrClicked(Sender: TObject);
begin
  RunUkrPhysicalBytes(RawByteString(FInput.Text));
end;

procedure TVykonanniaForm.UkrFileClicked(Sender: TObject);
begin
  if FUkrDialog.Execute then RunUkrPhysicalFile(FUkrDialog.FileName);
end;

procedure TVykonanniaForm.BatchClicked(Sender: TObject);
begin
  if FBatchDialog.Execute then RunPhysicalBatchFile(FBatchDialog.FileName);
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
  BlockedFile, BadT5MFile, MultiFile, BatchFile, BadBatchFile, UkrFile: String);
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

  { G3.20: відокремлена кнопка фізичного пакета, без зміни
    чинного контракту одиничної форми й української сесії. }
  Require(Assigned(FBatchButton.OnClick),
    'кнопку фізичного пакета Lazarus не підключено');
  Require(RunPhysicalBatchFile(BatchFile),
    'чотири фізичні D3 форми не виконалися в одному пакеті');
  Require((FGrid.RowCount=5) and
    (FGrid.Cells[0,1]='форма 1') and
    (FGrid.Cells[2,1]='W1:1') and
    (FGrid.Cells[2,2]='W1:0') and
    (FGrid.Cells[2,3]='W1:1') and
    (FGrid.Cells[2,4]='W3:000') and
    (Pos('ФІЗИЧНИЙ ПАКЕТ:', FStatus.Caption)=1),
    'чотири реально виконані D3 відповіді втратили порядок/ширину');
  DecodeT5M(FLastPhysicalAnswer,Words);
  Require((Length(Words)=4) and
    (Words[0]='1') and (Words[1]='0') and
    (Words[2]='1') and (Words[3]='000') and
    (EncodeT5M(Words)=FLastPhysicalAnswer),
    'пакет не має очікуваного канонічного фізичного T5M');
  Require(not RunPhysicalBatchFile(BadBatchFile),
    'пізню помилку фізичного пакета не відхилено');
  Require((FGrid.RowCount=2) and (FGrid.Cells[2,1]='') and
    (FLastPhysicalAnswer='') and
    (Pos('форма=2 слово=2', FStatus.Caption)>0),
    'пізня помилка не стерла байти/таблицю або втратила місце');
  Require(not RunPhysicalBatchFile(FileName),
    'український .lisp помилково прийнято за фізичний пакет');
  Require((FLastPhysicalAnswer='') and (FGrid.RowCount=2),
    'помилковий .lisp залишив стару відповідь');
  Require(RunPhysicalBatchFile(BatchFile),
    'фізичний пакет не відновився після пізньої відмови');
  Require((FGrid.RowCount=5) and (FGrid.Cells[2,4]='W3:000'),
    'повторний фізичний пакет повернув застарілу відповідь');

  { G5.39: повна укр-проєкція стає реальним фізичним виконанням
    через pinned T5M; коротка текстова сесія лишається незалежною. }
  Require(Assigned(FUkrButton.OnClick) and Assigned(FUkrFileButton.OnClick),
    'LCL укр-кнопки не підключені');
  FInput.Text:='ні так (атом? так)';
  FUkrButton.Click;
  Require((FGrid.RowCount=4) and
    (FGrid.Cells[2,1]='W1:0') and (FGrid.Cells[2,2]='W1:1') and
    (FGrid.Cells[2,3]='W1:1') and
    (Pos('УКР → ФІЗИЧНИЙ D3:',FStatus.Caption)=1),
    'повна укр форма не пройшла дійсний pinned D3');
  DecodeT5M(FLastPhysicalAnswer,Words);
  Require((Length(Words)=3) and
    (Words[0]='0') and (Words[1]='1') and (Words[2]='1') and
    (EncodeT5M(Words)=FLastPhysicalAnswer),
    'три укр-форми не дали байтово канонічного D3 T5M');
  Require(RunUkrPhysicalFile(UkrFile),
    'повний укр-файл .lisp не виконався фізично');
  Require((FGrid.RowCount=3) and
    (FGrid.Cells[2,1]='W1:0') and (FGrid.Cells[2,2]='W1:1'),
    'файловий укр-порядок D1 зіпсований');
  { G5.42: pair admission виконує прочитаний canonical .sens,
    а не згенеровані з тексту байти. Запис фізичної пари створив
    окремий чинний CLI senst5m. }
  Require(Assigned(FPairButton.OnClick),
    'справжню кнопку перевірки пари Lazarus не підключено');
  Require(RunPinnedPairFile(UkrFile),
    'правильну укр/.sens пару не виконано');
  Require((FGrid.RowCount=3) and
    (FGrid.Cells[2,1]='W1:0') and (FGrid.Cells[2,2]='W1:1') and
    (Pos('ПАРА УКР/.SENS:',FStatus.Caption)=1),
    'пара втратила exact D1 чи атомарне відображення');
  DecodeT5M(FLastPhysicalAnswer,Words);
  Require((Length(Words)=2) and
    (Words[0]='0') and (Words[1]='1') and
    (EncodeT5M(Words)=FLastPhysicalAnswer),
    'результат укр/.sens пари не є канонічним T5M');
  Bad:=FLastPhysicalAnswer;
  Require(RunPhysicalBatchFile(ChangeFileExt(UkrFile,'.sens')),
    'той самий фізичний .sens не виконався самостійно');
  Require((FLastPhysicalAnswer=Bad) and (FGrid.RowCount=3),
    'виконання пари не збігається з прямим фізичним runtime');
  Require(not RunPinnedPairFile(ExtractFilePath(UkrFile)+'пара-розбіжна.lisp'),
    'коректний, але НЕВІДПОВІДНИЙ .sens прийнято');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer=''),
    'розбіжність пари залишила попередню фізичну відповідь');
  Require(not RunPinnedPairFile(ExtractFilePath(UkrFile)+'пара-пошкоджена.lisp'),
    'пошкоджений T5M пари прийнято');
  Require(not RunPinnedPairFile(ExtractFilePath(UkrFile)+'пара-без-фізичного.lisp'),
    'без .sens пара нібито виконалася');
  Require(not RunPinnedPairFile(ExtractFilePath(UkrFile)+'пара-пізня.lisp'),
    'пізню D3 помилку фізичної пари прийнято');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer='') and
    (Pos('форма=2 слово=',FStatus.Caption)>0),
    'пізня фізична відмова пари не очистила snapshot або адресу');
  Require(not RunPinnedPairFile(ExtractFilePath(UkrFile)+'пара-en.lisp'),
    'англійську назву прийнято за повну укр');
  Require(not RunPinnedPairFile(ExtractFilePath(UkrFile)+'пара-D12.lisp'),
    'непідтверджений D12+ літерал прийнято');
  Require(not RunPinnedPairFile(ExtractFilePath(UkrFile)+'пара-UTF8.lisp'),
    'некоректний UTF-8 у фізичній парі прийнято');
  Require(not RunPinnedPairFile(ChangeFileExt(UkrFile,'.sens')),
    'фізичний файл не можна прийняти як людську .lisp пару');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer=''),
    'негативи пари залишили фізичний snapshot');
  Require(RunPinnedPairFile(UkrFile),
    'пара укр/.sens не відновилась після негативів');
  Require((FGrid.RowCount=3) and (FGrid.Cells[2,2]='W1:1'),
    'відновлена пара показала застарілі біти');
  WriteLn('LCL-УКР-ПАРА-ГАРАЗД .lisp+.sens=побайтово',
    ' канонічний=T5M D1=0/1',
    ' розбіжна/пошкоджена/відсутня=відхилено',
    ' пізня=форма2 en/D12+/UTF8=відхилено',
    ' фізичний-оракул=збіг відновлення=так');

  Require(not RunUkrPhysicalBytes('ні'+#10+'(як-є так ні)'),
    'пізню помилку укр програми виконано');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer='') and
    (Pos('форма=2 слово=',FStatus.Caption)>0),
    'пізня укр-помилка не очищує фізичний результат або адресу');
  Require(not RunUkrPhysicalBytes('car'), 'en-голову прийнято як укр');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer=''),
    'відхилена англійська назва залишила старі байти');
  Require(not RunUkrPhysicalBytes('123'), 'D12+ вгадано з тексту');
  Require(not RunUkrPhysicalBytes(#$C0#$AF),
    'некоректний UTF-8 укр-проєкції не відхилено');
  Require(not RunUkrPhysicalFile(D1File),
    'фізичний .sens помилково прийнято як укр .lisp');
  Require(not RunUkrPhysicalFile('відсутній-укр.lisp'),
    'відсутній файл укр помилково прийнято');
  Require((FGrid.RowCount=2) and (FLastPhysicalAnswer=''),
    'негативи укр залишили застарілу фізичну відповідь');
  Require(RunUkrPhysicalBytes('так'), 'повна укр не відновилася');
  Require((FGrid.RowCount=2) and (FGrid.Cells[2,1]='W1:1'),
    'повторне укр виконання повернуло застарілу відповідь');
  WriteLn('LCL-УКР-ФІЗИЧНО-ГАРАЗД укр=повна pinned=T5M', 
    ' редактор=3-форми файл=2-форми D1=точний',
    ' пізня-відмова=форма2 en/D12+/UTF8=відхилено',
    ' відновлення=так коротка-ук-сесія=незмінна');

  Require(RunPhysicalFile(D1File),'фізичний D3 executor не відновився');
  Require(FGrid.Cells[2,1]='W1:1',
    'повторний канонічний D1 не виконався');
  RunBytes(UkrainianBytes('так'));
  Require((FGrid.RowCount=2) and (FGrid.Cells[0,1]='10') and
    (FGrid.Cells[2,1]='1') and (FLastPhysicalAnswer=''),
    'двійковий режим змінив попередній стан української сесії');
  WriteLn('LCL-ПАКЕТ-D3-ГАРАЗД форми=4 D1=відокремлено',
    ' канонічний=T5M пізня-відмова=форма2:слово2',
    ' LCL=справжній Core4=ні D12+=ні');
  WriteLn('LCL-ФІЗИЧНЕ-D3-ГАРАЗД T5M=канонічний',
    ' D1=1 цитата=4-слова D4=відхилено',
    ' багато-коренів=відхилено пізня-помилка=очищено',
    ' текстова-сесія=форма-10 D12+=ні Core4=ні');

  WriteLn('LCL-ВИКОНАННЯ-ГАРАЗД форми=10 двійкові=так ',
    'LCL-кнопка=натиснута файл=виконаний помилки=відхилені ',
    'старі-клітинки=очищено повний-REPL=ні Core4=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title := 'SENS — двійкове виконання, проєкція ук';
    Application.CreateForm(TVykonanniaForm, Window);
    if (ParamCount>=1) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>10 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SmokeTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9),
        ParamStr(10));
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
