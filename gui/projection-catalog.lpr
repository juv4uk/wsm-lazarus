{ G2.26 — живий Lazarus/LCL каталог pinned проєкцій SENS D1–D10.
  Лише відображення (width,bits), не reader програм, LISP runtime або D12+.
  Усі поверхні з оригінальних .lisp, а не з Pascal register. }
program sens_projection_catalog;
{$mode objfpc}{$H+}{$codepage utf8}
uses
  Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,ExtCtrls,Grids,
  wsm.projectioncatalog;
type
  TProjectionWindow=class(TForm)
  private
    FData:TProjectionCatalog;
    FLoaded:Boolean;
    FDomain:TComboBox;
    FCoordinate:TEdit;
    FGo:TButton;
    FGrid:TStringGrid;
    FStatus:TLabel;
    procedure ShowDomain(D:Integer);
    procedure ChangeDomain(Sender:TObject);
    procedure GoClick(Sender:TObject);
    procedure Demand(Condition:Boolean;const Reason:String);
    function SelectExact(const Coordinate:RawByteString):Boolean;
  public
    constructor Create(AOwner:TComponent);override;
    procedure LoadRoot(const Root:String);
    procedure SelfTest;
  end;
var Window:TProjectionWindow;

constructor TProjectionWindow.Create(AOwner:TComponent);
var TopBar,BottomBar:TPanel; Help:TLabel;S:TProjectionSurface;D:Integer;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — усі шість pinned проєкцій і точні координати';
  Width:=1360;Height:=720;Position:=poScreenCenter;

  TopBar:=TPanel.Create(Self);
  TopBar.Parent:=Self;TopBar.Align:=alTop;TopBar.Height:=82;
  TopBar.BevelOuter:=bvNone;
  FDomain:=TComboBox.Create(Self);FDomain.Parent:=TopBar;
  FDomain.SetBounds(12,8,170,32);FDomain.Style:=csDropDownList;
  for D:=1 to 10 do FDomain.Items.Add('Домен D'+IntToStr(D));
  FDomain.OnChange:=@ChangeDomain;
  FCoordinate:=TEdit.Create(Self);FCoordinate.Parent:=TopBar;
  FCoordinate.SetBounds(195,8,210,32);
  FCoordinate.TextHint:='Точне слово D3:010';
  FGo:=TButton.Create(Self);FGo.Parent:=TopBar;
  FGo.SetBounds(418,8,178,32);
  FGo.Caption:='Показати координату';FGo.OnClick:=@GoClick;
  Help:=TLabel.Create(Self);Help.Parent:=TopBar;
  Help.SetBounds(12,50,1325,25);
  Help.Caption:='ук · укр · san (IAST) · en · LISP (лише довідка) · sym. Жодна назва не виконується.';

  BottomBar:=TPanel.Create(Self);BottomBar.Parent:=Self;
  BottomBar.Align:=alBottom;BottomBar.Height:=40;BottomBar.BevelOuter:=bvNone;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=BottomBar;
  FStatus.SetBounds(12,11,1310,26);
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;FGrid.Align:=alClient;
  FGrid.ColCount:=7;FGrid.RowCount:=2;FGrid.FixedRows:=1;FGrid.FixedCols:=1;
  FGrid.Options:=FGrid.Options-[goEditing];
  FGrid.Options:=FGrid.Options+[goRowSelect,goColSizing];
  FGrid.ColWidths[0]:=132;
  FGrid.ColWidths[1]:=196;FGrid.ColWidths[2]:=220;
  FGrid.ColWidths[3]:=230;FGrid.ColWidths[4]:=194;
  FGrid.ColWidths[5]:=190;FGrid.ColWidths[6]:=154;
  FGrid.Cells[0,0]:='Точне Dn:біти';
  for S:=Low(TProjectionSurface) to High(TProjectionSurface) do
    FGrid.Cells[Ord(S)+1,0]:=String(ProjectionColumnName(S));
  FLoaded:=False;
  FStatus.Caption:='Завантажте pinned SENS для перегляду — це не виконання.';
end;

procedure TProjectionWindow.Demand(Condition:Boolean;const Reason:String);
begin if not Condition then raise Exception.Create('LCL-ПРОЄКЦІЇ-ПОМИЛКА: '+Reason) end;

procedure TProjectionWindow.LoadRoot(const Root:String);
var Snapshot:TProjectionCatalog;D:Integer;
begin
  FLoaded:=False;FGrid.RowCount:=2;
  LoadProjectionCatalog(Root,Snapshot);
  for D:=1 to 10 do FData[D]:=Snapshot[D];
  FLoaded:=True;
  FDomain.ItemIndex:=2;
  ShowDomain(3);
end;

procedure TProjectionWindow.ShowDomain(D:Integer);
var I,J:Integer;S:TProjectionSurface;V:RawByteString;
begin
  if (not FLoaded) or (D<1) or (D>10) then Exit;
  if Length(FData[D])<>(1 shl D) then
    raise Exception.Create('Неповний pinned домен для UI');
  FGrid.RowCount:=Length(FData[D])+1;
  for I:=0 to High(FData[D]) do begin
    FGrid.Cells[0,I+1]:='D'+IntToStr(D)+':'+String(FData[D][I].Bits);
    for S:=Low(TProjectionSurface) to High(TProjectionSurface) do begin
      V:=FData[D][I].Names[S];
      if V='' then V:='()'; { показати саме відсутню поверхню }
      J:=Ord(S)+1;
      FGrid.Cells[J,I+1]:=String(V);
    end;
  end;
  FGrid.Row:=1;
  FStatus.Caption:='Pinned D'+IntToStr(D)+' · координат='+IntToStr(Length(FData[D]))+
    ' · значення не виконуються · D7 текстові символи ≠ D12+ числа';
  FGrid.Invalidate;
