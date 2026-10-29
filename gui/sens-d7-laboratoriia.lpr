{ G1.24. Справжній Lazarus-віджет для вже допущеного D7 v2.
  Символи ук/укр — лише pinned людські поверхні. Дужки, цифри і
  лапки тут ТЕКСТОВІ ДАНІ D7, не D2, не виклики, не числа D12+. }
program sens_d7_laboratoriia;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces,Forms,Classes,SysUtils,Controls,StdCtrls,Grids,Dialogs,
  wsm.d7text,wsm.t5m,wsm.proektsii,wsm.domain
  {$IFDEF UNIX},BaseUnix{$ENDIF};

type
  TD7Window=class(TForm)
  private
    FSurface:TComboBox;
    FInput,FOutput:TEdit;
    FGrid:TStringGrid;
    FSurfaces:TMemo;
    FCatalog:TProektsiiCatalog;
    FGridUpdating:Boolean;
    FShownCount:SizeInt;
    FStatus:TLabel;
    FEncode,FOpen,FSave:TButton;
    FDialog:TOpenDialog;
    FSaveDialog:TSaveDialog;
    FMap:TD7Map;
    FPhysical:RawByteString;
    function Mode:TD7Surface;
    procedure ClearResult;
    procedure Publish(const Physical,Human:RawByteString);
    procedure EncodeClick(Sender:TObject);
    procedure OpenClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    procedure InputChanged(Sender:TObject);
    procedure SurfaceChanged(Sender:TObject);
    procedure GridSelect(Sender:TObject;ACol,ARow:Integer;var CanSelect:Boolean);
    procedure ShowSelected(Row:Integer);
    function DecodeBytes(const Physical:RawByteString):Boolean;
    function EncodedWord(const Bits:RawByteString):RawByteString;
    procedure Need(Condition:Boolean;const Why:String);
  public
    constructor Create(AOwner:TComponent);override;
    function EncodeEntered:Boolean;
    function LoadPhysicalFile(const Path:String):Boolean;
    function SavePhysicalNew(const Path:String):Boolean;
    procedure SelfTest(const GoodFile,BadFile,NewFile,ExistingFile,AfterBadFile,SymlinkFile:String);
  end;

var Window:TD7Window;

