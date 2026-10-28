{ Окремий GUI-клієнт уже злитого двійкового виконавця.
  Віджети не створюють другого мовного закону або текстового парсера. }
unit wsm.runpanel;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Grids,
  wsm.execfault;
type
  TSensRunForm = class(TForm)
  private
    FFileName: TLabel;
    FStatus: TLabel;
    FOutput: TMemo;
    FCoordinates: TStringGrid; { фізичні адреси, не координати мови }
    FOpen: TButton;
    FDialog: TOpenDialog;
    procedure OpenClick(Sender: TObject);
    procedure Reject(const Reason: String);
    procedure ClearCoordinates;
    procedure ShowFault(E: ELocatedExecutionFault);
  public
    constructor Create(AOwner: TComponent); override;
    function ExecuteFile(const Path: String): Boolean;
    procedure SmokeTest(const GoodFile, BadFile, NestedFile,
      EofFile, BrokenFile, Expected: String);
  end;

implementation
uses wsm.binaryexec, wsm.t5m;
const
  PhysicalLimit = MAX_T5M_FILE_BYTES;

constructor TSensRunForm.Create(AOwner: TComponent);
var Bar, Footer, SpanPanel: TPanel; Heading: TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption := 'SENS — двійкове виконання';
  Position := poScreenCenter;
  Width := 810;
  Height := 470;
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 100;
  Bar.BevelOuter := bvNone;
  Heading := TLabel.Create(Self);
  Heading.Parent := Bar;
  Heading.SetBounds(14,8,760,22);
  Heading.Caption := 'Фізичний .sens — первинний; українська лише проєкція';
  FOpen := TButton.Create(Self);
  FOpen.Parent := Bar;
  FOpen.SetBounds(14,36,200,31);
  FOpen.Caption := 'Відкрити й виконати .sens…';
  FOpen.OnClick := @OpenClick;
  FFileName := TLabel.Create(Self);
  FFileName.Parent := Bar;
  FFileName.SetBounds(224,43,570,22);
  FFileName.Caption := 'Файл ще не вибрано';
  FDialog := TOpenDialog.Create(Self);
  FDialog.Filter := 'Фізичні файли SENS|*.sens';
  FDialog.Title := 'Оберіть фізичну програму SENS';
  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 56;
  Footer.BevelOuter := bvNone;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Footer;
  FStatus.SetBounds(14,5,780,44);
  FStatus.AutoSize := False;
  FStatus.WordWrap := True;
  FStatus.Caption := 'Очікується двійковий файл. Виконується тільки підтримана підмножина D1/D3.';
  { Таблиця показує фактичні напіввідкриті фізичні інтервали.
    Віджети належать Self і звільняються разом із TForm. }
  SpanPanel := TPanel.Create(Self);
  SpanPanel.Parent := Self;
  SpanPanel.Align := alBottom;
  SpanPanel.Height := 120;
  SpanPanel.BevelOuter := bvNone;
  FCoordinates := TStringGrid.Create(Self);
  FCoordinates.Parent := SpanPanel;
  FCoordinates.Align := alClient;
  FCoordinates.FixedCols := 0;
  FCoordinates.ColCount := 3;
  FCoordinates.RowCount := 4;
  FCoordinates.FixedRows := 1;
  FCoordinates.ColWidths[0] := 148;
  FCoordinates.ColWidths[1] := 170;
  FCoordinates.ColWidths[2] := 215;
  FCoordinates.Cells[0,0] := 'Фізична адреса';
  FCoordinates.Cells[1,0] := 'Початок';
  FCoordinates.Cells[2,0] := 'Кінець (виключно)';
  FCoordinates.Cells[0,1] := 'Слово (1-based)';
  FCoordinates.Cells[0,2] := 'Трити (0-based)';
  FCoordinates.Cells[0,3] := 'Байти (0-based)';
  ClearCoordinates;
  FOutput := TMemo.Create(Self);
  FOutput.Parent := Self;
  FOutput.Align := alClient;
  FOutput.ReadOnly := True;
  FOutput.ScrollBars := ssVertical;
  FOutput.Lines.Text := '';
