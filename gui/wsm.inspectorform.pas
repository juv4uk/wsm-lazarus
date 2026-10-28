{ Інспектор фізичного SENS: лише LCL-подання вже наявних T5M/D2 механізмів.
  Не має evaluator, реєстру законів, текстового dispatch або перетворення
  української проєкції у двійковий канон. }
unit wsm.inspectorform;
{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, wsm.t5m, wsm.d2source;

type
  TInspectorForm = class(TForm)
  private
    FWords: TListBox;
    FTree: TTreeView;
    FStatus: TLabel;
    FReport: TStringList;
    FSourcePath: String;
    procedure OpenClicked(Sender: TObject);
    procedure ExportClicked(Sender: TObject);
    procedure AppendTree(const SourceNode: TD2Node; ParentNode: TTreeNode;
      var Displayed: SizeInt);
    procedure Populate(const Words: TExactWords; Doc: TD2Document;
      const Path: String; PhysicalSize: Int64);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure InspectFile(const Path: String);
    function WordCount: Integer;
    function RootCount: Integer;
    function WordCaption(Index: Integer): String;
    function CurrentPath: String;
    function Evidence: String;
  end;

implementation

const
  DisplayLimit = 4096;

constructor TInspectorForm.Create(AOwner: TComponent);
var
  Toolbar, LeftPane: TPanel;
  OpenButton, ExportButton: TButton;
  Heading: TLabel;
begin
  inherited CreateNew(AOwner, 1); { Жодного .lfm чи зашитих компонентів }
  Caption := 'SENS — інспектор двійкового потоку';
  Width := 1050;
  Height := 660;
  Position := poScreenCenter;
  FReport := TStringList.Create;

  Toolbar := TPanel.Create(Self);
  Toolbar.Parent := Self;
  Toolbar.Align := alTop;
  Toolbar.Height := 82;

  OpenButton := TButton.Create(Self);
  OpenButton.Parent := Toolbar;
  OpenButton.Caption := 'Відкрити .sens';
  OpenButton.SetBounds(12, 10, 150, 30);
  OpenButton.OnClick := @OpenClicked;

  ExportButton := TButton.Create(Self);
  ExportButton.Parent := Toolbar;
  ExportButton.Caption := 'Експортувати свідчення';
  ExportButton.SetBounds(175, 10, 215, 30);
  ExportButton.OnClick := @ExportClicked;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Toolbar;
  FStatus.Caption := 'Файл не відкрито. Відображення не виконує програм SENS.';
  FStatus.SetBounds(12, 48, 1000, 23);
  FStatus.AutoSize := True;

  LeftPane := TPanel.Create(Self);
  LeftPane.Parent := Self;
  LeftPane.Align := alLeft;
  LeftPane.Width := 460;
  LeftPane.Caption := '';

  Heading := TLabel.Create(Self);
  Heading.Parent := LeftPane;
  Heading.Align := alTop;
  Heading.Caption := '  Точні фізичні слова — індекс / домен-ширина / біти';
  Heading.Height := 26;

  FWords := TListBox.Create(Self);
  FWords.Parent := LeftPane;
  FWords.Align := alClient;

  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.ShowRoot := True;
end;

destructor TInspectorForm.Destroy;
begin
  FReport.Free;
  inherited Destroy;
end;

procedure TInspectorForm.AppendTree(const SourceNode: TD2Node;
  ParentNode: TTreeNode; var Displayed: SizeInt);
var
  CurrentNode: TTreeNode;
  LabelText: String;
  I: SizeInt;
begin
  if Displayed >= DisplayLimit then Exit;
  if SourceNode = nil then
    raise Exception.Create('некоректне дерево: порожній вузол');
  case SourceNode.Kind of
    dkList: LabelText := 'список D2';
    dkPair: LabelText := 'пара D2';
    dkEmpty: LabelText := 'порожня структура D3:000';
    dkIdentity: LabelText := 'точне слово D' + IntToStr(SourceNode.Width) +
       ':' + String(SourceNode.Bits);
    else raise Exception.Create('невідомий фізичний вузол');
  end;
  LabelText := LabelText + ' — слово №' + IntToStr(SourceNode.WordIndex);
  CurrentNode := FTree.Items.AddChild(ParentNode, LabelText);
  Inc(Displayed);
  for I := 0 to High(SourceNode.Children) do
    AppendTree(SourceNode.Children[I], CurrentNode, Displayed);
end;

procedure TInspectorForm.Populate(const Words: TExactWords;
  Doc: TD2Document; const Path: String; PhysicalSize: Int64);
var
  NewReport: TStringList;
  I, Rendered: SizeInt;
begin
  NewReport := TStringList.Create;
  try
    NewReport.Add('SENS — фізичне свідчення без семантичного виконання');
    NewReport.Add('Файл: ' + Path);
    NewReport.Add('Фізичні байти: ' + IntToStr(PhysicalSize));
    NewReport.Add('Слів: ' + IntToStr(Length(Words)));
    NewReport.Add('Кореневих структур: ' + IntToStr(Length(Doc.Roots)));
    for I := 0 to High(Words) do
      NewReport.Add('слово №' + IntToStr(I + 1) + ' D' +
        IntToStr(Length(Words[I])) + ':' + String(Words[I]));
    { Тільки після успішної DecodeT5M + ParseD2Words змінюємо вікно.
      Пошкоджений файл не стирає останній перевірений перегляд. }
    FWords.Items.BeginUpdate;
    FTree.Items.BeginUpdate;
    try
      FWords.Clear;
      FTree.Items.Clear;
      for I := 0 to High(Words) do begin
        if I >= DisplayLimit then Break;
        FWords.Items.Add('№' + IntToStr(I + 1) + '  D' +
          IntToStr(Length(Words[I])) + ':' + String(Words[I]));
      end;
      Rendered := 0;
      for I := 0 to High(Doc.Roots) do
        AppendTree(Doc.Roots[I], nil, Rendered);
      if (Length(Words) > DisplayLimit) or (Rendered >= DisplayLimit) then
        FTree.Items.AddChild(nil,
          'Видимий перегляд обмежено 4096 вузлами; експорт містить усі слова');
      FTree.FullExpand;
    finally
      FTree.Items.EndUpdate;
      FWords.Items.EndUpdate;
    end;
    FReport.Assign(NewReport);
    FSourcePath := Path;
    FStatus.Caption := 'Допущено фізичних байтів: ' +
      IntToStr(PhysicalSize) + '; слів: ' + IntToStr(Length(Words)) +
      '; форм: ' + IntToStr(Length(Doc.Roots)) + '; виконання: немає';
  finally
    NewReport.Free;
  end;
end;

procedure TInspectorForm.InspectFile(const Path: String);
var
  Physical: RawByteString;
  Stream: TFileStream;
  Words: TExactWords;
  Doc: TD2Document;
  Bytes: Int64;
begin
  if LowerCase(ExtractFileExt(Path)) <> '.sens' then
    raise Exception.Create('потрібен фізичний двійковий файл .sens');
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyNone);
  try
    Bytes := Stream.Size;
    if (Bytes < 1) or (Bytes > MAX_T5M_FILE_BYTES) then
      raise Exception.Create('порожній або завеликий двійковий файл');
    SetLength(Physical, SizeInt(Bytes));
    Stream.ReadBuffer(Physical[1], SizeInt(Bytes));
  finally
    Stream.Free;
  end;
  DecodeT5M(Physical, Words);
  Doc := ParseD2Words(Words);
  try
    Populate(Words, Doc, Path, Bytes);
  finally
    Doc.Free;
  end;
