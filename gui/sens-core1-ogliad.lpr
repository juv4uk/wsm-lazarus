{ G1.49 — справжнє вікно Lazarus фізичної бібліотеки сучасного Core1.
  Канонічний T5M і D2 читаються лише чинними native units. ukr — проєкція.
  Жодного DEFINE/LAMBDA evaluator, нового закону SENS чи Core1 REPL. }
program sens_core1_ogliad;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Dialogs,
  Grids, wsm.t5m, wsm.d2source, wsm.physloc, wsm.source
  {$IFDEF UNIX}, cwstring, BaseUnix{$ENDIF};

type
  TRootEvidence = record
    WordStart, WordAfter, TritStart, TritAfter, ByteStart, ByteAfter: SizeInt;
    Head: String;  { Wn:exact bits, НІКОЛИ текстовий semantic dispatch }
  end;
  TRootEvidenceList = array of TRootEvidence;

  TCore1Form = class(TForm)
  private
    FPhysical, FHuman:TEdit;
    FOpen,FSave:TButton;
    FPick:TOpenDialog;
    FSaveDialog:TSaveDialog;
    FGrid:TStringGrid;
    FDetails, FProjection:TMemo;
    FState:TLabel;
    FRoots:TRootEvidenceList;
    FPhysicalBytes:RawByteString; { лише допущена фізична T5M копія }
    FTestTarget:String; { тільки GUI самоперевірка }
    procedure ClearSnapshot;
    procedure PathEdited(Sender:TObject);
    procedure SelectFile(Sender:TObject);
    procedure OpenClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    function ExportRoot(RootIndex:SizeInt;const Path:String):Boolean;
    procedure PublishPhysical(const Path:String;const Bytes:RawByteString);
    procedure SelectRow(Sender:TObject; Col,Row:LongInt;
      var CanSelect:Boolean);
    procedure ShowDetails(RowIndex:SizeInt);
    function ReadBounded(const Filename,Extension:String;
      MaxBytes:Int64):RawByteString;
    procedure Need(Ok:Boolean;const Why:String);
  public
    constructor Create(AOwner:TComponent); override;
    function LoadCore1(const PhysicalPath,ProjectionPath:String):Boolean;
    procedure SelfCheck(const Good,Human,Bad,InvalidHuman,TempDir:String);
  end;

var Window:TCore1Form;

{$IFDEF UNIX}
function CreatePrivateTemp(Template:PChar):cint; cdecl; external 'c' name 'mkstemp';
{$ENDIF}

procedure OutputUtf8(const MessageText:UnicodeString);
const LF:AnsiChar=#10;
var Bytes:UTF8String; F:THandleStream;
begin
  Bytes:=UTF8Encode(MessageText);
  F:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
    F.WriteBuffer(LF,1);
  finally F.Free; end;
end;

