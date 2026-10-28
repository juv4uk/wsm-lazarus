{ Графічне дерево фізичної двійкової SENS. Мовні закони належать pinned SENS.
  Віджет лише показує перевірену структуру wsm.binarytree, не виконує форми. }
program sens_binary_tree;
{$mode objfpc}{$H+}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Dialogs, wsm.t5m, wsm.bind, wsm.domain, wsm.d2source,
  wsm.binarytree;

const MaxVisibleNodes = 4096;

type
  TBinaryTreeForm = class(TForm)
  private
    FTree: TTreeView;
    FDetails: TMemo;
    FStatus: TLabel;
    FDialog: TOpenDialog;
    FEntries: TBinaryTreeEntries;
    FNodes: array of TTreeNode;
    procedure OpenClicked(Sender: TObject);
    procedure SelectedClicked(Sender: TObject);
    procedure ClearView;
    procedure ShowSelection;
    procedure Demand(Condition: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadPhysicalFile(const FileName: String): Boolean;
    procedure SelfCheck(const GoodFile, PairFile, BadFile, LargeFile: String);
  end;

var
  MainWindow: TBinaryTreeForm;

constructor TBinaryTreeForm.Create(AOwner: TComponent);
var
  Toolbar, Footer, Body: TPanel;
  OpenButton, DetailsButton: TButton;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'SENS — графічне двійкове дерево';
  Width := 1020;
  Height := 660;
  Position := poScreenCenter;
  Toolbar := TPanel.Create(Self);
  Toolbar.Parent := Self;
  Toolbar.Align := alTop;
  Toolbar.Height := 50;
  Toolbar.BevelOuter := bvNone;
  OpenButton := TButton.Create(Self);
  OpenButton.Parent := Toolbar;
  OpenButton.Caption := 'Відкрити двійковий .sens…';
  OpenButton.SetBounds(12, 8, 230, 34);
  OpenButton.OnClick := @OpenClicked;
  DetailsButton := TButton.Create(Self);
  DetailsButton.Parent := Toolbar;
  DetailsButton.Caption := 'Показати точні координати';
  DetailsButton.SetBounds(252, 8, 250, 34);
  DetailsButton.OnClick := @SelectedClicked;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Title := 'Виберіть фізичний двійковий файл SENS';
  FDialog.Filter := 'Двійкові файли SENS|*.sens';
  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 37;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Footer;
  FStatus.SetBounds(12, 11, 985, 22);
  Body := TPanel.Create(Self);
  Body.Parent := Self;
  Body.Align := alClient;
  FDetails := TMemo.Create(Self);
  FDetails.Parent := Body;
  FDetails.Align := alRight;
  FDetails.Width := 400;
  FDetails.ReadOnly := True;
  FDetails.ScrollBars := ssVertical;
  FTree := TTreeView.Create(Self);
  FTree.Parent := Body;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.OnClick := @SelectedClicked;
  ClearView;
end;

procedure TBinaryTreeForm.Demand(Condition: Boolean; const Why: String);
begin
  if not Condition then
    raise Exception.Create('візуальна перевірка дерева: ' + Why);
end;

procedure TBinaryTreeForm.ClearView;
begin
  FTree.Items.Clear;
  SetLength(FEntries, 0);
  SetLength(FNodes, 0);
  FDetails.Clear;
  FStatus.Caption := 'Двійкова SENS; українська — проєкція; виконання відсутнє.';
end;

procedure TBinaryTreeForm.ShowSelection;
var
  Index: PtrUInt;
  E: TBinaryTreeEntry;
  Span: String;
begin
  FDetails.Clear;
  if FTree.Selected = nil then Exit;
  Index := PtrUInt(FTree.Selected.Data);
  if (Index = 0) or (Index > PtrUInt(Length(FEntries))) then
    raise Exception.Create('неприпустимий індекс графічного вузла');
  E := FEntries[Index-1];
  if E.HasPhysicalWord then
    Span := 'Слово №: ' + IntToStr(E.Physical.WordIndex) + LineEnding +
      'Трити [початок, кінець): ' + IntToStr(E.Physical.TritStart) +
      ', ' + IntToStr(E.Physical.TritEnd) + LineEnding +
      'Байти [початок, кінець): ' + IntToStr(E.Physical.ByteStart) +
      ', ' + IntToStr(E.Physical.ByteEnd)
  else
    Span := 'Похідна пара: власного фізичного слова/адреси немає';
  FDetails.Lines.Add('Структура: ' + String(BinaryTreeCaption(E)));
  FDetails.Lines.Add('Верхня форма: ' + IntToStr(E.RootIndex));
  FDetails.Lines.Add('Рівень: ' + IntToStr(E.Depth));
  FDetails.Lines.Add('Батько (індекс): ' + IntToStr(E.ParentIndex));
  FDetails.Lines.Add('Дитина (індекс): ' + IntToStr(E.ChildIndex));
  FDetails.Lines.Add('Опорне слово: ' + IntToStr(E.AnchorWordIndex));
  FDetails.Lines.Add(Span);
  if E.Kind in [dkIdentity, dkEmpty] then begin
    FDetails.Lines.Add('Домен: D' + IntToStr(E.Key.Width));
    FDetails.Lines.Add('Точні біти: ' + String(KeyBits(E.Key)));
    if E.Ukrainian <> '' then
      FDetails.Lines.Add('Проєкція ук: ' + String(E.Ukrainian))
    else
      FDetails.Lines.Add('Проєкція ук: немає');
  end else
    FDetails.Lines.Add('Структура D2, а не виклик');
  FDetails.Lines.Add('Семантична викличність: не доведено');
end;

procedure TBinaryTreeForm.SelectedClicked(Sender: TObject);
begin
  ShowSelection;
end;

function TBinaryTreeForm.LoadPhysicalFile(const FileName: String): Boolean;
var
  Stream: TFileStream;
  Physical: RawByteString;
  Tables: TDomainSet;
  Next: TBinaryTreeEntries;
  I: SizeInt;
  Parent: TTreeNode;
begin
  Result := False;
  ClearView;
  try
    if LowerCase(ExtractFileExt(FileName)) <> '.sens' then
      raise Exception.Create('потрібен фізичний файл .sens');
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size <= 0) or (Stream.Size > MAX_T5M_FILE_BYTES) then
        raise Exception.Create('порожній або надмірний фізичний файл');
      SetLength(Physical, SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1], Length(Physical));
    finally
      Stream.Free;
    end;
    LoadPinnedDomains('external/sens', Tables);
    ReadBinaryTree(Physical, Tables, Next);
    if (Length(Next) = 0) or (Length(Next) > MaxVisibleNodes) then
      raise Exception.Create('потрібно від 1 до 4096 видимих вузлів');
    { Спершу вся фізика, координати й межі; лише потім змінюємо дерево. }
    FTree.Items.BeginUpdate;
    try
      SetLength(FNodes, Length(Next));
      for I := 0 to High(Next) do begin
        if Next[I].ParentIndex = -1 then Parent := nil
        else begin
          if (Next[I].ParentIndex < 0) or (Next[I].ParentIndex >= I) then
            raise Exception.Create('порушено порядок батьківських вузлів');
          Parent := FNodes[Next[I].ParentIndex];
        end;
        FNodes[I] := FTree.Items.AddChild(Parent, String(BinaryTreeCaption(Next[I])));
        FNodes[I].Data := Pointer(PtrUInt(I+1));
      end;
      FEntries := Next;
    finally
      FTree.Items.EndUpdate;
    end;
    FTree.FullExpand;
    FStatus.Caption := 'Фізичних/структурних вузлів: ' +
      IntToStr(Length(FEntries)) + '; pinned SENS; виконання відсутнє.';
    Result := True;
  except
    on E: ED2SourceError do begin
      ClearView;
      FStatus.Caption := 'Помилка слова ' + IntToStr(E.WordIndex) + ': ' + E.Message;
    end;
    on E: Exception do begin
      ClearView;
      FStatus.Caption := 'Помилка: ' + E.Message;
    end;
  end;
