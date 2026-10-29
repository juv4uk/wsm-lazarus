{ G6.71 — Lazarus/LCL візуалізує тільки вже перевірений HOST-звіт
  компіляторного ELF64 стенда. Жодної інтерпретації .sens/.lisp,
  D7/D12+, власних законів або обчислення джоулів. }
program sens_elf_chas_ogliad;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls,
  Dialogs, Grids, ExtCtrls, Graphics, fpjson, jsonparser, Math;

const
  Pin='1f1bf676eeac605e065035d9dd2adaae807f1788';
  Schema='sens-elf-c-rust-fpc-coldstart/1';
  Cases:array[0..3] of String=('тотожні-00','тотожні-01',
    'тотожні-10','тотожні-11');
  Engines:array[0..3] of String=('sens-elf','c-gcc','rust','free-pascal');
type
  TRow=record
    SourceName,EngineName:String;
    MedianMs,P95Ms:Double;
  end;
  TRows=array of TRow;
  TSeen=array[0..15,1..120] of Boolean;

  TWindow=class(TForm)
  private
    FPath:TEdit;
    FGrid:TStringGrid;
    FGraph:TPaintBox;
    FStatus:TLabel;
    FDialog:TOpenDialog;
    FRows:TRows;
    procedure ClearView;
    procedure PathChanged(Sender:TObject);
    procedure OpenClick(Sender:TObject);
    procedure PaintGraph(Sender:TObject);
    function ReadReport(const Path:String):TRows;
    function OpenReport(const Path:String):Boolean;
    procedure Check(Condition:Boolean;const Detail:String);
  public
    constructor Create(AOwner:TComponent);override;
    procedure SelfCheck(const Good,BadEnergy,BadSchema,BadMatrix:String);
  end;

var Window:TWindow;

procedure Need(Condition:Boolean;const Detail:String);
begin
  if not Condition then raise Exception.Create(Detail);
end;

function Item(const Obj:TJSONObject;const Key:String):TJSONData;
begin
  Result:=Obj.Find(Key);
  Need(Result<>nil,'немає поля '+Key);
end;

function ObjectItem(const Obj:TJSONObject;const Key:String):TJSONObject;
var Value:TJSONData;
begin
  Value:=Item(Obj,Key);
  Need(Value.JSONType=jtObject,'поле не є об’єктом: '+Key);
  Result:=TJSONObject(Value);
end;

function NumberItem(const Obj:TJSONObject;const Key:String):Double;
var Value:TJSONData;
begin
  Value:=Item(Obj,Key);
  Need(Value.JSONType=jtNumber,'поле не є числом: '+Key);
  Result:=Value.AsFloat;
  Need((not IsNan(Result)) and (not IsInfinite(Result)) and
    (Result>=0),'непридатне число: '+Key);
end;

function IndexOf(const S:String;const IsEngine:Boolean):Integer;
var I:Integer;
begin
  Result:=-1;
  for I:=0 to 3 do
    if IsEngine then begin
      if Engines[I]=S then Exit(I);
    end else if Cases[I]=S then Exit(I);
end;

constructor TWindow.Create(AOwner:TComponent);
var L:TLabel; B:TButton; I:Integer;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — час виконання нативних ELF64';
  Width:=1130; Height:=770; Position:=poScreenCenter;
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(12,9,1100,44);
  L.Caption:='Візуалізація вже отриманого cold-start звіту; це НЕ вимір'+
    ' продуктивності компіляції чи джоулів.'+LineEnding+
    'Результати різних ABI/runtime не становлять рейтингу мов.';
  FPath:=TEdit.Create(Self); FPath.Parent:=Self;
  FPath.SetBounds(12,65,900,30);
  B:=TButton.Create(Self);B.Parent:=Self;
  B.SetBounds(925,65,186,30);B.Caption:='Відкрити звіт JSON';
  B.OnClick:=@OpenClick;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='JSON звіти (*.json)|*.json';
  FDialog.Options:=FDialog.Options+[ofFileMustExist];
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(12,105,1099,44);
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;
  FGrid.SetBounds(12,151,1099,365);
  FGrid.FixedCols:=0;FGrid.FixedRows:=1;
  FGrid.ColCount:=4;FGrid.RowCount:=2;
  FGrid.Options:=FGrid.Options-[goEditing];
  FGrid.ColWidths[0]:=240;FGrid.ColWidths[1]:=270;
  FGrid.ColWidths[2]:=265;FGrid.ColWidths[3]:=275;
  FGrid.Cells[0,0]:='Фізична форма D3:101';
  FGrid.Cells[1,0]:='Виконавець ELF';
  FGrid.Cells[2,0]:='Медіана запуску (мс)';
  FGrid.Cells[3,0]:='p95 запуску (мс)';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(12,527,1080,25);
  L.Caption:='Відносна медіана всередині цього звіту; не інтерпретувати як енергію.';
  FGraph:=TPaintBox.Create(Self);FGraph.Parent:=Self;
  FGraph.SetBounds(12,557,1099,180);
  FGraph.OnPaint:=@PaintGraph;
  ClearView;
  FPath.OnChange:=@PathChanged;
  for I:=1 to 1 do FGrid.Rows[I].Clear;
