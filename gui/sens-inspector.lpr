{ Візуальний механічний інспектор SENS на Lazarus/LCL, без мовних законів. }
program sensinspector;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, ComCtrls, wsm.t5m, wsm.d2source, wsm.domain,
  wsm.bind, wsm.binarybind, wsm.binarytree, wsm.proektsii;

const MaxVisibleWords = 16384;
type
  TInspectorForm = class(TForm)
  private
    Grid: TStringGrid;
    Tree: TTreeView;
    SurfaceMemo: TMemo;
    FProjections: TProektsiiCatalog;
    FTree: TBinaryTreeEntries;
    FBound: TBinaryWords;
    FRowNodes: array of TTreeNode; { рядок фізичного слова → вже належний Tree.Items вузол }
    FSyncSelection: Boolean; { лише host LCL guard від рекурсії подій }
    Status: TLabel;
    OpenButton: TButton;
    Dialog: TOpenDialog;
    procedure OpenClick(Sender: TObject);
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure GridSelectCell(Sender: TObject; ACol, ARow: Longint;
      var CanSelect: Boolean);
    procedure DisplayNodeSurfaces(const Entry:TBinaryTreeEntry);
    procedure ClearData;
    procedure Fail(const Reason: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const FileName: String): Boolean;
    procedure SmokeTest(const GoodFile, BadFile, PairFile, SameByteFile: String);
  end;
var
  Window: TInspectorForm;

constructor TInspectorForm.Create(AOwner: TComponent);
var TopBar, BottomBar, TreePanel: TPanel;
    Splitter: TSplitter;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — двійковий інспектор';
  Width := 990;
  Height := 560;
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
  BottomBar.Height := 42;
  BottomBar.BevelOuter := bvNone;
  Status := TLabel.Create(Self);
  Status.Parent := BottomBar;
  Status.SetBounds(12, 10, 900, 24);
  Status.Caption := 'Двійкова програма SENS. Викличність не перевіряється.';
  TreePanel := TPanel.Create(Self);
  TreePanel.Parent := Self;
  TreePanel.Align := alLeft;
  TreePanel.Width := 340;
  TreePanel.Caption := '';
  TreePanel.BevelOuter := bvNone;
  Tree := TTreeView.Create(Self);
  Tree.Parent := TreePanel;
  Tree.Align := alClient;
  Tree.ReadOnly := True;
  Tree.HideSelection := False;
  Tree.OnChange := @TreeChange;
  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Align := alLeft;
  Splitter.Width := 6;
  Grid := TStringGrid.Create(Self);
  Grid.Parent := Self;
  Grid.Align := alClient;
  Grid.ColCount := 6;
  Grid.FixedCols := 0;
  Grid.RowCount := 2;
  Grid.FixedRows := 1;
  Grid.Options := Grid.Options + [goColSizing, goRowSelect];
  Grid.OnSelectCell := @GridSelectCell;
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
  { Шість pinned проєкцій конкретного фізичного вузла D2, не
    загальний D7 редактор і не список викличних голів. }
  SurfaceMemo := TMemo.Create(Self);
  SurfaceMemo.Parent := Self;
  SurfaceMemo.Align := alBottom;
  SurfaceMemo.Height := 172;
  SurfaceMemo.ReadOnly := True;
  SurfaceMemo.ScrollBars := ssVertical;
  SurfaceMemo.WordWrap := False;
  ClearData;
end;

procedure TInspectorForm.ClearData;
var J, D: Integer;
begin
  { Скидаємо запозичені TTreeNode-посилання ДО звільнення Tree.Items.
    При перезавантаженні Grid може надсилати OnSelectCell синхронно. }
  FSyncSelection := True;
  try
    SetLength(FRowNodes, 0);
    Tree.Items.Clear;
    for D := 1 to 10 do SetLength(FProjections[D],0);
    SurfaceMemo.Clear;
    SetLength(FTree, 0);
    SetLength(FBound, 0);
    Grid.RowCount := 2;
    for J := 0 to Grid.ColCount - 1 do Grid.Cells[J,1] := '';
  finally
    FSyncSelection := False;
  end;
end;