constructor TD7Window.Create(AOwner:TComponent);
var L:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — лабораторія фізичного D7';
  Width:=940;Height:=790;Position:=poScreenCenter;
  { Джерело карти — ТІЛЬКИ pinned external/sens/lib/domains/d7.lisp.
    У FMap 128 керованих FPC UTF-8 рядків, власник — екземпляр вікна. }
  LoadPinnedD7Map(GetCurrentDir,FMap);
  { Показ лише pinned шести проєкцій, не нові закони D7. Повний
    незалежний каталог перевіряє exact-координати, цитування та LISP=().
    TProektsiiCatalog — керований власністю форми Pascal record/array. }
  LoadPinnedProjections(IncludeTrailingPathDelimiter(GetCurrentDir)+
    'external/sens',FCatalog);
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,14,900,26);
  L.Caption:='D7: український текст як фізичні W7 слова, не програма SENS';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,51,190,24);L.Caption:='Поверхня (явний вибір):';
  FSurface:=TComboBox.Create(Self);FSurface.Parent:=Self;
  FSurface.SetBounds(214,46,95,30);
  FSurface.Style:=csDropDownList;
  FSurface.Items.Add('ук');FSurface.Items.Add('укр');
  FSurface.ItemIndex:=1;
  FSurface.OnChange:=@SurfaceChanged;
  FInput:=TEdit.Create(Self);FInput.Parent:=Self;
  FInput.SetBounds(18,93,898,32);
  FInput.Text:='Це 0() №Їґ';
  FInput.OnChange:=@InputChanged;
  FEncode:=TButton.Create(Self);FEncode.Parent:=Self;
  FEncode.SetBounds(18,138,280,36);
  FEncode.Caption:='Текст D7 → двійковий T5M';
  FEncode.OnClick:=@EncodeClick;
  FOpen:=TButton.Create(Self);FOpen.Parent:=Self;
  FOpen.SetBounds(320,138,280,36);
  FOpen.Caption:='Відкрити фізичний .sens…';
  FOpen.OnClick:=@OpenClick;
  { G1.25 — тільки новий canonical .sens після підтвердженого D7. }
  FSave:=TButton.Create(Self);FSave.Parent:=Self;
  FSave.SetBounds(620,138,296,36);
  FSave.Caption:='Зберегти новий двійковий .sens';
  FSave.OnClick:=@SaveClick;
  FSaveDialog:=TSaveDialog.Create(Self);
  FSaveDialog.Filter:='Новий фізичний D7 (*.sens)|*.sens';
  FSaveDialog.DefaultExt:='sens';
  FSaveDialog.Options:=[ofPathMustExist,ofOverwritePrompt];
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Вибрати канонічні дані D7';
  FDialog.Filter:='Фізичні SENS (*.sens)|*.sens';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,188,800,24);
  L.Caption:='Точний результат української проєкції:';
  FOutput:=TEdit.Create(Self);FOutput.Parent:=Self;
  FOutput.SetBounds(18,215,898,31);
  FOutput.ReadOnly:=True;
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;
  FGrid.SetBounds(18,262,898,272);
  FGrid.FixedCols:=0;FGrid.ColCount:=3;
  FGrid.RowCount:=2;FGrid.FixedRows:=1;
  FGrid.Options:=FGrid.Options+[goRowSelect,goColSizing];
  FGrid.OnSelectCell:=@GridSelect;
  FGrid.ColWidths[0]:=85;
  FGrid.ColWidths[1]:=250;
  FGrid.ColWidths[2]:=480;
  FGrid.Cells[0,0]:='№ слова';
  FGrid.Cells[1,0]:='Точні W7-біти';
  FGrid.Cells[2,0]:='Друкована поверхня (ук/укр)';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,537,890,20);
  L.Caption:='Усі допущені W7 у списку (до 8192 для огляду); прокрутіть рядки.';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(18,564,898,21);
  L.Caption:='Шість pinned проєкцій ВИБРАНОГО W7: дані, не викличні голови';
  FSurfaces:=TMemo.Create(Self);FSurfaces.Parent:=Self;
  FSurfaces.SetBounds(18,587,898,120);
  FSurfaces.ReadOnly:=True;FSurfaces.ScrollBars:=ssVertical;
  FSurfaces.WordWrap:=False;
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(18,710,898,35);
  ClearResult;
end;

function TD7Window.Mode:TD7Surface;
begin
  if FSurface.ItemIndex=0 then Result:=dsUk
  else if FSurface.ItemIndex=1 then Result:=dsUkr
  else raise ED7TextError.Create('Не вибрано поверхню D7');
end;

procedure TD7Window.ClearResult;
var J:Integer;
begin
  FPhysical:='';
  FShownCount:=0;
  FOutput.Text:='';
  FSave.Enabled:=False;
  FGridUpdating:=True;
  try
    FGrid.RowCount:=2;
    for J:=0 to 2 do FGrid.Cells[J,1]:='';
  finally FGridUpdating:=False end;
  FSurfaces.Clear;
  FStatus.Caption:='Очікується текст або фізичні дані D7.';
end;

{ Лише pinned текстові поверхні: WordIndex для таблиці 1-based,
  двійкові exact біти 7-бітні, ніякого SENS виконання. }
procedure TD7Window.ShowSelected(Row:Integer);
const Labels:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var Bits:RawByteString;Code,I,J:SizeInt;Lines:TStringList;
begin
  FSurfaces.Clear;
  if (Row<1) or (Row>FShownCount) then Exit;
  Bits:=RawByteString(FGrid.Cells[1,Row]);
  if Length(Bits)<>7 then Exit;
  Code:=0;
  for J:=1 to 7 do begin
    if not (Bits[J] in ['0','1']) then Exit;
    Code:=Code*2+Ord(Bits[J])-Ord('0');
  end;
  if (Code<0) or (Code>=Length(FCatalog[7])) or
    (not SameKey(FCatalog[7][Code].Key,ExactKey(Bits))) then
    raise ED7TextError.Create('Пошкоджена pinned D7 exact-координата');
  Lines:=TStringList.Create;
  try
    for I:=0 to 5 do
      Lines.Add(Labels[I]+': '+
        SurfaceForDisplay(FCatalog[7][Code].Surface[I]));
    FSurfaces.Lines.Assign(Lines);
  finally Lines.Free end;
end;