constructor TCore1Form.Create(AOwner:TComponent);
var LabelText:TLabel; B:TButton;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — сучасний Core1: фізичний оглядач';
  Width:=1190; Height:=785; Position:=poScreenCenter;
  LabelText:=TLabel.Create(Self); LabelText.Parent:=Self;
  LabelText.SetBounds(12,8,1160,24);
  LabelText.Caption:='Двійковий .sens — канон. .lisp — лише українська «укр» проєкція. Виконання Core1 не заявлене.';
  FPhysical:=TEdit.Create(Self); FPhysical.Parent:=Self;
  FPhysical.SetBounds(12,40,970,28); FPhysical.Text:='external/sens/lib/core1.sens';
  FHuman:=TEdit.Create(Self); FHuman.Parent:=Self;
  FHuman.SetBounds(12,75,970,28); FHuman.Text:='external/sens/lib/core1.lisp';
  B:=TButton.Create(Self); B.Parent:=Self;
  B.SetBounds(997,40,177,29);
  B.Caption:='Вибрати файл .sens'; B.OnClick:=@SelectFile;
  FOpen:=TButton.Create(Self); FOpen.Parent:=Self;
  FOpen.SetBounds(997,76,177,29);
  FOpen.Caption:='Завантажити Core1'; FOpen.OnClick:=@OpenClick;
  FSave:=TButton.Create(Self); FSave.Parent:=Self;
  FSave.SetBounds(997,111,177,29);
  FSave.Caption:='Зберегти корінь';
  FSave.OnClick:=@SaveClick; FSave.Enabled:=False;
  FSaveDialog:=TSaveDialog.Create(Self);
  FSaveDialog.DefaultExt:='sens';
  FSaveDialog.Filter:='Канонічний фізичний SENS (*.sens)|*.sens';
  FTestTarget:='';
  FPick:=TOpenDialog.Create(Self);
  FPick.Filter:='Канонічний Core1 SENS|*.sens';
  LabelText:=TLabel.Create(Self); LabelText.Parent:=Self;
  LabelText.SetBounds(12,111,965,24);
  LabelText.Caption:='Вибір .sens через діалог — текстова проєкція того самого basename .lisp; інші pinned поверхні: ук, san, en, LISP, sym.';
  FState:=TLabel.Create(Self); FState.Parent:=Self;
  FState.SetBounds(12,137,1150,30);
  FGrid:=TStringGrid.Create(Self); FGrid.Parent:=Self;
  FGrid.SetBounds(12,175,1162,258);
  FGrid.ColCount:=5; FGrid.FixedCols:=0;
  FGrid.FixedRows:=1; FGrid.RowCount:=2;
  FGrid.ColWidths[0]:=65; FGrid.ColWidths[1]:=205;
  FGrid.ColWidths[2]:=225; FGrid.ColWidths[3]:=225;
  FGrid.ColWidths[4]:=418;
  FGrid.OnSelectCell:=@SelectRow;
  LabelText:=TLabel.Create(Self); LabelText.Parent:=Self;
  LabelText.SetBounds(12,439,545,24);
  LabelText.Caption:='Точні фізичні координати вибраного D2-кореня';
  LabelText:=TLabel.Create(Self); LabelText.Parent:=Self;
  LabelText.SetBounds(597,439,560,24);
  LabelText.Caption:='Повний pinned core1.lisp (тільки проєкція укр)';
  FDetails:=TMemo.Create(Self); FDetails.Parent:=Self;
  FDetails.SetBounds(12,466,567,284);
  FDetails.ReadOnly:=True; FDetails.ScrollBars:=ssBoth;
  FDetails.WordWrap:=False; FDetails.Font.Name:='Monospace';
  FProjection:=TMemo.Create(Self); FProjection.Parent:=Self;
  FProjection.SetBounds(597,466,577,284);
  FProjection.ReadOnly:=True; FProjection.ScrollBars:=ssBoth;
  FProjection.WordWrap:=False; FProjection.Font.Name:='Monospace';
  ClearSnapshot;
  { OnChange підключається лише ПІСЛЯ створення таблиці/мемо:
    встановлення тексту в конструкторі не повинно викликати очищення
    ще неініціалізованих полів. }
  FPhysical.OnChange:=@PathEdited;
  FHuman.OnChange:=@PathEdited;
end;

procedure TCore1Form.Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create(Why);
end;

procedure TCore1Form.ClearSnapshot;
begin
  { Ніколи не утримуємо TD2Node / TSourceNode pointer після Free. }
  SetLength(FRoots,0);
  FGrid.RowCount:=2;
  FGrid.Cells[0,0]:='Форма';
  FGrid.Cells[1,0]:='Слова [1-based)';
  FGrid.Cells[2,0]:='Трити [0-based)';
  FGrid.Cells[3,0]:='Байти [0-based)';
  FGrid.Cells[4,0]:='Фізична голова Wn';
  FGrid.Rows[1].Clear;
  FDetails.Clear; FProjection.Clear;
  FPhysicalBytes:='';
  FSave.Enabled:=False;
  FState.Caption:='Двійковий Core1 не завантажено.';
end;

function TCore1Form.ReadBounded(const Filename,Extension:String;
  MaxBytes:Int64):RawByteString;
