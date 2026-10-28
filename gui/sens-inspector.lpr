{ Візуальний механічний інспектор SENS на Lazarus/LCL, без мовних законів. }
program sensinspector;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, ComCtrls, wsm.t5m, wsm.d2source, wsm.domain, wsm.bind,
  wsm.binarybind, wsm.binarytree;

const MaxVisibleWords = 16384;
      MaxVisibleNodes = 16384;
type
  TInspectorForm = class(TForm)
  private
    Grid: TStringGrid;
    Tree: TTreeView;
    Detail: TLabel;
    FEntries: TBinaryTreeEntries;
    Status: TLabel;
    OpenButton: TButton;
    Dialog: TOpenDialog;
    procedure OpenClick(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure CheckTree(const Entries: TBinaryTreeEntries);
    procedure ClearData;
    procedure Fail(const Reason: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const FileName: String): Boolean;
    procedure SmokeTest(const GoodFile, BadFile, PairFile, BadD2File: String);
  end;
var
  Window: TInspectorForm;

constructor TInspectorForm.Create(AOwner: TComponent);
var TopBar, BottomBar: TPanel;
    Divider: TSplitter;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — двійковий інспектор';
  Width := 1200;
  Height := 650;
  Position := poScreenCenter;
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 48;
  TopBar.BevelOuter := bvNone;
  OpenButton := TButton.Create(Self);
  OpenButton.Parent := TopBar;
  OpenButton.SetBounds(12, 8, 190, 32);
  OpenButton.Caption := 'Відкрити файл .sens…';
  OpenButton.OnClick := @OpenClick;
  Dialog := TOpenDialog.Create(Self);
  Dialog.Title := 'Оберіть двійковий файл SENS';
  Dialog.Filter := 'Двійкові файли SENS (*.sens)|*.sens';
  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 68;
  BottomBar.BevelOuter := bvNone;
  Status := TLabel.Create(Self);
  Status.Parent := BottomBar;
  Status.SetBounds(12, 8, 1140, 24);
  Status.Caption := 'Двійкова програма SENS. Викличність не перевіряється.';
  Detail := TLabel.Create(Self);
  Detail.Parent := BottomBar;
  Detail.SetBounds(12, 36, 1140, 24);
  Detail.Caption := 'Оберіть вузол для перегляду фізичних координат.';
  Tree := TTreeView.Create(Self);
  Tree.Parent := Self;
  Tree.Align := alLeft;
  Tree.Width := 410;
  Tree.ReadOnly := True;
  Tree.HideSelection := False;
  Tree.OnChange := @TreeChange;
  Divider := TSplitter.Create(Self);
  Divider.Parent := Self;
  Divider.Align := alLeft;
  Divider.Width := 6;
  Grid := TStringGrid.Create(Self);
  Grid.Parent := Self;
  Grid.Align := alClient;
  Grid.ColCount := 6;
  Grid.FixedCols := 0;
  Grid.RowCount := 2;
  Grid.FixedRows := 1;
  Grid.Options := Grid.Options + [goColSizing, goRowSelect];
  Grid.Cells[0,0] := 'Слово №';
  Grid.Cells[1,0] := 'Форма №';
  Grid.Cells[2,0] := 'Домен';
  Grid.Cells[3,0] := 'Точні біти';
  Grid.Cells[4,0] := 'Порожнє';
  Grid.Cells[5,0] := 'Українська (ук)';
  Grid.ColWidths[0] := 100;
  Grid.ColWidths[1] := 100;
  Grid.ColWidths[2] := 80;
  Grid.ColWidths[3] := 190;
  Grid.ColWidths[4] := 90;
  Grid.ColWidths[5] := 260;
  ClearData;
end;

procedure TInspectorForm.ClearData;
var J: Integer;
begin
  Tree.OnChange := nil;
  Tree.Items.Clear;
  SetLength(FEntries, 0);
  Tree.OnChange := @TreeChange;
  Grid.RowCount := 2;
  for J := 0 to Grid.ColCount - 1 do Grid.Cells[J,1] := '';
  Detail.Caption := 'Оберіть вузол для перегляду фізичних координат.';
end;

procedure TInspectorForm.Fail(const Reason: String);
begin
  ClearData;
  Status.Caption := 'Помилка: ' + Reason;
end;

procedure TInspectorForm.CheckTree(const Entries: TBinaryTreeEntries);
var I: SizeInt;
begin
  if (Length(Entries) < 1) or (Length(Entries) > MaxVisibleNodes) then
    raise Exception.Create('перевищено межу вузлів дерева');
  for I := 0 to High(Entries) do begin
    if (Entries[I].ParentIndex < -1) or (Entries[I].ParentIndex >= I) then
      raise Exception.Create('некоректний порядок батьків фізичного дерева');
    if (Entries[I].ParentIndex = -1) and (Entries[I].Depth <> 0) then
      raise Exception.Create('кореневий вузол має ненульову глибину');
    if (Entries[I].ParentIndex >= 0) and
       (Entries[I].Depth <> Entries[Entries[I].ParentIndex].Depth+1) then
      raise Exception.Create('некоректна глибина фізичного дерева');
  end;
end;

procedure TInspectorForm.TreeChange(Sender: TObject; Node: TTreeNode);
var I: SizeInt; Item: TBinaryTreeEntry;
begin
  if Node = nil then Exit;
  I := SizeInt(PtrUInt(Node.Data))-1;
  if (I < 0) or (I >= Length(FEntries)) then begin
    Detail.Caption := 'Вузол не має перевірених координат';
    Exit;
  end;
  Item := FEntries[I];
  Detail.Caption := 'Корінь '+IntToStr(Item.RootIndex)+
    ' · рівень '+IntToStr(Item.Depth)+
    ' · опорне слово '+IntToStr(Item.AnchorWordIndex);
  if Item.HasPhysicalWord then
    Detail.Caption := Detail.Caption+
      ' · трити ['+IntToStr(Item.Physical.TritStart)+','+
      IntToStr(Item.Physical.TritEnd)+')'+
      ' · байти ['+IntToStr(Item.Physical.ByteStart)+','+
      IntToStr(Item.Physical.ByteEnd)+')'
  else
    Detail.Caption := Detail.Caption+
      ' · похідна пара: немає окремого фізичного слова';
end;

function TInspectorForm.LoadFile(const FileName: String): Boolean;
var
  F: TFileStream;
  Physical, Surface: RawByteString;
  Tables: TDomainSet;
  Bound: TBinaryWords;
  CandidateTree: TBinaryTreeEntries;
  Nodes: array of TTreeNode;
  ParentNode: TTreeNode;
  I: SizeInt;
begin
  Result := False;
  ClearData;
  Status.Caption := 'Перевірка фізичного файлу…';
  try
    if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
      raise Exception.Create('очікується двійковий файл .sens');
    F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size <= 0) or (F.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або надто великий файл');
      SetLength(Physical, SizeInt(F.Size));
      F.ReadBuffer(Physical[1], Length(Physical));
    finally
      F.Free;
    end;
    LoadPinnedDomains('external/sens', Tables);
    BindT5MBinary(Physical, Tables, Bound);
    ReadBinaryTree(Physical, Tables, CandidateTree);
    CheckTree(CandidateTree);
    if Length(Bound) > MaxVisibleWords then
      raise Exception.Create('перевищено межу рядків вікна');
    { Жодна клітинка не оновлюється до повної перевірки вхідних даних. }
    Grid.RowCount := Length(Bound)+1;
    if Grid.RowCount < 2 then Grid.RowCount := 2;
    for I := 0 to High(Bound) do begin
      Grid.Cells[0,I+1] := IntToStr(Bound[I].WordIndex);
      Grid.Cells[1,I+1] := IntToStr(Bound[I].RootIndex);
      Grid.Cells[2,I+1] := 'D'+IntToStr(Bound[I].Key.Width);
      Grid.Cells[3,I+1] := String(KeyBits(Bound[I].Key));
      if Bound[I].IsEmpty then Grid.Cells[4,I+1] := 'так'
      else Grid.Cells[4,I+1] := 'ні';
      Surface := Bound[I].Ukrainian;
      if Surface = '' then Surface := '—';
      Grid.Cells[5,I+1] := String(Surface);
    end;
    SetLength(Nodes, Length(CandidateTree));
    Tree.Items.BeginUpdate;
    Tree.OnChange := nil;
    try
      FEntries := CandidateTree;
      for I := 0 to High(FEntries) do begin
        ParentNode := nil;
        if FEntries[I].ParentIndex >= 0 then
          ParentNode := Nodes[FEntries[I].ParentIndex];
        Nodes[I] := Tree.Items.AddChild(ParentNode,
          String(BinaryTreeCaption(FEntries[I])));
        Nodes[I].Data := Pointer(PtrUInt(I+1));
      end;
    finally
      Tree.Items.EndUpdate;
      Tree.OnChange := @TreeChange;
    end;
    Tree.Selected := Nodes[0];
    TreeChange(Tree, Nodes[0]);
    Status.Caption := 'Перевірено слів: '+IntToStr(Length(Bound))+
      ' · вузлів: '+IntToStr(Length(FEntries))+
      ' · pinned SENS · викличність не доведено';
    Result := True;
  except
    on E: ED2SourceError do
      Fail('слово '+IntToStr(E.WordIndex)+': '+E.Message);
    on E: Exception do Fail(E.Message);
  end;
end;

procedure TInspectorForm.OpenClick(Sender: TObject);
begin
  if Dialog.Execute then LoadFile(Dialog.FileName);
end;

procedure TInspectorForm.SmokeTest(
  const GoodFile, BadFile, PairFile, BadD2File: String);
begin
  if not LoadFile(GoodFile) then
    raise Exception.Create('позитивний вхід: '+Status.Caption);
  if (Grid.RowCount <> 4) or
     (Grid.Cells[2,1] <> 'D3') or (Grid.Cells[3,1] <> '111') or
     (Grid.Cells[5,1] <> 'сполучити') or
     (Grid.Cells[3,2] <> '1') or (Grid.Cells[5,2] <> 'так') or
     (Grid.Cells[3,3] <> '000') or (Grid.Cells[4,3] <> 'так') then
    raise Exception.Create('розбіжність клітинок LCL');
  if (Tree.Items.Count <> 4) or
     (FEntries[0].Kind <> dkList) or
     (FEntries[1].ParentIndex <> 0) or
     (Tree.Items[1].Parent <> Tree.Items[0]) or
     (FEntries[3].Kind <> dkEmpty) then
    raise Exception.Create('LCL дерево втратило D2 вкладеність');
  Tree.Selected := Tree.Items[3];
  TreeChange(Tree, Tree.Items[3]);
  if (Pos('трити [',Detail.Caption)=0) or
     (Pos('байти [',Detail.Caption)=0) then
    raise Exception.Create('немає фізичного інтервалу вибраного D3');

  if not LoadFile(PairFile) then
    raise Exception.Create('крапкова пара не прийнята: '+Status.Caption);
  if (Tree.Items.Count <> 6) or
     (FEntries[0].Kind <> dkPair) or
     FEntries[0].HasPhysicalWord or
     (FEntries[2].Kind <> dkPair) or
     FEntries[2].HasPhysicalWord or
     (Tree.Items[2].Parent <> Tree.Items[0]) then
    raise Exception.Create('похідну крапкову пару показано як токен');
  Tree.Selected := Tree.Items[0];
  TreeChange(Tree,Tree.Items[0]);
  if (Pos('немає окремого фізичного слова',Detail.Caption)=0) or
     (Pos('трити [',Detail.Caption)<>0) then
    raise Exception.Create('похідній парі вигадано фізичну адресу');

  if LoadFile(BadD2File) then
    raise Exception.Create('незакритий D2 прийнято');
  if (Tree.Items.Count <> 0) or (Grid.Cells[0,1] <> '') or
     (Pos('Помилка:',Status.Caption)<>1) then
    raise Exception.Create('D2 помилка залишила часткові дані');
  if LoadFile(BadFile) then
    raise Exception.Create('пошкоджений T5M прийнято');
  if (Tree.Items.Count <> 0) or (Grid.RowCount <> 2) or
     (Pos('Помилка:',Status.Caption)<>1) then
    raise Exception.Create('T5M помилка залишила старе дерево');
  if LoadFile('відсутній.sens') then
    raise Exception.Create('відсутній файл прийнято');
  if (Tree.Items.Count <> 0) or (Grid.Cells[0,1] <> '') or
     (Pos('Помилка:',Status.Caption)<>1) then
    raise Exception.Create('відсутній файл залишив старі дані');
  WriteLn('LCL-ДЕРЕВО-ГАРАЗД TTreeView=справжній вкладеність=так '+
    'адреси=фізичні крапкові-пари=похідні негативні=відхилено');
end;

begin
  Application.Initialize;
  Application.CreateForm(TInspectorForm, Window);
  if (ParamCount >= 1) and (ParamStr(1) = '--самоперевірка') then begin
    if ParamCount <> 5 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SmokeTest(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5));
      Window.Free;
      Halt(0);
    except on E: Exception do begin
      WriteLn(StdErr, 'LCL-ІНСПЕКТОР-ПОМИЛКА ', E.Message);
      Halt(1);
    end; end;
  end;
  if ParamCount = 1 then Window.LoadFile(ParamStr(1));
  Application.Run;
end.