end;

procedure TBinaryTreeForm.OpenClicked(Sender: TObject);
begin
  if FDialog.Execute then LoadPhysicalFile(FDialog.FileName);
end;

procedure TBinaryTreeForm.SelfCheck(const GoodFile, PairFile, BadFile, LargeFile: String);
var E: TBinaryTreeEntry;
begin
  Demand(LoadPhysicalFile(GoodFile), 'правильний двійковий вхід');
  Demand((Length(FEntries) = 4) and (FTree.Items.Count = 4),
    'список із трьома атомами повинен мати чотири вузли');
  Demand((FEntries[0].Kind = dkList) and (FEntries[0].Depth = 0),
    'структурний корінь D2');
  Demand((FEntries[1].ParentIndex = 0) and (FEntries[2].ParentIndex = 0)
    and (FEntries[3].ParentIndex = 0), 'діти структури');
  Demand((FEntries[1].Key.Width = 3) and
    (KeyBits(FEntries[1].Key) = '111') and
    (FEntries[1].Ukrainian = 'сполучити'), 'первинна D3:111');
  Demand((FEntries[2].Key.Width = 1) and
    (KeyBits(FEntries[2].Key) = '1'), 'первинна D1:1');
  Demand((FEntries[3].Kind = dkEmpty) and
    (KeyBits(FEntries[3].Key) = '000'), 'порожня D3:000');
  E := FEntries[3];
  Demand(E.Physical.TritEnd - E.Physical.TritStart = 3,
    'провідні нулі та ширина D3:000');
  FTree.Selected := FNodes[3];
  ShowSelection;
  Demand(Pos('D3', FDetails.Text) > 0, 'домен у вибраній клітинці');
  Demand(Pos('000', FDetails.Text) > 0, 'точні біти в подробицях');
  Demand(Pos('Трити [початок, кінець)', FDetails.Text) > 0,
    'фізичні трити у подробицях');
  Demand(LoadPhysicalFile(PairFile), 'правильна крапкова пара');
  Demand((Length(FEntries) = 3) and (FEntries[0].Kind = dkPair) and
    (not FEntries[0].HasPhysicalWord), 'похідна пара без фіктивного токена');
  FTree.Selected := FNodes[0];
  ShowSelection;
  Demand(Pos('власного фізичного слова/адреси немає', FDetails.Text) > 0,
    'заборонено фальшиву адресу пари');
  Demand(not LoadPhysicalFile(BadFile), 'пошкоджений T5M відхилено');
  Demand((FTree.Items.Count = 0) and (FDetails.Lines.Count = 0) and
    (Pos('Помилка', FStatus.Caption) = 1), 'після помилки старий екран лишився');
  Demand(not LoadPhysicalFile('відсутній.sens'), 'відсутній файл відхилено');
  Demand(FTree.Items.Count = 0, 'відсутній файл залишив вузли');
  Demand(not LoadPhysicalFile(LargeFile), 'межа 4096 вузлів');
  Demand(FTree.Items.Count = 0, 'великий файл залишив вузли');
  WriteLn('LCL-ДЕРЕВО-ГАРАЗД Lazarus=так дерево=справжнє ',
    'D2=структура D1_окремо_від_D3=так трити_байти=точні ',
    'пара=без_фальшивого_слова відмови=очищають виконання=ні');
end;

begin
  Application.Initialize;
  Application.Title := 'SENS — графічне двійкове дерево';
  Application.CreateForm(TBinaryTreeForm, MainWindow);
  if (ParamCount > 0) and (ParamStr(1) = '--самоперевірка') then begin
    if ParamCount <> 5 then Halt(64);
    try
      MainWindow.Show;
      Application.ProcessMessages;
      MainWindow.SelfCheck(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5));
    except on E: Exception do begin
      WriteLn(StdErr, 'LCL-ДЕРЕВО-ПОМИЛКА: ', E.Message);
      Halt(1);
    end; end;
  end else begin
    if ParamCount = 1 then MainWindow.LoadPhysicalFile(ParamStr(1));
    Application.Run;
  end;
end.
