{ G3.29: справжній Lazarus/LCL оглядач точних числових D12+.
  Вхід — лише людська десяткова проєкція або канонічний фізичний T5M.
  Мовна влада належить pinned SENS; арифметики та реєстру законів немає.
  Жодного записування .sens з GUI: тільки перевірений read-only snapshot. }
program sens_chysla_d12;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Dialogs, Grids,
  wsm.t5m, wsm.physloc, wsm.numericplane;

type
  { Borrowed physical coordinates become a private, verified GUI snapshot.
    Number: managed exact bits and explicit D12+; Span: transport location only.
    Decimal: presentation-only text, never a new numeric law. }
  TNumericBatchRow = record
    Number: TExplicitNumeric;
    Span: TPhysicalWordSpan;
    Decimal: RawByteString;
  end;
  TNumericBatchRows = array of TNumericBatchRow;

  TNumericWindow = class(TForm)
  private
    FDomain: TComboBox;
    FDecimal: TEdit;
    FEncode: TButton;
    FOpen: TButton;
    FOpenBatch: TButton;
    FDialog: TOpenDialog;
    FBatchGrid: TStringGrid;
    FBatchRows: TNumericBatchRows;
    FResult: TMemo;
    FStatus: TLabel;
    FPhysical: RawByteString; { власна перевірена фізична копія }
    FTestPath: String;       { лише host шлях для GUI самоперевірки }
    FBatchTestPath: String;  { окремий host шлях для пакетної перевірки }
    procedure ClearSnapshot;
    procedure DomainChanged(Sender: TObject);
    procedure DecimalChanged(Sender: TObject);
    procedure EncodeClicked(Sender: TObject);
    procedure OpenClicked(Sender: TObject);
    procedure OpenBatchClicked(Sender: TObject);
    procedure BatchSelected(Sender: TObject; ACol, ARow: Longint;
      var CanSelect: Boolean);
    procedure ShowBatchRow(ARow: SizeInt);
    procedure Publish(const Bytes: RawByteString;
      const Number: TExplicitNumeric);
    function ExplicitWidth: SizeInt;
    procedure Demand(Ok: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function ReadPhysicalFile(const Path: String): Boolean;
    function ReadPhysicalBatch(const Path: String): Boolean;
    procedure SelfCheck(const Good12, Good192, Corrupt, TextFile,
      GoodBatch, LateBadBatch, MixedBatch, ExcessBatch,
      Good24, Good48, Good96: String);
  end;

var Window: TNumericWindow;

constructor TNumericWindow.Create(AOwner: TComponent);
const Domains: array[0..4] of String=('D12','D24','D48','D96','D192');
var I: Integer; CaptionLabel: TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — точні числові домени D12–D192';
  Position:=poScreenCenter;
  Width:=1040; Height:=795;

  CaptionLabel:=TLabel.Create(Self);
  CaptionLabel.Parent:=Self;
  CaptionLabel.SetBounds(16,16,930,26);
  CaptionLabel.Caption:='Числовий домен обирається явно. Десятковий запис — українська людська проєкція.';
  FDomain:=TComboBox.Create(Self);
  FDomain.Parent:=Self;
  FDomain.SetBounds(16,52,148,32);
  FDomain.Style:=csDropDownList;
  for I:=0 to High(Domains) do FDomain.Items.Add(Domains[I]);
  FDomain.ItemIndex:=0;
  FDomain.OnChange:=@DomainChanged;

  FDecimal:=TEdit.Create(Self);
  FDecimal.Parent:=Self;
  FDecimal.SetBounds(172,52,770,32);
  FDecimal.Text:='-2048';
  FDecimal.OnChange:=@DecimalChanged;

  FEncode:=TButton.Create(Self);
  FEncode.Parent:=Self;
  FEncode.SetBounds(16,104,310,42);
  FEncode.Caption:='Перевірити десятковий запис → двійковий .sens';
  FEncode.OnClick:=@EncodeClicked;
  FOpen:=TButton.Create(Self);
  FOpen.Parent:=Self;
  FOpen.SetBounds(340,104,315,42);
  FOpen.Caption:='Відкрити фізичний .sens (явний домен)';
  FOpen.OnClick:=@OpenClicked;
  FOpenBatch:=TButton.Create(Self);
  FOpenBatch.Parent:=Self;
  FOpenBatch.SetBounds(668,104,350,42);
  FOpenBatch.Caption:='Відкрити пакет точних чисел .sens';
  FOpenBatch.OnClick:=@OpenBatchClicked;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Виберіть канонічний двійковий файл SENS';
  FDialog.Filter:='SENS фізичний (*.sens)|*.sens';

  FStatus:=TLabel.Create(Self);
  FStatus.Parent:=Self;
  FStatus.SetBounds(16,155,930,38);
  FStatus.Caption:='Введіть звичайне десяткове число або відкрийте .sens.';
  FResult:=TMemo.Create(Self);
  FResult.Parent:=Self;
  FResult.SetBounds(16,201,1002,172);
  FResult.ReadOnly:=True;
  FResult.WordWrap:=False;
  FResult.ScrollBars:=ssBoth;
  FBatchGrid:=TStringGrid.Create(Self);
  FBatchGrid.Parent:=Self;
  FBatchGrid.SetBounds(16,386,1002,338);
  FBatchGrid.ColCount:=6; FBatchGrid.FixedCols:=0;
  FBatchGrid.RowCount:=2; FBatchGrid.FixedRows:=1;
  FBatchGrid.ColWidths[0]:=75;
  FBatchGrid.ColWidths[1]:=90;
  FBatchGrid.ColWidths[2]:=150;
  FBatchGrid.ColWidths[3]:=250;
  FBatchGrid.ColWidths[4]:=190;
  FBatchGrid.ColWidths[5]:=202;
  FBatchGrid.Cells[0,0]:='Слово';
  FBatchGrid.Cells[1,0]:='Домен';
  FBatchGrid.Cells[2,0]:='Укр';
  FBatchGrid.Cells[3,0]:='Точні біти';
  FBatchGrid.Cells[4,0]:='Трити [від,до)';
  FBatchGrid.Cells[5,0]:='Байти [від,до)';
  FBatchGrid.OnSelectCell:=@BatchSelected;
  FTestPath:='';
  FBatchTestPath:='';
  FPhysical:='';
end;

{ Усі результати стають недійсними до першого кроку нового вводу.
  Host Boolean повертає лише успіх дії, не має стосунку до SENS D1. }
procedure TNumericWindow.ClearSnapshot;
begin
  FPhysical:='';
  SetLength(FBatchRows,0);
  FBatchGrid.RowCount:=2;
  { Скидаємо останній видимий рядок після зменшення RowCount. }
  FBatchGrid.Cells[0,1]:=''; FBatchGrid.Cells[1,1]:='';
  FBatchGrid.Cells[2,1]:=''; FBatchGrid.Cells[3,1]:='';
  FBatchGrid.Cells[4,1]:=''; FBatchGrid.Cells[5,1]:='';
  FResult.Clear;
  FStatus.Caption:='Немає перевіреного фізичного результату.';
end;

procedure TNumericWindow.DomainChanged(Sender:TObject);
begin
  ClearSnapshot;
end;

procedure TNumericWindow.DecimalChanged(Sender:TObject);
begin
  ClearSnapshot;
end;

function TNumericWindow.ExplicitWidth:SizeInt;
begin
  if (FDomain.ItemIndex<0) or
     (FDomain.ItemIndex>=FDomain.Items.Count) then
    raise ENumericPlaneError.Create('виберіть числовий домен');
  Result:=SelectedNumericDomain(RawByteString(FDomain.Items[FDomain.ItemIndex]));
end;

{ Bytes: канонічний T5M, Number: уже перевірений точний явний домен.
  RawByteString має власне FPC ref-counted життя, жодних native pointers.
  Коміт віджетів відбувається лише ПІСЛЯ всього byte/width/round-trip guard. }
procedure TNumericWindow.Publish(const Bytes: RawByteString;
  const Number:TExplicitNumeric);
var TextNumber:RawByteString;
begin
  if Length(Number.ExactBits)<>Number.DomainWidth then
    raise ENumericPlaneError.Create('втрачено точну ширину числа');
  TextNumber:=RenderNumericDecimal(Number);
  if EncodeNumericDecimal(TextNumber, Number.DomainWidth)<>Bytes then
    raise ENumericPlaneError.Create('не зійшлися фізичні байти T5M');
  FPhysical:=Bytes;
  FResult.Lines.Add('Явний домен: D'+IntToStr(Number.DomainWidth));
  FResult.Lines.Add('Точні двійкові біти ('+
    IntToStr(Length(Number.ExactBits))+'): '+String(Number.ExactBits));
  FResult.Lines.Add('Українська десяткова проєкція: '+String(TextNumber));
  FResult.Lines.Add('Канонічний .sens: '+IntToStr(Length(Bytes))+
    ' фізичних байтів T5M (лише перегляд, без запису).');
  FResult.Lines.Add('D1:0, D3:000, D7 та викличність не визначають число.');
  FStatus.Caption:='Фізичний T5M та точна числова проєкція перевірені.';
end;

procedure TNumericWindow.EncodeClicked(Sender:TObject);
var SelectedWidth:SizeInt; Physical:RawByteString; Num:TExplicitNumeric;
begin
  ClearSnapshot;
  try
    SelectedWidth:=ExplicitWidth;
    Physical:=EncodeNumericDecimal(RawByteString(FDecimal.Text),SelectedWidth);
    Num:=ReadNumericPhysical(Physical,SelectedWidth);
    if RenderNumericDecimal(Num)<>RawByteString(FDecimal.Text) then
      raise ENumericPlaneError.Create('необоротна десяткова проєкція');
    Publish(Physical,Num);
  except
    on E:Exception do begin
      ClearSnapshot;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

{ Path — лише host шлях, ніколи не є SENS програмою або мовним законом.
  Stream звільняється в finally; понад 64 байти відхиляються ДО читання.
  Помилка не залишає старий snapshot, новий — не публікується частково. }
function TNumericWindow.ReadPhysicalFile(const Path:String):Boolean;
var Stream:TFileStream; Bytes:RawByteString; Number:TExplicitNumeric;
begin
  Result:=False;
  ClearSnapshot;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise ENumericPlaneError.Create('очікується двійковий .sens, не .lisp');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<=0) or (Stream.Size>64) then
        raise ENumericPlaneError.Create('некоректна довжина фізичного числа');
      SetLength(Bytes,SizeInt(Stream.Size));
      Stream.ReadBuffer(Bytes[1],Length(Bytes));
    finally Stream.Free;end;
    Number:=ReadNumericPhysical(Bytes,ExplicitWidth);
    Publish(Bytes,Number);
    Result:=True;
  except
    on E:Exception do begin
      ClearSnapshot;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

