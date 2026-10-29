{ G5.32 — справжній Lazarus клієнт ПОСТІЙНОГО фізичного Core4-каналу.
  FPC LCL лише малює pinned D7 і приймає готові бінарні відповіді.
  Семантика живе в pinned SENS, TCore4Runtime і дочірньому каналі. }
program core4_d7_kanal;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids,
  wsm.core4runtime, wsm.core4wireclient, wsm.d7text, wsm.t5m;

type
  TChannelWindow=class(TForm)
  private
    FClient:TCore4WireClient;
    FBatchClient:TCore4WireClient; { окремий довгоживучий --канал-пакет }
    FKeys:array[0..2] of RawByteString;
    FNames:array[0..2] of RawByteString;
    FMap:TD7Map;
    FSelect:TComboBox;
    FSend,FBatchSend:TButton;
    FBatchChoices:array[0..3] of TCheckBox;
    FDefinitions,FHistory,FBatchResults:TStringGrid;
    FStatus,FAnswer,FBatchNote:TLabel;
    FBatchPhysical:RawByteString;
    FBatchWords:TExactWords;
    FBatchPID:Int64;
    FPhysicalAnswer:RawByteString;
    FAnswerBits:RawByteString;
    FHistoryCount:SizeInt;
    FInitialPID:Int64;
    function ProjectPinnedName(const Bits:RawByteString):RawByteString;
    procedure ClearAnswer;
    procedure AppendResult(const Operation:RawByteString;const W:RawByteString);
    function ExecuteFrame(const Physical:RawByteString;
      const Operation:RawByteString):Boolean;
    function ExecuteSelection:Boolean;
    function PhysicalForm(Index:SizeInt):RawByteString;
    function JoinPhysicalForms(const Forms:array of RawByteString):RawByteString;
    procedure ClearBatch;
    procedure BatchChoiceClick(Sender:TObject);
    function ExecuteBatchPhysical(const Physical:RawByteString; Expected:SizeInt):Boolean;
    function ExecuteSelectedBatch:Boolean;
    procedure BatchClick(Sender:TObject);
    procedure SendClick(Sender:TObject);
    procedure Need(Condition:Boolean;const Why:String);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure Connect(const Root,BinaryPath:String);
    procedure SelfTest(const Root,BinaryPath:String);
  end;

var Window:TChannelWindow;

