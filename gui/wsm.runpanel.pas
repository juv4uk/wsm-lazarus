{ Окремий GUI-клієнт уже злитого двійкового виконавця.
  Віджети не створюють другого мовного закону або текстового парсера. }
unit wsm.runpanel;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Grids,
  wsm.execfault, wsm.core4wireclient;
type
  TSensRunForm = class(TForm)
  private
    FFileName: TLabel;
    FStatus: TLabel;
    FOutput: TMemo;
    FCoordinates: TStringGrid; { фізичні адреси, не координати мови }
    FOpen: TButton;
    FChannelOpen: TButton;
    FChannelClient: TCore4WireClient; { власник — GUI, тільки host-transport }
    FChannelPID: Int64;
    FChannelLastPhysical: RawByteString; { фізичний T5M, не проєкція }
    FDialog: TOpenDialog;
    procedure OpenClick(Sender: TObject);
    procedure ChannelClick(Sender: TObject);
    function ReadChannelSource(const Path:String):RawByteString;
    procedure Reject(const Reason: String);
    procedure ClearCoordinates;
    procedure ShowFault(E: ELocatedExecutionFault);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ConnectChannel(const Root, Executable:String);
    function ExecuteChannelFile(const Path:String):Boolean;
    procedure SmokeTestChannel(const Root,Executable,GoodFile,ExpectedFile,
      LateBadFile,D12File,MultiFile,BrokenFile:String);
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
  Bar.Height := 112;
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
  FChannelClient := nil;
  FChannelPID := -1;
  FChannelLastPhysical := '';
  FChannelOpen := TButton.Create(Self);
  FChannelOpen.Parent := Bar;
  FChannelOpen.SetBounds(14,72,310,28);
  FChannelOpen.Caption := 'Виконати через постійний D3-канал';
  FChannelOpen.Enabled := False;
  FChannelOpen.OnClick := @ChannelClick;
  FFileName := TLabel.Create(Self);
  FFileName.Parent := Bar;
  FFileName.SetBounds(334,71,446,27);
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

{ Фізичний дитячий PID належить одному GUI об'єкту. Жодна форма
  не набуває persistent SENS bindings — збережений тільки transport. }
destructor TSensRunForm.Destroy;
begin
  FreeAndNil(FChannelClient);
  inherited Destroy;
end;

procedure TSensRunForm.ConnectChannel(const Root,Executable:String);
begin
  FChannelOpen.Enabled := False;
  FChannelLastPhysical := '';
  FOutput.Clear;
  ClearCoordinates;
  FreeAndNil(FChannelClient);
  FChannelPID := -1;
  FChannelClient := TCore4WireClient.Create(Executable,Root,False);
  FChannelPID := FChannelClient.ProcessID;
  if FChannelPID<=0 then begin
    FreeAndNil(FChannelClient);
    raise Exception.Create('дочірній D3-канал не запущено');
  end;
  FChannelOpen.Enabled := True;
  FStatus.Caption := 'Постійний фізичний D3-канал PID='+
    IntToStr(FChannelPID)+'; лише одиничні результати, не REPL.';
end;

{ Path: суто шлях ОС; Result — новий bounded canonical T5M buffer.
  TFileStream живе тільки всередині функції. Ні укр, ні D7, ні
  інші проєкції не використовуються для семантичного dispatch. }