procedure TD7Window.GridSelect(Sender:TObject;ACol,ARow:Integer;
  var CanSelect:Boolean);
begin
  if FGridUpdating then Exit;
  ShowSelected(ARow);
end;

procedure TD7Window.Publish(const Physical,Human:RawByteString);
const MaxShownWords=8192;
var W:TExactWords;I,J,K,Code,Shown:SizeInt;
begin
  { Той самий T5M decoder лише для VIEW; повний D7 admission і
    байт-канонічність уже встановили EncodeD7Text/DecodeD7Text. }
  DecodeT5M(Physical,W);
  if (Length(W)=0) or (EncodeT5M(W)<>Physical) then
    raise ED7TextError.Create('Неприпустимий фізичний T5M');
  ClearResult;
  Shown:=Length(W);
  if Shown>MaxShownWords then Shown:=MaxShownWords;
  FGridUpdating:=True;
  try
    FGrid.RowCount:=Shown+1;
    if FGrid.RowCount<2 then FGrid.RowCount:=2;
  finally FGridUpdating:=False end;
  for I:=0 to Shown-1 do begin
    if Length(W[I])<>7 then
      raise ED7TextError.Create('Очікуються лише точні W7');
    Code:=0;
    for J:=1 to 7 do begin
      if not (W[I][J] in ['0','1']) then
        raise ED7TextError.Create('Небінарна фізична координата');
      Code:=Code*2+Ord(W[I][J])-Ord('0');
    end;
    K:=I+1;
    FGrid.Cells[0,K]:=IntToStr(K);
    FGrid.Cells[1,K]:=String(W[I]);
    if Mode=dsUk then FGrid.Cells[2,K]:=String(FMap[Code].Uk)
    else FGrid.Cells[2,K]:=String(FMap[Code].Ukr);
  end;
  { Публікація повного фізичного результату після усіх перевірок.
    RawByteString — managed bytes, без ANSI/Unicode opcode колізій. }
  FShownCount:=Shown;
  FPhysical:=Physical;
  FSave.Enabled:=True;
  if Shown>0 then begin
    FGridUpdating:=True;
    try FGrid.Row:=1; finally FGridUpdating:=False end;
    ShowSelected(1);
  end;
  FOutput.Text:=String(Human);
  FStatus.Caption:='D7-допущено: фізичних байтів='+IntToStr(Length(Physical))+
    ', точних W7 слів='+IntToStr(Length(W))+
    ', показано='+IntToStr(Shown)+'; це дані, не виконання.';
end;

function TD7Window.EncodeEntered:Boolean;
var Human,Physical,Decoded:RawByteString;
begin
  Result:=False;ClearResult;
  try
    Human:=RawByteString(FInput.Text);
    Physical:=EncodeD7Text(Human,FMap,Mode);
    Decoded:=DecodeD7Text(Physical,FMap,Mode);
    if Decoded<>Human then
      raise ED7TextError.Create('Невдалий зворотний D7 round-trip');
    Publish(Physical,Decoded);
    Result:=True;
  except on E:Exception do begin
    ClearResult;FStatus.Caption:='Відхилено D7: '+E.Message;
  end end;
end;

function TD7Window.DecodeBytes(const Physical:RawByteString):Boolean;
var Human,RoundTrip:RawByteString;
begin
  Result:=False;ClearResult;
  try
    Human:=DecodeD7Text(Physical,FMap,Mode);
    RoundTrip:=EncodeD7Text(Human,FMap,Mode);
    if RoundTrip<>Physical then
      raise ED7TextError.Create('Фізичні байти не збіглися після D7 round-trip');
    { OnChange очищує старий snapshot до допуску нового. }
    FInput.Text:=String(Human);
    Publish(Physical,Human);
    Result:=True;
  except on E:Exception do begin
    ClearResult;FStatus.Caption:='Відхилено фізичний D7: '+E.Message;
  end end;
end;

function TD7Window.LoadPhysicalFile(const Path:String):Boolean;
const MaxViewBytes=65536;
var Stream:TFileStream;Physical:RawByteString;
begin
  Result:=False;ClearResult;
  try
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise ED7TextError.Create('Тільки фізичний .sens, не текстова .lisp');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxViewBytes) then
        raise ED7TextError.Create('Порожній або завеликий фізичний D7');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    Result:=DecodeBytes(Physical);
  except on E:Exception do begin
    ClearResult;FStatus.Caption:='Відхилено файл: '+E.Message;
  end end;