constructor TChannelWindow.Create(AOwner:TComponent);
var Note:TLabel;I:SizeInt;
begin
  inherited CreateNew(AOwner,1);
  Width:=1050; Height:=950; Position:=poScreenCenter;
  Caption:='SENS — постійний фізичний D7/Core4 канал';
  FClient:=nil;FBatchClient:=nil;FHistoryCount:=0;
  FInitialPID:=-1;FBatchPID:=-1;
  Note:=TLabel.Create(Self);Note.Parent:=Self;
  Note.SetBounds(18,12,980,24);
  Note.Caption:='Точні D7:7-бітні ключі з pinned Core4. Українські назви — тільки проєкції.';
  FDefinitions:=TStringGrid.Create(Self);
  FDefinitions.Parent:=Self;FDefinitions.SetBounds(18,45,1010,190);
  FDefinitions.ColCount:=3;FDefinitions.FixedCols:=0;
  FDefinitions.RowCount:=4;FDefinitions.FixedRows:=1;
  FDefinitions.ColWidths[0]:=75;
  FDefinitions.ColWidths[1]:=210;
  FDefinitions.ColWidths[2]:=685;
  FDefinitions.Cells[0,0]:='№';
  FDefinitions.Cells[1,0]:='Pinned укр-проєкція D7';
  FDefinitions.Cells[2,0]:='Повна двійкова D7-ідентичність';
  FSelect:=TComboBox.Create(Self);FSelect.Parent:=Self;
  FSelect.SetBounds(18,251,750,34);FSelect.Style:=csDropDownList;
  FSelect.Enabled:=False;
  FSend:=TButton.Create(Self);FSend.Parent:=Self;
  FSend.SetBounds(782,251,245,34);
  FSend.Caption:='Виконати у тому самому процесі';
  FSend.OnClick:=@SendClick;FSend.Enabled:=False;
  FAnswer:=TLabel.Create(Self);FAnswer.Parent:=Self;
  FAnswer.SetBounds(18,305,1008,50);
  FAnswer.AutoSize:=False;FAnswer.WordWrap:=True;
  FHistory:=TStringGrid.Create(Self);
  FHistory.Parent:=Self;FHistory.SetBounds(18,368,1010,235);
  FHistory.ColCount:=4;FHistory.FixedCols:=0;
  FHistory.RowCount:=13;FHistory.FixedRows:=1;
  FHistory.ColWidths[0]:=70;
  FHistory.ColWidths[1]:=290;
  FHistory.ColWidths[2]:=105;
  FHistory.ColWidths[3]:=525;
  FHistory.Cells[0,0]:='№';
  FHistory.Cells[1,0]:='Фізично виконано';
  FHistory.Cells[2,0]:='Wn (не Dn)';
  FHistory.Cells[3,0]:='Точні біти відповіді';
  Note:=TLabel.Create(Self);Note.Parent:=Self;
  Note.SetBounds(18,610,1008,24);
  Note.Caption:='Один фізичний пакет: оберіть від 1 до 4 реально pinned D7-форм.';
  for I:=0 to 3 do begin
    FBatchChoices[I]:=TCheckBox.Create(Self);
    FBatchChoices[I].Parent:=Self;
    FBatchChoices[I].SetBounds(18+(I mod 2)*508,635+(I div 2)*29,500,26);
    FBatchChoices[I].Caption:='Форма '+IntToStr(I+1);
    FBatchChoices[I].Enabled:=False;
    FBatchChoices[I].OnClick:=@BatchChoiceClick;
  end;
  FBatchSend:=TButton.Create(Self);FBatchSend.Parent:=Self;
  FBatchSend.SetBounds(18,698,1008,35);
  FBatchSend.Caption:='Виконати обраний фізичний пакет у тому самому процесі';
  FBatchSend.OnClick:=@BatchClick;FBatchSend.Enabled:=False;
  FBatchResults:=TStringGrid.Create(Self);FBatchResults.Parent:=Self;
  FBatchResults.SetBounds(18,739,1008,111);
  FBatchResults.FixedCols:=0;FBatchResults.FixedRows:=1;
  FBatchResults.ColCount:=3;FBatchResults.RowCount:=5;
  FBatchResults.ColWidths[0]:=80;
  FBatchResults.ColWidths[1]:=135;
  FBatchResults.ColWidths[2]:=765;
  FBatchResults.Cells[0,0]:='№ у пакеті';
  FBatchResults.Cells[1,0]:='Wn (не Dn)';
  FBatchResults.Cells[2,0]:='Точні фізичні біти результату';
  FBatchNote:=TLabel.Create(Self);FBatchNote.Parent:=Self;
  FBatchNote.SetBounds(18,850,1008,28);
  FBatchNote.AutoSize:=False;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(18,884,1010,38);
  FStatus.AutoSize:=False;FStatus.WordWrap:=True;
  FStatus.Caption:='Немає підключення до дочірнього Core4-каналу';
  ClearAnswer;ClearBatch;
end;

destructor TChannelWindow.Destroy;
begin
  FreeAndNil(FBatchClient);
  FreeAndNil(FClient);
  inherited Destroy;
end;

procedure TChannelWindow.Need(Condition:Boolean;const Why:String);
begin if not Condition then raise Exception.Create('LCL-КАНАЛ-ПОМИЛКА: '+Why) end;

{ Bits: concatenated exact D7 семибітні слова, прочитані з pinned DEFINE.
  Map: позичена pinned D7 таблиця, жоден glyph не дає новий opcode.
  Result: новий managed UTF-8 RawByteString, тільки для DISPLAY, не dispatch. }
function TChannelWindow.ProjectPinnedName(const Bits:RawByteString):RawByteString;
var I,J,Code:SizeInt;Glyph:RawByteString;
begin
  Result:='';
  if (Length(Bits)=0) or (Length(Bits) mod 7<>0) or
     (Length(Bits)>256*7) then
    raise Exception.Create('Ключ DEFINE не має повних D7 слів');
  for I:=0 to Length(Bits) div 7-1 do begin
    Code:=0;
    for J:=1 to 7 do begin
      if not (Bits[I*7+J] in ['0','1']) then
        raise Exception.Create('Небінарний D7-ідентифікатор');
      Code:=Code*2+Ord(Bits[I*7+J])-Ord('0');
    end;
    Glyph:=FMap[Code].Ukr;
    if Glyph='' then
      raise Exception.Create('Ім’я Core4 має непроєктований D7 glyph');
    Result:=Result+Glyph;
  end;