var Stream:TFileStream;
begin
  if LowerCase(ExtractFileExt(Filename))<>Extension then
    raise Exception.Create('неправильне розширення фізичного або людського файла');
  Stream:=TFileStream.Create(Filename,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>MaxBytes) then
      raise Exception.Create('порожній або завеликий pinned файл Core1');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free; end;
end;

{ G1.50: будь-яке редагування вхідного фізичного або людського ШЛЯХУ
  інвалідує snapshot *до* натискання кнопки. Немає припущення, що назва
  файла сама визначає фізичні дані: наступний LoadCore1 знову виконує
  DecodeT5MWithLocations/ParseD2WordsWide/ReadUkrainianSource.
  Sender — TEdit лише як host-подія; FRoots/FProjection належать TForm.
  Жодних позичених TD2Node або змін SENS-семантики тут немає.
  Питання: чому стара таблиця небезпечна після зміни шляху?
  Чому очищаємо ОБИДВІ поверхні, якщо змінено лише .lisp?
  Чому сам OnChange не може вважатися допуском фізичного SENS?
  Чи зберігаються дані після успішного наступного LoadCore1? }
procedure TCore1Form.PathEdited(Sender:TObject);
begin
  ClearSnapshot;
  FState.Caption:='Шлях змінено: попередній фізичний Core1 і укр '+
    'проєкцію скинуто. Завантажте й перевірте обидва файли знову.';
end;

procedure TCore1Form.ShowDetails(RowIndex:SizeInt);
var R:TRootEvidence;
begin
  FDetails.Clear;
  if (RowIndex<0) or (RowIndex>=Length(FRoots)) then Exit;
  R:=FRoots[RowIndex];
  FDetails.Lines.Add('Форма Core1: '+IntToStr(RowIndex+1));
  FDetails.Lines.Add('Голова: '+R.Head);
  FDetails.Lines.Add('Слова exact [1-based): ['+
    IntToStr(R.WordStart)+','+IntToStr(R.WordAfter)+')');
  FDetails.Lines.Add('Фізичні трити [0-based): ['+
    IntToStr(R.TritStart)+','+IntToStr(R.TritAfter)+')');
  FDetails.Lines.Add('Фізичні байти [0-based): ['+
    IntToStr(R.ByteStart)+','+IntToStr(R.ByteAfter)+')');
  FDetails.Lines.Add('П’ять тритів у T5M байті. Провідні нулі збережені.');
  FDetails.Lines.Add('D7 — дані; D12+ — окремі числові домени.');
  FDetails.Lines.Add('Структура ≠ закон, допуск ≠ виконання.');
end;

procedure TCore1Form.SelectRow(Sender:TObject;Col,Row:LongInt;
  var CanSelect:Boolean);
begin
  CanSelect:=True;
  if Row>0 then ShowDetails(Row-1);
end;

function TCore1Form.LoadCore1(const PhysicalPath,ProjectionPath:String):Boolean;
var
  Physical,Human:RawByteString;
  Words:TExactWords;
  Spans:TPhysicalWordSpans;
  Doc:TD2Document;
  Source:TSourceDocument;
  Candidate:TRootEvidenceList;
  Span:TPhysicalNodeSpan;
  Node,Head:TD2Node;
  I:SizeInt;
