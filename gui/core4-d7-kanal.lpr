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
    FKeys:array[0..2] of RawByteString;
    FNames:array[0..2] of RawByteString;
    FMap:TD7Map;
    FSelect:TComboBox;
    FSend:TButton;
    FDefinitions,FHistory:TStringGrid;
    FStatus,FAnswer:TLabel;
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
var Note:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Width:=1050; Height:=710; Position:=poScreenCenter;
  Caption:='SENS — постійний фізичний D7/Core4 канал';
  FClient:=nil;FHistoryCount:=0;FInitialPID:=-1;
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
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(18,620,1010,62);
  FStatus.AutoSize:=False;FStatus.WordWrap:=True;
  FStatus.Caption:='Немає підключення до дочірнього Core4-каналу';
  ClearAnswer;
end;

destructor TChannelWindow.Destroy;
begin
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

function TChannelWindow.ExecuteSelection:Boolean;
var Input:RawByteString;
begin
  Result:=False;ClearAnswer;
  try
    if FSelect.ItemIndex<0 then
      raise Exception.Create('Оберіть фізичну форму');
    case FSelect.ItemIndex of
      0: Input:=PhysicalD7Call(FKeys[0],'1');
      1: Input:=PhysicalD7Call(FKeys[0],'0');
      2: Input:=PhysicalD7Name(FKeys[1]);
      3: Input:=PhysicalD7Name(FKeys[2]);
    else raise Exception.Create('Невідома дія host-інтерфейсу')
    end;
    Result:=ExecuteFrame(Input,RawByteString(FSelect.Items[FSelect.ItemIndex]));
  except on E:Exception do begin
    ClearAnswer;FStatus.Caption:='Відхилено дію: '+E.Message;
  end end;
end;

procedure TChannelWindow.SendClick(Sender:TObject);
begin ExecuteSelection end;

procedure TChannelWindow.Connect(const Root,BinaryPath:String);
var Runtime:TCore4Runtime;I,J:SizeInt;
begin
  ClearAnswer;
  FSelect.Enabled:=False;FSend.Enabled:=False;
  FreeAndNil(FClient);
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
    FStatus.Caption:='Постійний двійковий Core4-канал, PID='+
      IntToStr(FInitialPID)+', три повні pinned D7 ключі. Це не загальний REPL.';
  except on E:Exception do begin
    FreeAndNil(FClient);
    FInitialPID:=-1;
    ClearAnswer;
    FStatus.Caption:='Не встановлено pinned Core4-канал: '+E.Message;
    raise;
  end end;
end;

procedure TChannelWindow.SelfTest(const Root,BinaryPath:String);
var I,J:SizeInt;ID,Changed:RawByteString;
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
  Changed:=Copy(FKeys[0],1,Length(FKeys[0])-1);
  try
    PhysicalD7Call(Changed,'1');
    Need(False,'Неповна D7 координата прийнята');
  except on E:ECore4WireError do begin end end;
  FSelect.ItemIndex:=0;
  Need(ExecuteSelection and (FAnswerBits='1') and
    (FClient.ProcessID=FInitialPID),
    'Відновлення реального Core4 після негативів у тому ж PID');
  Window.Show;Application.ProcessMessages;
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
