{ Візуальна карта лише наявних SENS файлів. Без мовної семантики.
  FPaths містить власні повні host-шляхи до обмеженого переліку файлів;
  LCL-компоненти належать формі та звільняються разом із нею.
  Д7 є текстовою проєкцією, а не способом обрати машинний закон.
  1) Чому карта не виконує вміст .sens?
  2) Чому в карті немає елементів «GC готовий» чи «Core4 готовий»?
  3) Чому обирати корінь можна, а відносний шлях до файлу — ні?
  4) Хто володіє FPaths і контролами форми? }
unit sens_ide_window;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, Dialogs, ExtCtrls;
type
  TSensPathOpen = procedure(const Path:String) of object;
  TSensMapWindow = class(TForm)
  private
    FRoot:String;
    FPaths:TStringList;
    FList:TListView;
    FStatus:TLabel;
    FChoose,FOpen:TButton;
    FOnOpenPath:TSensPathOpen;
    procedure Rebuild;
    procedure AddEntry(const Title,RelativePath,Description:String);
    procedure ChooseClick(Sender:TObject);
    procedure OpenClick(Sender:TObject);
    procedure ItemDoubleClick(Sender:TObject);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    function SetRepositoryRoot(const Path:String):Boolean;
    function OpenEntry(Index:Integer):Boolean;
    function EntryCount:Integer;
    function EntryPath(Index:Integer):String;
    property OnOpenPath:TSensPathOpen read FOnOpenPath write FOnOpenPath;
  end;
implementation

constructor TSensMapWindow.Create(AOwner:TComponent);
var TopPanel:TPanel;Col:TListColumn;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — мапа фізичного проєкту';
  Width:=980;Height:=590;Position:=poScreenCenter;
  FPaths:=TStringList.Create;
  TopPanel:=TPanel.Create(Self);TopPanel.Parent:=Self;
  TopPanel.Align:=alTop;TopPanel.Height:=64;
  FChoose:=TButton.Create(Self);FChoose.Parent:=TopPanel;
  FChoose.SetBounds(12,12,235,36);
  FChoose.Caption:='Обрати корінь проєкту SENS';
  FChoose.OnClick:=@ChooseClick;
  FOpen:=TButton.Create(Self);FOpen.Parent:=TopPanel;
  FOpen.SetBounds(266,12,240,36);
  FOpen.Caption:='Відкрити вибране в Lazarus';
  FOpen.OnClick:=@OpenClick;
  FList:=TListView.Create(Self);FList.Parent:=Self;
  FList.Align:=alClient;FList.ViewStyle:=vsReport;
  FList.RowSelect:=True;FList.ReadOnly:=True;FList.HideSelection:=False;
  FList.OnDblClick:=@ItemDoubleClick;
  Col:=FList.Columns.Add;Col.Caption:='Інструмент / джерело';Col.Width:=300;
  Col:=FList.Columns.Add;Col.Caption:='На диску';Col.Width:=115;
  Col:=FList.Columns.Add;Col.Caption:='Файл і фактична межа';Col.Width:=525;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.Align:=alBottom;FStatus.Height:=34;
  FStatus.Caption:='Оберіть каталог репозиторію; мапа не запускає жодних програм.';
  FOpen.Enabled:=True;
  if GetEnvironmentVariable('SENS_REPO_ROOT')<>'' then
    SetRepositoryRoot(GetEnvironmentVariable('SENS_REPO_ROOT'));
end;

destructor TSensMapWindow.Destroy;
begin
  FPaths.Free;
  inherited Destroy;
end;

{ За відносним шляхом існує лише вбудований allowlist справжніх файлів,
  а не довільний користувацький шлях. Status — лише наявність на диску,
  НЕ результат CI або дозвіл виклику координати. }
procedure TSensMapWindow.AddEntry(
  const Title,RelativePath,Description:String);
var Item:TListItem;FullPath:String;
begin
  FullPath:=FRoot+RelativePath;
  FPaths.Add(FullPath);
  Item:=FList.Items.Add;
  Item.Caption:=Title;
  if FileExists(FullPath) then Item.SubItems.Add('файл є')
  else Item.SubItems.Add('відсутній');
  Item.SubItems.Add(RelativePath+' — '+Description);
end;

