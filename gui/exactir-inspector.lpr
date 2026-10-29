{ Приватне двійкове ExactIR та ОКРЕМО вузьке реальне D3 виконання.
  Дерево походить із wsm.exactir, виконання лише з pinned
  TBinaryExecutor: UI не містить власних SENS законів. }
program exactirinspector;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Grids, Dialogs, wsm.t5m, wsm.domain, wsm.bind,
  wsm.exactir, wsm.exactirguard, wsm.binaryexec;

const MaxVisibleNodes = 16384;
      MaxShownAnswerWords = 64;
type
  TExactIRWindow = class(TForm)
  private
    Tree: TTreeView;
    Table: TStringGrid;
    Status: TLabel;
    Detail: TLabel;
    OpenButton: TButton;
    EvidenceButton: TButton;
    RunButton: TButton;
    EvidenceMemo: TMemo;
    ResultMemo: TMemo;
    CurrentPhysical, AnswerPhysical: RawByteString;
    Dialog: TOpenDialog;
    Links: array of TTreeNode;
    Current: TExactIR;
    procedure OpenClick(Sender: TObject);
    procedure EvidenceClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    function MakeEvidence(const Candidate: TExactIR): RawByteString;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure ClearView;
    procedure Fail(const Reason: String);
    procedure ValidateIR(const Candidate: TExactIR);
    procedure ShowIR(const Candidate: TExactIR);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const FileName: String): Boolean;
    procedure SelfTest(const GoodFile, PairFile, BadFile: String);
    procedure SelfTestExecution(const QuoteFile, QuoteAnswer,
      ConsFile, ConsAnswer, BlockedFile, BadFile: String);
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
const Titles: array[0..7] of String = ('Вузол №', 'Вид', 'Корінь', 'Батько',
       'Домен', 'Точні біти', 'Трити', 'Байти');
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
  Dialog := TOpenDialog.Create(Self);
  Dialog.Title := 'Виберіть фізичну двійкову програму SENS';
  Dialog.Filter := 'Фізичні програми SENS (*.sens)|*.sens';

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

  LeftPanel := TPanel.Create(Self);
  LeftPanel.Parent := Self;
  LeftPanel.Align := alLeft;
  LeftPanel.Width := 345;
  LeftPanel.BevelOuter := bvNone;
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
  Table.ColCount := 8;
  Table.FixedCols := 0;
  Table.RowCount := 2;
  Table.FixedRows := 1;
  Table.Options := Table.Options + [goColSizing, goRowSelect];
  for I := 0 to 7 do Table.Cells[I,0] := Titles[I];
  Table.ColWidths[0] := 80;
  Table.ColWidths[1] := 128;
  Table.ColWidths[2] := 72;
  Table.ColWidths[3] := 75;
  Table.ColWidths[4] := 72;
  Table.ColWidths[5] := 100;
  Table.ColWidths[6] := 130;
  Table.ColWidths[7] := 130;
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
  RunButton.Enabled := False;
  CurrentPhysical := '';
  AnswerPhysical := '';
  ResultMemo.Clear;
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

{ G3.14. Це виклик вже наявного runtime, не lowering/виконання IR.
  Джерело — ТОЧНІ незмінні байти успішно завантаженого .sens;
  на відмові не видно ні одного байта минулої відповіді. }
procedure TExactIRWindow.RunClick(Sender: TObject);
var Engine: TBinaryExecutor; Candidate: RawByteString;
    Words: TExactWords; Lines: TStringList; I, Limit: SizeInt;
begin
  AnswerPhysical := '';
  ResultMemo.Clear;
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
    { Атомарна публікація канонічного результату ПІСЛЯ всіх guard. }
    ResultMemo.Lines.Assign(Lines);
    AnswerPhysical := Candidate;
    Status.Caption := 'Виконано вузький D3: фізична T5M відповідь';
  except
    on E: EBinaryExecutionError do begin
      AnswerPhysical := '';
      ResultMemo.Clear;
      Status.Caption := 'Виконання відхилено, фізичне слово '+
        IntToStr(E.WordIndex)+': '+E.Message;
    end;
    on E: Exception do begin
      AnswerPhysical := '';
      ResultMemo.Clear;
      Status.Caption := 'Виконання відхилено: '+E.Message;
    end;
  end;
  Lines.Free;
  Engine.Free;
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
  Tree.Selected := Links[0];
  TreeChange(Tree,Links[0]);
end;

procedure TExactIRWindow.TreeChange(Sender: TObject; Node: TTreeNode);
var I: SizeInt; N: TExactIRNode;
begin
  if Node = nil then Exit;
  I := PtrInt(Node.Data)-1;
  if (I < 0) or (I >= Length(Current.Nodes)) then Exit;
  N := Current.Nodes[I];
  Table.Row := I+1;
  Detail.Caption := 'Вузол '+IntToStr(I)+
    ' · корінь '+IntToStr(N.RootIndex)+
    ' · глибина '+IntToStr(N.Depth)+
    ' · фізичне слово '+IntToStr(N.WordIndex);
  if N.Kind = ikPair then Detail.Caption := Detail.Caption+
    ' · похідна пара: немає власного фізичного токена';
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
    Result := True;
  except
    on E: Exception do Fail(E.Message);
  end;