{ Той самий admission, що й у пакетному FPC CLI: перевірені координати
  wsm.physloc, явний numericplane на кожному окремому точному слові.
  Дані живуть у локальних managed arrays до повного допуску.
  FBatchRows/FPhysical і TStringGrid стають видимими лише після всіх слів.
  Помилка на останньому слові відхиляє цілий пакет, не частковий UI.
  Вхідний Path — host шлях, не SENS код; усі TFileStream звільнено. }
function TNumericWindow.ReadPhysicalBatch(const Path:String):Boolean;
const
  MaxBatchBytes=65536;
  MaxBatchWords=1024;
var
  Stream:TFileStream;
  Bytes, PackedOne, Decimal:RawByteString;
  Words, One:TExactWords;
  Spans:TPhysicalWordSpans;
  Candidate:TNumericBatchRows;
  N:TExplicitNumeric;
  DomainWidth,I:SizeInt;
begin
  Result:=False;
  ClearSnapshot;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise ENumericPlaneError.Create('для пакета потрібен фізичний .sens');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxBatchBytes) then
        raise ENumericPlaneError.Create('пакет поза фізичною межею 1..65536 байтів');
      SetLength(Bytes,SizeInt(Stream.Size));
      Stream.ReadBuffer(Bytes[1],Length(Bytes));
    finally
      Stream.Free;
    end;

    DomainWidth:=ExplicitWidth;
    DecodeT5MWithLocations(Bytes,Words,Spans);
    if (Length(Words)<1) or (Length(Words)>MaxBatchWords) or
       (Length(Spans)<>Length(Words)) then
      raise ENumericPlaneError.Create('пакет поза межею 1..1024 слів');
    if EncodeT5M(Words)<>Bytes then
      raise ENumericPlaneError.Create('пакет має неканонічні T5M байти');
    SetLength(Candidate,Length(Words));
    SetLength(One,1);
    for I:=0 to High(Words) do begin
      One[0]:=Words[I];
      { Ширина не є самостійною семантикою: домен уже вибрано вручну. }
      if Length(One[0])<>DomainWidth then
        raise ENumericPlaneError.Create('слово '+IntToStr(I+1)+
          ': фізична ширина не відповідає явному числовому домену');
      PackedOne:=EncodeT5M(One);
      N:=ReadNumericPhysical(PackedOne,DomainWidth);
      Decimal:=RenderNumericDecimal(N);
      if EncodeNumericDecimal(Decimal,DomainWidth)<>PackedOne then
        raise ENumericPlaneError.Create('втрачено точні байти слова '+IntToStr(I+1));
      Candidate[I].Span:=LocatePhysicalWord(Bytes,Spans,I+1);
      if (Candidate[I].Span.WordIndex<>I+1) or
         (Candidate[I].Span.TritEnd-Candidate[I].Span.TritStart<>DomainWidth) then
        raise ENumericPlaneError.Create('невірні фізичні координати слова');
      Candidate[I].Number:=N;
      Candidate[I].Decimal:=Decimal;
    end;

    { Commit: немає жодного неперевіреного рядка. Якщо сам GUI не зможе
      опублікувати, обробник нижче очищає цілий managed snapshot. }
    FPhysical:=Bytes;
    FBatchRows:=Candidate;
    FBatchGrid.RowCount:=Length(FBatchRows)+1;
    for I:=0 to High(FBatchRows) do begin
      FBatchGrid.Cells[0,I+1]:=IntToStr(FBatchRows[I].Span.WordIndex);
      FBatchGrid.Cells[1,I+1]:='D'+IntToStr(DomainWidth);
      FBatchGrid.Cells[2,I+1]:=String(FBatchRows[I].Decimal);
      FBatchGrid.Cells[3,I+1]:=String(FBatchRows[I].Number.ExactBits);
      FBatchGrid.Cells[4,I+1]:='['+
        IntToStr(FBatchRows[I].Span.TritStart)+','+
        IntToStr(FBatchRows[I].Span.TritEnd)+')';
      FBatchGrid.Cells[5,I+1]:='['+
        IntToStr(FBatchRows[I].Span.ByteStart)+','+
        IntToStr(FBatchRows[I].Span.ByteEnd)+')';
    end;
    ShowBatchRow(1);
    FStatus.Caption:='Пакет допущено повністю: '+IntToStr(Length(FBatchRows))+
      ' точних числових слів D'+IntToStr(DomainWidth)+'.';
    Result:=True;
  except
    on E:Exception do begin
      ClearSnapshot;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