{ Поверхня — лише pinned рядок уже перевіреної exact-координати.
  TProektsiiaRow не володіє виконуваним значенням; масив рядків
  живе у FProjections до наступного LoadFile / ClearData. }
procedure TInspectorForm.DisplayNodeSurfaces(const Entry:TBinaryTreeEntry);
const
  Names: array[0..5] of String = ('ук','укр','san','en','LISP','sym');
var
  D,J,Index:SizeInt;
  R:TProektsiiaRow;
begin
  SurfaceMemo.Clear;
  if not (Entry.Kind in [dkIdentity,dkEmpty]) then begin
    SurfaceMemo.Lines.Add('Структурний D2-вузол: власної мовної координати немає.');
    Exit;
  end;
  D:=Entry.Key.Width;
  if (D<1) or (D>10) then
    raise Exception.Create('Поза підтриманими pinned-проєкціями D1–D10');
  Index:=Entry.Key.Bits;
  if (Index<0) or (Index>=Length(FProjections[D])) then
    raise Exception.Create('Не завантажено exact pinned координату');
  R:=FProjections[D][Index];
  if not SameKey(Entry.Key,R.Key) then
    raise Exception.Create('Фізичний ключ не збігається з pinned таблицею');
  SurfaceMemo.Lines.BeginUpdate;
  try
    SurfaceMemo.Lines.Add('D'+IntToStr(D)+':'+String(KeyBits(Entry.Key))+
      ' · шість людських проєкцій, не викличність');
    for J:=0 to 5 do
      SurfaceMemo.Lines.Add(Names[J]+': '+SurfaceForDisplay(R.Surface[J]));
  finally SurfaceMemo.Lines.EndUpdate end;
end;

{ Вхід: 1-based рядок UI, запозичений TTreeNode належить Tree.Items.
  Не є семантичним пошуком за укр/en: mapping побудовано з exact T5M.
  Коли дерево не завантажено, нічого не обираємо. }
procedure TInspectorForm.GridSelectCell(Sender: TObject; ACol, ARow: Longint;
  var CanSelect: Boolean);
var Node: TTreeNode;
begin
  if not CanSelect or FSyncSelection or (ARow < 1) or
     (ARow >= Length(FRowNodes)) then Exit;
  Node := FRowNodes[ARow];
  if Node = nil then begin
    CanSelect := False;
    Exit;
  end;
  FSyncSelection := True;
  try
    Tree.Selected := Node;
  finally
    FSyncSelection := False;
  end;
  { Без залежності від того, чи GTK2 послав OnChange при повторному виборі. }
  TreeChange(Tree, Node);
end;

procedure TInspectorForm.TreeChange(Sender: TObject; Node: TTreeNode);
var I, J: SizeInt;
    Entry: TBinaryTreeEntry;
begin
  if (Node = nil) or FSyncSelection then Exit;
  I := SizeInt(PtrUInt(Node.Data)) - 1;
  if (I < 0) or (I >= Length(FTree)) then Exit;
  Entry := FTree[I];
  DisplayNodeSurfaces(Entry);
  if Entry.HasPhysicalWord then begin
    Status.Caption := String(BinaryTreeCaption(Entry)) +
      ' · слово №' + IntToStr(Entry.AnchorWordIndex) +
      ' · трити=[' + IntToStr(Entry.Physical.TritStart) + ',' +
      IntToStr(Entry.Physical.TritEnd) + ')' +
      ' · байти=[' + IntToStr(Entry.Physical.ByteStart) + ',' +
      IntToStr(Entry.Physical.ByteEnd) + ')';
    if Entry.Kind in [dkIdentity, dkEmpty] then
      for J := 0 to High(FBound) do
        if FBound[J].WordIndex = Entry.AnchorWordIndex then begin
          FSyncSelection := True;
          try
            Grid.Row := J + 1;
          finally
            FSyncSelection := False;
          end;
          Break;
        end;
  end else
    Status.Caption := String(BinaryTreeCaption(Entry)) +
      ' · без власного фізичного слова T5M';
end;

procedure TInspectorForm.Fail(const Reason: String);
begin
  ClearData;
  Status.Caption := 'Помилка: ' + Reason;
