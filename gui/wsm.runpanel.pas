{ Окремий GUI-клієнт уже злитого двійкового виконавця.
  Віджети не створюють другого мовного закону або текстового парсера. }
unit wsm.runpanel;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs;
type
  TSensRunForm = class(TForm)
  private
    FFileName: TLabel;
    FStatus: TLabel;
    FOutput: TMemo;
    FOpen: TButton;
    FDialog: TOpenDialog;
    procedure OpenClick(Sender: TObject);
    procedure Reject(const Reason: String);
  public
    constructor Create(AOwner: TComponent); override;
    function ExecuteFile(const Path: String): Boolean;
    procedure SmokeTest(const GoodFile, BadFile, BrokenFile: String;
      const Expected: String);
  end;

implementation
uses wsm.binaryexec, wsm.t5m;
const
  PhysicalLimit = MAX_T5M_FILE_BYTES;

constructor TSensRunForm.Create(AOwner: TComponent);
var Bar, Footer: TPanel; Heading: TLabel;
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
  FOutput := TMemo.Create(Self);
  FOutput.Parent := Self;
  FOutput.Align := alClient;
  FOutput.ReadOnly := True;
  FOutput.ScrollBars := ssVertical;
  FOutput.Lines.Text := '';
end;

procedure TSensRunForm.Reject(const Reason: String);
begin
  FOutput.Clear;
  FStatus.Caption := 'Відхилено: ' + Reason;
end;

function TSensRunForm.ExecuteFile(const Path: String): Boolean;
var Input: TFileStream; Physical, Answer: RawByteString;
    Executor: TBinaryExecutor;
begin
  Result := False;
  FOutput.Clear;
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
      Answer := Executor.ExecutePhysical(Physical);
    finally
      Executor.Free;
    end;
    { Результат показуємо тільки після повного успіху фізичного допуску. }
    FOutput.Lines.Text := String(Answer);
    FStatus.Caption := 'Виконано фізичний файл ('+
      IntToStr(Length(Physical))+' байтів). Результат — вид чинного D3-виконавця, не .sens.';
    Result := True;
  except
    on E: EBinaryExecutionError do
      Reject('слово '+IntToStr(E.WordIndex)+': '+E.Message);
    on E: Exception do Reject(E.Message);
  end;
end;

procedure TSensRunForm.OpenClick(Sender: TObject);
begin
  if FDialog.Execute then ExecuteFile(FDialog.FileName);
end;

procedure TSensRunForm.SmokeTest(const GoodFile, BadFile, BrokenFile: String;
  const Expected: String);
  procedure Ensure(Ok: Boolean; const Why: String);
  begin
    if not Ok then raise Exception.Create('самоперевірка LCL: '+Why);
  end;
begin
  Ensure((FOutput <> nil) and (FStatus <> nil) and
    (FOpen <> nil) and Assigned(FOpen.OnClick), 'відсутні реальні віджети');
  Ensure(ExecuteFile(GoodFile),'не виконано чинний фізичний .sens');
  Ensure(Trim(FOutput.Lines.Text)=Expected,
    'GUI не відповідає тому самому нативному CLI');
  Ensure(Pos('Виконано', FStatus.Caption)=1,'немає стану виконання');
  Ensure(not ExecuteFile(BadFile),'невідома двійкова цитата прийнята');
  Ensure((FOutput.Lines.Text='') and
    (Pos('слово 2',FStatus.Caption)>0),'відмова залишила результат або втратила номер слова');
  Ensure(not ExecuteFile(BrokenFile),'пошкоджений T5M прийнято');
  Ensure((FOutput.Lines.Text='') and
    (Pos('слово 0',FStatus.Caption)>0),'пошкоджений байт не очищено');
  Ensure(not ExecuteFile('відсутній-файл.sens'),'відсутній файл прийнято');
  Ensure((FOutput.Lines.Text='') and
    (Pos('Відхилено:',FStatus.Caption)=1),'старий результат після помилки файлу');
  Ensure(not ExecuteFile('документ.lisp'),'текст прийнято як фізичний SENS');
  Ensure((FOutput.Lines.Text='') and
    (Pos('Відхилено:',FStatus.Caption)=1),'старий результат після відмови .lisp');
  Ensure(ExecuteFile(GoodFile),'повторне виконання не відновилося');
  Ensure(Trim(FOutput.Lines.Text)=Expected,'повторне виконання не детерміноване');
  WriteLn('LCL-ДВІЙКОВЕ-ВИКОНАННЯ-ГАРАЗД GTK2=так віджети=створено ',
    'CLI-паритет=фізичний D1/D3=підмножина відмови=очищають ',
    'Core4=НЕ_ВИКОНУЄТЬСЯ REPL=НЕ_ГОТОВИЙ');
end;
end.