end;

procedure TChannelWindow.ClearAnswer;
begin
  FPhysicalAnswer:='';FAnswerBits:='';
  FAnswer.Caption:='Відповідь ще не обчислено.';
end;

{ Атомарний фізичний snapshot: декодер T5M не визначає сенс,
  і W24 не отримує числову доменну ідентичність від ширини. }
procedure TChannelWindow.AppendResult(const Operation:RawByteString;
  const W:RawByteString);
var N:SizeInt;
begin
  Inc(FHistoryCount);
  if FHistoryCount>12 then FHistoryCount:=1;
  N:=FHistoryCount;
  FHistory.Cells[0,N]:=IntToStr(N);
  FHistory.Cells[1,N]:=String(Operation);
  FHistory.Cells[2,N]:='W'+IntToStr(Length(W));
  FHistory.Cells[3,N]:=String(W);
end;

function TChannelWindow.ExecuteFrame(const Physical:RawByteString;
  const Operation:RawByteString):Boolean;
var Answer:RawByteString;W:TExactWords;
begin
  Result:=False;ClearAnswer;
  try
    if FClient=nil then
      raise Exception.Create('Немає дочірнього процесу');
    Answer:=FClient.Execute(Physical);
    DecodeT5M(Answer,W);
    if (EncodeT5M(W)<>Answer) or (Length(W)<>1) then
      raise Exception.Create('Відповідь не є одним канонічним exact словом');
    FPhysicalAnswer:=Answer;FAnswerBits:=W[0];
    FAnswer.Caption:='Реальний результат W'+IntToStr(Length(W[0]))+
      ':'+String(W[0])+'; Wn — ширина, не доказ Dn';
    FStatus.Caption:='Виконано у дочірньому PID '+IntToStr(FClient.ProcessID)+
      '; pinned D7 ключ без текстового dispatch.';
    AppendResult(Operation,W[0]);
    Result:=True;
  except on E:Exception do begin
    ClearAnswer;
    FStatus.Caption:='Відхилено фізичний запит: '+E.Message;
  end end;
end;

{ Меню — host вибір рівно чотирьох ВЖЕ допущених pinned форм.
  Index: host індекс, НЕ Dn/opcode; результат — нові canonical T5M байти.
  D7 ключі отримані з pinned Core4; текст меню не бере участі у виклику. }
function TChannelWindow.PhysicalForm(Index:SizeInt):RawByteString;
begin
  case Index of
    0: Result:=PhysicalD7Call(FKeys[0],'1');
    1: Result:=PhysicalD7Call(FKeys[0],'0');
    2: Result:=PhysicalD7Name(FKeys[1]);
    3: Result:=PhysicalD7Name(FKeys[2]);
  else raise Exception.Create('Недопущений індекс host-меню D7')
  end;
end;

function TChannelWindow.ExecuteSelection:Boolean;
var Input:RawByteString;
begin
  Result:=False;ClearAnswer;
  try
    if FSelect.ItemIndex<0 then
      raise Exception.Create('Оберіть фізичну форму');
    Input:=PhysicalForm(FSelect.ItemIndex);
    Result:=ExecuteFrame(Input,RawByteString(FSelect.Items[FSelect.ItemIndex]));
  except on E:Exception do begin
    ClearAnswer;FStatus.Caption:='Відхилено дію: '+E.Message;
  end end;
end;

{ Forms: 1..4 повні canonical T5M фізичні D2-форми, позичені тільки
  на час виклику. Result: нові канонічні packed байти T5M без додаткової
  семантики. Всі TExactWords — керовані FPC масиви, їх lifetime локальний. }
function TChannelWindow.JoinPhysicalForms(
  const Forms:array of RawByteString):RawByteString;