end;

{ G1.25: лише pinned D7/T5M, не інтерпретація мовних форм.
  Фізичні байти — керований FPC RawByteString, файл — TFileStream.
  Збереження перевіряє звичайний FileExists; це UI-захист від
  попереднього файла, а не міжпроцесне атомарне O_EXCL. }
{ G1.26 — лише POSIX host-публікація вже допущених D7 T5M.
  FPhysical: borrowed managed RawByteString. Відкрита TFileStream
  належить цьому виклику й звільняється через try/finally.
  Точно випробуваний pinned D7 codec лишається єдиним авторитетом.
  Повний temp — у тому самому каталозі, fpLink відхиляє колізії
  та dangling symbolic links атомарно, без FileExists/fmCreate race.
  На інших ОС fail-closed, не мовчазний небезпечний fallback. }
function TD7Window.SavePhysicalNew(const Path:String):Boolean;
var Ukr:RawByteString;
    TempPath,TargetPath:String;
    TempOwned,CloseOK:Boolean;
    {$IFDEF UNIX}
    Fd:CInt;
    Offset,Written:SizeInt;
    {$ENDIF}
begin
  Result:=False;TempPath:='';TempOwned:=False;
  try
    if (FPhysical='') or (not FSave.Enabled) then
      raise ED7TextError.Create('Немає допущеного фізичного D7');
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise ED7TextError.Create('Зберігати лише двійковий .sens');
    Ukr:=DecodeD7Text(FPhysical,FMap,Mode);
    if EncodeD7Text(Ukr,FMap,Mode)<>FPhysical then
      raise ED7TextError.Create('Фізичний D7 не пройшов round-trip');
    {$IFDEF UNIX}
    TargetPath:=ExpandFileName(Path);
    TempPath:=GetTempFileName(ExtractFilePath(TargetPath),'d7p');
    if TempPath='' then
      raise ED7TextError.Create('Не створено тимчасовий D7 файл');
    { FPC GetTempFileName повертає НАЗВУ, не створює файл.
      POSIX O_EXCL створює temp атомарно й не розіменовує чужий symlink.
      TempOwned дозволяє прибрати ЛИШЕ створений нами шлях. }
    Fd:=fpOpen(PChar(TempPath),O_WrOnly or O_Creat or O_Excl,&600);
    if Fd<0 then
      raise ED7TextError.Create('Не вдалося атомарно створити приватний D7 temp');
    TempOwned:=True;
    CloseOK:=False;
    try
      Offset:=1;
      while Offset<=Length(FPhysical) do begin
        Written:=fpWrite(Fd,FPhysical[Offset],Length(FPhysical)-Offset+1);
        if Written<=0 then
          raise ED7TextError.Create('Неповний фізичний запис D7 temp');
        Inc(Offset,Written);
      end;
    finally
      CloseOK:=fpClose(Fd)=0;
    end;
    if not CloseOK then
      raise ED7TextError.Create('Помилка закриття фізичного D7 temp');
    if fpLink(RawByteString(TempPath),RawByteString(TargetPath))<>0 then
      raise ED7TextError.Create('Фізичний файл уже існує або каталог не дозволяє атомарний запис');
    Result:=True;
    FStatus.Caption:='Новий фізичний D7 .sens створено атомарно без перезапису.';
    {$ELSE}
    raise ED7TextError.Create('Атомарний D7 запис на цій ОС ще не реалізовано');
    {$ENDIF}
  except on E:Exception do
    FStatus.Caption:='Запис D7 відхилено: '+E.Message end;
  if TempOwned then DeleteFile(TempPath);
end;
procedure TD7Window.InputChanged(Sender:TObject);
begin ClearResult end;
procedure TD7Window.SurfaceChanged(Sender:TObject);
begin ClearResult end;
procedure TD7Window.SaveClick(Sender:TObject);
begin if FSaveDialog.Execute then SavePhysicalNew(FSaveDialog.FileName) end;