procedure TNumericWindow.ShowBatchRow(ARow:SizeInt);
var Item:TNumericBatchRow;
begin
  FResult.Clear;
  if (ARow<1) or (ARow>Length(FBatchRows)) then Exit;
  Item:=FBatchRows[ARow-1];
  FResult.Lines.Add('Слово №'+IntToStr(Item.Span.WordIndex)+
    ', явний D'+IntToStr(Item.Number.DomainWidth));
  FResult.Lines.Add('Десяткова проєкція укр: '+String(Item.Decimal));
  FResult.Lines.Add('Точні біти: '+String(Item.Number.ExactBits));
  FResult.Lines.Add('Трити=['+IntToStr(Item.Span.TritStart)+','+
    IntToStr(Item.Span.TritEnd)+'); байти=['+
    IntToStr(Item.Span.ByteStart)+','+IntToStr(Item.Span.ByteEnd)+')');
  FResult.Lines.Add('D7 — лише текстові дані; арифметика не виконується.');
end;

procedure TNumericWindow.BatchSelected(Sender:TObject; ACol,ARow:Longint;
  var CanSelect:Boolean);
begin
  CanSelect:=True;
  ShowBatchRow(ARow);
end;

procedure TNumericWindow.OpenBatchClicked(Sender:TObject);
begin
  if FBatchTestPath<>'' then ReadPhysicalBatch(FBatchTestPath)
  else if FDialog.Execute then ReadPhysicalBatch(FDialog.FileName);