var All,One:TExactWords;I,J,N:SizeInt;
begin
  if (Length(Forms)<1) or (Length(Forms)>4) then
    raise Exception.Create('Пакет має містити 1..4 фізичні форми');
  SetLength(All,0);
  for I:=0 to High(Forms) do begin
    DecodeT5M(Forms[I],One);
    if (Length(One)=0) or (EncodeT5M(One)<>Forms[I]) then
      raise Exception.Create('Неприпустима канонічність однієї форми');
    N:=Length(All);
    SetLength(All,N+Length(One));
    for J:=0 to High(One) do All[N+J]:=One[J];
  end;
  Result:=EncodeT5M(All);
end;

{ Snapshot від попередньої заявки ніде не лишається після нової,
  зокрема після пізньої помилки ДРУГОЇ форми. }
procedure TChannelWindow.ClearBatch;
var I,J:SizeInt;
begin
  FBatchPhysical:='';
  SetLength(FBatchWords,0);
  for I:=1 to 4 do for J:=0 to 2 do FBatchResults.Cells[J,I]:='';
  FBatchNote.Caption:='Пакетних відповідей немає.';
end;

procedure TChannelWindow.BatchChoiceClick(Sender:TObject);
begin
  ClearBatch;
  FBatchNote.Caption:='Вибір змінено: попередні фізичні відповіді скасовано.';
end;

{ Physical: один canonical T5M запит, Expected: кількість реально вибраних
  форм, Result:Boolean — статус HOST UI, не D1. При remote failure
  не публікується ні перша відповідь, ні остання — тільки цілісний пакет. }
function TChannelWindow.ExecuteBatchPhysical(
  const Physical:RawByteString;Expected:SizeInt):Boolean;
var Candidate:RawByteString; W:TExactWords;I:SizeInt;
begin
  Result:=False;ClearBatch;
  try
    if FBatchClient=nil then raise Exception.Create('Немає пакетного дочірнього PID');
    if (Expected<1) or (Expected>4) then
      raise Exception.Create('Потрібно вибрати 1..4 форми');
    Candidate:=FBatchClient.Execute(Physical);
    DecodeT5M(Candidate,W);
    if (Length(W)<>Expected) or (EncodeT5M(W)<>Candidate) then
      raise Exception.Create('Число або канонічність фізичних відповідей не збігаються');
    for I:=0 to High(W) do
      if (Length(W[I])<1) or (Length(W[I])>4096) then
        raise Exception.Create('Порожня або надмірна точна відповідь');
    FBatchPhysical:=Candidate;
    FBatchWords:=W;
    for I:=0 to High(W) do begin
      FBatchResults.Cells[0,I+1]:=IntToStr(I+1);
      FBatchResults.Cells[1,I+1]:='W'+IntToStr(Length(W[I]));
      FBatchResults.Cells[2,I+1]:=String(W[I]);
    end;
    FBatchNote.Caption:='Виконано '+IntToStr(Expected)+
      ' фізичні форми одним пакетом, PID='+IntToStr(FBatchClient.ProcessID)+
      '; Wn не встановлює числовий домен.';
    Result:=True;
  except on E:Exception do begin
    ClearBatch;
    FBatchNote.Caption:='Пакет цілком відхилено: '+E.Message;
  end end;
end;

function TChannelWindow.ExecuteSelectedBatch:Boolean;
var Forms:array of RawByteString;I,N:SizeInt;
begin
  Result:=False;
  ClearBatch;
  try
    SetLength(Forms,4);N:=0;
    for I:=0 to 3 do if FBatchChoices[I].Checked then begin
      Forms[N]:=PhysicalForm(I);
      Inc(N);
    end;
    if N=0 then raise Exception.Create('Порожній пакет не допускається');
    SetLength(Forms,N);
    Result:=ExecuteBatchPhysical(JoinPhysicalForms(Forms),N);
  except on E:Exception do begin
    ClearBatch;FBatchNote.Caption:='Пакет цілком відхилено: '+E.Message;
  end end;
end;

procedure TChannelWindow.BatchClick(Sender:TObject);
begin ExecuteSelectedBatch end;

procedure TChannelWindow.SendClick(Sender:TObject);
begin ExecuteSelection end;