end;

function TInspectorForm.LoadFile(const FileName: String): Boolean;
var
  F: TFileStream;
  Physical, Surface: RawByteString;
  Tables: TDomainSet;
  ProjectionCatalog:TProektsiiCatalog;
  Bound: TBinaryWords;
  Entries: TBinaryTreeEntries;
  Nodes: array of TTreeNode;
  CandidateRowNodes: array of TTreeNode;
  I, J, Lo, Hi, Mid, MatchedRow: SizeInt;
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
    LoadPinnedProjections('external/sens', ProjectionCatalog);
    BindT5MBinary(Physical, Tables, Bound);
    ReadBinaryTree(Physical, Tables, Entries);
    if Length(Entries) > 2 * MaxVisibleWords then
      raise Exception.Create('перевищено межу вузлів вікна');
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
    FBound := Bound;
    FTree := Entries;
    FProjections := ProjectionCatalog;
    SetLength(Nodes, Length(FTree));
    Tree.Items.BeginUpdate;
    try
      for I := 0 to High(FTree) do begin
        if FTree[I].ParentIndex = -1 then
          Nodes[I] := Tree.Items.Add(nil, String(BinaryTreeCaption(FTree[I])))
        else begin
          if (FTree[I].ParentIndex < 0) or
             (FTree[I].ParentIndex >= I) then
            raise Exception.Create('неправильний батьківський індекс дерева');
          Nodes[I] := Tree.Items.AddChild(Nodes[FTree[I].ParentIndex],
            String(BinaryTreeCaption(FTree[I])));
        end;
        Nodes[I].Data := Pointer(PtrUInt(I + 1));
      end;
      Tree.FullExpand;
      { Тільки реальні фізичні листки мають таблицю; D2 OPEN та
        похідні dkPair не стають штучним domain-key.
        G2.38 гарантує суворий фізичний порядок bound-атомів:
        lookup за 1-based WordIndex без квадратичного перегляду. }
      SetLength(CandidateRowNodes, Length(Bound) + 1);
      for I := 0 to High(FTree) do
        if FTree[I].Kind in [dkIdentity, dkEmpty] then begin
          Lo := 0;
          Hi := High(Bound);
          MatchedRow := -1;
          while Lo <= Hi do begin
            Mid := Lo + (Hi - Lo) div 2;
            if Bound[Mid].WordIndex = FTree[I].AnchorWordIndex then begin
              MatchedRow := Mid + 1;
              Break;
            end;
            if Bound[Mid].WordIndex < FTree[I].AnchorWordIndex then
              Lo := Mid + 1
            else
              Hi := Mid - 1;
          end;
          if (MatchedRow < 1) or
             (FTree[I].Physical.WordIndex <> FTree[I].AnchorWordIndex) or
             (FTree[I].RootIndex <> Bound[MatchedRow - 1].RootIndex) or
             not SameKey(FTree[I].Key, Bound[MatchedRow - 1].Key) or
             ((FTree[I].Kind = dkEmpty) <> Bound[MatchedRow - 1].IsEmpty) or
             (CandidateRowNodes[MatchedRow] <> nil) then
            raise Exception.Create('порушено точне зв’язування рядка й D2-листка');
          CandidateRowNodes[MatchedRow] := Nodes[I];
        end;
      for J := 1 to High(CandidateRowNodes) do
        if CandidateRowNodes[J] = nil then
          raise Exception.Create('фізичне слово не має власного D2-листка');
      { Посилання належать Tree.Items; масив лише запозичує їх до ClearData. }
      FRowNodes := CandidateRowNodes;
    finally
      Tree.Items.EndUpdate;
    end;
    Status.Caption := 'Перевірено слів: '+IntToStr(Length(Bound))+
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

procedure TInspectorForm.SmokeTest(const GoodFile, BadFile, PairFile,
  SameByteFile: String);