end;

procedure TSensRunForm.ClearCoordinates;
var I: Integer;
begin
  for I:=1 to 3 do begin
    FCoordinates.Cells[1,I] := '';
    FCoordinates.Cells[2,I] := '';
  end;
end;

procedure TSensRunForm.Reject(const Reason: String);
begin
  FOutput.Clear;
  ClearCoordinates;
  FStatus.Caption := 'Відхилено: ' + Reason;
end;

procedure TSensRunForm.ShowFault(E: ELocatedExecutionFault);
begin
  Reject(E.Message);
  FCoordinates.Cells[1,1] := IntToStr(E.WordIndex);
  if E.HasPhysicalSpan then begin
    if E.Span.IsEOF then FCoordinates.Cells[2,1] := 'EOF'
    else FCoordinates.Cells[2,1] := 'фізичне слово';
    FCoordinates.Cells[1,2] := IntToStr(E.Span.TritStart);
    FCoordinates.Cells[2,2] := IntToStr(E.Span.TritEnd);
    FCoordinates.Cells[1,3] := IntToStr(E.Span.ByteStart);
    FCoordinates.Cells[2,3] := IntToStr(E.Span.ByteEnd);
    FStatus.Caption := 'Відхилено: слово '+IntToStr(E.WordIndex)+
      ', трити ['+IntToStr(E.Span.TritStart)+','+
      IntToStr(E.Span.TritEnd)+'), байти ['+
      IntToStr(E.Span.ByteStart)+','+IntToStr(E.Span.ByteEnd)+')';
    if E.Span.IsEOF then FStatus.Caption := FStatus.Caption+' EOF';
  end else begin
    FCoordinates.Cells[2,1] := 'адреса невідома';
    FStatus.Caption := 'Відхилено: слово '+IntToStr(E.WordIndex)+
      ', фізична адреса невідома';
  end;
end;

function TSensRunForm.ExecuteFile(const Path: String): Boolean;
var Input: TFileStream; Physical, Answer: RawByteString;
    Executor: TBinaryExecutor;
begin
  Result := False;
  FOutput.Clear;
  ClearCoordinates;
  FStatus.Caption := 'Перевіряємо фізичні байти…';
  FFileName.Caption := 'Файл: ' + ExtractFileName(Path);
  try
    if LowerCase(ExtractFileExt(Path)) <> '.sens' then
      raise Exception.Create('очікується двійковий файл .sens');
    Input := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      if (Input.Size <= 0) or (Input.Size > PhysicalLimit) then
        raise Exception.Create('порожній або завеликий фізичний файл');
      SetLength(Physical,SizeInt(Input.Size));
      Input.ReadBuffer(Physical[1],Length(Physical));
    finally
      Input.Free;
    end;
    { TBinaryExecutor — вже протестований, не пов’язаний із LCL механізм.
      Кожен запуск має окремий обмежений runtime й відпускає його у finally. }
    Executor := TBinaryExecutor.Create('external/sens');
    try
      Answer := ExecuteWithPhysicalLocation(Physical,Executor);
    finally
      Executor.Free;
    end;
    { Результат показуємо тільки після повного успіху фізичного допуску. }
    FOutput.Lines.Text := String(Answer);
    FStatus.Caption := 'Виконано фізичний файл ('+
      IntToStr(Length(Physical))+' байтів). Результат — вид чинного D3-виконавця, не .sens.';
    Result := True;
  except
    on E: ELocatedExecutionFault do ShowFault(E);
    on E: Exception do Reject(E.Message);
  end;
end;

procedure TSensRunForm.OpenClick(Sender: TObject);
begin
  if FDialog.Execute then ExecuteFile(FDialog.FileName);
end;