begin
  Result:=False;
  ClearSnapshot;
  FPhysical.Text:=PhysicalPath;
  FHuman.Text:=ProjectionPath;
  Doc:=nil; Source:=nil;
  try
    try
      Physical:=ReadBounded(PhysicalPath,'.sens',MAX_T5M_FILE_BYTES);
      Human:=ReadBounded(ProjectionPath,'.lisp',4*1024*1024);
      DecodeT5MWithLocations(Physical,Words,Spans);
      Need(EncodeT5M(Words)=Physical,'пошкоджено канонічні фізичні T5M байти');
      Doc:=ParseD2WordsWide(Words);
      Source:=ReadUkrainianSource(Human);
      Need((Length(Doc.Roots)>0) and
        (Length(Doc.Roots)=Length(Source.Forms)),
        'фізичні та укр форми не мають однакової кількості');
      { Весь документ і ВСІ адреси перевіряємо перед першим GUI-рядком.
        Ключі не виводимо із назви чи ширини; ширина — лише Wn. }
      SetLength(Candidate,Length(Doc.Roots));
      for I:=0 to High(Doc.Roots) do begin
        Node:=Doc.Roots[I];
        Need((Node<>nil) and (Node.WordIndex>=1),
          'недопущений корінь Core1');
        Span:=LocatePhysicalNodeSpan(Physical,Spans,Node);
        Candidate[I].WordStart:=Span.WordStart;
        Candidate[I].WordAfter:=Span.WordEndExclusive;
        Candidate[I].TritStart:=Span.TritStart;
        Candidate[I].TritAfter:=Span.TritEnd;
        Candidate[I].ByteStart:=Span.ByteStart;
        Candidate[I].ByteAfter:=Span.ByteEnd;
        Candidate[I].Head:='структурний D2-корінь';
        if (Node.Kind=dkList) and (Length(Node.Children)>0) then begin
          Head:=Node.Children[0];
          if (Head<>nil) and (Head.Kind=dkIdentity) then
            Candidate[I].Head:='W'+IntToStr(Head.Width)+':'+String(Head.Bits);
        end;
      end;
      { Тільки після повного допуску: зберігаємо фізичні байти, а не
        TD2Node pointer чи людську проєкцію. Будь-яка відмова очищає кеш. }
      FRoots:=Candidate;
      FPhysicalBytes:=Physical;
      FSave.Enabled:=True;
      FGrid.RowCount:=Length(FRoots)+1;
      for I:=0 to High(FRoots) do begin
        FGrid.Cells[0,I+1]:=IntToStr(I+1);
        FGrid.Cells[1,I+1]:='['+IntToStr(FRoots[I].WordStart)+','+
          IntToStr(FRoots[I].WordAfter)+')';
        FGrid.Cells[2,I+1]:='['+IntToStr(FRoots[I].TritStart)+','+
          IntToStr(FRoots[I].TritAfter)+')';
        FGrid.Cells[3,I+1]:='['+IntToStr(FRoots[I].ByteStart)+','+
          IntToStr(FRoots[I].ByteAfter)+')';
        FGrid.Cells[4,I+1]:=FRoots[I].Head;
      end;
      FProjection.Text:=String(Human); { людський текст, ніколи oracle }
      FState.Caption:='Фізично допущено '+IntToStr(Length(FRoots))+
        ' D2-форм; байтів T5M='+IntToStr(Length(Physical))+
        '; семантика=НЕ-ПЕРЕВІРЕНО';
      ShowDetails(0);
      Result:=True;
    finally
      Doc.Free; Source.Free;
    end;
  except
    on E:Exception do begin
      ClearSnapshot;
      FState.Caption:='ВІДМОВА: '+E.Message;
      Result:=False;
    end;
  end;
end;


{ Фізичний запис — приватний тимчасовий файл 0600 і атомарне no-clobber
  посилання на нову ціль. Не відкриваємо ціль через fmCreate.
  Немає повноважень перезаписувати .sens або створювати .lisp. }
procedure TCore1Form.PublishPhysical(const Path:String;
  const Bytes:RawByteString);
{$IFDEF UNIX}
var Temp:RawByteString; FD:cint; Offset,Written:SizeInt; Created:Boolean;
{$ENDIF}
begin
  if (Path='') or (Length(Path)>4096) or
     (LowerCase(ExtractFileExt(Path))<>'.sens') then
    raise Exception.Create('ціль має бути НОВИМ фізичним .sens');
  if (Length(Bytes)<1) or (Length(Bytes)>MAX_T5M_FILE_BYTES) then
    raise Exception.Create('недійсний розмір фізичного T5M');
  {$IFDEF UNIX}
  Temp:=''; FD:=-1; Created:=False;
  try
    Temp:=RawByteString(IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(Path)))+'c1rXXXXXX');
    UniqueString(Temp);
    FD:=CreatePrivateTemp(PChar(Temp));
    if FD<0 then
      raise Exception.Create('не створено приватний тимчасовий файл');
    Created:=True;
    Offset:=0;
    while Offset<Length(Bytes) do begin
      Written:=fpWrite(FD,Bytes[Offset+1],Length(Bytes)-Offset);
      if Written<=0 then
        raise Exception.Create('не записано весь фізичний корінь');
      Inc(Offset,Written);
    end;
    if fpClose(FD)<>0 then begin
      FD:=-1;
      raise Exception.Create('помилка закриття фізичного кореня');
    end;
    FD:=-1;
    if fpLink(Temp,RawByteString(Path))<>0 then
      raise Exception.Create('ціль вже існує або її не можна створити');
  finally
    if FD>=0 then fpClose(FD);
    if Created then fpUnlink(Temp);
  end;
  {$ELSE}
  raise Exception.Create('приватний no-clobber експорт на цій ОС недоступний');
  {$ENDIF}
