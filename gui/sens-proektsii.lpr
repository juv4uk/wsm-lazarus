{ Справжній Lazarus/LCL оглядач pinned D1–D10 та шести проєкцій.
  Лише візуалізація координат, не SENS parser, evaluator або dispatch. }
program sens_proektsii;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Grids,
  ExtCtrls, Dialogs,
  wsm.domain, wsm.proektsii, wsm.t5m, wsm.physloc;
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
    Status,PhysicalNote:TLabel;
    PhysicalPanel:TPanel;
    PhysicalButton:TButton;
    PhysicalDialog:TOpenDialog;
    PhysicalGrid:TStringGrid;
    PhysicalData:RawByteString;
    PhysicalWords:TExactWords;
    PhysicalSpans:TPhysicalWordSpans;
    procedure ClearPhysical;
    function ReadPhysicalD7File(const Path:String):Boolean;
    procedure OpenPhysicalClick(Sender:TObject);
    procedure TestPhysicalD7(const TempDir:String);
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
    procedure SelfTestPhysicalD7(const TempDir:String);
  end;
var Window:TProektsiiForm;
constructor TProektsiiForm.Create(AOwner:TComponent);
const Columns:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var I:Integer; TopLine:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — шість проєкцій точних доменів';
  Width:=1200; Height:=945; Position:=poScreenCenter;
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
  { Д7-фізичні ДАНІ, не прихований syntax/semantic dispatch. }
  PhysicalPanel:=TPanel.Create(Self);
  PhysicalPanel.Parent:=Self; PhysicalPanel.Align:=alBottom;
  PhysicalPanel.Height:=212; PhysicalPanel.BevelOuter:=bvNone;
  PhysicalButton:=TButton.Create(Self);
  PhysicalButton.Parent:=PhysicalPanel;
  PhysicalButton.SetBounds(8,3,350,31);
  PhysicalButton.Caption:='Оглянути двійковий D7-файл .sens';
  PhysicalButton.Enabled:=False;
  PhysicalButton.OnClick:=@OpenPhysicalClick;
  PhysicalDialog:=TOpenDialog.Create(Self);
  PhysicalDialog.Title:='Лише фізичні Д7-дані — не виконуваний код';
  PhysicalDialog.Filter:='Канонічні фізичні дані (*.sens)|*.sens';
  PhysicalDialog.Options:=PhysicalDialog.Options+[ofFileMustExist];
  PhysicalNote:=TLabel.Create(Self);
  PhysicalNote.Parent:=PhysicalPanel;
  PhysicalNote.SetBounds(373,9,815,28);
  PhysicalNote.Caption:='Фізичний D7-файл не відкрито. W7 лише дані.';
  PhysicalGrid:=TStringGrid.Create(Self);
  PhysicalGrid.Parent:=PhysicalPanel;
  PhysicalGrid.SetBounds(8,41,1176,167);
  PhysicalGrid.ColCount:=10; PhysicalGrid.RowCount:=2;
  PhysicalGrid.FixedCols:=1;PhysicalGrid.FixedRows:=1;
  PhysicalGrid.ColWidths[0]:=38; PhysicalGrid.ColWidths[1]:=108;
  PhysicalGrid.ColWidths[2]:=112; PhysicalGrid.ColWidths[3]:=95;
  for I:=4 to 9 do PhysicalGrid.ColWidths[I]:=130;
  PhysicalGrid.Options:=PhysicalGrid.Options-[goEditing];
  PhysicalGrid.Cells[0,0]:='№';
  PhysicalGrid.Cells[1,0]:='Точний Д7:біти';
  PhysicalGrid.Cells[2,0]:='Трити [a,b)';
  PhysicalGrid.Cells[3,0]:='Байти [a,b)';
  PhysicalGrid.Cells[4,0]:='ук';PhysicalGrid.Cells[5,0]:='укр';
  PhysicalGrid.Cells[6,0]:='san';PhysicalGrid.Cells[7,0]:='en';
  PhysicalGrid.Cells[8,0]:='LISP';PhysicalGrid.Cells[9,0]:='sym';
  ClearPhysical;
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
  PhysicalButton.Enabled:=True;
end;

{ Усі файлові дані — ПОЗИЧЕНІ host байти canonical T5M до validation.
  Власні кеші є FPC managed RawByteString/TExactWords/TPhysicalWordSpans,
  живуть у вікні та вивільняються при новому вводі або закритті. }
procedure TProektsiiForm.ClearPhysical;
var J:Integer;
begin
  PhysicalData:='';
  SetLength(PhysicalWords,0);
  SetLength(PhysicalSpans,0);
  PhysicalGrid.RowCount:=2;
  for J:=0 to 9 do PhysicalGrid.Cells[J,1]:='';
  PhysicalNote.Caption:='Фізичні дані не завантажено.';
end;

