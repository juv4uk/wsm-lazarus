{ Приватне двійкове ExactIR та ОКРЕМО вузьке реальне D3 виконання.
  Дерево походить із wsm.exactir, виконання лише з pinned
  TBinaryExecutor: UI не містить власних SENS законів. }
program exactirinspector;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Grids, Dialogs, BaseUnix, wsm.t5m, wsm.domain, wsm.bind,
  wsm.exactir, wsm.exactirguard, wsm.binaryexec, wsm.d3batch,
  wsm.d2source;

const MaxVisibleNodes = 16384;
      MaxShownAnswerWords = 64;
      MaxShownAnswerNodes = 512;
      MaxShownAnswerDepth = 64;
type
  TExactIRWindow = class(TForm)
  private
    Tree: TTreeView;
    Table: TStringGrid;
    Status: TLabel;
    Detail: TLabel;
    OpenButton: TButton;
    NextButton: TButton;
    ParentButton: TButton;
    EvidenceButton: TButton;
    RunButton: TButton;
    BatchButton: TButton;
    SaveButton: TButton;
    EvidenceMemo: TMemo;
    ResultMemo: TMemo;
    AnswerTree: TTreeView;
    CurrentPhysical, AnswerPhysical: RawByteString;
    Dialog: TOpenDialog;
    SaveDialog: TSaveDialog;
    Links: array of TTreeNode;
    Current: TExactIR;
    procedure OpenClick(Sender: TObject);
    procedure NextClick(Sender: TObject);
    procedure ParentClick(Sender: TObject);
    procedure EvidenceClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure BatchClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ExportAnswer(const TargetPath:String);
    procedure ShowAnswerStructure(const Words:TExactWords);
    function MakeEvidence(const Candidate: TExactIR): RawByteString;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure SelectNode(NodeIndex: SizeInt);
    procedure ClearView;
    procedure Fail(const Reason: String);
    procedure ValidateIR(const Candidate: TExactIR);
    procedure ShowIR(const Candidate: TExactIR);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const FileName: String): Boolean;
    procedure SelfTest(const GoodFile, PairFile, BadFile: String;
      const TwoRootsFile: String = '');
    procedure SelfTestExecution(const QuoteFile, QuoteAnswer,
      ConsFile, ConsAnswer, BlockedFile, BadFile: String;
      const PairQuoteFile:String = ''; const PairQuoteAnswer:String = '');
    procedure SelfTestBatch(const GoodFile, ExpectedFile, LateBadFile,
      TooManyFile, BadFile: String);
  end;

var Window: TExactIRWindow;

function KindText(Kind: TExactIRKind): String;
begin
  case Kind of
    ikList: Result := 'список D2';
    ikPair: Result := 'похідна пара';
    ikIdentity: Result := 'координата';
    ikEmpty: Result := 'порожнє D3';
  else
    raise Exception.Create('невідомий вузол приватного IR');
  end;
end;

function HalfOpen(A, B: SizeInt): String;
begin
  Result := '[' + IntToStr(A) + ',' + IntToStr(B) + ')';
end;

function ReadPhysicalFile(const Name: String): RawByteString;
var F: TFileStream;
begin
  if LowerCase(ExtractFileExt(Name)) <> '.sens' then
    raise Exception.Create('потрібен фізичний файл .sens');
  F := TFileStream.Create(Name, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
      raise Exception.Create('порожній або надмірно великий фізичний файл');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1], Length(Result));
  finally F.Free; end;
end;

constructor TExactIRWindow.Create(AOwner: TComponent);
const Titles: array[0..8] of String = ('Вузол №', 'Вид', 'Корінь', 'Батько',
       'Домен', 'Точні біти', 'Трити', 'Байти', 'Піддерево [..)');