end;

{ Один вибраний D2-корінь із ПЕРЕВІРЕНИХ фізичних 1-based меж.
  Не використовуємо текст із таблиці чи .lisp для відновлення бітів.
  Перевірка самодостатньої D2-рамки перед публікацією обов'язкова. }
function TCore1Form.ExportRoot(RootIndex:SizeInt;
  const Path:String):Boolean;
var Words,Cut:TExactWords; Doc:TD2Document;
    First,Finish,I:SizeInt; Physical:RawByteString;
begin
  Result:=False;
  try
    if (FPhysicalBytes='') or (Length(FRoots)=0) or
       (not FSave.Enabled) then
      raise Exception.Create('немає чинного фізичного Core1 snapshot');
    if (RootIndex<1) or (RootIndex>Length(FRoots)) then
      raise Exception.Create('фізичний корінь поза перевіреним діапазоном');
    DecodeT5M(FPhysicalBytes,Words);
    if EncodeT5M(Words)<>FPhysicalBytes then
      raise Exception.Create('фізичний snapshot неканонічний');
    First:=FRoots[RootIndex-1].WordStart;
    Finish:=FRoots[RootIndex-1].WordAfter;
    if (First<1) or (Finish<=First) or (Finish>Length(Words)+1) then
      raise Exception.Create('невірні точні адреси D2-кореня');
    SetLength(Cut,Finish-First);
    for I:=0 to High(Cut) do Cut[I]:=Words[First-1+I];
    Doc:=ParseD2WordsWide(Cut);
    try
      if Length(Doc.Roots)<>1 then
        raise Exception.Create('зріз не є одним повним D2-коренем');
    finally Doc.Free end;
    Physical:=EncodeT5M(Cut);
    PublishPhysical(Path,Physical);
    FState.Caption:='Збережено корінь '+IntToStr(RootIndex)+
      ' як окремий канонічний .sens; виконання Core1 не заявлене.';
    Result:=True;
  except on E:Exception do
    FState.Caption:='ВІДМОВА експорту без перезапису: '+E.Message;
  end;
end;

procedure TCore1Form.SaveClick(Sender:TObject);
begin
  if not FSave.Enabled then Exit;
  { У тесті справді натискається та сама LCL-кнопка, але без діалогу
    Xvfb; у звичайній сесії шлях обирає користувач. }
  if FTestTarget<>'' then
    ExportRoot(FGrid.Row,FTestTarget)
  else if FSaveDialog.Execute then
    ExportRoot(FGrid.Row,FSaveDialog.FileName);
end;

procedure TCore1Form.OpenClick(Sender:TObject);
begin
  { Fail-closed діагностика вже показана у FState; без модального вікна,
    яке блокувало б Xvfb регресії після негативного вводу. }
  LoadCore1(FPhysical.Text,FHuman.Text);
end;

procedure TCore1Form.SelectFile(Sender:TObject);
begin
  if FPick.Execute then begin
    FPhysical.Text:=FPick.FileName;
    FHuman.Text:=ChangeFileExt(FPick.FileName,'.lisp');
  end;
end;

procedure TCore1Form.SelfCheck(const Good,Human,Bad,InvalidHuman,TempDir:String);
var FirstOut,SecondOut,WrongOut,StaleOut:String;
    Original,Exported:RawByteString;
    Words,Cut:TExactWords; StartAt,EndAt:SizeInt;
    Doc:TD2Document;
  procedure CheckSlice(Index:SizeInt;const Path:String);
  var J:SizeInt;
  begin
    Exported:=ReadBounded(Path,'.sens',MAX_T5M_FILE_BYTES);
    DecodeT5M(FPhysicalBytes,Words);
    StartAt:=FRoots[Index-1].WordStart;
    EndAt:=FRoots[Index-1].WordAfter;
    SetLength(Cut,EndAt-StartAt);
    for J:=0 to High(Cut) do Cut[J]:=Words[StartAt-1+J];
    Need(Exported=EncodeT5M(Cut),'експорт втратив фізичне T5M слово');
    Doc:=ParseD2WordsWide(Cut);
    try Need(Length(Doc.Roots)=1,'експорт не є цілим D2-коренем');
    finally Doc.Free end;
  end;
begin
  Need(DirectoryExists(TempDir),'немає ізольованого каталогу експорту');
  FirstOut:=IncludeTrailingPathDelimiter(TempDir)+'перший-корінь.sens';
  SecondOut:=IncludeTrailingPathDelimiter(TempDir)+'другий-корінь.sens';
  WrongOut:=IncludeTrailingPathDelimiter(TempDir)+'помилковий.lisp';
  StaleOut:=IncludeTrailingPathDelimiter(TempDir)+'застарілий.sens';
  Need(not FileExists(FirstOut),'перший файл уже існує');
  Need(not FileExists(SecondOut),'другий файл уже існує');
  FPhysical.Text:=Good; FHuman.Text:=Human;
  FOpen.Click; { реальна LCL-кнопка й той самий loader }
  Need(Length(FRoots)=96,'не всі 96 фізичних Core1 форм прочитано');
  Need(FRoots[0].Head='W4:0011','не фізична перша голова D4:0011');
  Need((FRoots[0].WordStart=1) and
    (FRoots[0].WordAfter>FRoots[0].WordStart) and
    (FRoots[0].TritAfter>FRoots[0].TritStart),
    'точна позиція першої бібліотечної форми');
  Need((Pos('ядро1-другий-елемент',FProjection.Text)>0) and
    (Pos('Слова exact',FDetails.Text)>0),
    'українська проєкція і фізичні адреси не відображені');
  { Два РІЗНІ фізичні D2-корені через справжній LCL OnClick.
    Не пишемо у джерело, а використовуємо окремий тимчасовий каталог. }
  Need(Assigned(FSave.OnClick) and FSave.Enabled and
    (FPhysicalBytes<>''),'немає активної LCL-кнопки експорту');
  FGrid.Row:=1; FTestTarget:=FirstOut; FSave.Click;
  Need(FileExists(FirstOut) and (Pos('Збережено корінь 1',FState.Caption)=1),
    'перший натиск LCL не зберіг корінь');
  CheckSlice(1,FirstOut);
  Original:=ReadBounded(FirstOut,'.sens',MAX_T5M_FILE_BYTES);
  FGrid.Row:=2; FTestTarget:=SecondOut; FSave.Click;
  Need(FileExists(SecondOut) and (Pos('Збережено корінь 2',FState.Caption)=1),
    'другий натиск LCL не зберіг корінь');
  CheckSlice(2,SecondOut);
  Need(ReadBounded(SecondOut,'.sens',MAX_T5M_FILE_BYTES)<>Original,
    'два різні Core1 корені злилися в один');
  FTestTarget:=FirstOut;FSave.Click;
  Need((Pos('ВІДМОВА',FState.Caption)=1) and
    (ReadBounded(FirstOut,'.sens',MAX_T5M_FILE_BYTES)=Original),
    'перезапис наявного фізичного файла не відхилено');
  FTestTarget:=WrongOut;FSave.Click;
  Need((Pos('ВІДМОВА',FState.Caption)=1) and (not FileExists(WrongOut)),
    'дозволено публікувати людську .lisp замість .sens');
  FTestTarget:='';
  ShowDetails(1);
  Need(Pos('Форма Core1: 2',FDetails.Text)>0,
    'вибір іншого кореня не перемкнув адресу');
  { G1.50: зміна ще НЕ ЗАВАНТАЖЕНОГО шляху має негайно сховати
    ВСІ старі 96 фізичних коренів, деталі та укр текст. Два незалежні
    OnChange: канонічний .sens і лише людська проєкція .lisp. }
  FPhysical.Text:=Bad;
  Need((not FSave.Enabled) and (FPhysicalBytes=''),
    'після зміни .sens доступний застарілий експорт');
  Need((Length(FRoots)=0) and (FProjection.Text='') and
    (FDetails.Text='') and (FGrid.Cells[1,1]='') and
    (Pos('Шлях змінено',FState.Caption)=1),
    'після редагування .sens видно застарілий фізичний snapshot');
  { ExportRoot закономірно замінює статус на «ВІДМОВА».
    Спочатку перевіряємо саме статус OnChange, потім заборону експорту. }
  Need(not ExportRoot(1,StaleOut) and (not FileExists(StaleOut)) and
    (Pos('ВІДМОВА',FState.Caption)=1),
    'застарілий snapshot було експортовано');
  Need(LoadCore1(Good,Human) and (Length(FRoots)=96),
    'після редагування фізичного шляху немає відновлення');
  FHuman.Text:=InvalidHuman;
  Need((not FSave.Enabled) and (FPhysicalBytes=''),
    'після зміни .lisp доступний застарілий експорт');
  Need((Length(FRoots)=0) and (FProjection.Text='') and
    (FDetails.Text='') and (FGrid.Cells[1,1]='') and
    (Pos('Шлях змінено',FState.Caption)=1),
    'після редагування .lisp видно застарілу фізичну відповідь');
  Need(LoadCore1(Good,Human) and (Length(FRoots)=96),
    'після редагування укр шляху немає відновлення');
  Need(not LoadCore1(Bad,Human),'пошкоджений хвіст T5M допущено');
  Need((not FSave.Enabled) and (FPhysicalBytes=''),
    'після хибного T5M експорт не заблоковано');
  Need((Length(FRoots)=0) and (FProjection.Text='') and
    (FDetails.Text='') and (Pos('ВІДМОВА:',FState.Caption)=1),
    'після хибного .sens лишилися старі дані');
  Need(not LoadCore1(Good,InvalidHuman),
    'недійсна укр проєкція прийнята');
  Need((Length(FRoots)=0) and (FProjection.Text='') and
    (FDetails.Text=''),'після хибного .lisp частина даних видима');
  Need(LoadCore1(Good,Human) and (Length(FRoots)=96),
    'Core1 не відновився після відмови');
  Need(not LoadCore1(Good,Human+'.немає'),
    'відсутній файл проєкції прийнято');
  Need((Length(FRoots)=0) and (FProjection.Text='') and
    (FDetails.Text=''),'старі дані після відсутнього .lisp');
  Need(LoadCore1(Good,Human) and (Length(FRoots)=96),
    'після відсутньої проєкції Core1 не відновився');
  OutputUtf8('LCL-CORE1-ФІЗИЧНИЙ-ОГЛЯД-ГАРАЗД форм=96 перша-D4=0011 '+
    'T5M=канон укр=проєкція редагування=2 відмова=очищено відновлення=так '+
    'Core1-виконання=НЕ-ПЕРЕВІРЕНО експорт=2 no-clobber=так '+ 
    'не-лісп=так приватний-файл=0600');
end;

begin
  Application.Initialize;
  Application.CreateForm(TCore1Form,Window);
  if (ParamCount=6) and (ParamStr(1)='--самоперевірка') then begin
    try
      Window.SelfCheck(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5),ParamStr(6));
    except on E:Exception do begin
      OutputUtf8('LCL-CORE1-ПОМИЛКА: '+UnicodeString(E.Message));
      Halt(1);
    end;
    end;
  end else begin
    if ParamCount<>0 then begin
      OutputUtf8('Використання: sens-core1-ogliad [--самоперевірка добрий.sens добрий.lisp поганий.sens поганий.lisp каталог-результатів]');
      Halt(64);
    end;
    Application.Run;
  end;
end.