procedure TChannelWindow.Connect(const Root,BinaryPath:String);
var Runtime:TCore4Runtime;I,J:SizeInt;
begin
  ClearAnswer;ClearBatch;
  FSelect.Enabled:=False;FSend.Enabled:=False;
  FBatchSend.Enabled:=False;
  for I:=0 to 3 do FBatchChoices[I].Enabled:=False;
  FreeAndNil(FBatchClient);
  FreeAndNil(FClient);
  FBatchPID:=-1;
  for I:=0 to 2 do begin FKeys[I]:='';FNames[I]:='' end;
  try
    { Два власники одного upstream: цей snapshot читає 3 pinned DEFINE
      лише заради точного KEY; реальне виконання — інший процес. }
    LoadPinnedD7Map(Root,FMap);
    Runtime:=TCore4Runtime.Create(Root);
    try
      Need(Runtime.BindingCount=3,
        'Очікується рівно три вже підтримані pinned DEFINE');
      for I:=0 to 2 do begin
        FKeys[I]:=Runtime.BindingIdentifier(I);
        FNames[I]:=ProjectPinnedName(FKeys[I]);
        for J:=0 to I-1 do Need(FKeys[I]<>FKeys[J],
          'Колізія двох повних D7 ідентичностей Core4');
      end;
    finally Runtime.Free end;
    FClient:=TCore4WireClient.Create(BinaryPath,Root,False);
    Need(FClient.ProcessID>0,'Немає справжнього Core4 PID');
    FInitialPID:=FClient.ProcessID;
    FBatchClient:=TCore4WireClient.Create(BinaryPath,Root,True);
    Need((FBatchClient.ProcessID>0) and
      (FBatchClient.ProcessID<>FInitialPID),
      'Потрібен окремий живий пакетний PID');
    FBatchPID:=FBatchClient.ProcessID;
    FSelect.Items.Clear;
    FSelect.Items.Add('Замикання '+String(FNames[0])+': D1:1');
    FSelect.Items.Add('Замикання '+String(FNames[0])+': D1:0');
    FSelect.Items.Add('Глобал '+String(FNames[1]));
    FSelect.Items.Add('Глобал '+String(FNames[2]));
    FSelect.ItemIndex:=0;
    for I:=0 to 2 do begin
      FDefinitions.Cells[0,I+1]:=IntToStr(I+1);
      FDefinitions.Cells[1,I+1]:=String(FNames[I]);
      FDefinitions.Cells[2,I+1]:=String(FKeys[I]);
    end;
    FSelect.Enabled:=True;FSend.Enabled:=True;
    for I:=0 to 3 do begin
      FBatchChoices[I].Caption:=FSelect.Items[I];
      FBatchChoices[I].Checked:=(I<>2);
      FBatchChoices[I].Enabled:=True;
    end;
    FBatchSend.Enabled:=True;
    ClearBatch;
    FStatus.Caption:='Постійний двійковий Core4-канал, PID='+
      IntToStr(FInitialPID)+', три повні pinned D7 ключі. Це не загальний REPL.';
  except on E:Exception do begin
    FreeAndNil(FBatchClient);
    FreeAndNil(FClient);
    FInitialPID:=-1;FBatchPID:=-1;
    FBatchSend.Enabled:=False;
    for I:=0 to 3 do FBatchChoices[I].Enabled:=False;
    ClearAnswer;
    FStatus.Caption:='Не встановлено pinned Core4-канал: '+E.Message;
    raise;
  end end;
end;

procedure TChannelWindow.SelfTest(const Root,BinaryPath:String);
var I,J:SizeInt;ID,TruncatedD7,WrongPacket,ExpectedPacket:RawByteString;
    ExpectedWords:TExactWords;