var TopBar, BottomBar, LeftPanel: TPanel; Split: TSplitter;
    I: Integer;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — візуальний оглядач точного двійкового IR';
  Width := 1220;
  Height := 660;
  Position := poScreenCenter;

  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 48;
  TopBar.BevelOuter := bvNone;
  OpenButton := TButton.Create(Self);
  OpenButton.Parent := TopBar;
  OpenButton.SetBounds(10, 8, 210, 32);
  OpenButton.Caption := 'Відкрити фізичний .sens…';
  OpenButton.OnClick := @OpenClick;
  EvidenceButton := TButton.Create(Self);
  EvidenceButton.Parent := TopBar;
  EvidenceButton.SetBounds(232, 8, 234, 32);
  EvidenceButton.Caption := 'Показати TSV-свідчення';
  EvidenceButton.OnClick := @EvidenceClick;
  RunButton := TButton.Create(Self);
  RunButton.Parent := TopBar;
  RunButton.SetBounds(478, 8, 264, 32);
  RunButton.Caption := 'Виконати фізичний D3';
  RunButton.OnClick := @RunClick;
  BatchButton := TButton.Create(Self);
  BatchButton.Parent := TopBar;
  BatchButton.SetBounds(754, 8, 257, 32);
  BatchButton.Caption := 'Виконати пакет D3';
  BatchButton.OnClick := @BatchClick;
  SaveButton := TButton.Create(Self);
  SaveButton.Parent := TopBar;
  SaveButton.SetBounds(1022,8,185,32);
  SaveButton.Caption := 'Зберегти відповідь .sens';
  SaveButton.OnClick := @SaveClick;
  Dialog := TOpenDialog.Create(Self);
  Dialog.Title := 'Виберіть фізичну двійкову програму SENS';
  Dialog.Filter := 'Фізичні програми SENS (*.sens)|*.sens';
  SaveDialog := TSaveDialog.Create(Self);
  SaveDialog.Title := 'Зберегти виконану фізичну відповідь D3';
  SaveDialog.Filter := 'Канонічний фізичний SENS (*.sens)|*.sens';
  SaveDialog.DefaultExt := 'sens';

  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 64;
  BottomBar.BevelOuter := bvNone;
  Status := TLabel.Create(Self);
  Status.Parent := BottomBar;
  Status.SetBounds(12, 8, 1180, 24);
  Detail := TLabel.Create(Self);
  Detail.Parent := BottomBar;
  Detail.SetBounds(12, 34, 1180, 24);

  { Видимий машинно-відтворюваний текст: це тільки проєкція ExactIR. }
  EvidenceMemo := TMemo.Create(Self);
  EvidenceMemo.Parent := Self;
  EvidenceMemo.Align := alBottom;
  EvidenceMemo.Height := 165;
  EvidenceMemo.ReadOnly := True;
  EvidenceMemo.ScrollBars := ssBoth;
  EvidenceMemo.WordWrap := False;

  { Візуальний результат ДІЙСНОГО вузького native execution
    відокремлений від структурного ExactIR та його TSV. }
  ResultMemo := TMemo.Create(Self);
  ResultMemo.Parent := Self;
  ResultMemo.Align := alBottom;
  ResultMemo.Height := 106;
  ResultMemo.ReadOnly := True;
  ResultMemo.ScrollBars := ssBoth;
  ResultMemo.WordWrap := False;

  { G3.28: фізична Д2-структура ВЖЕ виконаної відповіді, не AST входу.
    Віджет має lifetime форми; тимчасовий Doc звільняється відразу. }
  AnswerTree := TTreeView.Create(Self);
  AnswerTree.Parent := Self;
  AnswerTree.Align := alBottom;
  AnswerTree.Height := 112;
  AnswerTree.ReadOnly := True;

  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Self;
  LeftPanel.Align := alLeft;
  LeftPanel.Width := 345;
  LeftPanel.BevelOuter := bvNone;
  { G6.48: єдина додаткова навігація в справжньому TTreeView.
    Індекс End із уже перевіреного ExactIR є host preorder, не Wn. }
  NextButton := TButton.Create(Self);
  NextButton.Parent := LeftPanel;
  NextButton.Align := alTop;
  NextButton.Height := 36;
  NextButton.Caption := 'Перейти за вибране піддерево';
  NextButton.OnClick := @NextClick;
  { Навігація G6.50 — лише на основі перевіреного ParentIndex. }
  ParentButton := TButton.Create(Self);
  ParentButton.Parent := LeftPanel;
  ParentButton.Align := alTop;
  ParentButton.Height := 36;
  ParentButton.Caption := 'Перейти до батьківського вузла';
  ParentButton.OnClick := @ParentClick;
  Tree := TTreeView.Create(Self);
  Tree.Parent := LeftPanel;
  Tree.Align := alClient;
  Tree.ReadOnly := True;
  Tree.OnChange := @TreeChange;

  Split := TSplitter.Create(Self);
  Split.Parent := Self;
  Split.Align := alLeft;
  Split.Width := 6;
  Table := TStringGrid.Create(Self);
  Table.Parent := Self;
  Table.Align := alClient;
  Table.ColCount := 9;
  Table.FixedCols := 0;
  Table.RowCount := 2;
  Table.FixedRows := 1;
  Table.Options := Table.Options + [goColSizing, goRowSelect];
  for I := 0 to 8 do Table.Cells[I,0] := Titles[I];
  Table.ColWidths[0] := 80;
  Table.ColWidths[1] := 128;
  Table.ColWidths[2] := 72;
  Table.ColWidths[3] := 75;
  Table.ColWidths[4] := 72;
  Table.ColWidths[5] := 100;
  Table.ColWidths[6] := 130;
  Table.ColWidths[7] := 130;
  Table.ColWidths[8] := 136;
  ClearView;
end;

procedure TExactIRWindow.ClearView;
var I: Integer;
begin
  Tree.Items.Clear;
  SetLength(Links, 0);
  SetLength(Current.Nodes, 0);
  SetLength(Current.Roots, 0);
  Current.BoundLeaves := 0;
  EvidenceMemo.Clear;
  EvidenceButton.Enabled := False;
  NextButton.Enabled := False;
  ParentButton.Enabled := False;
  RunButton.Enabled := False;
  BatchButton.Enabled := False;
  CurrentPhysical := '';
  AnswerPhysical := ''; SaveButton.Enabled:=False;
  ResultMemo.Clear;
  AnswerTree.Items.Clear;
  Table.RowCount := 2;
  for I := 0 to Table.ColCount-1 do Table.Cells[I,1] := '';
  Detail.Caption := 'Виберіть вузол для огляду фізичної адреси.';
end;

procedure TExactIRWindow.Fail(const Reason: String);
begin
  ClearView;
  Status.Caption := 'Помилка двійкового IR: ' + Reason;
end;

procedure TExactIRWindow.ValidateIR(const Candidate: TExactIR);
var Stats: TExactIRGuardStats;
begin
  { Єдиний headless gate: не повторювати неповний GUI-валідатор. }
  VerifyExactIRStructure(Candidate, Stats);
  if Stats.Nodes > MaxVisibleNodes then
    raise Exception.Create('перевищено межу вузлів вікна');
end;

function TExactIRWindow.MakeEvidence(const Candidate: TExactIR): RawByteString;
var Lines: TStringList; I: SizeInt; N: TExactIRNode;
    DomainText, BitsText, TritText, ByteText: String;