end;

{ FRows — керований FPC-масив host метрик; TForm володіє віджетами.
  Зміна шляху обнуляє старі значення ДО нового читання; GUI не утримує
  вказівників на TJSONData після звільнення дерева. }
procedure TWindow.ClearView;
var I:Integer;
begin
  SetLength(FRows,0);
  FGrid.RowCount:=2;
  for I:=0 to FGrid.ColCount-1 do FGrid.Cells[I,1]:='';
  FStatus.Caption:='Немає перевіреного звіту. ENERGY_NOT_MEASURED.';
  FGraph.Invalidate;
end;

procedure TWindow.PathChanged(Sender:TObject);
begin ClearView; end;

{ Bounded читання до 4 MiB та парсинг в окреме тимчасове JSON-дерево;
  один відхилений запис скидає ВСЮ таблицю, а не лише рядок. }
function TWindow.ReadReport(const Path:String):TRows;
var Stream:TFileStream; Bytes:RawByteString; Root:TJSONData;
  Doc,Stats,Files,Method,Entry,Run:TJSONObject;
  Samples:TJSONArray;
  Seen:TSeen;
  I,J,K,Count,CaseNo,EngineNo,BlockNo:Integer;
  Key:String; Median,P95,Minimum,Maximum:Double;
begin
  SetLength(Result,0);
  Need(LowerCase(ExtractFileExt(Path))='.json','потрібен host JSON');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Stream.Size>0) and (Stream.Size<=4*1024*1024),
      'файл порожній або завеликий');
    SetLength(Bytes,SizeInt(Stream.Size));
    Stream.ReadBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free; end;
  Root:=GetJSON(String(Bytes),True);
  try
    Need(Root.JSONType=jtObject,'корінь звіту не JSON-об’єкт');
    Doc:=TJSONObject(Root);
    Need(Item(Doc,'схема').AsString=Schema,'невідома схема звіту');
    Need(Item(Doc,'pinned_SENS_SHA').AsString=Pin,
      'не той pinned SENS');
    Need(Item(Doc,'енергія').AsString='ENERGY_NOT_MEASURED',
      'цей звіт не має права заявляти джоулі');
    Method:=ObjectItem(Doc,'метод');
    Count:=Round(NumberItem(Method,'повторів'));
    Need((Count>=30) and (Count<=120) and
      (NumberItem(Method,'повторів')=Count),
      'некоректна кількість повторів');
    Stats:=ObjectItem(Doc,'підсумки');
    Files:=ObjectItem(Doc,'виконувані');
    Need((Stats.Count=16) and (Files.Count=16),
      'матриця повинна містити рівно 16 машин');
    SetLength(Result,16);
    K:=0;
    for I:=0 to 3 do for J:=0 to 3 do begin
      Key:=Cases[I]+'/'+Engines[J];
      Entry:=ObjectItem(Stats,Key);
      Need(Round(NumberItem(Entry,'повторів'))=Count,
        'різна кількість проб у '+Key);
      Median:=NumberItem(Entry,'медіана_мс');
      P95:=NumberItem(Entry,'р95_мс');
      Minimum:=NumberItem(Entry,'мін_мс');
      Maximum:=NumberItem(Entry,'макс_мс');
      Need((Minimum<=Median) and (Median<=P95) and
        (P95<=Maximum) and (Maximum>0),
        'неправильний порядок статистик '+Key);
      Entry:=ObjectItem(Files,Key);
      Need((Length(Item(Entry,'sha256').AsString)=64) and
        (NumberItem(Entry,'ELF_байтів')>120),
        'неповний фізичний паспорт ELF '+Key);
      Result[K].SourceName:=Cases[I];
      Result[K].EngineName:=Engines[J];
      Result[K].MedianMs:=Median;
      Result[K].P95Ms:=P95;
      Inc(K);
    end;
    Need(Item(Doc,'сирі_виміри').JSONType=jtArray,
      'сирі проби відсутні');
    Samples:=TJSONArray(Item(Doc,'сирі_виміри'));
    Need(Samples.Count=16*Count,'втрачено сирі виміри');
    FillChar(Seen,SizeOf(Seen),0);
    for K:=0 to Samples.Count-1 do begin
      Need(Samples.Items[K].JSONType=jtObject,'неправильна проба');
      Run:=TJSONObject(Samples.Items[K]);
      CaseNo:=IndexOf(Item(Run,'випадок').AsString,False);
      EngineNo:=IndexOf(Item(Run,'виконавець').AsString,True);
      BlockNo:=Round(NumberItem(Run,'блок'));
      Need((CaseNo>=0) and (EngineNo>=0) and
        (BlockNo>=1) and (BlockNo<=Count) and
        (NumberItem(Run,'блок')=BlockNo),
        'проба з невідомим доменом, машиною чи блоком');
      Need(NumberItem(Run,'наносекунд')>0,
        'неприпустима тривалість');
      I:=CaseNo*4+EngineNo;
      Need(not Seen[I,BlockNo],'дублікат машинного виміру');
      Seen[I,BlockNo]:=True;
    end;
  finally Root.Free; end;