end;

procedure TProjectionWindow.ChangeDomain(Sender:TObject);
begin
  if FLoaded and (FDomain.ItemIndex>=0) then ShowDomain(FDomain.ItemIndex+1);
end;

function TProjectionWindow.SelectExact(const Coordinate:RawByteString):Boolean;
var P,I,D,N:Integer;Bits:RawByteString;
begin
  Result:=False;
  P:=Pos(':',Coordinate);
  if (Length(Coordinate)<4) or (Coordinate[1]<>'D') or (P<3) then Exit;
  D:=0;
  for I:=2 to P-1 do begin
    if not (Coordinate[I] in ['0'..'9']) then Exit;
    D:=D*10+(Ord(Coordinate[I])-Ord('0'));
    if D>10 then Exit;
  end;
  if (D<1) or (D>10) then Exit;
  Bits:=Copy(Coordinate,P+1,Length(Coordinate));
  if Length(Bits)<>D then Exit;
  N:=0;
  for I:=1 to Length(Bits) do begin
    N:=N*2;
    if Bits[I]='1' then Inc(N)
    else if Bits[I]<>'0' then Exit;
  end;
  if FData[D][N].Bits<>Bits then Exit;
  FDomain.ItemIndex:=D-1;
  ShowDomain(D);
  FGrid.Row:=N+1;
  FStatus.Caption:=FStatus.Caption+' · вибрано '+String(Coordinate);
  Result:=True;
end;

procedure TProjectionWindow.GoClick(Sender:TObject);
begin
  if not FLoaded then Exit;
  if not SelectExact(RawByteString(FCoordinate.Text)) then
    FStatus.Caption:='Відмова: потрібна точна Dn:біти, не назва й не число.';
end;

procedure TProjectionWindow.SelfTest;
begin
  Demand(FLoaded,'каталог не завантажено');
  Demand(Length(FData[10])=1024,'D10 не 1024');
  Demand(FGrid.ColCount=7,'потрібні 6 поверхонь і точна координата');
  Demand(SelectExact('D3:010'),'точна D3:010');
  Demand((FGrid.RowCount=9) and (FGrid.Row=3),'вибрано фізичну D3 координату');
  Demand((FGrid.Cells[1,3]='атом?') and
    (FGrid.Cells[2,3]='атом?') and
    (FGrid.Cells[3,3]='aṇu') and
    (FGrid.Cells[4,3]='atom?') and
    (FGrid.Cells[5,3]='ATOM') and
    (FGrid.Cells[6,3]='.?'),'усі шість pinned поверхонь D3:010');
  Demand(SelectExact('D4:0101'),'D4:0101');
  Demand((FGrid.Cells[1,6]='порожнє?') and
    (FGrid.Cells[2,6]='порожній?'),'ук не слід плутати з укр');
  Demand(SelectExact('D7:0110000'),'D7 текстова цифра');
  Demand((FGrid.Cells[1,49]='0') and
    (FGrid.Cells[5,49]='()'),'D7 цифра не LISP/D12');
  Demand(SelectExact('D7:0010110'),'D7 SYN');
  Demand((FGrid.Cells[1,23]='()') and
    (FGrid.Cells[5,23]='()'),'керувальний SYN не є друкованим');
  Demand(not SelectExact('D3:10'),'відмова за втраченою шириною');
  Demand(not SelectExact('D12:000000000000'),'D12 поза цим UI');
  Demand(not SelectExact('D3:ATOM'),'ніякого text dispatch');
  Demand(SelectExact('D10:0000000000'),'провідні нулі D10');
  Demand(FGrid.RowCount=1025,'повні 1024 рядки Lazarus TStringGrid');
  FGrid.Repaint;Application.ProcessMessages;
  WriteLn('LCL-ПРОЄКЦІЇ-ГАРАЗД D1-D10=2046 колонки=6 ',
    'D3:010=точно D4:0101=ук-укр D7=SYN/0 D10=1024 ',
    'LISP=довідка виконання=ні');
end;

begin
  Application.Initialize;
  Application.CreateForm(TProjectionWindow,Window);
  if (ParamCount=2) and (ParamStr(1)='--selftest') then begin
    try
      Window.LoadRoot(ParamStr(2));
      Window.Show;Application.ProcessMessages;
      Window.SelfTest;
      Window.Free;Window:=nil;
      Halt(0);
    except on E:Exception do begin
      WriteLn(StdErr,'LCL-ПРОЄКЦІЇ-ПОМИЛКА: '+E.Message);
      Halt(2);
    end end;
  end;
  try Window.LoadRoot(GetCurrentDir)
  except on E:Exception do begin
    WriteLn(StdErr,'Не знайдено pinned таблиць D1–D10: '+E.Message);
    Halt(2)
  end end;
  Application.Run;
end.
