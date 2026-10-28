{ Справжній Lazarus LCL-оглядач фізичних широких T5M слів.
  Числова драбина починається з D12 згідно pinned SENS Contract 12.0,
  але довжина бітів сама по собі НЕ є доменною числовою identity.
  Тільки wsm.widespan визначає транспортні адреси; немає виконання. }
program sens_shyroki;
{$mode objfpc}{$H+}{$codepage utf8}

uses
  Interfaces, Forms, Controls, StdCtrls, Grids, Dialogs, Classes,
  SysUtils, wsm.t5m, wsm.widespan;

const MaxVisibleWide = 256;
type
  TShyrokiWindow = class(TForm)
  private
    FButton: TButton;
    FDialog: TOpenDialog;
    FGrid: TStringGrid;
    FDetail, FTSV: TMemo;
    FStatus: TLabel;
    FCurrentPath: String;
    FWide: TWideWords;
    procedure ResetView;
    procedure OpenClicked(Sender: TObject);
    procedure CellSelected(Sender: TObject; ACol, ARow: Integer;
      var CanSelect: Boolean);
    procedure ShowWord(Row: Integer);
    procedure Demand(Condition: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const Path: String): Boolean;
    procedure SelfCheck(const Good, Shared, Short, Bad, Empty,
      TooMany, TextFile: String);
  end;

var Window: TShyrokiWindow;

constructor TShyrokiWindow.Create(AOwner: TComponent);
var I: Integer;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — точні широкі фізичні слова D12+';
  Width := 1190; Height := 740;
  Position := poScreenCenter;
  FButton := TButton.Create(Self);
  FButton.Parent := Self;
  FButton.SetBounds(12,12,290,36);
  FButton.Caption := 'Відкрити фізичний файл .sens';
  FButton.OnClick := @OpenClicked;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Title := 'Оберіть канонічний двійковий SENS';
  FDialog.Filter := 'Фізичні SENS (*.sens)|*.sens';
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(12,54,1140,35);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.SetBounds(12,95,1150,310);
  FGrid.ColCount := 5;
  FGrid.FixedRows := 1;
  FGrid.RowCount := 2;
  FGrid.ColWidths[0] := 100;
  FGrid.ColWidths[1] := 115;
  FGrid.ColWidths[2] := 500;
  FGrid.ColWidths[3] := 190;
  FGrid.ColWidths[4] := 190;
  FGrid.Cells[0,0] := 'Слово (1-based)';
  FGrid.Cells[1,0] := 'Ширина бітів';
  FGrid.Cells[2,0] := 'Точний двійковий вміст';
  FGrid.Cells[3,0] := 'Трити [від,до)';
  FGrid.Cells[4,0] := 'Байти [від,до)';
  FGrid.OnSelectCell := @CellSelected;
  FDetail := TMemo.Create(Self);
  FDetail.Parent := Self;
  FDetail.SetBounds(12,414,1150,93);
  FDetail.ReadOnly := True;
  FDetail.ScrollBars := ssBoth;
  FTSV := TMemo.Create(Self);
  FTSV.Parent := Self;
  FTSV.SetBounds(12,518,1150,165);
  FTSV.ReadOnly := True;
  FTSV.ScrollBars := ssBoth;
  FTSV.WordWrap := False;
  FCurrentPath := '';
  SetLength(FWide,0);
  ResetView;
  for I := 0 to 4 do
    if FGrid.Cells[I,0] = '' then
      raise Exception.Create('відсутній український заголовок');
end;

procedure TShyrokiWindow.ResetView;
var I:Integer;
begin
  SetLength(FWide,0);
  FGrid.RowCount := 2;
  for I:=0 to 4 do FGrid.Cells[I,1]:='';
  FDetail.Clear;
  FTSV.Clear;
  FStatus.Caption := 'Тільки фізичні слова D12+: виконання/арифметика НЕ доведені.';
end;

