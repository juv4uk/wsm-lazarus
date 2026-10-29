{ Справжній Lazarus/LCL оглядач pinned D1–D10 та шести проєкцій.
  Лише візуалізація координат, не SENS parser, evaluator або dispatch. }
program sens_proektsii;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Grids,
  ExtCtrls,
  wsm.domain, wsm.proektsii;
type
  { Індекс до вже допущеного каталогу, НЕ семантичний opcode. }
  TSurfaceHit=record Domain:Integer; Index:SizeInt; end;
  TSurfaceHits=array of TSurfaceHit;
  TProektsiiForm=class(TForm)
  private
    Catalog:TProektsiiCatalog;
    Selector:TComboBox;
    Matrix:TStringGrid;
    SearchPanel:TPanel;
    SurfaceSelector:TComboBox;
    SearchField:TEdit;
    SearchButton:TButton;
    Found:TListBox;
    Hits:TSurfaceHits;
    Status:TLabel;
    procedure ChangeDomain(Sender:TObject);
    procedure SearchClick(Sender:TObject);
    procedure FoundClick(Sender:TObject);
    function FindProjection(const SurfaceName:RawByteString;
      SurfaceColumn:Integer):Boolean;
    procedure JumpToHit(HitIndex:SizeInt);
    procedure ClearHits;
    procedure FillDomain(D:Integer);
    procedure Check(OK:Boolean;const Explanation:String);
  public
    constructor Create(AOwner:TComponent); override;
    procedure LoadAuthority(const Root:String);
    procedure SelfTest;
  end;
var Window:TProektsiiForm;
constructor TProektsiiForm.Create(AOwner:TComponent);
const Columns:array[0..5] of String=('ук','укр','san','en','LISP','sym');
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
  SearchPanel:=TPanel.Create(Self);
  SearchPanel.Parent:=Self; SearchPanel.Align:=alTop;
  SearchPanel.Height:=44; SearchPanel.BevelOuter:=bvNone;
  SurfaceSelector:=TComboBox.Create(Self);
  SurfaceSelector.Parent:=SearchPanel;
  SurfaceSelector.SetBounds(8,6,100,30);
  SurfaceSelector.Style:=csDropDownList;
  for I:=0 to 5 do SurfaceSelector.Items.Add(Columns[I]);
  SurfaceSelector.ItemIndex:=1;
  SearchField:=TEdit.Create(Self);
  SearchField.Parent:=SearchPanel;
  SearchField.SetBounds(116,6,455,30);
  SearchField.TextHint:='Точна pinned проєкція: map, svarūpa, QUOTE';
  SearchField.MaxLength:=1024;
  SearchButton:=TButton.Create(Self);
  SearchButton.Parent:=SearchPanel;
  SearchButton.SetBounds(581,6,280,30);
  SearchButton.Caption:='Знайти всі точні координати';
  SearchButton.OnClick:=@SearchClick;
  Status:=TLabel.Create(Self);
  Status.Parent:=Self; Status.Align:=alBottom; Status.Height:=30;
  Found:=TListBox.Create(Self);
  Found.Parent:=Self; Found.Align:=alBottom; Found.Height:=120;
  Found.OnClick:=@FoundClick;
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
  ClearHits;
  if (Selector.ItemIndex>=0) and (Selector.ItemIndex<=9) then
    FillDomain(Selector.ItemIndex+1);
end;
{ G2.29: людські проєкції не є SENS викличними головами.
  Шукаємо точні UTF-8 байти лише в одній обраній колонці,
  без нормалізації. TSurfaceHits є адресами pinned Catalog,
  кандидат публікуємо лише після повної перевірки 2046 рядків. }
procedure TProektsiiForm.ClearHits;
begin
  SetLength(Hits,0);
  Found.Items.Clear;
end;

function TProektsiiForm.FindProjection(const SurfaceName:RawByteString;
  SurfaceColumn:Integer):Boolean;
const Names:array[0..5] of RawByteString=
  ('ук','укр','san','en','LISP','sym');
var Candidate:TSurfaceHits; Lines:TStringList;
    D,I,N:SizeInt; V:RawByteString;