{ Повна віконна перевірка стану: після успіху й відмов дані
  не залишаються у grid або у виводі від попередньої програми. }
procedure TSensRunForm.SmokeTest(const GoodFile, BadFile, NestedFile,
  EofFile, BrokenFile, Expected: String);
  procedure Ensure(Ok:Boolean; const Why:String);
  begin
    if not Ok then raise Exception.Create('самоперевірка LCL: '+Why);
  end;
  procedure CheckSpan(const Word, TStart, TEnd, BStart, BEnd: String);
  begin
    Ensure((FOutput.Lines.Text='') and
      (FCoordinates.Cells[1,1]=Word) and
      (FCoordinates.Cells[1,2]=TStart) and
      (FCoordinates.Cells[2,2]=TEnd) and
      (FCoordinates.Cells[1,3]=BStart) and
      (FCoordinates.Cells[2,3]=BEnd),
      'помилкова фізична адреса або старий результат');
  end;
begin
  Ensure((FOutput<>nil) and (FCoordinates<>nil) and
    (FStatus<>nil) and (FOpen<>nil) and Assigned(FOpen.OnClick),
    'відсутні справжні графічні віджети');
  Ensure((FCoordinates.ColCount=3) and (FCoordinates.RowCount=4),
    'таблиця координат не створена');
  Ensure(ExecuteFile(GoodFile),'чинний фізичний D1/D3 не виконався');
  Ensure(Trim(FOutput.Lines.Text)=Expected,'розбіжність із нативним CLI');
  Ensure(FCoordinates.Cells[1,1]='','після успіху залишилася стара адреса');
  Ensure(not ExecuteFile(BadFile),'непідтверджена D3 цитата прийнята');
  CheckSpan('2','3','6','0','2');
  Ensure(not ExecuteFile(NestedFile),'вкладена непідтверджена голова прийнята');
  CheckSpan('5','12','15','2','3');
  Ensure(not ExecuteFile(EofFile),'незакритий D2 список прийнято');
  CheckSpan('3','4','4','1','1');
  Ensure(FCoordinates.Cells[2,1]='EOF','втрачено фізичний EOF');
  Ensure(not ExecuteFile(BrokenFile),'пошкоджений T5M прийнято');
  Ensure((FCoordinates.Cells[1,1]='0') and
    (FCoordinates.Cells[2,1]='адреса невідома') and
    (FCoordinates.Cells[1,2]='') and (FCoordinates.Cells[1,3]='') and
    (FOutput.Lines.Text=''),
    'для невалідного T5M вигадано адресу');
  Ensure(not ExecuteFile('відсутній-файл.sens'),'відсутній файл прийнято');
  Ensure((FOutput.Lines.Text='') and (FCoordinates.Cells[1,1]=''),
    'відсутній файл залишив попередній результат/адресу');
  Ensure(not ExecuteFile('документ.lisp'),'текст помилково прийнято як .sens');
  Ensure((FOutput.Lines.Text='') and (FCoordinates.Cells[1,1]=''),
    'нефізичний текст залишив попередній результат/адресу');
  Ensure(ExecuteFile(GoodFile),'повторний нативний запуск не виконався');
  Ensure(Trim(FOutput.Lines.Text)=Expected,
    'повторний запуск не збігся з чинним CLI');
  Ensure((FCoordinates.Cells[1,1]='') and
    (FCoordinates.Cells[1,2]='') and (FCoordinates.Cells[1,3]=''),
    'новий успіх не прибрав стару фізичну адресу');
  WriteLn('LCL-ФІЗИЧНА-ПОМИЛКА-ГАРАЗД GTK2=справжній ',
    'D3=наявний word=точний trit-byte=half-open EOF=явний ',
    'T5M-corrupt=без-адреси після-помилки=чисто CLI-паритет=так ',
    'Core4=НЕ_ВИКОНУЄТЬСЯ REPL=НЕ_ГОТОВИЙ');
end;
end.