procedure TShyrokiWindow.Demand(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('помилка графічної перевірки: '+Why);
end;

procedure TShyrokiWindow.ShowWord(Row:Integer);
var W:TWideWord;
begin
  FDetail.Clear;
  if (Row<1) or (Row>Length(FWide)) then Exit;
  W:=FWide[Row-1];
  FDetail.Lines.Add('Фізичне слово №'+IntToStr(W.Span.WordIndex)+
    '; точна ширина '+IntToStr(W.Width)+' біт; не числовий закон');
  FDetail.Lines.Add('Біти (з усіма провідними нулями): '+String(W.Bits));
  FDetail.Lines.Add('Трити ['+IntToStr(W.Span.TritStart)+','+
    IntToStr(W.Span.TritEnd)+'); байти ['+
    IntToStr(W.Span.ByteStart)+','+IntToStr(W.Span.ByteEnd)+')');
end;

procedure TShyrokiWindow.CellSelected(Sender:TObject;ACol,ARow:Integer;
  var CanSelect:Boolean);
begin
  CanSelect := True;
  ShowWord(ARow);
end;

function TShyrokiWindow.LoadFile(const Path:String):Boolean;
var Stream:TFileStream; Physical, TSV:RawByteString;
    Staged:TWideWords; I:SizeInt; W:TWideWord;
begin
  Result:=False;
  ResetView;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('потрібен канонічний двійковий .sens, не .lisp');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або надмірний фізичний файл');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free; end;
    { Слова/адреси походять тільки з уже фізично перевіреного T5M.
      TSV валідовано ДО зміни віджетів, щоб не показати частковий звіт. }
    CollectWideWords(Physical,Staged);
    if Length(Staged)>MaxVisibleWide then
      raise Exception.Create('графічна межа 256 широких слів');
    TSV:=WideTSV(Staged);
    FWide:=Staged;
    if Length(FWide)>0 then FGrid.RowCount:=Length(FWide)+1;
    for I:=0 to High(FWide) do begin
      W:=FWide[I];
      FGrid.Cells[0,I+1]:=IntToStr(W.Span.WordIndex);
      FGrid.Cells[1,I+1]:=IntToStr(W.Width);
      FGrid.Cells[2,I+1]:=String(W.Bits);
      FGrid.Cells[3,I+1]:='['+IntToStr(W.Span.TritStart)+','+
        IntToStr(W.Span.TritEnd)+')';
      FGrid.Cells[4,I+1]:='['+IntToStr(W.Span.ByteStart)+','+
        IntToStr(W.Span.ByteEnd)+')';
    end;
    FTSV.Text:=String(TSV);
    FStatus.Caption:='Фізичних широких слів: '+IntToStr(Length(FWide))+
      '; арифметика=НЕ-ДОВЕДЕНА; довжина бітів ≠ числова identity.';
    if Length(FWide)>0 then ShowWord(1);
    Result:=True;
  except on E:Exception do begin
    ResetView;
    FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
  end end;
end;

procedure TShyrokiWindow.OpenClicked(Sender:TObject);
begin
  if FCurrentPath<>'' then
    LoadFile(FCurrentPath)
  else if FDialog.Execute then
    LoadFile(FDialog.FileName);
end;

procedure TShyrokiWindow.SelfCheck(const Good,Shared,Short,Bad,Empty,
  TooMany,TextFile:String);
begin
  FCurrentPath:=Good;
  FButton.Click; { фізичний LCL шлях натискання; не прямий виклик тестом }
  Demand(Length(FWide)=3,'D12/D13/D12 відсутні');
  Demand((FWide[0].Span.WordIndex=2) and (FWide[0].Width=12) and
    (FWide[0].Bits='000000000001'),'втрачено точне D12');
  Demand((FWide[1].Span.WordIndex=4) and (FWide[1].Width=13) and
    (FWide[1].Bits='0000000000000'),'втрачено D13 або провідні нулі');
  Demand((FWide[2].Span.WordIndex=6) and
    (FWide[2].Bits='111111111111'),'втрачено другий D12');
  Demand((FGrid.RowCount=4) and (FGrid.Cells[3,1]='[2,14)') and
    (FGrid.Cells[4,1]='[0,3)') and
    (FGrid.Cells[3,2]='[18,31)') and
    (FGrid.Cells[4,3]='[8,12)'),'неправильні тритові/байтові межі');
  Demand(Pos('000000000001',FDetail.Text)>0,
    'немає детального показу усіх бітів');
  Demand(Pos('D13'+#9+'0000000000000',FTSV.Text)>0,
    'TSV не показує точну D13 ширину');

  Demand(LoadFile(Shared),'два слова з перекриттям байта');
  Demand((Length(FWide)=2) and
    (FGrid.Cells[4,1]='[0,3)') and
    (FGrid.Cells[4,2]='[2,5)'),
    'фізичний спільний байт не збережений');
  Demand(LoadFile(Short),'законні короткі T5M слова');
  Demand((Length(FWide)=0) and (FGrid.RowCount=2),
    'D1/D2/D10/D11 неправдиво показані як D12+');

  Demand(LoadFile(Good),'повторно відкрити добрий .sens');
  Demand(not LoadFile(Bad),'фізичний байт 243');
  Demand((Length(FWide)=0) and (FGrid.Cells[2,1]='') and
    (FDetail.Text='') and (FTSV.Text=''),
    'після битого байта залишено стару таблицю');
  Demand(not LoadFile(Empty),'порожній .sens');
  Demand(not LoadFile('відсутній.sens'),'відсутній .sens');
  Demand(not LoadFile(TextFile),'заборонена підміна .lisp');
  Demand(not LoadFile(TooMany),'не спрацювала межа GUI 256');
  Demand((Length(FWide)=0) and (FGrid.RowCount=2) and
    (FGrid.Cells[2,1]='') and (FTSV.Text=''),
    'після перевищення межі лишились старі дані');
  Demand(LoadFile(Good) and (Length(FWide)=3),
    'не вдалося відновити коректне T5M');
  WriteLn('LCL-ШИРОКІ-ГАРАЗД Lazarus=справжній GTK2 ',
    'кнопка=натиснута D12=точний D13=точний ',
    'трит-байт=точний спільний-байт=так D10-D11=не-числа ',
    'помилки=очищено відновлення=так арифметика=НЕ-ДОВЕДЕНА');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — широкі фізичні слова';
    Application.CreateForm(TShyrokiWindow,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>8 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8));
      Window.Free;
      Halt(0);
    end;
    if ParamCount>1 then
      raise Exception.Create('неприпустима кількість аргументів');
    if ParamCount=1 then Window.LoadFile(ParamStr(1));
    Application.Run;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-ШИРОКІ-ПОМИЛКА: ',E.Message);
    Halt(2);
  end end;
end.
