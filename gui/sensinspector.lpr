{ SENS — нативний інспектор фізичного двійкового потоку на Lazarus/LCL.
  GUI тільки показує вже прочитане wsm.physloc, без власних мовних законів. }
program sensinspector;
{$mode objfpc}{$H+}
{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, wsm.t5m, wsm.physloc, wsm.domain, wsm.bind,
  wsm.inspectorview;

type
  TInspectorForm = class(TForm)
  private
    TopPanel: TPanel;
    FileBox: TEdit;
    OpenButton: TButton;
    Table: TStringGrid;
    Status: TLabel;
    Picker: TOpenDialog;
    procedure ChooseFile(Sender: TObject);
    procedure LoadPhysicalFile(const FilePath: String);
    procedure DisplayWords(const Data: TVisualWords; ByteCount: SizeInt);
    procedure ResetView;
  public
    constructor Create(AOwner: TComponent); override;
    procedure VerifyWidget;
  end;

constructor TInspectorForm.Create(AOwner: TComponent);
var I: Integer;
begin
  inherited CreateNew(AOwner, 0);
  Caption:='SENS — огляд двійкових слів (без виконання)';
  Width:=1200; Height:=680;
  Position:=poScreenCenter;

  TopPanel:=TPanel.Create(Self);
  TopPanel.Parent:=Self;
  TopPanel.Align:=alTop;
  TopPanel.Height:=96;

  FileBox:=TEdit.Create(Self);
  FileBox.Parent:=TopPanel;
  FileBox.SetBounds(14,12,940,30);
  FileBox.Anchors:=[akLeft,akTop,akRight];
  FileBox.Text:='';
  FileBox.ReadOnly:=True;

  OpenButton:=TButton.Create(Self);
  OpenButton.Parent:=TopPanel;
  OpenButton.SetBounds(970,12,200,30);
  OpenButton.Anchors:=[akTop,akRight];
  OpenButton.Caption:='Відкрити .sens…';
  OpenButton.OnClick:=@ChooseFile;

  Status:=TLabel.Create(Self);
  Status.Parent:=TopPanel;
  Status.SetBounds(14,54,1150,28);
  Status.Caption:='Фізичні слова T5M; домен і біти первинні, «ук» — проєкція pinned SENS.';
  Status.Anchors:=[akLeft,akRight,akTop];

  Table:=TStringGrid.Create(Self);
  Table.Parent:=Self;
  Table.Align:=alClient;
  Table.ColCount:=7;
  Table.FixedCols:=0;
  Table.FixedRows:=1;
  Table.RowCount:=2;
  Table.Options:=Table.Options+[goRowSelect];
  Table.Cells[0,0]:='№';
  Table.Cells[1,0]:='Домен';
  Table.Cells[2,0]:='Ширина';
  Table.Cells[3,0]:='Двійкове слово';
  Table.Cells[4,0]:='Трити [від,до)';
  Table.Cells[5,0]:='Байти [від,до)';
  Table.Cells[6,0]:='ук (проєкція SENS)';
  Table.ColWidths[0]:=55;
  Table.ColWidths[1]:=90;
  Table.ColWidths[2]:=80;
  Table.ColWidths[3]:=185;
  Table.ColWidths[4]:=180;
  Table.ColWidths[5]:=180;
  Table.ColWidths[6]:=370;
  for I:=0 to 6 do Table.Cells[I,1]:='';

  Picker:=TOpenDialog.Create(Self);
  Picker.Title:='Виберіть фізичний двійковий файл SENS';
  Picker.Filter:='Двійкові файли SENS|*.sens|Усі файли|*';
end;

procedure TInspectorForm.ResetView;
var K: Integer;
begin
  Table.RowCount:=2;
  for K:=0 to 6 do Table.Cells[K,1]:='';
  FileBox.Text:='';
  Status.Caption:='Немає прийнятого фізичного файла.';
end;

procedure TInspectorForm.DisplayWords(const Data: TVisualWords;
  ByteCount: SizeInt);
var I: SizeInt;
begin
  if Length(Data)=0 then raise EVisualInspect.Create('немає фізичних слів');
  Table.RowCount:=Length(Data)+1;
  for I:=0 to High(Data) do begin
    Table.Cells[0,I+1]:=IntToStr(Data[I].Index);
    Table.Cells[1,I+1]:='D'+IntToStr(Data[I].Key.Width);
    Table.Cells[2,I+1]:=IntToStr(Data[I].Key.Width);
    Table.Cells[3,I+1]:=String(Data[I].Bits);
    Table.Cells[4,I+1]:=Format('[%d,%d)',
      [Data[I].Position.TritStart,Data[I].Position.TritEnd]);
    Table.Cells[5,I+1]:=Format('[%d,%d)',
      [Data[I].Position.ByteStart,Data[I].Position.ByteEnd]);
    if Data[I].Ukrainian='' then Table.Cells[6,I+1]:='—'
    else Table.Cells[6,I+1]:=String(Data[I].Ukrainian);
  end;
  Status.Caption:=Format('Фізичний T5M: %d байт; %d слів. Виконання і викличність не перевірено.',
    [ByteCount,Length(Data)]);
end;

procedure TInspectorForm.LoadPhysicalFile(const FilePath: String);
var
  Input: TFileStream;
  Physical: RawByteString;
  Tables: TDomainSet;
  Data: TVisualWords;
begin
  try
    if LowerCase(ExtractFileExt(FilePath))<>'.sens' then
      raise EVisualInspect.Create('потрібен фізичний файл .sens');
    Input:=TFileStream.Create(FilePath,fmOpenRead or fmShareDenyWrite);
    try
      if (Input.Size<1) or (Input.Size>MAX_T5M_FILE_BYTES) then
        raise EVisualInspect.Create('фізичний файл порожній або завеликий');
      SetLength(Physical,Input.Size);
      Input.ReadBuffer(Physical[1],Length(Physical));
    finally Input.Free; end;
    LoadPinnedDomains('external/sens',Tables);
    BuildVisualWords(Physical,Tables,Data);
    DisplayWords(Data,Length(Physical));
    FileBox.Text:=FilePath;
  except
    ResetView;
    raise;
  end;
end;

procedure TInspectorForm.ChooseFile(Sender: TObject);
begin
  if not Picker.Execute then Exit;
  try LoadPhysicalFile(Picker.FileName);
  except
    on E:Exception do
      MessageDlg('Помилка фізичного читання SENS',E.Message,mtError,[mbOK],0);
  end;
end;

procedure TInspectorForm.VerifyWidget;
var T: TDomainSet; W: TExactWords; Data: TVisualWords;
begin
  SetLength(W,6);
  W[0]:='10'; W[1]:='111'; W[2]:='00';
  W[3]:='1'; W[4]:='000'; W[5]:='01';
  LoadPinnedDomains('external/sens',T);
  BuildVisualWords(EncodeT5M(W),T,Data);
  DisplayWords(Data,Length(EncodeT5M(W)));
  if (Table.RowCount<>7) or (Table.Cells[3,2]<>'111') or
     (Table.Cells[6,2]<>'сполучити') or
     (Table.Cells[3,5]<>'000') or
     (Table.Cells[1,5]<>'D3') then
    raise EVisualInspect.Create('LCL таблиця спотворила точне двійкове слово');
  WriteLn('LCL-ІНСПЕКТОР-ГАРАЗД: вікно=створено таблиця=7-рядків ',
    'двійкові-біти=точні проєкція=pinned виконання=не-перевірено');
end;

var Window: TInspectorForm;
begin
  Application.Initialize;
  Window:=TInspectorForm.Create(nil);
  try
    if (ParamCount=1) and (ParamStr(1)='--самоперевірка') then
      Window.VerifyWidget
    else begin
      if ParamCount=1 then Window.LoadPhysicalFile(ParamStr(1));
      Window.Show;
      Application.Run;
    end;
  finally Window.Free; end;
end.
