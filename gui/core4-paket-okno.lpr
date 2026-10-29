{ G5.33 — справжнє LCL-вікно пакета з канонічного фізичного .sens.
  Жодного власного evaluator: TCore4WireClient запускає окремий pinned
  Core4 runtime, а UI показує тільки підтверджені точні T5M відповіді.
  Wn позначає фізичну ширину, НЕ семантичний домен Dn. }
program core4_paket_okno;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids, Dialogs,
  wsm.core4wireclient, wsm.core4runtime, wsm.t5m,
  wsm.bind, wsm.ukroundtrip, wsm.proektsii, wsm.domain
  {$IFDEF UNIX},BaseUnix{$ENDIF};

type
  TBatchWindow = class(TForm)
  private
    FClient: TCore4WireClient;          { owned: один дочірній процес }
    FPath: TEdit;
    FPick, FRun, FPickUkr, FRunUkr, FSave: TButton;
    FResults: TStringGrid;
    FChosenDomain: TComboBox; { тільки явна host-координата D1..D10 }
    FProjectionGrid: TStringGrid; { 6 pinned поверхонь, read-only }
    FProjectionLabel: TLabel;
    FProjectionCatalog: TProektsiiCatalog; { managed, завантажено з pin }
    FProjectionCatalogReady: Boolean;
    FSelectedWord: SizeInt; { номер фізичного слова у вже виконаній відповіді }
    FStatus: TLabel;
    FDialog, FDialogUkr: TOpenDialog;
    FSaveDialog: TSaveDialog;
    FRoot: String;
    FTables: TDomainSet;
    FLongs: TLongProjection;
    FProjectionReady: Boolean;
    FRows: SizeInt;
    FAnswer: RawByteString; { власна канонічна відповідь, не таблиця }
    FInitialPID: Int64;
    procedure ClearResults;
    procedure ClearProjections;
    procedure ShowChosenProjection;
    procedure DomainChanged(Sender:TObject);
    procedure ResultCellSelected(Sender:TObject; ACol,ARow:Integer;
      var CanSelect:Boolean);
    function ReadPhysical(const Path: String): RawByteString;
    function ReadProjection(const Path: String): RawByteString;
    procedure EnsureProjectionReady;
    function ExecutePhysical(const Physical: RawByteString): Boolean;
    function ExecuteFile(const Path: String): Boolean;
    function ExecuteUkrFile(const Path: String): Boolean;
    procedure PickClick(Sender: TObject);
    procedure PickUkrClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure RunUkrClick(Sender: TObject);
    procedure InputChanged(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAnswerNew(const TargetPath:String);
    procedure Need(OK: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Connect(const Root, Executable: String);
    procedure SelfTest(const Root, Executable: String);
  end;

var Window: TBatchWindow;

constructor TBatchWindow.Create(AOwner: TComponent);
var Note: TLabel; I:Integer;
const SurfaceNames:array[0..5] of String =
  ('ук','укр','san','en','LISP','sym');
begin
  inherited CreateNew(AOwner,1);
  Width:=1300; Height:=740; Position:=poScreenCenter;
  Caption:='SENS — фізичний пакет Core4 у Lazarus';
  FClient:=nil; FRows:=0; FInitialPID:=-1;
  FProjectionReady:=False; FProjectionCatalogReady:=False;
  FSelectedWord:=0; FRoot:=''; FAnswer:='';
  Note:=TLabel.Create(Self); Note.Parent:=Self;
  Note.SetBounds(16,12,1000,48); Note.AutoSize:=False; Note.WordWrap:=True;
  Note.Caption:='Фізичний .sens або ЯВНО вибрана українська укр-проєкція .lisp.'+
    ' Ук/укр/san/en/LISP/sym не задають семантики: лише pinned перетворення'+
    ' укр → точний T5M → окремий постійний Core4-процес.';
  FPath:=TEdit.Create(Self); FPath.Parent:=Self;
  FPath.SetBounds(16,68,494,32); FPath.Text:='';
  FPath.OnChange:=@InputChanged;
  FPick:=TButton.Create(Self); FPick.Parent:=Self;
  FPick.SetBounds(520,68,116,32); FPick.Caption:='Обрати .sens';
  FPick.OnClick:=@PickClick;
  FPickUkr:=TButton.Create(Self); FPickUkr.Parent:=Self;
  FPickUkr.SetBounds(642,68,116,32); FPickUkr.Caption:='Обрати .lisp';
  FPickUkr.OnClick:=@PickUkrClick;
  FRun:=TButton.Create(Self); FRun.Parent:=Self;
  FRun.SetBounds(764,68,122,32); FRun.Caption:='Виконати .sens';
  FRun.Enabled:=False; FRun.OnClick:=@RunClick;
  FRunUkr:=TButton.Create(Self); FRunUkr.Parent:=Self;
  FRunUkr.SetBounds(891,68,136,32); FRunUkr.Caption:='Виконати укр';
  FRunUkr.Enabled:=False; FRunUkr.OnClick:=@RunUkrClick;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичні SENS (*.sens)|*.sens';
  FDialogUkr:=TOpenDialog.Create(Self);
  FDialogUkr.Filter:='Українська проєкція (*.lisp)|*.lisp';
  FSaveDialog:=TSaveDialog.Create(Self);
  FSaveDialog.Filter:='Фізична відповідь SENS (*.sens)|*.sens';
  FSaveDialog.DefaultExt:='.sens';
  FSaveDialog.Options:=FSaveDialog.Options-[ofOverwritePrompt];
  FSave:=TButton.Create(Self); FSave.Parent:=Self;
  FSave.SetBounds(16,625,204,32);
  FSave.Caption:='Зберегти відповідь .sens';
  FSave.Enabled:=False; FSave.OnClick:=@SaveClick;
  FResults:=TStringGrid.Create(Self); FResults.Parent:=Self;
  FResults.SetBounds(16,119,810,490);
  FResults.ColCount:=3; FResults.RowCount:=2;
  FResults.FixedCols:=0; FResults.FixedRows:=1;
  FResults.ColWidths[0]:=95;
  FResults.ColWidths[1]:=120;
  FResults.ColWidths[2]:=760;
  FResults.Cells[0,0]:='Форма';
  FResults.Cells[1,0]:='Ширина Wn';
  FResults.Cells[2,0]:='Точні біти фізичної відповіді';
  FResults.Options:=FResults.Options-[goEditing];
  FResults.OnSelectCell:=@ResultCellSelected;
  { Праворуч вікно проєкцій створюється ТІЛЬКИ для читання.
    Dn користувач вибирає явно. Wn сама по собі НЕ є Dn. }
  FProjectionLabel:=TLabel.Create(Self);FProjectionLabel.Parent:=Self;
  FProjectionLabel.SetBounds(845,119,425,53);
  FProjectionLabel.AutoSize:=False;FProjectionLabel.WordWrap:=True;
  FChosenDomain:=TComboBox.Create(Self);FChosenDomain.Parent:=Self;
  FChosenDomain.SetBounds(845,176,425,30);
  FChosenDomain.Style:=csDropDownList;
  FChosenDomain.Items.Add('Без вибраного домену — тільки фізичні біти');
  for I:=1 to 10 do
    FChosenDomain.Items.Add('D'+IntToStr(I)+' — явна координата');
  FChosenDomain.ItemIndex:=0;
  FChosenDomain.OnChange:=@DomainChanged;
  FProjectionGrid:=TStringGrid.Create(Self);FProjectionGrid.Parent:=Self;
  FProjectionGrid.SetBounds(845,213,425,395);
  FProjectionGrid.ColCount:=2;FProjectionGrid.RowCount:=7;
  FProjectionGrid.FixedCols:=0;FProjectionGrid.FixedRows:=1;
  FProjectionGrid.ColWidths[0]:=73;
  FProjectionGrid.ColWidths[1]:=330;
  FProjectionGrid.Cells[0,0]:='Поверхня';
  FProjectionGrid.Cells[1,0]:='З pinned SENS, не викличність';
  FProjectionGrid.Options:=FProjectionGrid.Options-[goEditing];
  for I:=0 to 5 do FProjectionGrid.Cells[0,I+1]:=SurfaceNames[I];
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(230,625,1040,70); FStatus.AutoSize:=False;
  FStatus.WordWrap:=True;
  ClearResults;
end;

destructor TBatchWindow.Destroy;
begin
  FreeAndNil(FClient);
  inherited Destroy;
end;

procedure TBatchWindow.Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('LCL-ПАКЕТ-ПОМИЛКА: '+Why);
end;

{ Ніяка зміна входу, реконсект чи remote error не лишає проєкції.
  Каталог pinned може лишатись у пам'яті, але не видається за відповідь. }
procedure TBatchWindow.ClearProjections;
var I:SizeInt;
begin
  for I:=1 to 6 do FProjectionGrid.Cells[1,I]:='';
  FProjectionLabel.Caption:='Оберіть домен D1–D10 вручну. Wn ≠ Dn.';
end;

{ Тільки фізичне слово З УСПІШНОЇ remote відповіді, domain=ОБРАНИЙ,
  а не виведений із Length(bits). Жоден LISP/D7 напис не є функцією. }
procedure TBatchWindow.ShowChosenProjection;
var Words:TExactWords;Key:TDomainKey;D,I:SizeInt;
    Pin:String;
begin
  ClearProjections;
  if (FAnswer='') or (FSelectedWord<1) or (FSelectedWord>FRows) then Exit;
  D:=FChosenDomain.ItemIndex; { 0=без вибору, 1..10=явний Dn }
  if (D<1) or (D>10) then Exit;
  try
    DecodeT5M(FAnswer,Words);
    if (Length(Words)<>FRows) or (FSelectedWord>Length(Words)) or
       (EncodeT5M(Words)<>FAnswer) then
      raise Exception.Create('втрачено точні T5M байти відповіді');
    if Length(Words[FSelectedWord-1])<>D then begin
      FProjectionLabel.Caption:='Не проєктувати: W'+
        IntToStr(Length(Words[FSelectedWord-1]))+' ≠ явно вибраний D'+
        IntToStr(D)+'. Числа D12+ не вгадуються.';
      Exit;
    end;
    { Весь каталoг перевіряє штатний loader; cached тільки після успіху. }
    if not FProjectionCatalogReady then begin
      Pin:=IncludeTrailingPathDelimiter(FRoot)+'external'+PathDelim+'sens';
      LoadPinnedProjections(Pin,FProjectionCatalog);
      FProjectionCatalogReady:=True;
    end;
    Key:=ExactKey(Words[FSelectedWord-1]);
    if (Key.Width<>D) or (Key.Bits>=Length(FProjectionCatalog[D])) or
      (not SameKey(FProjectionCatalog[D][Key.Bits].Key,Key)) then
      raise Exception.Create('немає exact координати pinned D'+IntToStr(D));
    for I:=0 to 5 do
      FProjectionGrid.Cells[1,I+1]:=
        SurfaceForDisplay(FProjectionCatalog[D][Key.Bits].Surface[I]);
    FProjectionLabel.Caption:='Форма '+IntToStr(FSelectedWord)+
      ', явно обрано D'+IntToStr(D)+':'+String(KeyBits(Key))+
      '. Тільки pinned людські проєкції, не доказ домену чи викличності.';
  except on E:Exception do begin
    ClearProjections;
    FProjectionLabel.Caption:='Проєкцію не допущено: '+E.Message;
  end end;
end;

procedure TBatchWindow.DomainChanged(Sender:TObject);
begin ShowChosenProjection end;

procedure TBatchWindow.ResultCellSelected(Sender:TObject;ACol,ARow:Integer;
  var CanSelect:Boolean);
begin
  if (ARow<1) or (ARow>FRows) then Exit;
  FSelectedWord:=ARow;
  ShowChosenProjection;
end;

procedure TBatchWindow.ClearResults;
var I,J:SizeInt;
begin
  FRows:=0; FAnswer:=''; FSelectedWord:=0; FSave.Enabled:=False;
  FChosenDomain.ItemIndex:=0;ClearProjections;
  for I:=1 to FResults.RowCount-1 do
    for J:=0 to 2 do FResults.Cells[J,I]:='';
  FResults.RowCount:=2;
end;

{ Path — host-шлях, не назва/проєкція SENS.
  Result — новий RawByteString канонічних фізичних T5M байтів.
  TFileStream локально належить цій функції; всі відмови до виконання. }
function TBatchWindow.ReadPhysical(const Path:String):RawByteString;
var F:TFileStream; Words:TExactWords;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise Exception.Create('очікується фізичний файл з розширенням .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxCore4WireBytes) then
      raise Exception.Create('фізичний файл поза межею 1..1 МіБ');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
  DecodeT5M(Result,Words);
  if (Length(Words)<1) or (EncodeT5M(Words)<>Result) then
    raise Exception.Create('неканонічний фізичний T5M');
end;

{ Одна транзакція відображення: стара відповідь спершу очищується.
  Всі точні слова отримані ТІЛЬКИ з реальної відповіді дочірнього процесу.
  Пізній remote fault не лишає жодного рядка, повторний запит — той самий PID. }
function TBatchWindow.ExecutePhysical(const Physical:RawByteString):Boolean;
var Answer:RawByteString; Words:TExactWords; I:SizeInt;
begin
  Result:=False; ClearResults;
  try
    if FClient=nil then raise Exception.Create('немає живого Core4-каналу');
    Answer:=FClient.Execute(Physical);
    DecodeT5M(Answer,Words);
    if (Length(Words)<1) or (Length(Words)>64) or
      (EncodeT5M(Words)<>Answer) then
      raise Exception.Create('відповідь не є канонічним пакетом 1..64');
    FResults.RowCount:=Length(Words)+1;
    for I:=0 to High(Words) do begin
      FResults.Cells[0,I+1]:=IntToStr(I+1);
      FResults.Cells[1,I+1]:='W'+IntToStr(Length(Words[I]));
      FResults.Cells[2,I+1]:=String(Words[I]);
    end;
    FRows:=Length(Words);
    FAnswer:=Answer; FSave.Enabled:=True;
    FSelectedWord:=1; ShowChosenProjection;
    FStatus.Caption:='Виконано '+IntToStr(FRows)+
      ' фізичних форм у незмінному PID='+IntToStr(FClient.ProcessID)+
      '. Wn — фізична ширина, а не домен Dn. Core4 не є загальним REPL.';
    Result:=True;
  except on E:Exception do begin
    ClearResults;
    FStatus.Caption:='Відмова без часткових результатів: '+E.Message;
  end end;
end;


{ Власник FTables/FLongs — форма. Усі записи читаємо тільки з pinned
  external/sens, одномоментно до готовності; ніяких власних D7 законів.
  Це кеш механічних укр назв для явно вибраного режиму, не dispatcher. }
procedure TBatchWindow.EnsureProjectionReady;
var Pin:String;
begin
  if FProjectionReady then Exit;
  if FRoot='' then raise Exception.Create('немає кореня pinned SENS');
  Pin:=IncludeTrailingPathDelimiter(FRoot)+'external'+PathDelim+'sens';
  LoadPinnedDomains(RawByteString(Pin),FTables);
  LoadPinnedLongProjection(RawByteString(Pin),FTables,FLongs);
  FProjectionReady:=True;
end;

{ Вхід — ТІЛЬКИ явна людська .lisp/укр UTF-8 проєкція.
  Managed RawByteString зберігає байти без Unicode→D7 припущень;
  parser та exact lookup належать вже наявному wsm.ukroundtrip. }
function TBatchWindow.ReadProjection(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.lisp') then
    raise EUkRoundtripError.Create('потрібен явний файл проєкції .lisp');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>1024*1024) then
      raise EUkRoundtripError.Create('порожня або завелика укр-проєкція');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

{ Два файли — два РІЗНІ host-входи, але ОДИН виконавчий канал.
  Український reader має доказ точних T5M байтів або відмовляє;
  ніякого fallback до англійських імен, D12+ чи host evaluator. }
function TBatchWindow.ExecuteFile(const Path:String):Boolean;
begin
  ClearResults; Result:=False;
  try Result:=ExecutePhysical(ReadPhysical(Path))
  except on E:Exception do begin
    ClearResults;
    FStatus.Caption:='Фізичний .sens відхилено: '+E.Message;
  end end;
end;

function TBatchWindow.ExecuteUkrFile(const Path:String):Boolean;
var Physical:RawByteString;
begin
  ClearResults; Result:=False;
  try
    EnsureProjectionReady;
    Physical:=UkrainianToPhysical(ReadProjection(Path),FTables,FLongs);
    Result:=ExecutePhysical(Physical);
  except on E:Exception do begin
    ClearResults;
    FStatus.Caption:='Українську укр-проєкцію відхилено: '+E.Message;
  end end;
end;

{ G5.38 — жодної реконструкції відповіді з таблиці/укр-проєкції.
  RawByteString FAnswer належить вікну, очищується при кожній відмові.
  Temp fd 0600 належить лише цій транзакції; fpLink — атомарний
  no-clobber навіть для існуючого dangling symbolic link. }
procedure TBatchWindow.SaveAnswerNew(const TargetPath:String);
var
  Words:TExactWords;
  TempPath,OutputPath:String;
  TempOwned,CloseOK:Boolean;
  Fd:LongInt;
  Offset,Written:SizeInt;
begin
  if (not FSave.Enabled) or (FAnswer='') or (FRows<1) or
     (FRows>64) then
    raise Exception.Create('немає підтвердженої фізичної Core4 відповіді');
  if (TargetPath='') or (ExtractFileName(TargetPath)='') or
     (Length(TargetPath)>4096) or
     (LowerCase(ExtractFileExt(TargetPath))<>'.sens') then
    raise Exception.Create('вихід має бути новим двійковим файлом .sens');
  if Length(FAnswer)>MaxCore4WireBytes then
    raise Exception.Create('завелика фізична відповідь');
  DecodeT5M(FAnswer,Words);
  if (Length(Words)<>FRows) or (EncodeT5M(Words)<>FAnswer) then
    raise Exception.Create('пошкоджена канонічна фізична відповідь');
  {$IFDEF UNIX}
  TempPath:=''; TempOwned:=False;
  try
    OutputPath:=ExpandFileName(TargetPath);
    TempPath:=GetTempFileName(ExtractFilePath(OutputPath),'c4o');
    if TempPath='' then
      raise Exception.Create('не отримано ім’я приватного temp');
    Fd:=fpOpen(PChar(TempPath),O_WrOnly or O_Creat or O_Excl,&600);
    if Fd<0 then
      raise Exception.Create('не створено приватний temp через O_EXCL');
    TempOwned:=True;
    CloseOK:=False;
    try
      Offset:=1;
      while Offset<=Length(FAnswer) do begin
        Written:=fpWrite(Fd,FAnswer[Offset],Length(FAnswer)-Offset+1);
        if Written<=0 then
          raise Exception.Create('частковий запис фізичної відповіді');
        Inc(Offset,Written);
      end;
    finally
      CloseOK:=fpClose(Fd)=0;
    end;
    if not CloseOK then
      raise Exception.Create('не вдалося закрити фізичний temp');
    if fpLink(RawByteString(TempPath),RawByteString(OutputPath))<>0 then
      raise Exception.Create('ціль уже існує або заборонено no-clobber');
  finally
    if TempOwned then DeleteFile(TempPath);
  end;
  {$ELSE}
  raise Exception.Create('атомарний запис .sens на цій ОС не підтверджено');
  {$ENDIF}
end;

procedure TBatchWindow.SaveClick(Sender:TObject);
begin
  if not FSave.Enabled then Exit;
  if not FSaveDialog.Execute then Exit;
  try
    SaveAnswerNew(FSaveDialog.FileName);
    FStatus.Caption:='Збережено точну фізичну Core4 відповідь без перезапису.';
  except on E:Exception do
    FStatus.Caption:='Фізичний експорт відхилено: '+E.Message end;
end;

procedure TBatchWindow.InputChanged(Sender:TObject);
begin
  ClearResults;
  FStatus.Caption:='Вхід змінено; попередній результат очищено.';
end;

procedure TBatchWindow.PickClick(Sender:TObject);
begin
  if FDialog.Execute then begin
    ClearResults;
    FPath.Text:=FDialog.FileName;
    FStatus.Caption:='Файл обрано; ще не виконано.';
  end;
end;

procedure TBatchWindow.PickUkrClick(Sender:TObject);
begin
  if FDialogUkr.Execute then begin
    ClearResults;
    FPath.Text:=FDialogUkr.FileName;
    FStatus.Caption:='Українську укр-проєкцію обрано; ще не виконано.';
  end;
end;

procedure TBatchWindow.RunClick(Sender:TObject);
begin ExecuteFile(FPath.Text) end;

procedure TBatchWindow.RunUkrClick(Sender:TObject);
begin ExecuteUkrFile(FPath.Text) end;

procedure TBatchWindow.Connect(const Root,Executable:String);
begin
  ClearResults; FRun.Enabled:=False; FRunUkr.Enabled:=False;
  FreeAndNil(FClient); FInitialPID:=-1;
  FProjectionReady:=False; FProjectionCatalogReady:=False;
  FRoot:=ExpandFileName(Root);
  FClient:=TCore4WireClient.Create(Executable,Root,True);
  FInitialPID:=FClient.ProcessID;
  Need(FInitialPID>0,'дочірній Core4-процес не запущено');
  FRun.Enabled:=True; FRunUkr.Enabled:=True;
  FStatus.Caption:='Core4-канал підключено, PID='+
    IntToStr(FInitialPID)+'. Очікується фізичний .sens з 1..64 формами.';
end;

{ Тестові пакети — лише T5M над реальними pinned D7-ключами.
  Для підтвердження результату використовується справжній remote runtime.
  Цей selftest не називає W24 числом D12+, не є SENS oracle. }
procedure TBatchWindow.SelfTest(const Root,Executable:String);
var
  Runtime:TCore4Runtime;
  Key0,Key1,Key2:RawByteString;
  Valid,UkrValid,Invalid,Combined,Projected:RawByteString;
  Temporary,Path,UkrPath,OutputPath,LinkPath:String;
  Expected,Existing:RawByteString;
  AnswerWords:TExactWords;
  LinkBuffer:array[0..4095] of AnsiChar;
  F:TFileStream;
  Rejected,CanChoose:Boolean;

  function Pack(const Sources:array of RawByteString):RawByteString;
  var A,B:TExactWords; X,Y,Start:SizeInt;
  begin
    SetLength(A,0);
    for X:=0 to High(Sources) do begin
      DecodeT5M(Sources[X],B);
      Start:=Length(A);
      SetLength(A,Start+Length(B));
      for Y:=0 to High(B) do A[Start+Y]:=B[Y];
    end;
    Result:=EncodeT5M(A);
  end;

  procedure Put(const Payload:RawByteString);
  begin
    F:=TFileStream.Create(Path,fmCreate);
    try if Length(Payload)>0 then F.WriteBuffer(Payload[1],Length(Payload))
    finally F.Free end;
  end;
  procedure PutUkr(const Payload:RawByteString);
  begin
    F:=TFileStream.Create(UkrPath,fmCreate);
    try if Length(Payload)>0 then F.WriteBuffer(Payload[1],Length(Payload))
    finally F.Free end;
  end;
begin
  Need(Assigned(FRun.OnClick) and Assigned(FPick.OnClick) and
    Assigned(FRunUkr.OnClick) and Assigned(FPickUkr.OnClick) and
    Assigned(FSave.OnClick) and Assigned(FPath.OnChange) and
    Assigned(FResults.OnSelectCell) and Assigned(FChosenDomain.OnChange) and
    (FResults.ColCount=3) and (FProjectionGrid.RowCount=7) and
    (FChosenDomain.Items.Count=11) and (not FSave.Enabled),
    'відсутні справжні LCL-контроли двох явних форматів');
  Connect(Root,Executable);
  Runtime:=TCore4Runtime.Create(Root);
  try
    Need(Runtime.BindingCount=3,'три pinned Core4 визначення не завантажено');
    Key0:=Runtime.BindingIdentifier(0);
    Key1:=Runtime.BindingIdentifier(1);
    Key2:=Runtime.BindingIdentifier(2);
    Need((Key0<>Key1) and (Key0<>Key2) and (Key1<>Key2),
      'повні D7 ключі мають бути різні');
  finally Runtime.Free end;

  Temporary:=GetTempFileName(GetTempDir(False),'s4p');
  Need(Temporary<>'','не створено тимчасовий тестовий файл');
  Path:=Temporary+'.sens';
  UkrPath:=Temporary+'.lisp';
  OutputPath:=Temporary+'.answer.sens';
  LinkPath:=Temporary+'.symlink.sens';
  try
    { GetTempFileName може повертати лише зарезервовану назву, а не
      готовий файл. Put створить власну фізичну .sens fixture. }
    Valid:=Pack([PhysicalD7Call(Key0,'1'),
      PhysicalD7Name(Key1),PhysicalD7Name(Key2)]);
    Put(Valid);
    Need(ExecuteFile(Path) and (FRows=3),'remote-пакет трьох форм');
    Need((FResults.Cells[1,1]='W1') and
      (FResults.Cells[2,1]='1') and
      (FResults.Cells[1,2]='W24') and
      (FResults.Cells[2,2]='000000000000000000000000') and
      (FResults.Cells[1,3]='W24') and
      (FResults.Cells[2,3]='000000000000000000000001'),
      'реальні Core4 T5M біти та окремі ширини');
    { G5.50: жодного неявного Wn → Dn. Свідок тільки З УЖЕ
      реально виконаних pinned Core4 W1 та W24 і ручного вибору. }
    Need((FChosenDomain.ItemIndex=0) and
      (FProjectionGrid.Cells[1,1]=''),
      'неявно призначено домен із фізичної W1-ширини');
    FChosenDomain.ItemIndex:=1; { користувач ЯВНО вибрав D1 }
    DomainChanged(nil);
    Need((FProjectionGrid.Cells[1,1]='так') and
      (FProjectionGrid.Cells[1,2]='так') and
      (FProjectionGrid.Cells[1,3]='ām') and
      (FProjectionGrid.Cells[1,4]='yes') and
      (FProjectionGrid.Cells[1,5]='T') and
      (FProjectionGrid.Cells[1,6]='(відсутня)'),
      'шість pinned D1:1 поверхонь першої РЕАЛЬНОЇ форми');
    CanChoose:=True;
    ResultCellSelected(FResults,1,2,CanChoose); { та сама LCL подія }
    Need(CanChoose and (FSelectedWord=2),
      'справжнє LCL вибрання другого фізичного слова');
    Need((FProjectionGrid.Cells[1,1]='') and
      (Pos('W24',FProjectionLabel.Caption)>0),
      'W24 заборонено вгадувати як numeric D12+ чи D1');
    FChosenDomain.ItemIndex:=7;DomainChanged(nil);
    Need((FProjectionGrid.Cells[1,2]='') and
      (Pos('W24',FProjectionLabel.Caption)>0),
      'W24 не можна приписати D7, текстові glyph — не dispatch');
    FSelectedWord:=1;ShowChosenProjection;
    Need(FProjectionGrid.Cells[1,2]='',
      'W1 не можна приписати D7');
    FChosenDomain.ItemIndex:=1;DomainChanged(nil);
    Need(FProjectionGrid.Cells[1,2]='так',
      'відновлення явної D1 проєкції на правильній формі');
    Need(FClient.ProcessID=FInitialPID,'змінений PID після пакета');
    SetLength(AnswerWords,3);
    AnswerWords[0]:='1';
    AnswerWords[1]:='000000000000000000000000';
    AnswerWords[2]:='000000000000000000000001';
    Expected:=EncodeT5M(AnswerWords);
    Need(FSave.Enabled and (FAnswer=Expected),
      'немає підтвердженої фізичної Core4 відповіді');
    SaveAnswerNew(OutputPath);
    Need(ReadPhysical(OutputPath)=Expected,
      'експорт фізичної W1/W24 відповіді не побайтовий');
    Existing:=ReadPhysical(OutputPath);
    Rejected:=False;
    try SaveAnswerNew(OutputPath)
    except on E:Exception do Rejected:=True end;
    Need(Rejected and (ReadPhysical(OutputPath)=Existing),
      'існуючий результат перезаписано');
    Rejected:=False;
    try SaveAnswerNew(OutputPath+'.lisp')
    except on E:Exception do Rejected:=True end;
    Need(Rejected and (not FileExists(OutputPath+'.lisp')),
      'вихід .lisp помилково прийнято');
    Rejected:=False;
    try SaveAnswerNew(Temporary+'.missing-folder/not-created.sens')
    except on E:Exception do Rejected:=True end;
    Need(Rejected and (not FileExists(Temporary+'.missing-folder/not-created.sens')),
      'неіснуючий каталог запису прийнято');
    {$IFDEF UNIX}
    Need(fpSymlink(PChar(Temporary+'.absent.sens'),PChar(LinkPath))=0,
      'не створено dangling symlink для перевірки');
    Rejected:=False;
    try SaveAnswerNew(LinkPath)
    except on E:Exception do Rejected:=True end;
    Need(Rejected and (fpReadLink(PChar(LinkPath),LinkBuffer,SizeOf(LinkBuffer))>0)
      and (not FileExists(Temporary+'.absent.sens')),
      'dangling symlink перезаписано або створено чужу ціль');
    {$ENDIF}
    Need(FSave.Enabled and (FAnswer=Expected),
      'негатив експорту знищив перевірену відповідь');

    { Українська укр отримана з ТОГО САМОГО точного фізичного
      pinned D7 пакета, а не з вигаданих текстових назв. }
    EnsureProjectionReady;
    { Той самий фізичний пакет з дефісними pinned D7 глобалами
      НЕ МОЖНА втратовільно проєктувати як набір окремих укр атомів.
      Контрактний негатив: жодного мовчазного fallback. }
    Rejected:=False;
    try Projected:=PhysicalToUkrainian(Valid,FTables,FLongs)
    except on E:EUkRoundtripError do Rejected:=True end;
    Need(Rejected,'синтаксично неоднозначний pinned D7 пройшов укр projection');
    { Похідні глобальні D7-імена можуть містити синтаксично
      недопустимі окремі glyph для звичайної оборотної проєкції.
      Ніколи не підмінюємо їх спрощеною декомпозицією чи Unicode.
      Перевіряємо справжній pinned оборотний піднабір Key0 без дефіса. }
    UkrValid:=Pack([PhysicalD7Call(Key0,'1'),
      PhysicalD7Call(Key0,'0')]);
    Projected:=PhysicalToUkrainian(UkrValid,FTables,FLongs);
    Need((Projected<>'') and
      (UkrainianToPhysical(Projected,FTables,FLongs)=UkrValid),
      'не оборотний pinned D7/укр → фізичний T5M');
    PutUkr(Projected);
    Need(ExecuteUkrFile(UkrPath) and (FRows=2) and
      (FResults.Cells[1,1]='W1') and
      (FResults.Cells[2,1]='1') and
      (FResults.Cells[1,2]='W1') and
      (FResults.Cells[2,2]='0'),
      'реальний пакет з двох українських .lisp проєкцій');
    Need(FClient.ProcessID=FInitialPID,'укр запросив новий дочірній PID');
    SetLength(AnswerWords,2);
    AnswerWords[0]:='1'; AnswerWords[1]:='0';
    Expected:=EncodeT5M(AnswerWords);
    Need(FSave.Enabled and (FAnswer=Expected),
      'українська відповідь не є реальними двома W1');
    SaveAnswerNew(Temporary+'.ukr-answer.sens');
    Need(ReadPhysical(Temporary+'.ukr-answer.sens')=Expected,
      'експорт укр не дорівнює фізичній remote-відповіді');

    Need(not ExecuteUkrFile(Path),'двійковий файл в укр-режимі прийнято');
    PutUkr('');
    Need(not ExecuteUkrFile(UkrPath),'порожній укр файл прийнято');
    PutUkr(#$D1);
    Need(not ExecuteUkrFile(UkrPath),'зіпсований UTF-8 прийнято');
    PutUkr('(невідома-назва)');
    Need(not ExecuteUkrFile(UkrPath),'невідому укр-назву прийнято');
    Need((FRows=0) and (FResults.Cells[2,1]='') and
      (FClient.ProcessID=FInitialPID),
      'після укр відмови збережено рядки чи втрачено PID');
    { Пізня remote-відмова після першої правильної укр-форми. }
    Projected:=PhysicalToUkrainian(
      Pack([PhysicalD7Call(Key0,'1'),PhysicalD7Name(Key0)]),
      FTables,FLongs);
    PutUkr(Projected);
    Need(not ExecuteUkrFile(UkrPath),'пізня укр remote помилка пройшла');
    Need((FRows=0) and (FAnswer='') and (not FSave.Enabled) and
      (FClient.ProcessID=FInitialPID),
      'пізня укр remote помилка залишила старий результат');
    PutUkr(PhysicalToUkrainian(UkrValid,FTables,FLongs));
    Need(ExecuteUkrFile(UkrPath) and (FRows=2) and
      (FClient.ProcessID=FInitialPID),
      'реальне укр виконання не відновилось після негативів');
    FPath.Text:=UkrPath;
    Need((FRows=0) and (FAnswer='') and (not FSave.Enabled) and
      (FChosenDomain.ItemIndex=0) and (FProjectionGrid.Cells[1,1]='') and
      (FProjectionGrid.Cells[1,2]=''),
      'редагування поля не очистило відповідь та шість проєкцій');


    Need(not ExecuteFile(Path+'.lisp'),'вхід .lisp помилково виконаний');
    Need((FRows=0) and (FResults.Cells[2,1]=''),
      'залишилася попередня відповідь після .lisp');
    Put(Chr(243));
    Need(not ExecuteFile(Path),'неправильний T5M помилково прийнято');
    Need((FRows=0) and (FClient.ProcessID=FInitialPID),
      'неканонічний вхід залишив стан або перезапустив PID');

    { Перша форма успішна, ДРУГА навмисне не викликається:
      початкове pinned замикання не є глобальним exact значенням. }
    Invalid:=Pack([PhysicalD7Call(Key0,'1'),PhysicalD7Name(Key0)]);
    Put(Invalid);
    Need(not ExecuteFile(Path),'пізня remote-відмова не відхилена');
    Need((FRows=0) and (FResults.Cells[2,1]='') and
      (FAnswer='') and (not FSave.Enabled) and
      (FClient.ProcessID=FInitialPID),'частковий результат або інший PID');

    Combined:=Pack([PhysicalD7Call(Key0,'0'),
      PhysicalD7Call(Key0,'1')]);
    Put(Combined);
    Need(ExecuteFile(Path) and (FRows=2) and
      (FResults.Cells[2,1]='0') and (FResults.Cells[2,2]='1') and
      (FClient.ProcessID=FInitialPID),
      'відновлення після remote-відмови в тому самому процесі');
    Window.Show; Application.ProcessMessages;
    WriteLn('LCL-CORE4-ПРОЄКЦІЇ-ГАРАЗД ',
      'D1=явний pinned=6 W24=без-домену D7=не-dispatch ',
      'вхід-змінено=очищено PID=один');
    WriteLn('LCL-CORE4-ПАКЕТ-ГАРАЗД ',
      'Lazarus=GTK2 реальний-PID=один пакет=3 ',
      'W1-W24=побайтово пізня-помилка=атомарна ',
      'T5M=відхилено lisp=відхилено відновлення=так ',
      'D12+=без-вгадування REPL=ні');
    WriteLn('LCL-CORE4-ЕКСПОРТ-ГАРАЗД ',
      'T5M=byte-exact W1-W24=збережено укр=збережено ',
      'O_EXCL=так hardlink=no-clobber symlink=відхилено ',
      'lisp=відхилено stale=очищено');
    WriteLn('LCL-CORE4-УКР-ГАРАЗД ',
      'укр=лише-явно D7=pinned T5M=byte-exact ',
      'W1=реально W24=лише-фізичний пізня-відмова=очищено ',
      'UTF8=відхилено unknown=відхилено PID=один ',
      'редагування=очищено');
  finally
    if FileExists(Path) then DeleteFile(Path);
    if FileExists(OutputPath) then DeleteFile(OutputPath);
    if FileExists(Temporary+'.ukr-answer.sens') then
      DeleteFile(Temporary+'.ukr-answer.sens');
    {$IFDEF UNIX}
    fpUnlink(PChar(LinkPath));
    {$ENDIF}
    if FileExists(UkrPath) then DeleteFile(UkrPath);
    if FileExists(Temporary) then DeleteFile(Temporary);
  end;
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — фізичний пакет Core4';
    Application.CreateForm(TBatchWindow,Window);
    if (ParamCount=3) and (ParamStr(1)='--самоперевірка') then begin
      Window.SelfTest(ParamStr(2),ParamStr(3));
      Window.Free;
    end else if ParamCount=2 then begin
      Window.Connect(ParamStr(1),ParamStr(2));
      Application.Run;
    end else begin
      WriteLn(StdErr,'Використання: core4-paket-okno ROOT senscore4kanal ',
        'або --самоперевірка ROOT senscore4kanal');
      Halt(64);
    end;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-ПАКЕТ-ПОМИЛКА: ',E.Message);
    Halt(2);
  end end;
end.