begin
  { Спершу повний gate, жодного часткового TSV для несправного IR. }
  ValidateIR(Candidate);
  Lines := TStringList.Create;
  try
    Lines.LineBreak := #10;
    Lines.Add('вузол'+#9+'вид'+#9+'корінь'+#9+'батько'+#9+
      'дитина'+#9+'глибина'+#9+'слово'+#9+'домен'+#9+
      'біти'+#9+'трити'+#9+'байти');
    for I := 0 to High(Candidate.Nodes) do begin
      N := Candidate.Nodes[I];
      DomainText := '—'; BitsText := '—';
      TritText := '—'; ByteText := '—';
      if N.HasKey then begin
        DomainText := 'D'+IntToStr(N.Key.Width);
        BitsText := String(KeyBits(N.Key));
      end;
      if N.Kind <> ikPair then begin
        TritText := HalfOpen(N.Physical.TritStart, N.Physical.TritEnd);
        ByteText := HalfOpen(N.Physical.ByteStart, N.Physical.ByteEnd);
      end;
      Lines.Add(IntToStr(I)+#9+KindText(N.Kind)+#9+
        IntToStr(N.RootIndex)+#9+IntToStr(N.ParentIndex)+#9+
        IntToStr(N.ChildIndex)+#9+IntToStr(N.Depth)+#9+
        IntToStr(N.WordIndex)+#9+DomainText+#9+BitsText+#9+
        TritText+#9+ByteText);
    end;
    Result := RawByteString(Lines.Text);
  finally Lines.Free; end;
end;

procedure TExactIRWindow.EvidenceClick(Sender: TObject);
begin
  if Length(Current.Nodes) = 0 then Exit;
  try
    EvidenceMemo.Lines.Text := String(MakeEvidence(Current));
  except
    on E: Exception do Fail(E.Message);
  end;
end;

{ G3.28: Words — позичені ТОЧНІ слова вже перевіреного T5M.
  Єдиний чинний ParseD2WordsWide повертає тимчасовий власний Doc.
  Екранний ліміт 512 вузлів / глибина 64 — не відсікання .sens,
  не D12+ закон і не дозвіл виклику. Після return Doc.Free;
  TTreeView утримує тільки незалежні host-рядки, жодних TD2Node.
  Питання: чому W24 не дорівнює D24? Коли звільняється Doc?
  Чому скорочений екран не змінює фізичний результат? }
procedure TExactIRWindow.ShowAnswerStructure(const Words:TExactWords);
var Doc:TD2Document; I, Used:SizeInt; Truncated:Boolean;

  procedure AddNode(Node:TD2Node; Parent:TTreeNode; Depth:SizeInt);
  var CaptionText:String; Child:TTreeNode; J:SizeInt;
  begin
    if (Used>=MaxShownAnswerNodes) or (Depth>=MaxShownAnswerDepth) then begin
      if not Truncated then begin
        AnswerTree.Items.AddChild(Parent,
          '… лише екранне скорочення; фізична відповідь повна');
        Truncated:=True;
      end;
      Exit;
    end;
    if Node=nil then raise Exception.Create('порожній вузол відповіді D2');
    case Node.Kind of
      dkList:CaptionText:='список D2';
      dkPair:CaptionText:='крапкова пара D2';
      dkEmpty:CaptionText:='порожнє D3:000';
      dkIdentity:CaptionText:='точне W'+IntToStr(Node.Width)+
        ':'+String(Node.Bits);
      else raise Exception.Create('невідомий вузол відповіді D2');
    end;
    Child:=AnswerTree.Items.AddChild(Parent,CaptionText);
    Inc(Used);
    for J:=0 to High(Node.Children) do AddNode(Node.Children[J],Child,Depth+1);
  end;

begin
  Doc:=ParseD2WordsWide(Words);
  try
    Used:=0; Truncated:=False;
    AnswerTree.Items.BeginUpdate;
    try
      AnswerTree.Items.Clear;
      for I:=0 to High(Doc.Roots) do
        AddNode(Doc.Roots[I],nil,0);
    finally AnswerTree.Items.EndUpdate; end;
  finally Doc.Free; end;
end;

{ G3.14. Це виклик вже наявного runtime, не lowering/виконання IR.
  Джерело — ТОЧНІ незмінні байти успішно завантаженого .sens;
  на відмові не видно ні одного байта минулої відповіді. }
procedure TExactIRWindow.RunClick(Sender: TObject);
var Engine: TBinaryExecutor; Candidate: RawByteString;
    Words: TExactWords; Lines: TStringList; I, Limit: SizeInt;
begin
  AnswerPhysical := ''; SaveButton.Enabled:=False;
  ResultMemo.Clear;
  AnswerTree.Items.Clear;
  if (CurrentPhysical = '') or (not RunButton.Enabled) then begin
    Status.Caption := 'Виконання відхилено: немає перевіреного .sens';
    Exit;
  end;
  Engine := nil;
  Lines := nil;
  try
    Engine := TBinaryExecutor.Create('external/sens');
    Candidate := Engine.ExecutePhysicalT5M(CurrentPhysical);
    DecodeT5M(Candidate, Words);
    if (EncodeT5M(Words) <> Candidate) or (Length(Words)=0) then
      raise Exception.Create('результат native D3 не є канонічним T5M');
    Lines := TStringList.Create;
    Lines.Add('Фізичний результат виконаного D3: '+
      IntToStr(Length(Words))+' точних двійкових слів; '+
      IntToStr(Length(Candidate))+' байтів T5M');
    Limit := Length(Words);
    if Limit > MaxShownAnswerWords then Limit := MaxShownAnswerWords;
    for I := 0 to Limit-1 do
      Lines.Add('слово '+IntToStr(I+1)+': '+String(Words[I]));
    if Limit < Length(Words) then
      Lines.Add('… ще '+IntToStr(Length(Words)-Limit)+
        ' слів; скорочено лише екранний показ');
    { Структура вже обчисленої відповіді: той самий D2 reader,
      жодного повторного T5M decode чи текстового виконання. }
    ShowAnswerStructure(Words);
    { Атомарна публікація канонічного результату ПІСЛЯ всіх guard. }
    ResultMemo.Lines.Assign(Lines);
    AnswerPhysical := Candidate; SaveButton.Enabled:=True;
    Status.Caption := 'Виконано вузький D3: фізична T5M відповідь';
  except
    on E: EBinaryExecutionError do begin
      AnswerPhysical := ''; SaveButton.Enabled:=False;
      ResultMemo.Clear; AnswerTree.Items.Clear;
      Status.Caption := 'Виконання відхилено, фізичне слово '+
        IntToStr(E.WordIndex)+': '+E.Message;
    end;
    on E: Exception do begin
      AnswerPhysical := ''; SaveButton.Enabled:=False;
      ResultMemo.Clear; AnswerTree.Items.Clear;
      Status.Caption := 'Виконання відхилено: '+E.Message;
    end;
  end;
  Lines.Free;
  Engine.Free;
end;

{ Пакетний режим НЕ виконує IR і НЕ створює другу мовну семантику.
  Одна інстанція чинного D3 executor для 1..64 самостійних форм.
  Відповідь з'являється у GUI лише після всіх успішних форм. }
procedure TExactIRWindow.BatchClick(Sender: TObject);
var Candidate:RawByteString; W:TExactWords; Forms, I, Limit:SizeInt;
    Lines:TStringList;
begin
  AnswerPhysical:=''; SaveButton.Enabled:=False;
  ResultMemo.Clear;
  AnswerTree.Items.Clear;
  if (CurrentPhysical='') or (not BatchButton.Enabled) then begin
    Status.Caption:='Пакет D3 відхилено: немає перевіреного .sens';
    Exit;
  end;
  Lines:=nil;
  try
    ExecutePhysicalD3Batch(CurrentPhysical,'external/sens',Candidate,Forms);
    DecodeT5M(Candidate,W);
    if (Length(W)=0) or (EncodeT5M(W)<>Candidate) then
      raise Exception.Create('пакет не повернув канонічний T5M');
    Lines:=TStringList.Create;
    Lines.Add('Виконано пакет D3: '+IntToStr(Forms)+
      ' незалежних форм, '+IntToStr(Length(W))+
      ' точних двійкових слів, '+IntToStr(Length(Candidate))+' байтів');
    Limit:=Length(W);
    if Limit>MaxShownAnswerWords then Limit:=MaxShownAnswerWords;
    for I:=0 to Limit-1 do
      Lines.Add('слово '+IntToStr(I+1)+': '+String(W[I]));
    if Limit<Length(W) then Lines.Add('… ще '+
      IntToStr(Length(W)-Limit)+' слів: лише екранне скорочення');
    ShowAnswerStructure(W);
    ResultMemo.Lines.Assign(Lines);
    AnswerPhysical:=Candidate; SaveButton.Enabled:=True;
    Status.Caption:='Виконано пакет D3: '+IntToStr(Forms)+
      ' незалежних фізичних форм';
  except
    on E:ED3BatchError do begin
      AnswerPhysical:=''; SaveButton.Enabled:=False; ResultMemo.Clear;
      AnswerTree.Items.Clear;
      Status.Caption:='Пакет D3 відхилено, форма '+
        IntToStr(E.FormIndex)+', фізичне слово '+
        IntToStr(E.WordIndex)+': '+E.Message;
    end;
    on E:Exception do begin
      AnswerPhysical:=''; SaveButton.Enabled:=False; ResultMemo.Clear;
      AnswerTree.Items.Clear;
      Status.Caption:='Пакет D3 відхилено: '+E.Message;
    end;
  end;
  Lines.Free;
end;

{ G3.18 — публікація тільки вже обчисленого фізичного T5M.
  Ця процедура не трактує SIR як виконуваний код. }
procedure TExactIRWindow.ExportAnswer(const TargetPath:String);
var W:TExactWords; Temp:String; F:TFileStream;
begin
  if (not SaveButton.Enabled) or (AnswerPhysical='') then
    raise Exception.Create('немає виконаної фізичної відповіді');
  if (ExtractFileName(TargetPath)='') or (LowerCase(ExtractFileExt(TargetPath))<>'.sens') then
    raise Exception.Create('потрібен новий файл .sens, не людська .lisp');
  if Length(AnswerPhysical)>MAX_T5M_FILE_BYTES then
    raise Exception.Create('фізична T5M відповідь завелика');
  DecodeT5M(AnswerPhysical,W);
  if (Length(W)=0) or (EncodeT5M(W)<>AnswerPhysical) then
    raise Exception.Create('неканонічна фізична T5M відповідь');
  Temp:='';
  try
    { Temp у цільовій директорії; fpLink не перезаписує й symlink. }
    Temp:=GetTempFileName(ExtractFilePath(ExpandFileName(TargetPath)),'d3o');
    if Temp='' then raise Exception.Create('неможливо створити тимчасовий файл');
    F:=TFileStream.Create(Temp,fmCreate);
    try F.WriteBuffer(AnswerPhysical[1],Length(AnswerPhysical));
    finally F.Free; end;
    if fpLink(RawByteString(Temp),RawByteString(TargetPath))<>0 then
      raise Exception.Create('ім’я результату вже зайняте або недоступне');
  finally
    if Temp<>'' then DeleteFile(Temp);
  end;
end;

procedure TExactIRWindow.SaveClick(Sender:TObject);
begin
  if not SaveButton.Enabled then Exit;
  if not SaveDialog.Execute then Exit;
  try
    ExportAnswer(SaveDialog.FileName);
    Status.Caption:='Збережено точну фізичну відповідь: '+SaveDialog.FileName;
  except
    on E:Exception do Status.Caption:='Експорт D3 відхилено: '+E.Message;
  end;
end;

procedure TExactIRWindow.ShowIR(const Candidate: TExactIR);
var I: SizeInt; N: TExactIRNode; CaptionText, BitsText, Dom: String;
    ParentNode: TTreeNode;
begin
  { До цього виклику повністю перевірено T5M, D2, pinned домени та IR. }
  ValidateIR(Candidate);
  Current := Candidate;
  SetLength(Links, Length(Current.Nodes));
  Table.RowCount := Length(Current.Nodes)+1;
  Tree.Items.BeginUpdate;
  try
    for I := 0 to High(Current.Nodes) do begin
      N := Current.Nodes[I];
      Dom := '—'; BitsText := '—';
      if N.HasKey then begin
        Dom := 'D' + IntToStr(N.Key.Width);
        BitsText := String(KeyBits(N.Key));
      end;
      CaptionText := IntToStr(I)+': '+KindText(N.Kind);
      if N.HasKey then CaptionText := CaptionText+' '+Dom+':'+BitsText;
      ParentNode := nil;
      if N.ParentIndex >= 0 then ParentNode := Links[N.ParentIndex];
      Links[I] := Tree.Items.AddChild(ParentNode, CaptionText);
      Links[I].Data := Pointer(PtrInt(I + 1));
      Table.Cells[0,I+1] := IntToStr(I);
      Table.Cells[1,I+1] := KindText(N.Kind);
      Table.Cells[2,I+1] := IntToStr(N.RootIndex);
      Table.Cells[3,I+1] := IntToStr(N.ParentIndex);
      Table.Cells[4,I+1] := Dom;
      Table.Cells[5,I+1] := BitsText;
      { Піддерево — індекс вузлів у приватному IR, не фізичний
        тритовий/байтовий інтервал: пара теж має свій вузол. }
      Table.Cells[8,I+1] := HalfOpen(I,N.SubtreeEndExclusive);
      if N.Kind = ikPair then begin
        { Похідна пара не має власного окремого токена фізичного T5M. }
        Table.Cells[6,I+1] := '—';
        Table.Cells[7,I+1] := '—';
      end else begin
        Table.Cells[6,I+1] :=
          HalfOpen(N.Physical.TritStart,N.Physical.TritEnd);
        Table.Cells[7,I+1] :=
          HalfOpen(N.Physical.ByteStart,N.Physical.ByteEnd);
      end;
    end;
  finally
    Tree.Items.EndUpdate;
  end;
  Tree.FullExpand;
  Status.Caption := 'Приватне IR: вузлів '+IntToStr(Length(Current.Nodes))+
    ', коренів '+IntToStr(Length(Current.Roots))+
    ', двійкових листків '+IntToStr(Current.BoundLeaves)+
    ' · виконання НЕ доведено';
  EvidenceButton.Enabled := True;
  SelectNode(0);
end;

{ Програмний TTreeView.Selected у GTK2/LCL може відкласти OnChange.
  Синхронізуємо read-only Detail/кнопку негайно. Реальний клік
  користувача й надалі йде тим самим TreeChange, без нового parser.
  Links існують тільки протягом життя поточного перевіреного IR. }
procedure TExactIRWindow.SelectNode(NodeIndex: SizeInt);
begin
  if (NodeIndex<0) or (NodeIndex>=Length(Current.Nodes)) or
     (NodeIndex>=Length(Links)) then
    raise Exception.Create('індекс вузла поза перевіреним IR');
  Tree.Selected := Links[NodeIndex];
  TreeChange(Tree,Links[NodeIndex]);
end;

procedure TExactIRWindow.TreeChange(Sender: TObject; Node: TTreeNode);
var I: SizeInt; N: TExactIRNode;
begin
  if Node = nil then Exit;
  I := PtrInt(Node.Data)-1;
  if (I < 0) or (I >= Length(Current.Nodes)) then Exit;
  N := Current.Nodes[I];
  Table.Row := I+1;
  NextButton.Enabled := (N.SubtreeEndExclusive>I) and
    (N.SubtreeEndExclusive<Length(Current.Nodes));
  ParentButton.Enabled := (N.ParentIndex>=0) and
    (N.ParentIndex<I) and (N.ParentIndex<Length(Links));
  Detail.Caption := 'Вузол '+IntToStr(I)+
    ' · корінь '+IntToStr(N.RootIndex)+
    ' · глибина '+IntToStr(N.Depth)+
    ' · фізичне слово '+IntToStr(N.WordIndex)+
    ' · вузли піддерева '+HalfOpen(I,N.SubtreeEndExclusive);
  if N.Kind = ikPair then Detail.Caption := Detail.Caption+
    ' · похідна пара: немає власного фізичного токена';
end;

{ G6.48: N — уже guard-верифікований вузол, End — 0-based індекс
  першого вузла ПІСЛЯ [I,End) у Current.Nodes. Немає нових масивів,
  фізичних декодувань, дозвільних прапорів виконання чи .lisp-шляху.
  TTreeView/Links володіє посиланнями весь час до ClearView. }
procedure TExactIRWindow.NextClick(Sender: TObject);
var I, Following: SizeInt;
begin
  if (not NextButton.Enabled) or (Tree.Selected=nil) then Exit;
  I := PtrInt(Tree.Selected.Data)-1;
  if (I<0) or (I>=Length(Current.Nodes)) then Exit;
  Following := Current.Nodes[I].SubtreeEndExclusive;
  if (Following<=I) or (Following>=Length(Current.Nodes)) or
     (Following>=Length(Links)) then Exit;
  SelectNode(Following);
end;

{ G6.50: ParentIndex походить виключно з guard-перевіреного ExactIR.
  Це 0-based індекс вузла в цьому самому Current, НЕ семантична
  координата SENS. Жодних нових алокацій: використовуються наявні Links.
  Корені (-1) й невдалі/очищені snapshots нікуди не переходять. }
procedure TExactIRWindow.ParentClick(Sender: TObject);
var I, ParentIndex: SizeInt;
begin
  if (not ParentButton.Enabled) or (Tree.Selected=nil) then Exit;
  I := PtrInt(Tree.Selected.Data)-1;
  if (I<0) or (I>=Length(Current.Nodes)) then Exit;
  ParentIndex := Current.Nodes[I].ParentIndex;
  if (ParentIndex<0) or (ParentIndex>=I) or
     (ParentIndex>=Length(Links)) then Exit;
  SelectNode(ParentIndex);
end;

function TExactIRWindow.LoadFile(const FileName: String): Boolean;
var Physical: RawByteString; Tables: TDomainSet; Candidate: TExactIR;
begin
  Result := False;
  ClearView;
  Status.Caption := 'Читання точного двійкового IR…';
  try
    Physical := ReadPhysicalFile(FileName);
    LoadPinnedDomains('external/sens',Tables);
    BuildExactIR(Physical,Tables,Candidate);
    ShowIR(Candidate);
    CurrentPhysical := Physical;
    RunButton.Enabled := True;
    BatchButton.Enabled := True;
    Result := True;
  except
    on E: Exception do Fail(E.Message);
  end;
end;

procedure TExactIRWindow.OpenClick(Sender: TObject);
begin
  if Dialog.Execute then LoadFile(Dialog.FileName);
end;

procedure TExactIRWindow.SelfTest(const GoodFile, PairFile, BadFile: String;
  const TwoRootsFile: String);
var SavedEvidence, OldStatus: String; Tampered: TExactIR; Rejected: Boolean;
begin
  if not LoadFile(GoodFile) then
    raise Exception.Create('позитивне IR: '+Status.Caption);
  if (Tree.Items.Count <> 4) or (Table.RowCount <> 5) or
     (Table.Cells[4,2] <> 'D3') or (Table.Cells[5,2] <> '111') or
     (Table.Cells[4,3] <> 'D1') or (Table.Cells[5,3] <> '0') or
     (Table.Cells[4,4] <> 'D3') or (Table.Cells[5,4] <> '000') or
     (Table.Cells[6,4] <> '[12,15)') or
     (Table.Cells[7,4] <> '[2,3)') then
    raise Exception.Create('порушені точні координати LCL-таблиці');
  Tree.Selected := Links[3];
  Application.ProcessMessages;
  if (Pos('слово 5',Detail.Caption)=0) or (Table.Row<>4) or
     (not ParentButton.Enabled) then
    raise Exception.Create('не працює вибір вузла IR у вікні');
  ParentClick(Self); Application.ProcessMessages;
  if (Tree.Selected<>Links[0]) or (Table.Row<>1) or
     ParentButton.Enabled or (Pos('піддерева [0,4)',Detail.Caption)=0) then
    raise Exception.Create('LCL не повернувся до батька фізичного листка');
  ParentClick(Self);
  if Tree.Selected<>Links[0] then
    raise Exception.Create('корінь IR має хибного батька');
  SelectNode(3); Application.ProcessMessages;
  if not EvidenceButton.Enabled then
    raise Exception.Create('недоступне свідчення перевіреного IR');
  if (Table.Cells[8,1]<>'[0,4)') or
     (Table.Cells[8,2]<>'[1,2)') or
     (Table.Cells[8,4]<>'[3,4)') or
     (Pos('піддерева [3,4)',Detail.Caption)=0) or
     NextButton.Enabled then
    raise Exception.Create('втрачені доведені межі списку або листка');
  { Відома фізична форма: корінь охоплює усі три листки.
    Перехід із першого листка має перестрибнути рівно його subtree. }
  SelectNode(1); Application.ProcessMessages;
  if not NextButton.Enabled then
    raise Exception.Create('не активована LCL навігація після листка');
  NextClick(Self);
  if (Tree.Selected<>Links[2]) or (Table.Row<>3) or
     (Pos('піддерева [2,3)',Detail.Caption)=0) then
    raise Exception.Create('неправильний крок за піддерево в списку');
  NextClick(Self);
  if (Tree.Selected<>Links[3]) or (Table.Row<>4) or NextButton.Enabled then
    raise Exception.Create('навігація вийшла за кінець фізичного списку');
  OldStatus:=Status.Caption;
  NextClick(Self);
  if (Tree.Selected<>Links[3]) or (Status.Caption<>OldStatus) then
    raise Exception.Create('недопустима навігація за кінець IR');
  EvidenceClick(Self);
  SavedEvidence := EvidenceMemo.Lines.Text;
  if (Pos('вузол'+#9+'вид'+#9+'корінь',SavedEvidence) <> 1) or
     (Pos(#9+'D1'+#9+'0'+#9,SavedEvidence) = 0) or
     (Pos(#9+'D3'+#9+'000'+#9+'[12,15)'+#9+'[2,3)',SavedEvidence) = 0) or
     (EvidenceMemo.Lines.Count <> 5) then
    raise Exception.Create('TSV не зберіг точну структуру IR');
  EvidenceClick(Self);
  if SavedEvidence <> EvidenceMemo.Lines.Text then
    raise Exception.Create('TSV не є відтворюваним');
  { Окрема негативна перевірка GUI-gate: мутований IR не публікується. }
  Tampered := Current;
  Tampered.Nodes := Copy(Current.Nodes,0,Length(Current.Nodes));
  Tampered.Nodes[1].ParentIndex := High(Current.Nodes)+1;
  Rejected := False;
  try ShowIR(Tampered);
  except on E: EExactIRGuardError do Rejected := True; end;
  if (not Rejected) or (SavedEvidence <> EvidenceMemo.Lines.Text) or
     (Tree.Items.Count <> 4) or (Table.Cells[5,2] <> '111') then
    raise Exception.Create('пошкоджений parent пройшов GUI-сторож');
  Tampered.Nodes := Copy(Current.Nodes,0,Length(Current.Nodes));
  Inc(Tampered.Nodes[1].Physical.TritEnd);
  Rejected := False;
  try ShowIR(Tampered);
  except on E: EExactIRGuardError do Rejected := True; end;
  if (not Rejected) or (SavedEvidence <> EvidenceMemo.Lines.Text) then
    raise Exception.Create('пошкоджені трити пройшли GUI-сторож');
  Tampered.Nodes := Copy(Current.Nodes,0,Length(Current.Nodes));
  Tampered.Nodes[0].SubtreeEndExclusive := 3;
  Rejected := False;
  try ShowIR(Tampered);
  except on E:EExactIRGuardError do Rejected := True; end;
  if (not Rejected) or (Tree.Items.Count<>4) or
     (Table.Cells[8,1]<>'[0,4)') or
     (SavedEvidence<>EvidenceMemo.Lines.Text) then
    raise Exception.Create('підроблену межу опубліковано у LCL');

  if not LoadFile(PairFile) then
    raise Exception.Create('позитивна пара: '+Status.Caption);
  if (Tree.Items.Count <> 5) or
     (Table.Cells[1,1] <> 'похідна пара') or
     (Table.Cells[6,1] <> '—') or
     (Table.Cells[7,1] <> '—') or
     (Table.Cells[1,3] <> 'похідна пара') or
     (Table.Cells[7,3] <> '—') then
    raise Exception.Create('вигадано фізичну адресу для похідної пари');
  EvidenceClick(Self);
  if (Table.Cells[8,1]<>'[0,5)') or
     (Table.Cells[8,3]<>'[2,5)') then
    raise Exception.Create('межі похідної крапкової пари пошкоджено');
  SelectNode(1); Application.ProcessMessages;
  NextClick(Self);
  if (Tree.Selected<>Links[2]) or (Table.Cells[8,3]<>'[2,5)') or
     NextButton.Enabled or (not ParentButton.Enabled) then
    raise Exception.Create('LCL не пропустив праве піддерево пари');
  SelectNode(4); Application.ProcessMessages;
  if not ParentButton.Enabled then
    raise Exception.Create('у фізичної пари загубився батько');
  ParentClick(Self);
  if (Tree.Selected<>Links[2]) or (Table.Row<>3) or
     (Table.Cells[6,3]<>'—') then
    raise Exception.Create('LCL не відновив похідного батька пари');
  ParentClick(Self);
  if (Tree.Selected<>Links[0]) or ParentButton.Enabled or
     (Table.Cells[8,1]<>'[0,5)') then
    raise Exception.Create('LCL помилково перетнув корінь пари');
  if (EvidenceMemo.Lines.Count <> 6) or
     (Pos('похідна пара',EvidenceMemo.Lines[1])=0) or
     (Pos(#9+'—'+#9+'—'+#9+'—'+#9+'—',EvidenceMemo.Lines[1])=0) then
    raise Exception.Create('похідна пара отримала підроблену TSV-адресу');
  if TwoRootsFile<>'' then begin
    if not LoadFile(TwoRootsFile) then
      raise Exception.Create('два корені фізичного T5M: '+Status.Caption);
    if (Tree.Items.Count<>3) or (Table.Cells[8,1]<>'[0,2)') or
       (Table.Cells[8,3]<>'[2,3)') then
      raise Exception.Create('змішано два незалежні корені D2');
    SelectNode(0); Application.ProcessMessages;
    if not NextButton.Enabled then
      raise Exception.Create('неактивний перехід до другого кореня');
    NextClick(Self);
    if (Tree.Selected<>Links[2]) or (Table.Row<>3) or
       NextButton.Enabled or ParentButton.Enabled or
       (Pos('піддерева [2,3)',Detail.Caption)=0) then
      raise Exception.Create('перехід між D2 коренями порушив межі');
    ParentClick(Self);
    if Tree.Selected<>Links[2] then
      raise Exception.Create('другий корінь отримав чужого батька');
  end;
  if LoadFile(BadFile) then
    raise Exception.Create('зіпсований T5M прийнято');
  if (Tree.Items.Count<>0) or (Table.RowCount<>2) or
     (EvidenceMemo.Lines.Count<>0) or EvidenceButton.Enabled or
     NextButton.Enabled or ParentButton.Enabled or
     (Table.Cells[8,1]<>'') or
     (Table.Cells[0,1]<>'') or
     (Pos('Помилка',Status.Caption)<>1) then
    raise Exception.Create('застарілі вузли після помилки');
  if LoadFile('відсутній.sens') then
    raise Exception.Create('відсутній файл прийнято');
  if (Tree.Items.Count<>0) or (Table.Cells[0,1]<>'') or
     NextButton.Enabled or ParentButton.Enabled or
     (Table.Cells[8,1]<>'') or
     (EvidenceMemo.Lines.Count<>0) then
    raise Exception.Create('залишився попередній IR після відмови');
  WriteLn('LCL-БАТЬКІВСЬКА-НАВІГАЦІЯ-ГАРАЗД дерево=справжнє',
    ' список=так пара=так два-корені=без-перетину',
    ' відмова=очищення батько=тільки-IR');
  WriteLn('LCL-ПІДДЕРЕВА-ГАРАЗД межі=піввідкриті',
    ' навігація=реальна два-корені=точні',
    ' сторож=відхиляє-підміну помилки=очищено');
  WriteLn('LCL-ТОЧНЕ-IR-ГАРАЗД дерево=справжнє таблиця=справжня ',
    'D1:0_не_D3:000=так трити-байти=точні пара=без-фальшивої-адреси ',
    'негативні=очищення сторож=спільний TSV=відтворюваний виконання=НЕ-ДОВЕДЕНО');
end;

procedure TExactIRWindow.SelfTestExecution(
  const QuoteFile, QuoteAnswer, ConsFile, ConsAnswer,
  BlockedFile, BadFile, PairQuoteFile, PairQuoteAnswer: String);
var Saved:RawByteString; Path:String; Rejected:Boolean;
begin
  { Доказ: два різні pinned механізми D3 дають не текстову
    проєкцію, а РЕАЛЬНІ канонічні bytes через один native API. }
  if not LoadFile(QuoteFile) or (not RunButton.Enabled) then
    raise Exception.Create('не допущено фізичну D3 цитату: '+Status.Caption);
  RunClick(Self);
  Saved := ReadPhysicalFile(QuoteAnswer);
  if (AnswerPhysical <> Saved) or
     (AnswerTree.Items.Count<>1) or
     (AnswerTree.Items[0].Text<>'порожнє D3:000') or
     (Pos('слово 1: 000',ResultMemo.Text)=0) or
     (Pos('слово 1: 0'+#13#10,ResultMemo.Text)>0) or
     (Pos('Виконано',Status.Caption)<>1) then
    raise Exception.Create('цитата D3 не виконана в канонічний T5M');
  Path:=ChangeFileExt(QuoteAnswer,'')+'-експорт.sens';
  ExportAnswer(Path);
  if ReadPhysicalFile(Path)<>Saved then
    raise Exception.Create('відмінність фізичного експорту D3 цитати');
  if not LoadFile(ConsFile) or (AnswerPhysical<>'') or
     (ResultMemo.Lines.Count<>0) then
    raise Exception.Create('попередня фізична відповідь пережила нове .sens');
  RunClick(Self);
  Saved := ReadPhysicalFile(ConsAnswer);
  if (AnswerPhysical<>Saved) or
     (AnswerTree.Items.Count<>3) or
     (AnswerTree.Items[0].Text<>'крапкова пара D2') or
     (AnswerTree.Items[1].Text<>'точне W1:1') or
     (AnswerTree.Items[2].Text<>'точне W1:0') or
     (Pos('слово 3: 11',ResultMemo.Text)=0) then
    raise Exception.Create('виконаний D3:111 не повернув точну крапкову пару');
  Path:=ChangeFileExt(ConsAnswer,'')+'-експорт.sens';
  ExportAnswer(Path);
  if ReadPhysicalFile(Path)<>Saved then
    raise Exception.Create('відмінність фізичного експорту D3:111');
  if PairQuoteFile<>'' then begin
    if (PairQuoteAnswer='') or (not LoadFile(PairQuoteFile)) then
      raise Exception.Create('не завантажено фізичну цитату крапкової пари');
    RunClick(Self);
    Saved:=ReadPhysicalFile(PairQuoteAnswer);
    if (AnswerPhysical<>Saved) or
       (AnswerTree.Items.Count<>3) or
       (AnswerTree.Items[0].Text<>'крапкова пара D2') or
       (AnswerTree.Items[1].Text<>'точне W1:1') or
       (AnswerTree.Items[2].Text<>'точне W1:0') or
       (not SaveButton.Enabled) then
      raise Exception.Create('LCL не показав виконану фізичну D3:001 пару');
    Path:=ChangeFileExt(PairQuoteAnswer,'')+'-експорт.sens';
    ExportAnswer(Path);
    if ReadPhysicalFile(Path)<>Saved then
      raise Exception.Create('експорт цитованої пари змінив фізичні байти');
  end;
  if not LoadFile(BlockedFile) then
    raise Exception.Create('чинний D2 reader має приймати фізичну пару');
  RunClick(Self);
  if (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) or
     (AnswerTree.Items.Count<>0) or
     (Pos('Виконання відхилено',Status.Caption)<>1) or
     (Tree.Items.Count=0) then
    raise Exception.Create('заборонена вхідна D2 пара видала результат');
  if SaveButton.Enabled then
    raise Exception.Create('stale кнопка експорту після D3 відмови');
  Path:=ChangeFileExt(ConsAnswer,'')+'-не-допущено.sens';
  Rejected:=False;
  try ExportAnswer(Path);
  except on E:Exception do Rejected:=True; end;
  if (not Rejected) or FileExists(Path) then
    raise Exception.Create('дозволено експорт після D3 відмови');
  if LoadFile(BadFile) or RunButton.Enabled or
     (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) or
     (AnswerTree.Items.Count<>0) then
    raise Exception.Create('зіпсований T5M залишив фізичну відповідь');
  if LoadFile('відсутній.sens') or RunButton.Enabled or
     (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) or
     (AnswerTree.Items.Count<>0) then
    raise Exception.Create('неіснуючий .sens залишив фізичну відповідь');
  if not LoadFile(QuoteFile) then
    raise Exception.Create('здорову цитату не відновлено після негативів');
  RunClick(Self);
  if AnswerPhysical<>ReadPhysicalFile(QuoteAnswer) then
    raise Exception.Create('повторний фізичний D3 виклик не відновився');
  WriteLn('LCL-ДЕРЕВО-ВІДПОВІДІ-ГАРАЗД D2=вузли',
    ' quoted-pair=виконано D1=точні opaque-Wn=дані',
    ' відмова=очищення');
  WriteLn('LCL-D3-ВИКОНАННЯ-ГАРАЗД quote=дійсний cons=дійсний',
    ' T5M=побайтовий D2-dot=збережено негативи=очищені',
    ' Core4=НЕ-ДОВЕДЕНО D12+=НЕ-ДОВЕДЕНО');
end;


procedure TExactIRWindow.SelfTestBatch(const GoodFile, ExpectedFile,
  LateBadFile, TooManyFile, BadFile:String);
var Path,Retry,LinkPath,InvalidPath:String; Rejected:Boolean;
begin
  if not LoadFile(GoodFile) or (not BatchButton.Enabled) then
    raise Exception.Create('фізичний D3 пакет не завантажено');
  { Чинний одиничний D3 API НЕ має мовчки трактувати пакет. }
  RunClick(Self);
  if (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) or SaveButton.Enabled then
    raise Exception.Create('одиничний D3 режим прийняв кілька коренів');
  InvalidPath:=ChangeFileExt(ExpectedFile,'')+'-заблоковано.sens';
  Rejected:=False;
  try ExportAnswer(InvalidPath);
  except on E:Exception do Rejected:=True; end;
  if (not Rejected) or FileExists(InvalidPath) then
    raise Exception.Create('експорт допущений до виконання');
  BatchClick(Self);
  if (AnswerPhysical<>ReadPhysicalFile(ExpectedFile)) or
     (Pos('Виконано пакет D3: 4',Status.Caption)<>1) or
     (Pos('слово 1: 0',ResultMemo.Text)=0) or
     (Pos('слово 2: 000',ResultMemo.Text)=0) or
     (Pos('слово 5: 11',ResultMemo.Text)=0) then
    raise Exception.Create('D3 пакет не дав фізичний чотириформовий T5M');
  if not SaveButton.Enabled then
    raise Exception.Create('успішний пакет не відкрив кнопку експорту');
  Path:=ChangeFileExt(ExpectedFile,'')+'-експорт-пакета.sens';
  ExportAnswer(Path);
  if ReadPhysicalFile(Path)<>ReadPhysicalFile(ExpectedFile) then
    raise Exception.Create('експорт D3 змінив канонічну фізичну відповідь');
  Rejected:=False;
  try ExportAnswer(ExpectedFile);
  except on E:Exception do Rejected:=True; end;
  if (not Rejected) or
    (ReadPhysicalFile(ExpectedFile)<>ReadPhysicalFile(Path)) then
    raise Exception.Create('перезаписано існуючий фізичний файл');
  LinkPath:=ChangeFileExt(ExpectedFile,'')+'-симлінк.sens';
  Rejected:=False;
  try ExportAnswer(LinkPath);
  except on E:Exception do Rejected:=True; end;
  if (not Rejected) or
    (ReadPhysicalFile(LinkPath)<>ReadPhysicalFile(ExpectedFile)) then
    raise Exception.Create('перезаписано символічне посилання');
  Rejected:=False;
  try ExportAnswer(ChangeFileExt(Path,'.lisp'));
  except on E:Exception do Rejected:=True; end;
  if (not Rejected) or FileExists(ChangeFileExt(Path,'.lisp')) then
    raise Exception.Create('підміна машини текстовою .lisp');
  Rejected:=False;
  try ExportAnswer(ExtractFilePath(ExpectedFile)+'немає-такого-каталогу/result.sens');
  except on E:Exception do Rejected:=True; end;
  if not Rejected then
    raise Exception.Create('допущений експорт у відсутню директорію');
  if not LoadFile(LateBadFile) or (AnswerPhysical<>'') or
     (ResultMemo.Lines.Count<>0) then
    raise Exception.Create('нова фізична форма не очистила попередній пакет');
  BatchClick(Self);
  if (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) or
     SaveButton.Enabled or
     (Pos('форма 2, фізичне слово 2',Status.Caption)=0) then
    raise Exception.Create('пізня D3 відмова опублікувала часткові байти');
  if not LoadFile(TooManyFile) then
    raise Exception.Create('65 D1 коренів мають бути фізично припустимі');
  BatchClick(Self);
  if (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) or
     (Pos('Пакет D3 відхилено',Status.Caption)<>1) then
    raise Exception.Create('надмірний фізичний пакет прийнято');
  if LoadFile(BadFile) or BatchButton.Enabled or
     (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) then
    raise Exception.Create('неканонічні байти не очистили пакет D3');
  if not LoadFile(GoodFile) then
    raise Exception.Create('позитивний пакет не відновлено після негативів');
  BatchClick(Self);
  if AnswerPhysical<>ReadPhysicalFile(ExpectedFile) then
    raise Exception.Create('відновлений D3 пакет змінив фізичні байти');
  Retry:=ChangeFileExt(ExpectedFile,'')+'-повторний-експорт.sens';
  ExportAnswer(Retry);
  if ReadPhysicalFile(Retry)<>ReadPhysicalFile(ExpectedFile) then
    raise Exception.Create('відновлений експорт D3 змінив байти');
  WriteLn('LCL-ПАКЕТ-D3-ГАРАЗД форм=4 D2-крапка=точна',
    ' пізня-відмова=атомарна межа=64 відновлення=так',
    ' Lazarus=справжній експорт=побайтовий Core4=НЕ-ДОВЕДЕНО');
end;


begin
  Application.Initialize;
  Application.CreateForm(TExactIRWindow,Window);
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка-пакета') then begin
    if ParamCount<>6 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTestBatch(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6));
      Window.Free;
      Halt(0);
    except
      on E:Exception do begin
        WriteLn(StdErr,'LCL-ПАКЕТ-D3-ПОМИЛКА ',E.Message);
        Halt(1);
      end;
    end;
  end;
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка-виконання') then begin
    if (ParamCount<>7) and (ParamCount<>9) then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      if ParamCount=9 then
        Window.SelfTestExecution(ParamStr(2),ParamStr(3),
          ParamStr(4),ParamStr(5),ParamStr(6),ParamStr(7),
          ParamStr(8),ParamStr(9))
      else
        Window.SelfTestExecution(ParamStr(2),ParamStr(3),
          ParamStr(4),ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;
      Halt(0);
    except
      on E: Exception do begin
        WriteLn(StdErr,'LCL-D3-ВИКОНАННЯ-ПОМИЛКА ',E.Message);
        Halt(1);
      end;
    end;
  end;
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка') then begin
    if (ParamCount<>4) and (ParamCount<>5) then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      if ParamCount=5 then
        Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5))
      else
        Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4));
      Window.Free;
      Halt(0);
    except
      on E: Exception do begin
        WriteLn(StdErr,'LCL-ТОЧНЕ-IR-ПОМИЛКА ',E.Message);
        Halt(1);
      end;
    end;
  end;
  if ParamCount=1 then Window.LoadFile(ParamStr(1));
  Application.Run;
end.
