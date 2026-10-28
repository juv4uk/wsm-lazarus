{ Справжній LCL-перегляд приватного WSMIMG1, НЕ програми .sens.
  Єдиний loader — wsm.image.LoadFrameImage, використаний через imagecatalog.
  Українські колонки — людський інтерфейс, а не семантична проєкція. }
program sens_image_catalog;
{$mode objfpc}{$H+}
uses
  Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, ExtCtrls,
  Grids, Dialogs, wsm.domain, wsm.imagecatalog;

type
  TCatalogForm = class(TForm)
  private
    FGrid: TStringGrid;
    FStatus: TLabel;
    FOpen: TButton;
    FDialog: TOpenDialog;
    procedure OpenClicked(Sender: TObject);
    procedure ClearData;
    procedure Demand(OK: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function LoadFile(const Path: String): Boolean;
    procedure SelfCheck(const GoodFile, BadFile: String);
  end;
var
  Window: TCatalogForm;

constructor TCatalogForm.Create(AOwner: TComponent);
var TopBar, BottomBar: TPanel;
begin
  inherited CreateNew(AOwner,1);
  Caption := 'SENS — приватний лексичний образ';
  Width := 920;
  Height := 560;
  Position := poScreenCenter;
  TopBar := TPanel.Create(Self);
  TopBar.Parent := Self;
  TopBar.Align := alTop;
  TopBar.Height := 52;
  TopBar.BevelOuter := bvNone;
  FOpen := TButton.Create(Self);
  FOpen.Parent := TopBar;
  FOpen.Caption := 'Відкрити приватний образ…';
  FOpen.SetBounds(12,10,255,33);
  FOpen.OnClick := @OpenClicked;
  FDialog := TOpenDialog.Create(Self);
  FDialog.Title := 'Оберіть приватний лексичний образ WSMIMG1';
  FDialog.Filter := 'Приватні образи (*.img;*.wsmimg)|*.img;*.wsmimg|Усі файли|*.*';
  BottomBar := TPanel.Create(Self);
  BottomBar.Parent := Self;
  BottomBar.Align := alBottom;
  BottomBar.Height := 48;
  BottomBar.BevelOuter := bvNone;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := BottomBar;
  FStatus.SetBounds(12,12,870,30);
  FGrid := TStringGrid.Create(Self);
  FGrid.Parent := Self;
  FGrid.Align := alClient;
  FGrid.ColCount := 5;
  FGrid.FixedCols := 0;
  FGrid.RowCount := 2;
  FGrid.FixedRows := 1;
  FGrid.Options := FGrid.Options - [goEditing];
  FGrid.Options := FGrid.Options + [goRowSelect,goColSizing];
  FGrid.ColWidths[0] := 105;
  FGrid.ColWidths[1] := 115;
  FGrid.ColWidths[2] := 165;
  FGrid.ColWidths[3] := 220;
  FGrid.ColWidths[4] := 260;
  FGrid.Cells[0,0] := 'Запис №';
  FGrid.Cells[1,0] := 'Домен';
  FGrid.Cells[2,0] := 'Точні біти';
  FGrid.Cells[3,0] := 'Host-значення (hex)';
  FGrid.Cells[4,0] := 'Тлумачення';
  ClearData;
end;

procedure TCatalogForm.ClearData;
var J: Integer;
begin
  FGrid.RowCount := 2;
  for J:=0 to FGrid.ColCount-1 do FGrid.Cells[J,1]:='';
  FStatus.Caption := 'Фізичний WSMIMG1; не є системним образом або програмою SENS.';
end;

procedure TCatalogForm.Demand(OK: Boolean; const Why: String);
begin
  if not OK then
    raise Exception.Create('LCL-каталог: ' + Why);
end;

function TCatalogForm.LoadFile(const Path: String): Boolean;
var
  Input: TFileStream;
  Rows: TImageCatalog;
  I: SizeInt;
begin
  Result := False;
  ClearData;
  try
    if not (LowerCase(ExtractFileExt(Path)) in ['.img','.wsmimg']) then
      raise Exception.Create('очікується приватний файл .img або .wsmimg');
    Input := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      ReadImageCatalog(Input,Rows);
    finally
      Input.Free;
    end;
    { Всі записи й повторний canonical save вже перевірені.
      Лише зараз змінюємо фізичні клітинки LCL. }
    FGrid.BeginUpdate;
    try
      FGrid.RowCount := Length(Rows)+1;
      for I:=0 to High(Rows) do begin
        FGrid.Cells[0,I+1] := IntToStr(I+1);
        FGrid.Cells[1,I+1] := 'D'+IntToStr(Rows[I].Key.Width);
        FGrid.Cells[2,I+1] := String(KeyBits(Rows[I].Key));
        FGrid.Cells[3,I+1] := IntToHex(Rows[I].OpaqueHandle,16);
        FGrid.Cells[4,I+1] := 'непрозоре host-значення';
      end;
    finally FGrid.EndUpdate; end;
    FStatus.Caption := 'Відновлено прив’язок: ' + IntToStr(Length(Rows)) +
      '; канонічний приватний образ; виконання: ні.';
    Result := True;
  except
    on E: Exception do begin
      ClearData;
      FStatus.Caption := 'Помилка: '+ E.Message;
    end;
  end;
end;

procedure TCatalogForm.OpenClicked(Sender: TObject);
begin
  if FDialog.Execute then LoadFile(FDialog.FileName);
end;

procedure TCatalogForm.SelfCheck(const GoodFile, BadFile: String);
begin
  Demand(LoadFile(GoodFile),'не відновлено фізичний образ');
  Demand(FGrid.RowCount=5,'кількість фактичних записів');
  Demand((FGrid.Cells[1,1]='D1') and (FGrid.Cells[2,1]='0') and
    (FGrid.Cells[3,1]='0000000000000000'), 'D1:0 і нульовий host-handle');
  Demand((FGrid.Cells[1,2]='D2') and (FGrid.Cells[2,2]='01') and
    (FGrid.Cells[3,2]='000000000000002A'),'D2:01 і host 42');
  Demand((FGrid.Cells[1,3]='D3') and (FGrid.Cells[2,3]='000') and
    (FGrid.Cells[3,3]='0000000000000009'),'D3:000 не є D1:0');
  Demand((FGrid.Cells[1,4]='D3') and (FGrid.Cells[2,4]='001') and
    (FGrid.Cells[3,4]='FFFFFFFFFFFFFFFF'),'opaque u64');
  Demand(Pos('виконання: ні', FStatus.Caption)>0, 'UI приховує межі доказу');
  Demand(not LoadFile(BadFile),'пошкоджену контрольну суму прийнято');
  Demand((FGrid.RowCount=2) and (FGrid.Cells[0,1]='') and
    (Pos('Помилка:',FStatus.Caption)=1),'помилка лишила старі клітинки');
  Demand(not LoadFile('відсутній_лексичний_образ.wsmimg'),'немає файла');
  Demand((FGrid.Cells[0,1]='') and (Pos('Помилка:',FStatus.Caption)=1),
    'відсутній файл лишив старе свідчення');
  WriteLn('LCL-ОБРАЗ-ГАРАЗД Lazarus=так віджети=справжні ',
    'D1_не_D3=так host_u64=точне відновлення=так ',
    'пошкодження=відхилено системний_образ_SENS=ні');
end;

begin
  Application.Initialize;
  Application.Title := 'SENS — каталог приватного лексичного образу';
  Application.CreateForm(TCatalogForm,Window);
  if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
    if ParamCount<>3 then Halt(64);
    try
      Window.Show;
      Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3));
    except
      on E:Exception do begin
        WriteLn(StdErr,'LCL-ОБРАЗ-ПОМИЛКА: ',E.Message);
        Halt(1);
      end;
    end;
  end else begin
    if ParamCount=1 then Window.LoadFile(ParamStr(1));
    Application.Run;
  end;
end.