var CanSelect: Boolean;
begin
  if not LoadFile(GoodFile) then
    raise Exception.Create('позитивний вхід: '+Status.Caption);
  if (Grid.RowCount <> 4) or
     (Grid.Cells[2,1] <> 'D3') or (Grid.Cells[3,1] <> '111') or
     (Grid.Cells[5,1] <> 'сполучити') or
     (Grid.Cells[3,2] <> '1') or (Grid.Cells[5,2] <> 'так') or
     (Grid.Cells[3,3] <> '000') or (Grid.Cells[4,3] <> 'так') then
    raise Exception.Create('розбіжність справжніх LCL-клітинок');
  if (Tree.Items.Count <> 4) or
     (Tree.Items[1].Parent <> Tree.Items[0]) or
     (Tree.Items[3].Parent <> Tree.Items[0]) or
     (FTree[3].Kind <> dkEmpty) or
     (Pos('порожня структура D3:000', Tree.Items[3].Text) = 0) then
    raise Exception.Create('помилкова ієрархія фізичного дерева D2');
  TreeChange(Tree, Tree.Items[3]);
  if (SurfaceMemo.Lines.Count<>7) or
     (Pos('D3:000',SurfaceMemo.Lines[0])<>1) or
     (SurfaceMemo.Lines[1]<>'ук: (відсутня)') or
     (SurfaceMemo.Lines[2]<>'укр: (відсутня)') or
     (SurfaceMemo.Lines[5]<>'LISP: (відсутня)') then
    raise Exception.Create('D3:000 втратило окремі шість pinned поверхонь');
  TreeChange(Tree,Tree.Items[1]); { точний D3:111, НЕ текстовий dispatch }
  if (SurfaceMemo.Lines.Count<>7) or
     (Pos('D3:111',SurfaceMemo.Lines[0])<>1) or
     (SurfaceMemo.Lines[1]<>'ук: сполучити') or
     (SurfaceMemo.Lines[2]<>'укр: сполучити') or
     (SurfaceMemo.Lines[3]<>'san: saṃyuj') or
     (SurfaceMemo.Lines[4]<>'en: cons') or
     (SurfaceMemo.Lines[5]<>'LISP: CONS') or
     (SurfaceMemo.Lines[6]<>'sym: +:') then
    raise Exception.Create('D3:111 втратив pinned шість окремих колонок');
  TreeChange(Tree, Tree.Items[3]);
  if (Grid.Row <> 3) or
     (Pos('трити=[', Status.Caption) = 0) or
     (Pos('байти=[', Status.Caption) = 0) then
    raise Exception.Create('вибір дерева не вказав на фізичне слово');

  { Фізична таблиця → дерево. Справжні LCL TTreeNode, TStringGrid:
    не порівнюємо українські назви, шукаємо тільки WordIndex. }
  CanSelect := True;
  GridSelectCell(Grid, 0, 1, CanSelect);
  if not CanSelect or (Tree.Selected <> Tree.Items[1]) or
     (Grid.Row <> 1) or
     (Pos('D3:111', SurfaceMemo.Lines[0]) <> 1) or
     (Pos('слово №2', Status.Caption) = 0) then
    raise Exception.Create('точний рядок №1 не показав D3:111 у дереві');
  CanSelect := True;
  GridSelectCell(Grid, 0, 3, CanSelect);
  if not CanSelect or (Tree.Selected <> Tree.Items[3]) or
     (Pos('D3:000', SurfaceMemo.Lines[0]) <> 1) then
    raise Exception.Create('рядок №3 не показав окреме D3:000');
  CanSelect := True;
  GridSelectCell(Grid, 0, 0, CanSelect);
  if Tree.Selected <> Tree.Items[3] then
    raise Exception.Create('заголовок не має фізичної адреси');

  if not LoadFile(PairFile) then
    raise Exception.Create('крапкова пара: '+Status.Caption);
  if (Tree.Items.Count <> 6) or
     FTree[0].HasPhysicalWord or FTree[2].HasPhysicalWord or
     (Tree.Items[2].Parent <> Tree.Items[0]) then
    raise Exception.Create('похідні вузли пар мають хибну адресу');
  TreeChange(Tree, Tree.Items[0]);
  if (SurfaceMemo.Lines.Count<>1) or
     (Pos('власної мовної координати немає',SurfaceMemo.Lines[0])=0) then
    raise Exception.Create('похідна пара отримала вигадану проєкцію');
  if Pos('без власного фізичного слова', Status.Caption) = 0 then
    raise Exception.Create('вузлу крапкової пари вигадано T5M адресу');
  CanSelect := True;
  GridSelectCell(Grid, 0, 1, CanSelect);
  if not CanSelect or (Tree.Selected <> Tree.Items[1]) or
     (FTree[0].HasPhysicalWord) or
     (Pos('фізичне', Status.Caption) <> 0) then
    raise Exception.Create('рядок крапкової пари послав на синтетичну опору');

  { Два різні exact D1 слова у ТОМУ САМОМУ T5M байті.
    Збіг ByteStart не є ідентичністю; тритове зміщення та
    WordIndex однозначно прив’язують кожний листок. }
  if not LoadFile(SameByteFile) then
    raise Exception.Create('два слова в одному байті: '+Status.Caption);
  if (Grid.RowCount <> 3) or (Tree.Items.Count <> 2) or
     (Length(FRowNodes) <> 3) or
     (FTree[0].Physical.ByteStart <> FTree[1].Physical.ByteStart) or
     (FTree[0].Physical.TritStart <> 0) or
     (FTree[1].Physical.TritStart <> 2) then
    raise Exception.Create('два незалежні слова одного T5M байта переплутані');
  CanSelect := True;
  GridSelectCell(Grid, 0, 2, CanSelect);
  if not CanSelect or (Tree.Selected <> Tree.Items[1]) or
     (Pos('D1:1',SurfaceMemo.Lines[0]) <> 1) or
     (Pos('слово №2',Status.Caption) = 0) then
    raise Exception.Create('друге фізичне слово одного байта загублено');
  Tree.Selected := Tree.Items[0]; { дерево → фізичний grid-рядок }
  TreeChange(Tree,Tree.Items[0]);
  if (Grid.Row <> 1) or
     (Pos('D1:0',SurfaceMemo.Lines[0]) <> 1) or
     (Pos('слово №1',Status.Caption) = 0) then
    raise Exception.Create('зворотний вибір першого D1 у спільному байті');

  if LoadFile(BadFile) then
    raise Exception.Create('некоректний T5M прийнято');
  if (Grid.RowCount <> 2) or (Grid.Cells[0,1] <> '') or
     (Tree.Items.Count <> 0) or (Length(FRowNodes) <> 0) or
     (SurfaceMemo.Lines.Count<>0) or
     (Pos('Помилка:', Status.Caption) <> 1) then
    raise Exception.Create('помилка залишила часткові результати');
  if LoadFile('відсутній.sens') then
    raise Exception.Create('відсутній файл прийнято');
  if (Grid.Cells[0,1] <> '') or (Tree.Items.Count <> 0) or
     (Length(FRowNodes) <> 0) or
     (SurfaceMemo.Lines.Count<>0) or
     (Pos('Помилка:', Status.Caption) <> 1) then
    raise Exception.Create('відсутній файл залишив старі клітинки');
  if not LoadFile(GoodFile) then
    raise Exception.Create('після відмови дерево не відновлюється');
  CanSelect := True;
  GridSelectCell(Grid,0,2,CanSelect);
  if not CanSelect or (Tree.Selected <> Tree.Items[2]) or
     (Pos('D1:1', SurfaceMemo.Lines[0]) <> 1) then
    raise Exception.Create('після відмови залишилась стара відповідність рядків');
  WriteLn('LCL-ДЕРЕВО-НАВІГАЦІЯ-ГАРАЗД GTK2=так рядок-до-дерева=так', 
    ' дерево-до-рядка=так спільний-байт=2 похідні-пари=без-підміни',
    ' негативи=очищені відновлення=так');
  WriteLn('LCL-ДЕРЕВО-ПРОЄКЦІЇ-ГАРАЗД GTK2=так pinned=6 D3:111=точно', 
    ' D3:000=окремо пара=без-координати відмови=очищено');
  WriteLn('LCL-ДЕРЕВО-ГАРАЗД GTK2=так дерево=справжнє вибір-тритів=так пари=похідні негативні=очищають');
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