begin
  Need(Assigned(FSend.OnClick) and (FDefinitions.ColCount=3) and
    (FHistory.ColCount=4) and (FSelect.Style=csDropDownList),
    'Немає реального LCL управління');
  Connect(Root,BinaryPath);
  Need((FInitialPID>0) and (FClient.ProcessID=FInitialPID) and
    (FSelect.Items.Count=4),'Дочірній Core4 процес чи меню неправильне');
  for I:=0 to 2 do begin
    Need((Length(FKeys[I])>=7) and (Length(FKeys[I]) mod 7=0) and
      (FNames[I]<>'') and (FDefinitions.Cells[2,I+1]=String(FKeys[I])),
      'Pinned D7 ключі обрізані або не відображені');
    for J:=0 to I-1 do Need(FKeys[I]<>FKeys[J],
      'D7 колізія повного ключа');
  end;
  FSelect.ItemIndex:=0;
  Need(ExecuteSelection and (FAnswerBits='1'),
    'справжнє Core4 замикання D1:1');
  Need(FPhysicalAnswer=EncodeT5M([RawByteString('1')]),
    'канонічні байти D1:1');
  FSelect.ItemIndex:=1;
  Need(ExecuteSelection and (FAnswerBits='0'),
    'справжнє Core4 замикання D1:0');
  FSelect.ItemIndex:=2;
  Need(ExecuteSelection and
    (FAnswerBits='000000000000000000000000'),
    'перший pinned W24 глобал, не доменний висновок');
  FSelect.ItemIndex:=3;
  Need(ExecuteSelection and
    (FAnswerBits='000000000000000000000001'),
    'другий pinned W24 глобал, не D12+ арифметика');
  Need(FClient.ProcessID=FInitialPID,'дочірній PID змінений');

  ID:=FKeys[0];
  if ID[1]='0' then ID[1]:='1' else ID[1]:='0';
  for I:=0 to 2 do Need(ID<>FKeys[I],
    'Негативний D7 ключ випадково дорівнює pinned ключу');
  Need(not ExecuteFrame(PhysicalD7Call(ID,'1'),'незнайоме pinned ім’я'),
    'Дозволено виклик невідомого D7 ключа');
  Need((FPhysicalAnswer='') and (FAnswerBits=''),
    'Старий фізичний результат після remote помилки');
  Need(FClient.ProcessID=FInitialPID,'remote помилка перезапустила Core4');
  Need(not ExecuteFrame(Chr(243),'зіпсований T5M'),
    'Дозволено некоректний фізичний T5M');
  Need((FPhysicalAnswer='') and (FClient.ProcessID=FInitialPID),
    'Локальна відмова стерла процес або лишила старий результат');
  TruncatedD7:=Copy(FKeys[0],1,Length(FKeys[0])-1);
  try
    PhysicalD7Call(TruncatedD7,'1');
    Need(False,'Неповна D7 координата прийнята');
  except on E:ECore4WireError do begin end end;
  FSelect.ItemIndex:=0;
  Need(ExecuteSelection and (FAnswerBits='1') and
    (FClient.ProcessID=FInitialPID),
    'Відновлення реального Core4 після негативів у тому ж PID');
  { G5.33: пакет 3 із чекбоксів, реальна LCL подія.
    Всі три відповіді друкуються ТІЛЬКИ після успішного remote batch. }
  Need(Assigned(FBatchSend.OnClick) and
    (FBatchResults.RowCount=5) and (FBatchPID>0) and
    (FBatchClient.ProcessID=FBatchPID) and (FBatchPID<>FInitialPID),
    'Немає LCL batch елементів або окремого постійного PID');
  for I:=0 to 3 do Need(Assigned(FBatchChoices[I].OnClick),
    'Відсутня інвалідація попереднього фізичного пакета');
  FBatchChoices[0].Checked:=True;
  FBatchChoices[1].Checked:=True;
  FBatchChoices[2].Checked:=False;
  FBatchChoices[3].Checked:=True;
  FBatchSend.Click;
  Need((Length(FBatchWords)=3) and
    (FBatchWords[0]='1') and (FBatchWords[1]='0') and
    (FBatchWords[2]='000000000000000000000001') and
    (FBatchResults.Cells[2,3]='000000000000000000000001'),
    'Реальні три пакетні відповіді відсутні');
  ExpectedPacket:=JoinPhysicalForms([
    PhysicalForm(0),PhysicalForm(1),PhysicalForm(3)]);
  SetLength(ExpectedWords,3);
  ExpectedWords[0]:='1';ExpectedWords[1]:='0';
  ExpectedWords[2]:='000000000000000000000001';
  Need((FBatchPhysical=EncodeT5M(ExpectedWords)) and
    (Length(ExpectedPacket)>0),
    'Пакет трьох фізичних відповідей втратив T5M канон');

  { Зміна складу пакета має інвалідовувати старий snapshot. }
  FBatchChoices[2].Checked:=True;
  { Lazarus 3.0 TCheckBox не експортує Click; для самотесту
    прямо викликаємо той САМИЙ handler, прив'язаний до OnClick. }
  BatchChoiceClick(FBatchChoices[2]);
  Need((Length(FBatchWords)=0) and (FBatchPhysical='') and
    (FBatchResults.Cells[2,3]=''),
    'Після зміни чекбокса залишилися попередні фізичні біти');
  Need(ExecuteSelectedBatch and (Length(FBatchWords)=4) and
    (FBatchWords[2]='000000000000000000000000') and
    (FBatchWords[3]='000000000000000000000001'),
    'Фізичний batch=4 не виконав глобали');
  for I:=0 to 3 do FBatchChoices[I].Checked:=False;
  Need(not ExecuteSelectedBatch,'Порожній пакет помилково допущений');
  Need((FBatchPhysical='') and (Length(FBatchWords)=0) and
    (FBatchResults.Cells[2,1]=''), 'Порожня відмова лишила результат');

  { Пізня REMOTE-помилка: перша форма дозволена, друга має
    інший повний D7 ключ. Пакет не повинен видати першу відповідь. }
  ID:=FKeys[0];
  if ID[1]='0' then ID[1]:='1' else ID[1]:='0';
  for I:=0 to 2 do Need(ID<>FKeys[I],
    'Пошкоджений D7 ключ збігається із pinned');
  WrongPacket:=JoinPhysicalForms([
    PhysicalForm(0),PhysicalD7Call(ID,'1')]);
  Need(not ExecuteBatchPhysical(WrongPacket,2),
    'Пізній невідомий D7 не відхилений');
  Need((FBatchPhysical='') and (Length(FBatchWords)=0) and
    (FBatchResults.Cells[2,1]=''),
    'Remote-помилка видала частковий фізичний результат');
  Need(FBatchClient.ProcessID=FBatchPID,'Remote-помилка змінила PID');
  Need(not ExecuteBatchPhysical(Chr(243),1),
    'Неканонічний T5M в пакетному каналі допущено');
  Need((FBatchPhysical='') and (FBatchClient.ProcessID=FBatchPID),
    'Локальна помилка лишила packet або перезапустила PID');
  FBatchChoices[0].Checked:=True;
  FBatchChoices[1].Checked:=True;
  FBatchChoices[2].Checked:=False;
  FBatchChoices[3].Checked:=True;
  Need(ExecuteSelectedBatch and
    (FBatchPhysical=EncodeT5M(ExpectedWords)) and
    (FBatchClient.ProcessID=FBatchPID),
    'Постійний batch не відновився після remote/local помилок');
  Window.Show;Application.ProcessMessages;
  WriteLn('LCL-D7-АТОМАРНИЙ-ПАКЕТ-ГАРАЗД ',
    'Lazarus=GTK2 batch=3+4 W1/W24=побайтово ',
    'remote-пізня-відмова=атомарно T5M-пошкодження=відхилено ',
    'порожній=відхилено зміна-вибору=очищення PID=незмінний ',
    'відновлення=так D7=повний REPL=ні');
  WriteLn('LCL-D7-ПОСТІЙНИЙ-КАНАЛ-ГАРАЗД ',
    'Lazarus=GTK2 pinned-DEFINE=3 ukr=проєкція ',
    'D7=повні-ключі W1=точно W24=opaque ',
    'remote=відхилено T5M=відхилено PID=один ',
    'відновлення=так REPL=ні D12+=не-вгадувати');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — постійний D7/Core4';
    Application.CreateForm(TChannelWindow,Window);
    if (ParamCount=3) and (ParamStr(1)='--самоперевірка') then begin
      Window.SelfTest(ParamStr(2),ParamStr(3));
      Window.Free;
    end else if ParamCount=2 then begin
      Window.Connect(ParamStr(1),ParamStr(2));
      Application.Run;
    end else begin
      WriteLn(StdErr,
        'Використання: core4-d7-kanal ROOT ШЛЯХ-ДО-senscore4kanal ',
        'або --самоперевірка ROOT ШЛЯХ');
      Halt(64);
    end;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-КАНАЛ-ПОМИЛКА: ',E.Message);Halt(2);
  end end;
end.