function TSensRunForm.ReadChannelSource(const Path:String):RawByteString;
var Input:TFileStream; Words:TExactWords;
begin
  Result := '';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise Exception.Create('канал приймає тільки фізичний файл .sens');
  Input := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Input.Size<1) or (Input.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('порожній або завеликий фізичний файл');
    SetLength(Result,SizeInt(Input.Size));
    Input.ReadBuffer(Result[1],Length(Result));
  finally Input.Free end;
  DecodeT5M(Result,Words);
  if (Length(Words)=0) or (EncodeT5M(Words)<>Result) then
    raise Exception.Create('неканонічний фізичний T5M');
end;

{ Один запит проходить реальний senspotikd3 --канал в тому самому PID.
  TCore4WireClient позичаємо тільки для існуючого механічного протоколу
  (u32le + T5M, status + u32le + bytes), НЕ для семантики Core4.
  При відмові знищуємо весь попередній GUI результат. }
function TSensRunForm.ExecuteChannelFile(const Path:String):Boolean;
var Request,Answer:RawByteString; Words:TExactWords;
begin
  Result:=False;
  FOutput.Clear;
  ClearCoordinates;
  FChannelLastPhysical:='';
  FFileName.Caption:='Файл: '+ExtractFileName(Path);
  try
    if FChannelClient=nil then
      raise Exception.Create('постійний D3-канал не підключено');
    Request:=ReadChannelSource(Path);
    Answer:=FChannelClient.Execute(Request);
    DecodeT5M(Answer,Words);
    if (Length(Words)<>1) or (EncodeT5M(Words)<>Answer) then
      raise Exception.Create('для цього режиму очікується один exact результат');
    FChannelLastPhysical:=Answer;
    FOutput.Lines.Text:='W'+IntToStr(Length(Words[0]))+':'+String(Words[0]);
    FStatus.Caption:='Двійковий результат фізичного D3, PID='+
      IntToStr(FChannelClient.ProcessID)+
      '; Wn — ширина, не доказ домену Dn. REPL не реалізовано.';
    Result:=True;
  except on E:Exception do begin
    FChannelLastPhysical:='';
    Reject('постійний D3-канал: '+E.Message);
  end end;
end;

procedure TSensRunForm.ChannelClick(Sender:TObject);
begin
  if FDialog.Execute then ExecuteChannelFile(FDialog.FileName);
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
  FChannelLastPhysical:='';
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
  FChannelLastPhysical:='';
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
{ Перевіряємо справжню кнопку, той самий дочірній PID, фізичний
  байтовий oracle G3.17, remote відмови та відсутність stale-result. }
procedure TSensRunForm.SmokeTestChannel(const Root,Executable,GoodFile,
  ExpectedFile,LateBadFile,D12File,MultiFile,BrokenFile:String);
var Expected,Again:RawByteString; W:TExactWords;
  procedure Ensure(OK:Boolean;const Why:String);
  begin
    if not OK then raise Exception.Create('LCL-D3-КАНАЛ: '+Why);
  end;
  procedure EmptyAfterFailure(const Why:String);
  begin
    Ensure((FChannelLastPhysical='') and (FOutput.Lines.Text='') and
      (FCoordinates.Cells[1,1]='') and
      (FCoordinates.Cells[1,2]='') and
      (FCoordinates.Cells[1,3]=''),Why+': залишився старий результат');
    Ensure(FChannelClient.ProcessID=FChannelPID,
      Why+': дочірній PID змінився');
  end;
begin
  Ensure(Assigned(FChannelOpen.OnClick) and
    (FChannelOpen.Caption<>'') and (FChannelClient=nil),
    'немає справжньої кнопки або стан початково забруднений');
  ConnectChannel(Root,Executable);
  Ensure(FChannelOpen.Enabled and (FChannelPID>0),
    'не запущено реальний канал');
  Expected:=ReadChannelSource(ExpectedFile);
  DecodeT5M(Expected,W);
  Ensure(Length(W)=1,'незалежний очікуваний T5M не є одним словом');
  Ensure(ExecuteChannelFile(GoodFile),'перша фізична D3 форма не виконалась');
  Ensure((FChannelLastPhysical=Expected) and
    (Trim(FOutput.Lines.Text)='W'+IntToStr(Length(W[0]))+':'+String(W[0])),
    'відповідь не збігається з незалежним G3.17 T5M oracle');
  Again:=FChannelLastPhysical;
  Ensure(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Again) and
    (FChannelClient.ProcessID=FChannelPID),
    'повторний фізичний запит у тому самому PID');
  Ensure(not ExecuteChannelFile(LateBadFile),'пізня D3 помилка прийнята');
  EmptyAfterFailure('пізня remote відмова');
  Ensure(not ExecuteChannelFile(D12File),'D12+ помилково виконано як D3');
  EmptyAfterFailure('D12+');
  Ensure(not ExecuteChannelFile(MultiFile),
    'багатослівна відповідь пройшла одноформовий host-режим');
  EmptyAfterFailure('багато відповідей');
  Ensure(not ExecuteChannelFile(BrokenFile),'пошкоджений T5M прийнято');
  EmptyAfterFailure('невалідний T5M');
  Ensure(not ExecuteChannelFile(GoodFile+'.lisp'),
    'текстова проєкція помилково прийнята як фізична');
  EmptyAfterFailure('неправильне розширення');
  Ensure(not ExecuteChannelFile('відсутній-D3-файл.sens'),
    'відсутній файл помилково виконано');
  EmptyAfterFailure('відсутній файл');
  Ensure(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Expected) and
    (FChannelClient.ProcessID=FChannelPID),
    'відновлення після всіх відмов без зміни PID');
  Ensure((FCoordinates.Cells[1,1]='') and
    (FCoordinates.Cells[1,2]='') and (FCoordinates.Cells[1,3]=''),
    'remote успіх залишив фізичні адреси старого локального режиму');
  Show;
  Repaint;
  Application.ProcessMessages;
  WriteLn('LCL-Д3-ПОСТІЙНИЙ-КАНАЛ-ГАРАЗД ', 
    'Lazarus=GTK2 PID=незмінний T5M=побайтово ', 
    'пізня-відмова=очищено D12+=відхилено пакет=відхилено ', 
    'лісп=відхилено несправний-T5M=відхилено ',
    'відновлення=так REPL=ні Core4=не-виконується');
end;

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
  CheckSpan('6','16','17','3','4');
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