{ Явно Д7-дані: файл .sens → pinned-derived T5M + адреси → pinned
  Catalog[7]. Ні виклику, ні перетворення ширини W7 на функцію.
  Boolean є лише HOST результатом спроби, не D1-значенням. }
function TProektsiiForm.ReadPhysicalD7File(const Path:String):Boolean;
const MaxPhysicalD7Bytes=65536; MaxPhysicalD7Words=128;
var Input:TFileStream; Physical:RawByteString;
    W:TExactWords; Sp:TPhysicalWordSpans; I,J,K,Code:SizeInt;
begin
  Result:=False;
  ClearPhysical;
  try
    if ExtractFileExt(Path)<>'.sens' then
      raise Exception.Create('Потрібен канонічний двійковий .sens, не .lisp');
    Input:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Input.Size<1) or (Input.Size>MaxPhysicalD7Bytes) then
        raise Exception.Create('Фізичний Д7-файл поза межею 1..65536 байтів');
      SetLength(Physical,SizeInt(Input.Size));
      Input.ReadBuffer(Physical[1],Length(Physical));
    finally Input.Free end;
    DecodeT5MWithLocations(Physical,W,Sp);
    if (EncodeT5M(W)<>Physical) or (Length(W)<1) or
       (Length(W)>MaxPhysicalD7Words) or (Length(Sp)<>Length(W)) then
      raise Exception.Create('Неканонічний або надмірний фізичний Д7-пакет');
    if Length(Catalog[7])<>128 then
      raise Exception.Create('Не завантажено pinned D7 v2');
    for I:=0 to High(W) do begin
      if Length(W[I])<>7 then
        raise Exception.Create('Не W7 у Д7-пакеті, слово='+IntToStr(I+1));
      Code:=0;
      for K:=1 to 7 do begin
        if not (W[I][K] in ['0','1']) then
          raise Exception.Create('Пошкоджене двійкове слово Д7');
        Code:=Code*2+Ord(W[I][K])-Ord('0');
      end;
      if (Catalog[7][Code].Key.Width<>7) or
         (KeyBits(Catalog[7][Code].Key)<>W[I]) or
         (Sp[I].WordIndex<>I+1) or Sp[I].IsEOF then
        raise Exception.Create('Порушено точний pinned ключ / фізичну адресу');
      { Ніякої друкованої функції із SYN чи інших control-гліфів. }
      if (Code=22) and
         ((Catalog[7][Code].Surface[0]<>'') or
          (Catalog[7][Code].Surface[4]<>'')) then
        raise Exception.Create('D7 SYN 0010110 не може мати викличну назву');
    end;
    { ЄДИНА публікація після повної перевірки усіх фізичних слів. }
    PhysicalGrid.RowCount:=Length(W)+1;
    for I:=0 to High(W) do begin
      Code:=0;
      for K:=1 to 7 do Code:=Code*2+Ord(W[I][K])-Ord('0');
      PhysicalGrid.Cells[0,I+1]:=IntToStr(I+1);
      PhysicalGrid.Cells[1,I+1]:='D7:'+String(W[I]);
      PhysicalGrid.Cells[2,I+1]:='['+IntToStr(Sp[I].TritStart)+
        ','+IntToStr(Sp[I].TritEnd)+')';
      PhysicalGrid.Cells[3,I+1]:='['+IntToStr(Sp[I].ByteStart)+
        ','+IntToStr(Sp[I].ByteEnd)+')';
      for J:=0 to 5 do
        PhysicalGrid.Cells[J+4,I+1]:=
          SurfaceForDisplay(Catalog[7][Code].Surface[J]);
    end;
    PhysicalData:=Physical;
    PhysicalWords:=W;
    PhysicalSpans:=Sp;
    PhysicalNote.Caption:='Фізичні D7-дані: '+IntToStr(Length(W))+
      ' точних W7, '+IntToStr(Length(Physical))+
      ' T5M байтів; шість pinned проєкцій, без виконання.';
    Result:=True;
  except on E:Exception do begin
    ClearPhysical;
    PhysicalNote.Caption:='Відхилено D7 .sens: '+E.Message;
  end end;
end;

procedure TProektsiiForm.OpenPhysicalClick(Sender:TObject);
begin
  if PhysicalDialog.Execute then ReadPhysicalD7File(PhysicalDialog.FileName);
end;

{ Лише в --selftest: власні файли в унікальному тимчасовому каталозі,
  наданому оболонкою CI. Це НЕ шлях публікації користувацьких .sens.
  Усі byte-exact очікування порівнюються із чинним FPC EncodeT5M. }
procedure TProektsiiForm.TestPhysicalD7(const TempDir:String);
var F:TFileStream;Good,Bad,T5,Many,Path:String;
    W:TExactWords;I:SizeInt;
  procedure SaveOne(const Name:String;const Data:RawByteString);
  var S:TFileStream;
  begin
    S:=TFileStream.Create(IncludeTrailingPathDelimiter(TempDir)+Name,fmCreate);
    try S.WriteBuffer(Data[1],Length(Data)) finally S.Free end;
  end;