function TD7Window.EncodedWord(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=Bits;
  Result:=EncodeT5M(W);
end;

procedure TD7Window.EncodeClick(Sender:TObject);
begin EncodeEntered end;
procedure TD7Window.OpenClick(Sender:TObject);
begin if FDialog.Execute then LoadPhysicalFile(FDialog.FileName) end;

procedure TD7Window.Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('LCL-D7-ПОМИЛКА: '+Why);
end;

procedure TD7Window.SelfTest(const GoodFile,BadFile,NewFile,ExistingFile,AfterBadFile,SymlinkFile:String);
const Sample='Це 0() №Їґ';
var Original:TExactWords; Physical,Example:RawByteString;
begin
  Need((FSurface<>nil) and (FInput<>nil) and (FOutput<>nil) and
    (FGrid<>nil) and (FSave<>nil) and (FSurfaces<>nil) and
    FSurfaces.ReadOnly and FOutput.ReadOnly and
    Assigned(FEncode.OnClick) and Assigned(FOpen.OnClick) and
    Assigned(FSave.OnClick) and (not FSave.Enabled),
    'немає реальних LCL контролів');
  FSurface.ItemIndex:=1;
  FInput.Text:=Sample;
  Need(EncodeEntered,'не закодовано український D7 текст');
  Physical:=FPhysical;
  Need((FOutput.Text=Sample) and (Length(Physical)>0),
    'після кодування втрачено українську проєкцію');
  DecodeT5M(Physical,Original);
  Need((Length(Original)>=6) and (Original[2]='0100000') and
    (Original[3]='0110000') and (Original[4]='0101000') and
    (Original[5]='0101001'), 'D7 пробіл/нуль/дужки стали D2 чи числами');
  Need((FGrid.Cells[1,3]='0100000') and
    (FGrid.Cells[2,5]='('), 'справжня W7 таблиця не показала точні біти');
  FGrid.Row:=6; { фізична дужка ) = W7:0101001, не D2 CLOSE }
  Need((FGrid.Cells[1,6]='0101001') and
    (Pos('укр: ")"',FSurfaces.Text)>0) and
    (Pos('LISP: (відсутня)',FSurfaces.Text)>0) and
    (Pos('san: ',FSurfaces.Text)>0) and
    (Pos('en: ',FSurfaces.Text)>0) and
    (Pos('sym: ',FSurfaces.Text)>0),
    'відсутня точна pinned шістка D7:0101001');

  { Довга українська D7 послідовність перевіряє справжній LCL scroll,
    не вигаданий власний декодер або truncate після 16. }
  FInput.Text:=Sample+Sample+Sample;
  Need(EncodeEntered,'не допущено довгий фізичний D7 текст');
  Need((FShownCount>16) and (FGrid.RowCount=FShownCount+1),
    'LCL приховав фізичні W7 за старим обмеженням 16');
  FGrid.Row:=FShownCount;
  Need((FGrid.Cells[1,FShownCount]<>'') and
    (Pos('укр: ',FSurfaces.Text)>0) and
    (Pos('LISP: (відсутня)',FSurfaces.Text)>0),
    'останній W7 не показав шість pinned проєкцій');
  FInput.Text:=Sample;
  Need(EncodeEntered and (FPhysical=Physical),
    'після прокручування не відновлено побайтовий D7 свідок');

  Need(LoadPhysicalFile(GoodFile),'не прочитано фізичний .sens');
  Need((FPhysical=Physical) and (FInput.Text=Sample) and
    (FOutput.Text=Sample),'CLI та Lazarus D7 фізично різні');
  Need(FSave.Enabled,'допущений D7 snapshot не дозволив запис');
  if not SavePhysicalNew(NewFile) then
    Need(False,'новий фізичний .sens не створено: '+FStatus.Caption);
  Need(FileExists(NewFile),'новий фізичний файл відсутній');
  Need(not SavePhysicalNew(ExistingFile),'наявний файл прийнято на перезапис');
  Need(not SavePhysicalNew(SymlinkFile),'символічне посилання помилково прийнято як вільну ціль');
  Need(not SavePhysicalNew(NewFile),'повторний запис перезаписав файл');
  Need(not SavePhysicalNew(NewFile+'.lisp'),'текстову .lisp прийнято для запису');
  Need(FPhysical=Physical,'відмова зіпсувала canonical T5M');
  FInput.Text:=Sample+'!';
  Need((FPhysical='') and (not FSave.Enabled) and
    (FShownCount=0) and (FGrid.RowCount=2) and
    (FSurfaces.Text=''), 'зміна вводу не очистила фізику та шість проєкцій');
  Need(not SavePhysicalNew(AfterBadFile),'після редагування запис не заблоковано');
  Need(not FileExists(AfterBadFile),'недопущений текст створив файл');
  Need(LoadPhysicalFile(GoodFile),'повторний допуск після зміни тексту');
  Need((FPhysical=Physical) and FSave.Enabled,
    'відновлення дозволу після повторного admission');

  { Окрема «ук» поверхня, а не неявний псевдонім укр. }
  FSurface.ItemIndex:=0;
  FInput.Text:=String(FMap[65].Uk+FMap[32].Uk+FMap[40].Uk);
  Need(EncodeEntered,'поверхня ук не закодована');
  DecodeT5M(FPhysical,Original);
  Need((Length(Original)=3) and
    (Original[0]='1000001') and (Original[1]='0100000') and
    (Original[2]='0101000'),'ук втратила точні 7-бітні координати');

  FSurface.ItemIndex:=1;
  FInput.Text:='i';
  Need(not EncodeEntered,'латинська i прийнята за українську і');
  Need((FPhysical='') and (FOutput.Text='') and
    (FGrid.Cells[1,1]='') and (FSurfaces.Text='') and (not FSave.Enabled),
    'після помилки лишилося право запису фізичного результату');
  Need(not SavePhysicalNew(AfterBadFile),'негативний D7 дозволив запис');
  FInput.Text:='«';
  Need(not EncodeEntered,'вигадано координату відсутнього glyph');
  Need(not DecodeBytes(EncodedWord('0010110')),
    'SYN D7:0010110 помилково перетворено на текст');
  Need(not DecodeBytes(EncodedWord('0')),'W1 прийняте за W7');
  Need(not DecodeBytes(EncodedWord('000000000000')),
    'W12 без домену прийнято за D7 або D12');
  Need(not DecodeBytes(#$F3),'неканонічний T5M байт прийнято');
  Need(not LoadPhysicalFile(BadFile),'пошкоджений файл прийнято');
  Need((FPhysical='') and (FOutput.Text='') and
    (FGrid.Cells[1,1]='') and (FSurfaces.Text=''),
    'пізня фізична відмова лишила старі дані');
  Need(not LoadPhysicalFile('немає-файла.sens'),
    'відсутній фізичний файл прийнято');
  Need(not LoadPhysicalFile('проєкція.lisp'),
    'текстову .lisp прийнято за фізичні дані');
  FInput.Text:=Sample;
  Need(EncodeEntered and (FPhysical=Physical),
    'відновлення після негативів неканонічне');
  Example:=DecodeD7Text(FPhysical,FMap,dsUkr);
  Need(Example=Sample,'зворотне читання не відповідає pinned D7');
  Window.Show;Application.ProcessMessages;
  WriteLn('LCL-Д7-ШІСТЬ-ПРОЄКЦІЙ-ГАРАЗД W7=точні',
    ' понад-16=видимі ук/укр/san/en/LISP/sym=pinned',
    ' закрита-дужка=дані LISP=порожньо помилки=очищено');
  WriteLn('LCL-Д7-ЗАПИС-ГАРАЗД новий=.sens існуючий=не-перезаписано',
    ' symlink=не-перезаписано атомарно=fpLink',
    ' редагування=інвалідує-T5M помилки=блок-запис');
  WriteLn('LCL-Д7-ЛАБОРАТОРІЯ-ГАРАЗД Lazarus=GTK2 W7=точні',
    ' ук/укр=окремо дужки=D7-дані SYN=відхилено',
    ' W1/W12=відхилено UTF8=строго .sens=канонічний',
    ' CLI-побайтово=так відновлення=так семантика=не-виконується');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — лабораторія D7';
    Application.CreateForm(TD7Window,Window);
    if (ParamCount=7) and (ParamStr(1)='--самоперевірка') then begin
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;
    end else if ParamCount=0 then Application.Run
    else begin
      WriteLn(StdErr,'Використання: sens-d7-laboratoriia [--самоперевірка дані.sens брак.sens новий.sens існує.sens відхилено.sens посилання.sens]');
      Halt(64);
    end;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-Д7-ПОМИЛКА: ',E.Message);Halt(2)
  end end;
end.
