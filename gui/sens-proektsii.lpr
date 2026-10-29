{ Справжній Lazarus/LCL оглядач pinned D1–D10 та шести проєкцій.
  Лише візуалізація координат, не SENS parser, evaluator або dispatch. }
program sens_proektsii;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Grids,
  wsm.domain, wsm.proektsii;
type
  TProektsiiForm=class(TForm)
  private
    Catalog:TProektsiiCatalog;
    Selector:TComboBox;
    Matrix:TStringGrid;
    Status:TLabel;
    procedure ChangeDomain(Sender:TObject);
    procedure FillDomain(D:Integer);
    procedure Check(OK:Boolean;const Explanation:String);
  public
    constructor Create(AOwner:TComponent); override;
    procedure LoadAuthority(const Root:String);
    procedure SelfTest;
  end;
var Window:TProektsiiForm;
constructor TProektsiiForm.Create(AOwner:TComponent);
var I:Integer; TopLine:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — шість проєкцій точних доменів';
  Width:=1200; Height:=720; Position:=poScreenCenter;
  TopLine:=TLabel.Create(Self);
  TopLine.Parent:=Self; TopLine.Align:=alTop; TopLine.Height:=28;
  TopLine.Caption:='Машинна тотожність — двійкові біти + домен; назви лише людські проєкції.';
  Selector:=TComboBox.Create(Self);
  Selector.Parent:=Self; Selector.Align:=alTop; Selector.Style:=csDropDownList;
  Selector.Height:=32;
  for I:=1 to 10 do Selector.Items.Add('D'+IntToStr(I));
  Selector.OnChange:=@ChangeDomain;
  Status:=TLabel.Create(Self);
  Status.Parent:=Self; Status.Align:=alBottom; Status.Height:=30;
  Matrix:=TStringGrid.Create(Self);
  Matrix.Parent:=Self; Matrix.Align:=alClient;
  Matrix.ColCount:=7; Matrix.RowCount:=2;
  Matrix.FixedCols:=1; Matrix.FixedRows:=1;
  Matrix.DefaultColWidth:=158; Matrix.ColWidths[0]:=115;
  Matrix.Options:=Matrix.Options-[goEditing];
  Matrix.Cells[0,0]:='Домен:біти';
  Matrix.Cells[1,0]:='ук'; Matrix.Cells[2,0]:='укр';
  Matrix.Cells[3,0]:='san'; Matrix.Cells[4,0]:='en';
  Matrix.Cells[5,0]:='LISP'; Matrix.Cells[6,0]:='sym';
  Status.Caption:='Тільки pinned таблиці SENS; викличність не визначається назвами';
end;
procedure TProektsiiForm.Check(OK:Boolean;const Explanation:String);
begin
  if not OK then raise Exception.Create('LCL-ПРОЄКЦІЇ-ПОМИЛКА: '+Explanation);
end;
procedure TProektsiiForm.LoadAuthority(const Root:String);
begin
  LoadPinnedProjections(Root,Catalog);
  Selector.ItemIndex:=2;
  FillDomain(3);
end;
procedure TProektsiiForm.ChangeDomain(Sender:TObject);
begin
  if (Selector.ItemIndex>=0) and (Selector.ItemIndex<=9) then
    FillDomain(Selector.ItemIndex+1);
end;
procedure TProektsiiForm.FillDomain(D:Integer);
var I,J:Integer;
begin
  Check((D>=1) and (D<=10) and
    (Length(Catalog[D])=(1 shl D)),'Неповна pinned таблиця');
  Matrix.RowCount:=Length(Catalog[D])+1;
  for I:=0 to High(Catalog[D]) do begin
    Matrix.Cells[0,I+1]:='D'+IntToStr(D)+':'+String(KeyBits(Catalog[D][I].Key));
    for J:=0 to 5 do
      Matrix.Cells[J+1,I+1]:=SurfaceForDisplay(Catalog[D][I].Surface[J]);
  end;
  Status.Caption:='D'+IntToStr(D)+': '+IntToStr(Length(Catalog[D]))+
    ' exact-координат; 6 людських проєкцій; не виконавчий реєстр';
end;
procedure TProektsiiForm.SelfTest;
begin
  Check(Length(Catalog[7])=128,'D7 v2 не містить 128 координат');
  Check((Catalog[7][22].Surface[0]='') and (Catalog[7][22].Surface[4]=''),
    'D7 SYN має лишатися без друкованої назви/функції');
  Check(SameProjectedText(Catalog[4][5].Surface[0],'порожнє?'),'D4 ук не зчитано');
  Check(SameProjectedText(Catalog[4][5].Surface[1],'порожній?'),'D4 укр не відрізняється');
  Check(SameProjectedText(Catalog[3][1].Surface[2],'svarūpa'),'D3 san IAST втрачено');
  Check(Catalog[3][1].Surface[3]='quote','D3 en проєкцію втрачено');
  Check(Catalog[3][1].Surface[4]='QUOTE','D3 LISP як дані втрачено');
  FillDomain(7);
  Check(Matrix.RowCount=129,'LCL grid D7 розміру 128 не відображено');
  Check(Matrix.Cells[0,23]='D7:0010110','D7 SYN втратив провідні нулі');
  Check(SameProjectedText(RawByteString(Matrix.Cells[1,23]),'(відсутня)'),
    'D7 недруковану адресу вигадано');
  FillDomain(10);
  Check(Matrix.RowCount=1025,'LCL grid D10 розміру 1024 не відображено');
  Check(Matrix.Cells[0,1024]='D10:1111111111','D10 exact-ключ втрачено');
  FillDomain(4);
  Check(Matrix.Cells[1,6]<>Matrix.Cells[2,6],
    'LCL злив ук та укр в одну поверхню');
  WriteLn('LCL-ПРОЄКЦІЇ-ГАРАЗД D1-D10=2046 D7=128 D10=1024 колонок=6');
end;
begin
  Application.Initialize;
  Window:=TProektsiiForm.Create(Application);
  try
    if (ParamCount=2) and (ParamStr(1)='--selftest') then begin
      Window.LoadAuthority(ParamStr(2));
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest;
    end else if ParamCount=0 then begin
      Window.LoadAuthority('external/sens');
      Window.Show;
      Application.Run;
    end else raise Exception.Create('Виклик: sens-proektsii [--selftest ROOT]');
  finally Window.Free end;
end.
