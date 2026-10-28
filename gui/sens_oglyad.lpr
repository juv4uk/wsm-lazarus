{ Lazarus/LCL — українська ВІЗУАЛЬНА проєкція фізичного двійкового SENS.
  Жодних обчислень мови, додаткового reader або власного реєстру законів. }
program sens_oglyad;
{$mode objfpc}{$H+}
{$codepage utf8}

uses Interfaces, Forms, Controls, StdCtrls, ExtCtrls, Grids,
     Dialogs, SysUtils, Classes, wsm.t5m, wsm.oglyadmodel;

type
  TOgliadForm = class(TForm)
  private
    FModel: TOghliadModel;
    FGrid: TStringGrid;
    FDetails: TMemo;
    FStatus: TLabel;
    FOpen: TButton;
    FDialog: TOpenDialog;
    procedure OpenPhysical(Sender:TObject);
    procedure RowSelected(Sender:TObject; ACol, ARow:Integer;
      var CanSelect:Boolean);
    procedure ShowDetails(ARow:Integer);
    procedure Render;
  public
    constructor Create(TheOwner:TComponent); override;
    destructor Destroy; override;
    procedure VisualSmoke;
  end;

var
  MainWindow: TOgliadForm;

constructor TOgliadForm.Create(TheOwner:TComponent);
var TopPanel, BottomPanel:TPanel;
begin
  inherited CreateNew(TheOwner,1);
  Caption:='SENS — оглядач фізичного двійкового коду';
  Width:=1080;
  Height:=660;
  Position:=poScreenCenter;
  FModel:=TOghliadModel.Create;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичний двійковий SENS|*.sens|Усі файли|*.*';
  FDialog.Title:='Відкрити фізичний файл .sens';

  TopPanel:=TPanel.Create(Self);
  TopPanel.Parent:=Self;
  TopPanel.Align:=alTop;
  TopPanel.Height:=56;
  TopPanel.BevelOuter:=bvNone;

  FOpen:=TButton.Create(Self);
  FOpen.Parent:=TopPanel;
  FOpen.SetBounds(12,10,175,36);
  FOpen.Caption:='Відкрити .sens';
  FOpen.OnClick:=@OpenPhysical;

  FStatus:=TLabel.Create(Self);
  FStatus.Parent:=TopPanel;
  FStatus.Left:=205; FStatus.Top:=19;
  FStatus.Caption:='Оберіть фізичний двійковий файл SENS';

  BottomPanel:=TPanel.Create(Self);
  BottomPanel.Parent:=Self;
  BottomPanel.Align:=alBottom;
  BottomPanel.Height:=155;
  BottomPanel.BevelOuter:=bvNone;

  FDetails:=TMemo.Create(Self);
  FDetails.Parent:=BottomPanel;
  FDetails.Align:=alClient;
  FDetails.ReadOnly:=True;
  FDetails.ScrollBars:=ssVertical;
  FDetails.Lines.Text:='Виберіть слово для перегляду фізичних позицій.';
  FDetails.Font.Name:='Monospace';

  FGrid:=TStringGrid.Create(Self);
  FGrid.Parent:=Self;
  FGrid.Align:=alClient;
  FGrid.ColCount:=6;
  FGrid.RowCount:=2;
  FGrid.FixedRows:=1;
  FGrid.Options:=FGrid.Options+[goRowSelect];
  FGrid.DefaultRowHeight:=26;
  FGrid.ColWidths[0]:=68;
  FGrid.ColWidths[1]:=75;
  FGrid.ColWidths[2]:=285;
  FGrid.ColWidths[3]:=260;
  FGrid.ColWidths[4]:=158;
  FGrid.ColWidths[5]:=158;
  FGrid.Cells[0,0]:='Слово';
  FGrid.Cells[1,0]:='Домен';
  FGrid.Cells[2,0]:='Точні біти';
  FGrid.Cells[3,0]:='Структурний огляд';
  FGrid.Cells[4,0]:='Трити [від, до)';
  FGrid.Cells[5,0]:='Байти [від, до)';
  FGrid.OnSelectCell:=@RowSelected;