end;

procedure TExactIRWindow.OpenClick(Sender: TObject);
begin
  if Dialog.Execute then LoadFile(Dialog.FileName);
end;

procedure TExactIRWindow.SelfTest(const GoodFile, PairFile, BadFile: String);
var SavedEvidence: String; Tampered: TExactIR; Rejected: Boolean;
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
  if (Pos('слово 5',Detail.Caption)=0) or (Table.Row<>4) then
    raise Exception.Create('не працює вибір вузла IR у вікні');
  if not EvidenceButton.Enabled then
    raise Exception.Create('недоступне свідчення перевіреного IR');
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
  if (EvidenceMemo.Lines.Count <> 6) or
     (Pos('похідна пара',EvidenceMemo.Lines[1])=0) or
     (Pos(#9+'—'+#9+'—'+#9+'—'+#9+'—',EvidenceMemo.Lines[1])=0) then
    raise Exception.Create('похідна пара отримала підроблену TSV-адресу');
  if LoadFile(BadFile) then
    raise Exception.Create('зіпсований T5M прийнято');
  if (Tree.Items.Count<>0) or (Table.RowCount<>2) or
     (EvidenceMemo.Lines.Count<>0) or EvidenceButton.Enabled or
     (Table.Cells[0,1]<>'') or
     (Pos('Помилка',Status.Caption)<>1) then
    raise Exception.Create('застарілі вузли після помилки');
  if LoadFile('відсутній.sens') then
    raise Exception.Create('відсутній файл прийнято');
  if (Tree.Items.Count<>0) or (Table.Cells[0,1]<>'') or
     (EvidenceMemo.Lines.Count<>0) then
    raise Exception.Create('залишився попередній IR після відмови');
  WriteLn('LCL-ТОЧНЕ-IR-ГАРАЗД дерево=справжнє таблиця=справжня ',
    'D1:0_не_D3:000=так трити-байти=точні пара=без-фальшивої-адреси ',
    'негативні=очищення сторож=спільний TSV=відтворюваний виконання=НЕ-ДОВЕДЕНО');
end;

procedure TExactIRWindow.SelfTestExecution(
  const QuoteFile, QuoteAnswer, ConsFile, ConsAnswer,
  BlockedFile, BadFile: String);
var Saved:RawByteString;
begin
  { Доказ: два різні pinned механізми D3 дають не текстову
    проєкцію, а РЕАЛЬНІ канонічні bytes через один native API. }
  if not LoadFile(QuoteFile) or (not RunButton.Enabled) then
    raise Exception.Create('не допущено фізичну D3 цитату: '+Status.Caption);
  RunClick(Self);
  Saved := ReadPhysicalFile(QuoteAnswer);
  if (AnswerPhysical <> Saved) or
     (Pos('слово 1: 000',ResultMemo.Text)=0) or
     (Pos('слово 1: 0'+#13#10,ResultMemo.Text)>0) or
     (Pos('Виконано',Status.Caption)<>1) then
    raise Exception.Create('цитата D3 не виконана в канонічний T5M');
  if not LoadFile(ConsFile) or (AnswerPhysical<>'') or
     (ResultMemo.Lines.Count<>0) then
    raise Exception.Create('попередня фізична відповідь пережила нове .sens');
  RunClick(Self);
  Saved := ReadPhysicalFile(ConsAnswer);
  if (AnswerPhysical<>Saved) or
     (Pos('слово 3: 11',ResultMemo.Text)=0) then
    raise Exception.Create('виконаний D3:111 не повернув точну крапкову пару');
  if not LoadFile(BlockedFile) then
    raise Exception.Create('чинний D2 reader має приймати фізичну пару');
  RunClick(Self);
  if (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) or
     (Pos('Виконання відхилено',Status.Caption)<>1) or
     (Tree.Items.Count=0) then
    raise Exception.Create('заборонена вхідна D2 пара видала результат');
  if LoadFile(BadFile) or RunButton.Enabled or
     (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) then
    raise Exception.Create('зіпсований T5M залишив фізичну відповідь');
  if LoadFile('відсутній.sens') or RunButton.Enabled or
     (AnswerPhysical<>'') or (ResultMemo.Lines.Count<>0) then
    raise Exception.Create('неіснуючий .sens залишив фізичну відповідь');
  if not LoadFile(QuoteFile) then
    raise Exception.Create('здорову цитату не відновлено після негативів');
  RunClick(Self);
  if AnswerPhysical<>ReadPhysicalFile(QuoteAnswer) then
    raise Exception.Create('повторний фізичний D3 виклик не відновився');
  WriteLn('LCL-D3-ВИКОНАННЯ-ГАРАЗД quote=дійсний cons=дійсний',
    ' T5M=побайтовий D2-dot=збережено негативи=очищені',
    ' Core4=НЕ-ДОВЕДЕНО D12+=НЕ-ДОВЕДЕНО');
end;


begin
  Application.Initialize;
  Application.CreateForm(TExactIRWindow,Window);
  if (ParamCount>=1) and (ParamStr(1)='--самоперевірка-виконання') then begin
    if ParamCount<>7 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
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
    if ParamCount<>4 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
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
