{ Графічне представлення ПРИВАТНОГО двійкового ExactIR.
  Єдиний власник IR: wsm.exactir з pinned механізмами SENS.
  Віджети не визначають мовних законів і не виконують SENS-форми. }
program exactirinspector;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Grids, Dialogs, wsm.t5m, wsm.domain, wsm.bind, wsm.exactir;

const MaxVisibleNodes = 16384;
type
  TExactIRWindow = class(TForm)
  private
    Tree: TTreeView;
    Table: TStringGrid;
    Status: TLabel;
    Detail: TLabel;
    OpenButton: TButton;
    Dialog: TOpenDialog;
    Links: array of TTreeNode;
    Current: TExactIR;
    procedure OpenClick(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure ClearView;
    procedure Fail(const Reason: String);
    procedure ValidateIR(const Candidate: TExactIR);
    procedure ShowIR(const Candidate: TExactIR);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const FileName: String): Boolean;
    procedure SelfTest(const GoodFile, PairFile, BadFile: String);
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
var TopBar, BottomBar, LeftPanel: TPanel; Split: TSplitter;
    I: Integer;
    Titles: array[0..7] of String = ('Вузол №', 'Вид', 'Корінь', 'Батько',
       'Домен', 'Точні біти', 'Трити', 'Байти');
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
var I, P, LeafCount: SizeInt; N: TExactIRNode;
begin
  if (Length(Candidate.Nodes) = 0) or
     (Length(Candidate.Nodes) > MaxVisibleNodes) or
     (Length(Candidate.Roots) = 0) then
    raise Exception.Create('неприпустима кількість вузлів у вікні');
  LeafCount := 0;
  for I := 0 to High(Candidate.Nodes) do begin
    N := Candidate.Nodes[I];
    if (N.RootIndex < 0) or (N.RootIndex >= Length(Candidate.Roots)) or
       (N.Depth < 0) or (N.Depth > MaxExactIRDepth) or
       (N.ChildIndex < 0) then
      raise Exception.Create('неприпустимий індекс вузла');
    P := N.ParentIndex;
    if P = -1 then begin
      if (N.Depth <> 0) or (Candidate.Roots[N.RootIndex] <> I) then
        raise Exception.Create('неправильне кореневе посилання');
    end else if (P < 0) or (P >= I) or
       (Candidate.Nodes[P].Depth+1 <> N.Depth) or
       (Candidate.Nodes[P].RootIndex <> N.RootIndex) then
      raise Exception.Create('неправильне посилання на батька');
    if N.Kind in [ikEmpty, ikIdentity] then begin
      if not N.HasKey then raise Exception.Create('доменний листок без ключа');
      if (N.Key.Width < 1) or (N.Key.Width > 9) or
         (N.Key.Width = 2) then
        raise Exception.Create('неприпустима ширина домену');
      Inc(LeafCount);
    end else if N.HasKey then
      raise Exception.Create('структурний вузол отримав ключ виклику');
  end;
  if LeafCount <> Candidate.BoundLeaves then
    raise Exception.Create('неправильна кількість зв’язаних листків');
end;

procedure TExactIRWindow.ShowIR(const Candidate: TExactIR);
var I: SizeInt; N: TExactIRNode; CaptionText, BitsText, Dom: String;
    Parent: TTreeNode;
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
      Parent := nil;
      if N.ParentIndex >= 0 then Parent := Links[N.ParentIndex];
      Links[I] := Tree.Items.AddChild(Parent, CaptionText);
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

  if not LoadFile(PairFile) then
    raise Exception.Create('позитивна пара: '+Status.Caption);
  if (Tree.Items.Count <> 5) or
     (Table.Cells[1,1] <> 'похідна пара') or
     (Table.Cells[6,1] <> '—') or
     (Table.Cells[7,1] <> '—') or
     (Table.Cells[1,3] <> 'похідна пара') or
     (Table.Cells[7,3] <> '—') then
    raise Exception.Create('вигадано фізичну адресу для похідної пари');
  if LoadFile(BadFile) then
    raise Exception.Create('зіпсований T5M прийнято');
  if (Tree.Items.Count<>0) or (Table.RowCount<>2) or
     (Table.Cells[0,1]<>'') or
     (Pos('Помилка',Status.Caption)<>1) then
    raise Exception.Create('застарілі вузли після помилки');
  if LoadFile('відсутній.sens') then
    raise Exception.Create('відсутній файл прийнято');
  if (Tree.Items.Count<>0) or (Table.Cells[0,1]<>'') then
    raise Exception.Create('залишився попередній IR після відмови');
  WriteLn('LCL-ТОЧНЕ-IR-ГАРАЗД дерево=справжнє таблиця=справжня ',
    'D1:0_не_D3:000=так трити-байти=точні пара=без-фальшивої-адреси ',
    'негативні=очищення виконання=НЕ-ДОВЕДЕНО');
end;

begin
  Application.Initialize;
  Application.CreateForm(TExactIRWindow,Window);
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