begin
  Result:=False;
  ClearHits;
  Lines:=TStringList.Create;
  try
    try
      if (SurfaceColumn<0) or (SurfaceColumn>5) then
        raise EProektsiiError.Create('Оберіть одну з шести pinned проєкцій');
      if (Length(SurfaceName)=0) or (Length(SurfaceName)>1024) or
         (SurfaceName='()') then
        raise EProektsiiError.Create('Порожня/неприпустима текстова проєкція');
      SetLength(Candidate,0);
      N:=0;
      for D:=1 to 10 do begin
        if Length(Catalog[D])<>(SizeInt(1) shl D) then
          raise EProektsiiError.Create('Неповна pinned таблиця проєкцій');
        for I:=0 to High(Catalog[D]) do begin
          if (Catalog[D][I].Key.Width<>D) or
             (Catalog[D][I].Key.Bits<>I) then
            raise EProektsiiError.Create('Пошкоджена точна координата');
          V:=Catalog[D][I].Surface[SurfaceColumn];
          if (V<>'') and (V=SurfaceName) then begin
            SetLength(Candidate,N+1);
            Candidate[N].Domain:=D;
            Candidate[N].Index:=I;
            Lines.Add('D'+IntToStr(D)+':'+
              String(KeyBits(Catalog[D][I].Key))+
              ' · '+String(Names[SurfaceColumn])+' = '+
              String(V));
            Inc(N);
          end;
        end;
      end;
      Hits:=Candidate;
      Found.Items.Assign(Lines);
      Found.ItemIndex:=-1;
      Status.Caption:=String(Names[SurfaceColumn])+
        ': точних збігів '+IntToStr(N)+
        ' (усі D1–D10). Назва НЕ доказ викличності';
      Result:=True;
    except
      on E:Exception do begin
        ClearHits;
        Status.Caption:='Помилка пошуку проєкції: '+E.Message;
      end;
    end;
  finally Lines.Free end;
end;

procedure TProektsiiForm.SearchClick(Sender:TObject);
begin
  FindProjection(RawByteString(SearchField.Text),SurfaceSelector.ItemIndex);
end;

{ Перехід лише за збереженим exact-key, НЕ за іменем чи кодпойнтом. }
procedure TProektsiiForm.JumpToHit(HitIndex:SizeInt);
var D,I:SizeInt;
begin
  if (HitIndex<0) or (HitIndex>High(Hits)) then
    raise EProektsiiError.Create('Невідомий результат пошуку');
  D:=Hits[HitIndex].Domain;
  I:=Hits[HitIndex].Index;
  if (D<1) or (D>10) or (I<0) or (I>=Length(Catalog[D])) or
     (Catalog[D][I].Key.Width<>D) or
     (Catalog[D][I].Key.Bits<>I) then
    raise EProektsiiError.Create('Пошкоджений exact результат пошуку');
  Selector.ItemIndex:=D-1;
  FillDomain(D);
  Matrix.Row:=I+1;
  Matrix.Col:=0;
  Status.Caption:='Показано точне D'+IntToStr(D)+':'+
    String(KeyBits(Catalog[D][I].Key))+
    ' з усіма шістьма pinned проєкціями; не виклик функції';
end;