end;

procedure TInspectorForm.OpenClicked(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(Self);
  try
    Dialog.Title := 'Оберіть фізичний двійковий файл SENS';
    Dialog.Filter := 'Двійкові програми SENS|*.sens';
    if Dialog.Execute then
      try
        InspectFile(Dialog.FileName);
      except
        on E: ED2SourceError do
          MessageDlg('Помилка D2 у слові №' + IntToStr(E.WordIndex) +
            ': ' + E.Message, mtError, [mbOK], 0);
        on E: Exception do
          MessageDlg('Двійковий файл відхилено: ' + E.Message,
            mtError, [mbOK], 0);
      end;
  finally
    Dialog.Free;
  end;
end;

procedure TInspectorForm.ExportClicked(Sender: TObject);
var
  Dialog: TSaveDialog;
begin
  if FReport.Count = 0 then begin
    MessageDlg('Спочатку відкрийте перевірений .sens файл',
      mtInformation, [mbOK], 0);
    Exit;
  end;
  Dialog := TSaveDialog.Create(Self);
  try
    Dialog.Title := 'Зберегти механічне свідчення';
    Dialog.Filter := 'Текстове свідчення|*.txt';
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    if Dialog.Execute then
      try
        FReport.SaveToFile(Dialog.FileName);
      except
        on E: Exception do
          MessageDlg('Помилка експорту: ' + E.Message,
            mtError, [mbOK], 0);
      end;
  finally
    Dialog.Free;
  end;
end;

function TInspectorForm.WordCount: Integer;
begin Result := FWords.Items.Count; end;
function TInspectorForm.RootCount: Integer;
begin Result := FTree.Items.Count; end;
function TInspectorForm.WordCaption(Index: Integer): String;
begin Result := FWords.Items[Index]; end;
function TInspectorForm.CurrentPath: String;
begin Result := FSourcePath; end;
function TInspectorForm.Evidence: String;
begin Result := FReport.Text; end;

end.