end;

procedure TNumericWindow.OpenClicked(Sender:TObject);
begin
  if FTestPath<>'' then ReadPhysicalFile(FTestPath)
  else if FDialog.Execute then ReadPhysicalFile(FDialog.FileName);
end;

procedure TNumericWindow.Demand(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('LCL-ЧИСЛО-ТЕСТ: '+Why);
end;

{ Тести натискають РЕАЛЬНІ LCL кнопки та виконують справжній numericplane.
  Два файли Good містять незалежно створений FPC CLI канонічний T5M. }
procedure TNumericWindow.SelfCheck(
  const Good12, Good192, Corrupt, TextFile,
  GoodBatch,LateBadBatch,MixedBatch,ExcessBatch,
  Good24,Good48,Good96:String);
const
  LargeMin='-3138550867693340381917894711603833208051177722232017256448';
var I:Integer; Accept:Boolean;
    NumericWidth:SizeInt; Physical24,Physical48,Physical96,Prior:RawByteString;
    PhysicalPaths:array[1..3] of String;
begin
  FDomain.ItemIndex:=0;
  FDecimal.Text:='-2048'; FEncode.Click;
  Demand((Pos('D12',FResult.Text)>0) and
    (Pos('100000000000',FResult.Text)>0) and
    (FPhysical<>''),'D12 мінімум не породив точний T5M');
  FDecimal.Text:='2047'; FEncode.Click;
  Demand(Pos('011111111111',FResult.Text)>0,
    'D12 максимум утратив старший нуль');
  for I:=0 to 4 do begin
    FDomain.ItemIndex:=I;
    FDecimal.Text:='-1'; FEncode.Click;
    Demand((FPhysical<>'') and
      (Pos(StringOfChar('1',SelectedNumericDomain(
        RawByteString(FDomain.Items[I]))),FResult.Text)>0),
      'не пройшла точна знакова ширина D12/D24/D48/D96/D192');
  end;

  FDomain.ItemIndex:=0;
  FDecimal.Text:='2048'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text='') and
    (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),
    'переповнення D12 залишило попередній snapshot');
  FDecimal.Text:='-0'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'неканонічний мінус-нуль прийнято');
  FDecimal.Text:='00'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'неканонічні початкові нулі прийнято');
  FDecimal.Text:='1.5'; FEncode.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'дробовий літерал без окремого закону прийнято');

  FTestPath:=Good12; FOpen.Click;
  Demand((FPhysical<>'') and (Pos('100000000000',FResult.Text)>0),
    'реальний фізичний D12 не прочитано');
  FDomain.ItemIndex:=1; FTestPath:=Good12; FOpen.Click;
  Demand((FPhysical='') and (FResult.Text='') and
    (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),
    'неявне розширення D12→D24 допущено');

  FDomain.ItemIndex:=4; FTestPath:=Good192; FOpen.Click;
  Demand((FPhysical<>'') and (Pos(LargeMin,FResult.Text)>0) and
    (Pos('Точні двійкові біти (192):',FResult.Text)>0),
    'втрачено фізичну D192 мінімальну межу');

  { Три незалежні .sens створює зовнішній FPC CLI, не GUI.
    Домен користувач обирає явно; T5M та числова семантика з pinned SENS.
    PhysicalPaths — позичені host strings, FPhysical — owned managed bytes.
    1) Чому D24/D48/D96 не виводимо із десяткового -7?
    2) Чому ширини не можна об'єднувати?
    3) Чи лишається застарілий snapshot після помилки?
    4) Чому файл створюється незалежним CLI, а не віджетом? }
  PhysicalPaths[1]:=Good24;
  PhysicalPaths[2]:=Good48;
  PhysicalPaths[3]:=Good96;
  Physical24:=''; Physical48:=''; Physical96:='';
  for I:=1 to 3 do begin
    FDomain.ItemIndex:=I;
    FTestPath:=PhysicalPaths[I];
    FOpen.Click;
    NumericWidth:=SelectedNumericDomain(RawByteString(FDomain.Items[I]));
    Demand((FPhysical<>'') and
      (FPhysical=EncodeNumericDecimal('-7',NumericWidth)) and
      (Pos('Точні двійкові біти ('+IntToStr(NumericWidth)+'):',FResult.Text)>0) and
      (Pos('Українська десяткова проєкція: -7',FResult.Text)>0),
      'D'+IntToStr(NumericWidth)+': файл не відповідає явному домену');
    Prior:=FPhysical;
    case I of
      1: Physical24:=Prior;
      2: Physical48:=Prior;
      3: Physical96:=Prior;
    end;
    FDomain.ItemIndex:=(I mod 3)+1;
    FOpen.Click;
    Demand((FPhysical='') and (FResult.Text='') and
      (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),
      'D'+IntToStr(NumericWidth)+': чужий домен прийнято або залишено snapshot');
    FDomain.ItemIndex:=I;
    FOpen.Click;
    Demand(FPhysical=Prior,
      'D'+IntToStr(NumericWidth)+': не відновлено фізичний файл після відмови');
  end;
  Demand((Physical24<>Physical48) and
    (Physical48<>Physical96) and (Physical24<>Physical96),
    'три точні фізичні ширини помилково збіглися');
  WriteLn('LCL-ЧИСЛА-СЕРЕДНІ-ДОМЕНИ-ГАРАЗД ',
    'D24+D48+D96=3 фізичних-T5M=звірено ',
    'чужий-домен=відхилено відновлення=так');

  FTestPath:=Corrupt; FOpen.Click;
  Demand((FPhysical='') and (FResult.Text='') and
    (Pos('ВІДХИЛЕНО:',FStatus.Caption)=1),
    'пошкоджений T5M залишив старі дані');
  FTestPath:=TextFile; FOpen.Click;
  Demand((FPhysical='') and (FResult.Text=''),
    'текстова .lisp підмінила фізичний .sens');
  FDomain.ItemIndex:=4; { Відновити явний D192 після перевірок D24/D48/D96. }
  Demand(ExplicitWidth=192,'помилка відновлення явного D192');
  FTestPath:=Good192; FOpen.Click;
  Demand((FPhysical<>'') and (Pos(LargeMin,FResult.Text)>0),
    'не відновлено читання після негативів');
  { Три точні T5M слова, а не одна десяткова програма. }
  FDomain.ItemIndex:=0;
  FBatchTestPath:=GoodBatch;
  FOpenBatch.Click;
  Demand((Length(FBatchRows)=3) and (FBatchGrid.RowCount=4) and
    (FPhysical<>'') and
    (FBatchGrid.Cells[2,1]='-2048') and
    (FBatchGrid.Cells[2,2]='-1') and
    (FBatchGrid.Cells[2,3]='0') and
    (FBatchGrid.Cells[3,1]='100000000000') and
    (FBatchGrid.Cells[3,2]='111111111111') and
    (FBatchGrid.Cells[3,3]='000000000000'),
    'пакет утратив точні фізичні D12 атоми');
  Demand((FBatchRows[0].Span.WordIndex=1) and
    (FBatchRows[0].Span.TritStart=0) and
    (FBatchRows[0].Span.TritEnd=12) and
    (FBatchRows[0].Span.ByteStart=0) and
    (FBatchRows[0].Span.ByteEnd=3) and
    (FBatchRows[1].Span.WordIndex=2) and
    (FBatchRows[1].Span.TritStart=13) and
    (FBatchRows[1].Span.TritEnd=25) and
    (FBatchRows[1].Span.ByteStart=2) and
    (FBatchRows[1].Span.ByteEnd=5) and
    (FBatchRows[2].Span.WordIndex=3) and
    (FBatchRows[2].Span.TritStart=26) and
    (FBatchRows[2].Span.TritEnd=38) and
    (FBatchRows[2].Span.ByteStart=5) and
    (FBatchRows[2].Span.ByteEnd=8),
    'неточні фізичні три- і байтові межі');
  Accept:=True; BatchSelected(FBatchGrid,2,2,Accept);
  Demand(Accept and (Pos('Слово №2',FResult.Text)>0) and
    (Pos('Трити=[13,25)',FResult.Text)>0),
    'відмова у виборі другого реального слова');

  FDomain.ItemIndex:=1;
  FOpenBatch.Click;
  Demand((FPhysical='') and (Length(FBatchRows)=0) and
    (FBatchGrid.RowCount=2) and (FBatchGrid.Cells[3,1]='') and
    (FResult.Text=''), 'неявне D12→D24 залишило фізичні клітинки');
  FDomain.ItemIndex:=0;
  FBatchTestPath:=LateBadBatch;
  FOpenBatch.Click;
  Demand((FPhysical='') and (Length(FBatchRows)=0) and
    (FBatchGrid.RowCount=2) and (FBatchGrid.Cells[2,1]='') and
    (FResult.Text=''), 'пізній W13 залишив частковий пакет');
  FBatchTestPath:=MixedBatch;
  FOpenBatch.Click;
  Demand((FPhysical='') and (Length(FBatchRows)=0) and
    (FBatchGrid.RowCount=2) and (FBatchGrid.Cells[3,1]=''),
    'пакет зі змішаними W12/W1 залишив рядки');
  FBatchTestPath:=ExcessBatch;
  FOpenBatch.Click;
  Demand((FPhysical='') and (Length(FBatchRows)=0) and
    (FBatchGrid.RowCount=2) and (FResult.Text=''),
    'пакет із 1025 слів подолав квоту');
  FBatchTestPath:=Corrupt;
  FOpenBatch.Click;
  Demand((FPhysical='') and (FBatchGrid.RowCount=2),
    'зіпсований T5M залишив пакет');
  FBatchTestPath:=TextFile;
  FOpenBatch.Click;
  Demand((FPhysical='') and (FBatchGrid.RowCount=2),
    'текстова проєкція пройшла як фізичний пакет');
  FBatchTestPath:=GoodBatch;
  FOpenBatch.Click;
  Demand((Length(FBatchRows)=3) and
    (Pos('Пакет допущено повністю',FStatus.Caption)>0),
    'не відновлено пакет після негативних свідків');
  FDecimal.Text:='2047';
  Demand((FPhysical='') and (Length(FBatchRows)=0) and
    (FBatchGrid.Cells[3,1]=''),
    'редагування числової проєкції не очистило пакет');

  WriteLn('LCL-ЧИСЛА-ПАКЕТ-ГАРАЗД Lazarus=GTK2 ',
    'D12=три-слова trit=[0,12)/[13,25)/[26,38) ',
    'байти=[0,3)/[2,5)/[5,8) пізня-відмова=атомарна ');
  WriteLn('LCL-ЧИСЛА-D12-ГАРАЗД Lazarus=GTK2 FPC=реальний ',
    'D12-D192=точні T5M=канонічний укр=проєкція ',
    'переповнення=відхилено W12->W24=неявно-заборонено ',
    'очищення=атомарне арифметика=НЕ-ДОВЕДЕНА');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — точні числа D12–D192';
    Application.CreateForm(TNumericWindow,Window);
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>12 then Halt(64);
      Window.Show; Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5),
        ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9),
        ParamStr(10),ParamStr(11),ParamStr(12));
      Window.Free;
      Halt(0);
    end;
    if ParamCount<>0 then Halt(64);
    Application.Run;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-ЧИСЛА-D12-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