procedure TProektsiiForm.FoundClick(Sender:TObject);
begin
  if Found.ItemIndex>=0 then JumpToHit(Found.ItemIndex);
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
  { LCL натискання на всі шість проєкцій; дубльовані назви
    повинні показати дві exact ідентичності, а не callable dispatch. }
  Check((SearchPanel.Parent=Self) and (SearchField.Parent=SearchPanel) and
    (SurfaceSelector.Items.Count=6) and (Found.Parent=Self) and
    (SearchButton.Parent=SearchPanel),
    'Справжні LCL віджети шести проєкцій відсутні');
  SurfaceSelector.ItemIndex:=2; SearchField.Text:='svarūpa';
  SearchButton.Click;
  Check((Length(Hits)=1) and (Hits[0].Domain=3) and
    (Hits[0].Index=1) and (Found.Items.Count=1) and
    (Pos('D3:001',Found.Items[0])=1),
    'san IAST не визначив точну D3:001 координату');
  Found.ItemIndex:=0; FoundClick(Found);
  Check((Selector.ItemIndex=2) and (Matrix.Row=2) and
    (Matrix.Cells[0,2]='D3:001') and
    (Matrix.Cells[3,2]='svarūpa') and
    (Matrix.Cells[4,2]='quote') and
    (Matrix.Cells[5,2]='QUOTE'),
    'LCL вибір san не показав шість pinned проєкцій D3:001');
  SurfaceSelector.ItemIndex:=3; SearchField.Text:='quote';
  SearchButton.Click;
  Check((Length(Hits)=1) and (Hits[0].Domain=3) and
    (Hits[0].Index=1), 'en quote не підтвердив D3:001');
  SurfaceSelector.ItemIndex:=4; SearchField.Text:='QUOTE';
  SearchButton.Click;
  Check((Length(Hits)=1) and (Hits[0].Domain=3) and
    (Hits[0].Index=1), 'LISP QUOTE є лише історичною проєкцією');
  SurfaceSelector.ItemIndex:=0; SearchField.Text:='порожнє?';
  SearchButton.Click;
  Check((Length(Hits)=1) and (Hits[0].Domain=4) and
    (Hits[0].Index=5),'коротка ук D4:0101 втрачена');
  SurfaceSelector.ItemIndex:=1; SearchField.Text:='порожній?';
  SearchButton.Click;
  Check((Length(Hits)=1) and (Hits[0].Domain=4) and
    (Hits[0].Index=5),'довга укр D4:0101 змішалася з ук');
  Found.ItemIndex:=0; Found.Click;
  Check((Matrix.Cells[0,6]='D4:0101') and
    (Matrix.Row=6) and
    (Matrix.Cells[1,6]<>Matrix.Cells[2,6]),
    'клік LCL не перемкнув матрицю до точної D4:0101');
  { Pinned en=map одночасно D6:101000 і D8:11000101. }
  SurfaceSelector.ItemIndex:=3; SearchField.Text:='map';
  SearchButton.Click;
  Check((Length(Hits)=2) and (Found.Items.Count=2) and
    (Hits[0].Domain=6) and (Hits[0].Index=40) and
    (Hits[1].Domain=8) and (Hits[1].Index=197) and
    (Pos('D6:101000',Found.Items[0])=1) and
    (Pos('D8:11000101',Found.Items[1])=1),
    'en=map приховав дві різні exact SENS координати');
  Found.ItemIndex:=1; Found.Click;
  Check((Selector.ItemIndex=7) and (Matrix.Row=198) and
    (Matrix.Cells[0,198]='D8:11000101') and
    (Found.Items.Count=2),
    'другий map-результат перетворив назву на dispatch');
  SurfaceSelector.ItemIndex:=5;
  SearchField.Text:=#34+#39+#34; { sym цитована апострофа }
  SearchButton.Click;
  Check((Length(Hits)=2) and (Hits[0].Domain=3) and
    (Hits[0].Index=1) and (Hits[1].Domain=7) and
    (Hits[1].Index=39),
    'символьна цитата не зберегла дві exact ідентичності');
  SurfaceSelector.ItemIndex:=0; SearchField.Text:='ф';
  SearchButton.Click;
  Check((Length(Hits)=1) and (Hits[0].Domain=7) and
    (Hits[0].Index=97),
    'українське ф має pinned D7:1100001');
  SearchField.Text:='()'; SearchButton.Click;
  Check((Length(Hits)=0) and (Found.Items.Count=0) and
    (Pos('Помилка пошуку проєкції:',Status.Caption)=1),
    '() відсутня поверхня стала функцією/ключем');
  SearchField.Text:=''; SearchButton.Click;
  Check((Length(Hits)=0) and (Found.Items.Count=0),
    'порожній пошук залишив попередні адреси');
  SurfaceSelector.ItemIndex:=3; SearchField.Text:='Map';
  SearchButton.Click;
  Check((Length(Hits)=0) and (Found.Items.Count=0) and
    (Pos('точних збігів 0',Status.Caption)>0),
    'неявна зміна регістру en перетворила Map у map');
  SearchField.Text:='map'; SearchButton.Click;
  Check(Length(Hits)=2,'після відмови пошук pinned en не відновився');
  Selector.ItemIndex:=6; ChangeDomain(Selector);
  Check((Length(Hits)=0) and (Found.Items.Count=0) and
    (Matrix.Cells[0,23]='D7:0010110') and
    (Matrix.Cells[1,23]='(відсутня)'),
    'ручна зміна домену лишила stale пошук або вигадала SYN текст');
  WriteLn('LCL-ШІСТЬ-ПРОЄКЦІЙ-ПОШУК-ГАРАЗД D1-D10=2046',
    ' колонок=ук/укр/san/en/LISP/sym',
    ' san=svarūpa en=quote LISP=QUOTE',
    ' en-map=2 символьна-цитата=2',
    ' D7-SYN=відсутній unicode=точно',
    ' відмови=атомарні вибір=LCL');
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