end;

destructor TOgliadForm.Destroy;
begin
  FModel.Free;
  inherited Destroy;
end;

procedure TOgliadForm.OpenPhysical(Sender:TObject);
begin
  if not FDialog.Execute then Exit;
  try
    FModel.LoadFile(FDialog.FileName);
    Render;
  except
    on E:Exception do begin
      FStatus.Caption:='Фізичний файл не допущено';
      MessageDlg('Помилка фізичного читання: '+E.Message,mtError,[mbOK],0);
    end;
  end;
end;

procedure TOgliadForm.Render;
var I:SizeInt; R:TOghliadWord;
begin
  FGrid.RowCount:=FModel.WordCount+1;
  for I:=0 to FModel.WordCount-1 do begin
    R:=FModel.WordAt(I);
    FGrid.Cells[0,I+1]:=IntToStr(R.Index);
    FGrid.Cells[1,I+1]:='D'+IntToStr(R.Width);
    FGrid.Cells[2,I+1]:=String(R.Bits);
    FGrid.Cells[3,I+1]:=String(R.Kind);
    FGrid.Cells[4,I+1]:=IntToStr(R.TritStart)+' — '+IntToStr(R.TritEnd);
    FGrid.Cells[5,I+1]:=IntToStr(R.ByteStart)+' — '+IntToStr(R.ByteEnd);
  end;
  FStatus.Caption:='Байти: '+IntToStr(FModel.ByteCount)+
    ' · слова: '+IntToStr(FModel.WordCount)+
    ' · верхні форми D2: '+IntToStr(FModel.RootCount)+
    ' · виконання: НЕ ПЕРЕВІРЕНО';
  ShowDetails(1);
end;

procedure TOgliadForm.RowSelected(Sender:TObject; ACol,ARow:Integer;
  var CanSelect:Boolean);
begin
  if ARow>0 then ShowDetails(ARow);
end;

procedure TOgliadForm.ShowDetails(ARow:Integer);
var R:TOghliadWord;
begin
  if (ARow<1) or (ARow>FModel.WordCount) then Exit;
  R:=FModel.WordAt(ARow-1);
  FDetails.Lines.Text:=
    'Фізичне слово № '+IntToStr(R.Index)+LineEnding+
    'Точний домен: D'+IntToStr(R.Width)+LineEnding+
    'Двійкове слово: '+String(R.Bits)+LineEnding+
    'Відрізок тритів: ['+IntToStr(R.TritStart)+', '+IntToStr(R.TritEnd)+')'+LineEnding+
    'Фізичні байти: ['+IntToStr(R.ByteStart)+', '+IntToStr(R.ByteEnd)+')'+LineEnding+
    'Фізичний вміст (hex): '+String(FModel.HexAt(ARow-1))+LineEnding+
    'Примітка: українські підписи — проєкція; закони SENS тут не виконуються.';
end;

procedure TOgliadForm.VisualSmoke;
var Words:TExactWords;
begin
  SetLength(Words,3);
  Words[0]:='10'; Words[1]:='0'; Words[2]:='01';
  FModel.LoadBytes(EncodeT5M(Words));
  Render;
  Show;
  Application.ProcessMessages;
  if (FModel.WordCount<>3) or (FGrid.RowCount<>4) or
     (FGrid.Cells[2,2]<>'0') or (FGrid.Cells[1,2]<>'D1') or
     (FGrid.Cells[3,1]='') or (FStatus.Caption='') then
    raise Exception.Create('Збій створення реальних LCL контролів');
  WriteLn('LAZARUS-VISUAL-OK вікно=створено таблиця=3 D1=0 D2=структура');
end;

begin
  Application.Initialize;
  Application.CreateForm(TOgliadForm,MainWindow);
  if (ParamCount=1) and (ParamStr(1)='--перевірка-вікна') then begin
    MainWindow.VisualSmoke;
    MainWindow.Free;
  end else Application.Run;
end.