end;

function TWindow.OpenReport(const Path:String):Boolean;
var Candidate:TRows;I:Integer;
begin
  Result:=False;
  FPath.Text:=Path;
  ClearView;
  try
    Candidate:=ReadReport(Path);
    FRows:=Candidate;
    FGrid.RowCount:=17;
    for I:=0 to High(FRows) do begin
      FGrid.Cells[0,I+1]:=FRows[I].SourceName;
      FGrid.Cells[1,I+1]:=FRows[I].EngineName;
      FGrid.Cells[2,I+1]:=FormatFloat('0.000000',FRows[I].MedianMs);
      FGrid.Cells[3,I+1]:=FormatFloat('0.000000',FRows[I].P95Ms);
    end;
    FStatus.Caption:='16 ELF; 4 фізичні D3 форми; pinned Contract 12.0. '+
      'ENERGY_NOT_MEASURED. Це НЕ загальний рейтинг мов.';
    FGraph.Invalidate;
    Result:=True;
  except
    on E:Exception do begin
      ClearView;
      FStatus.Caption:='ВІДМОВА: '+E.Message+
        '. Попередні значення очищено. ENERGY_NOT_MEASURED.';
    end;
  end;
end;

procedure TWindow.OpenClick(Sender:TObject);
begin
  if FDialog.Execute then OpenReport(FDialog.FileName);
end;

procedure TWindow.PaintGraph(Sender:TObject);
var I,Width,Y:Integer; MaxV:Double;
begin
  FGraph.Canvas.Brush.Color:=clWhite;
  FGraph.Canvas.FillRect(FGraph.ClientRect);
  if Length(FRows)<>16 then Exit;
  MaxV:=0;
  for I:=0 to High(FRows) do
    if FRows[I].MedianMs>MaxV then MaxV:=FRows[I].MedianMs;
  if MaxV<=0 then Exit;
  for I:=0 to High(FRows) do begin
    Width:=Round((FRows[I].MedianMs/MaxV)*(FGraph.Width-20));
    Y:=I*11+2;
    FGraph.Canvas.Brush.Color:=clTeal;
    FGraph.Canvas.FillRect(Rect(4,Y,4+Width,Y+7));
  end;
end;

procedure TWindow.Check(Condition:Boolean;const Detail:String);
begin Need(Condition,'LCL-тест: '+Detail);end;

procedure TWindow.SelfCheck(const Good,BadEnergy,BadSchema,BadMatrix:String);
begin
  Check(OpenReport(Good),'добрий JSON відхилено');
  Check((Length(FRows)=16) and (FGrid.RowCount=17) and
    (Pos('ENERGY_NOT_MEASURED',FStatus.Caption)>0),
    'таблиця/межа бенчмарку');
  FGraph.Repaint;
  FPath.Text:=BadEnergy;
  Check((Length(FRows)=0) and (FGrid.Cells[2,1]=''),
    'після зміни шляху залишились старі дані');
  Check(not OpenReport(BadEnergy),'вигадані джоулі прийнято');
  Check((Length(FRows)=0) and (Pos('ВІДМОВА',FStatus.Caption)>0),
    'відмова залишила попередній зріз');
  Check(not OpenReport(BadSchema),'невідому схему прийнято');
  Check(not OpenReport(BadMatrix),'дубль вимірювань прийнято');
  Check(OpenReport(Good),'не вдалося відновитись після відмов');
  Check((FGrid.Cells[0,16]='тотожні-11') and
    (FGrid.Cells[1,16]='free-pascal'), 'відновлена матриця неповна');
  WriteLn('ЛКЛ-ELF-ЧАС-ГАРАЗД Lazarus=GTK2 рядків=16 '+
    'енергія=ENERGY_NOT_MEASURED stale=очищено відмови=3');
end;

begin
  Application.Initialize;
  Window:=TWindow.Create(nil);
  try
    if (ParamCount=5) and (ParamStr(1)='--самоперевірка') then begin
      try
        Window.Show;
        Application.ProcessMessages;
        Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5));
      except
        on E:Exception do begin
          WriteLn(StdErr,'ЛКЛ-ELF-ЧАС-БЛОК: ',E.Message);
          Halt(1);
        end;
      end;
    end else Application.Run;
  finally Window.Free;end;
end.
{ Питання: 1) Чому JSON не є SENS-оракулом? 2) Чому потрібно всі 16 пар?
  3) Чому очищуємо таблицю до відкриття? 4) Хто звільняє JSON-дерево?
  5) Чому cold-start мілісекунди не конвертуємо у джоулі? }