begin
  Check(DirectoryExists(TempDir),'Немає ізольованого тимчасового каталогу');
  Good:=IncludeTrailingPathDelimiter(TempDir)+'дані.sens';
  Bad:=IncludeTrailingPathDelimiter(TempDir)+'пошкоджений.sens';
  SetLength(W,3);
  W[0]:='1100001';W[1]:='0010110';W[2]:='0100111';
  T5:=EncodeT5M(W);
  SaveOne('дані.sens',T5);
  Check(ReadPhysicalD7File(Good),'Реальний canonical Д7-файл відхилено');
  Check((PhysicalData=T5) and (Length(PhysicalWords)=3) and
    (Length(PhysicalSpans)=3) and (PhysicalGrid.RowCount=4),
    'Фізичний D7 snapshot не збережений цілком');
  Check((PhysicalGrid.Cells[1,1]='D7:1100001') and
    (PhysicalGrid.Cells[1,2]='D7:0010110') and
    (PhysicalGrid.Cells[2,1]='[0,7)') and
    (PhysicalGrid.Cells[2,2]='[8,15)') and
    (PhysicalGrid.Cells[2,3]='[16,23)') and
    (PhysicalGrid.Cells[3,2]='[1,3)'),
    'Втрата exact D7 біта чи тритової/байтової адреси');
  Check((PhysicalGrid.Cells[4,1]=
    SurfaceForDisplay(Catalog[7][97].Surface[0])) and
    (PhysicalGrid.Cells[4,2]='(відсутня)') and
    (PhysicalGrid.Cells[8,2]='(відсутня)') and
    (PhysicalGrid.Cells[9,3]=
    SurfaceForDisplay(Catalog[7][39].Surface[5])),
    'Шість pinned проєкцій або контроль SYN некоректні');
  SaveOne('пошкоджений.sens',Chr(243));
  Check(not ReadPhysicalD7File(Bad),'243-й байт T5M мав бути відхилений');
  Check((PhysicalData='') and (Length(PhysicalWords)=0) and
    (PhysicalGrid.Cells[1,1]=''),
    'Невдалий фізичний вхід лишив стару таблицю');
  SetLength(W,2);W[0]:='1100001';W[1]:='1';
  SaveOne('неповне.sens',EncodeT5M(W));
  Check(not ReadPhysicalD7File(
    IncludeTrailingPathDelimiter(TempDir)+'неповне.sens'),
    'Пізнє W1 помилково видане за D7');
  Check((PhysicalData='') and (PhysicalGrid.Cells[1,1]=''),
    'Пізня W1 відмова опублікувала перший D7 рядок');
  SetLength(W,129);
  for I:=0 to High(W) do W[I]:='1100001';
  SaveOne('надмірне.sens',EncodeT5M(W));
  Check(not ReadPhysicalD7File(
    IncludeTrailingPathDelimiter(TempDir)+'надмірне.sens'),
    '129 D7 слів перевищили межу');
  Check(not ReadPhysicalD7File(
    IncludeTrailingPathDelimiter(TempDir)+'дані.lisp'),
    '.lisp неправомірно прийнято за фізичні дані');
  Check(not ReadPhysicalD7File(
    IncludeTrailingPathDelimiter(TempDir)+'відсутній.sens'),
    'Відсутній файл не відхилено');
  Check((PhysicalData='') and (Length(PhysicalSpans)=0),
    'Негативи не стерли фізичні адреси');
  Check(ReadPhysicalD7File(Good) and (PhysicalData=T5) and
    (PhysicalGrid.Cells[2,3]='[16,23)'),
    'Після негативів canonical D7 не відновився');
  Check((Matrix.ColCount=7) and
    (Matrix.Cells[0,23]='D7:0010110'),
    'Д7-файловий огляд зруйнував шість колонок основної матриці');
  WriteLn('LCL-Д7-ФАЙЛ-ПРОЄКЦІЇ-ГАРАЗД ',
    'Lazarus=GTK2 T5M=канонічно слів=3 ',
    'адреси=трит/байт SYN=контроль ',
    'колонок=6 W1-пізній=відхилено 129=відхилено ',
    'помилки=атомарні відновлення=так без-виконання=так');
end;

procedure TProektsiiForm.SelfTestPhysicalD7(const TempDir:String);
begin TestPhysicalD7(TempDir) end;

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
    if (ParamCount>=2) and (ParamCount<=3) and
       (ParamStr(1)='--selftest') then begin
      Window.LoadAuthority(ParamStr(2));
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest;
      if ParamCount=3 then begin
        Window.SelfTestPhysicalD7(ParamStr(3));
      end;
    end else if ParamCount=0 then begin
      Window.LoadAuthority('external/sens');
      Window.Show;
      Application.Run;
    end else raise Exception.Create('Виклик: sens-proektsii [--selftest ROOT [TMP]]');
  finally Window.Free end;
end.