procedure TSensMapWindow.Rebuild;
begin
  FList.Items.BeginUpdate;
  try
    FPaths.Clear;
    FList.Items.Clear;
    if FRoot='' then Exit;
    AddEntry('Фізичний SENS Core1','external/sens/lib/core1.sens',
      'канонічні T5M; сам файл не доводить повний runtime');
    AddEntry('Українська проєкція Core1','external/sens/lib/core1.lisp',
      'укр; не канонічне машинне джерело');
    AddEntry('Фізичний SENS Core4','external/sens/lib/core4.sens',
      'канонічні T5M; завантаження окремо');
    AddEntry('Точні домени','external/sens/contracts/language-contract-12.lisp',
      'тільки pinned закони SENS 12.0');
    AddEntry('Компілятор WideIR','src/wsm.irwidefront.pas',
      'спільний перевірений backend підтриманих форм');
    AddEntry('Графічний компілятор','gui/sens-wide-compiler.lpi',
      'існуючий Lazarus/LCL проєкт');
    AddEntry('Фізичний інспектор','gui/sens-inspector.lpi',
      'існуючий Lazarus/LCL проєкт');
    AddEntry('Тест нативного потоку','scripts/test-irwidefront-potik.sh',
      'механічні ELF64 і незалежний SENS oracle');
  finally
    FList.Items.EndUpdate;
  end;
end;

{ FRoot містить лише явно перевірений каталог; відсутня модель
  відображається порожньою мапою, не старим snapshot.
  1) Чому невірний корінь очищає старий стан?
  2) Яка фізична сутність визначає закони?
  3) Чому однакова назва файлу не засвідчує семантичну відповідність? }
function TSensMapWindow.SetRepositoryRoot(const Path:String):Boolean;
var Candidate:String;
begin
  FRoot:='';FPaths.Clear;FList.Items.Clear;
  Result:=False;
  if Path='' then Exit;
  Candidate:=IncludeTrailingPathDelimiter(ExpandFileName(Path));
  if (not DirectoryExists(Candidate)) or
     (not FileExists(Candidate+'AGENTS.md')) or
     (not FileExists(Candidate+'gui/sens-inspector.lpi')) then begin
    FStatus.Caption:='ВІДМОВА: це не перевірений корінь wsm-lazarus';
    Exit;
  end;
  FRoot:=Candidate;Rebuild;
  FStatus.Caption:='Каталог: '+FRoot+' · статус лише наявності, не семантики';
  Result:=True;
end;

procedure TSensMapWindow.ChooseClick(Sender:TObject);
var Pick:TSelectDirectoryDialog;
begin
  Pick:=TSelectDirectoryDialog.Create(Self);
  try
    Pick.Title:='Оберіть корінь wsm-lazarus';
    if Pick.Execute then SetRepositoryRoot(Pick.FileName);
  finally Pick.Free end;
end;

{ Повертає True лише коли існує файл і IDE-зворотний виклик.
  IDE API, а не shell/exec, відкриває вже існуючий проєкт чи текст.
  1) Чому не запускаємо зовнішній ELF?
  2) Чому не відкриваємо відсутній файл як нібито готовий?
  3) Чому index перевіряється до доступу до FPaths? }
function TSensMapWindow.OpenEntry(Index:Integer):Boolean;
var Path:String;
begin
  Result:=False;
  if (Index<0) or (Index>=FPaths.Count) then begin
    FStatus.Caption:='ВІДМОВА: виберіть наявний рядок';
    Exit;
  end;
  Path:=FPaths[Index];
  if not FileExists(Path) then begin
    FStatus.Caption:='ВІДМОВА: файл відсутній: '+Path;
    Exit;
  end;
  if not Assigned(FOnOpenPath) then begin
    FStatus.Caption:='ВІДМОВА: IDE-інтерфейс відкриття не підключений';
    Exit;
  end;
  FOnOpenPath(Path);
  FStatus.Caption:='Передано до Lazarus IDE: '+Path;
  Result:=True;
end;

procedure TSensMapWindow.OpenClick(Sender:TObject);
begin OpenEntry(FList.ItemIndex) end;
procedure TSensMapWindow.ItemDoubleClick(Sender:TObject);
begin OpenEntry(FList.ItemIndex) end;
function TSensMapWindow.EntryCount:Integer;
begin Result:=FPaths.Count end;
function TSensMapWindow.EntryPath(Index:Integer):String;
begin
  Result:='';
  if (Index>=0) and (Index<FPaths.Count) then Result:=FPaths[Index];
end;
end.
