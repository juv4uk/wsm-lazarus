{ Окремий GUI-клієнт уже злитого двійкового виконавця.
  Віджети не створюють другого мовного закону або текстового парсера. }
unit wsm.runpanel;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs, Grids,
  wsm.execfault, wsm.core4wireclient, wsm.proektsii;
type
  TSensRunForm = class(TForm)
  private
    FFileName: TLabel;
    FStatus: TLabel;
    FOutput: TMemo;
    FCoordinates: TStringGrid; { фізичні адреси, не координати мови }
    FProjectionGrid: TStringGrid; { 6 pinned поверхонь, тільки відображення }
    FProjectionLabel: TLabel;
    FProjections: TProektsiiCatalog; { кеш D1..D10 чинного pin }
    FProjectionReady: Boolean;
    FOpen: TButton;
    FChannelOpen: TButton;
    FUkrOpen: TButton; { реальна кнопка української проєкції }
    FSavePhysical: TButton; { неактивна без справжньої D3 відповіді }
    FChannelClient: TCore4WireClient; { власник — GUI, тільки host-transport }
    FChannelPID: Int64;
    FChannelRoot: String; { host-шлях до pinned SENS }
    FChannelLastPhysical: RawByteString; { фізичний T5M, не проєкція }
    FDialog: TOpenDialog;
    FUkrDialog: TOpenDialog;
    FSaveDialog: TSaveDialog;
    procedure OpenClick(Sender: TObject);
    procedure ChannelClick(Sender: TObject);
    procedure UkrClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    function ReadUkrSource(const Path:String):RawByteString;
    function DisplayChannelAnswer(const Answer:RawByteString;
      const FromUkr:Boolean):Boolean;
    function ReadChannelSource(const Path:String):RawByteString;
    procedure Reject(const Reason: String);
    procedure ClearCoordinates;
    procedure ClearProjections;
    procedure ShowProjectionWord(const Bits:RawByteString);
    procedure ShowFault(E: ELocatedExecutionFault);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ConnectChannel(const Root, Executable:String);
    function ExecuteChannelFile(const Path:String):Boolean;
    function ExecuteUkrFile(const Path:String):Boolean;
    function SavePhysicalNew(const Path:String):Boolean;
    procedure SmokeTestProjections(const Root,Executable,GoodFile,
      ExpectedFile,AtomUkrFile,AtomAnswer,LateBadFile,D12File:String);
    procedure SmokeTestSave(const Root,Executable,GoodFile,
      ExpectedFile,LateBadFile,OutputDir:String);
    procedure SmokeTestUkr(const Root,Executable,PhysicalFile,
      OneUkrFile,OneAnswer,AtomUkrFile,AtomAnswer,NegativeDir:String);
    procedure SmokeTestChannel(const Root,Executable,GoodFile,ExpectedFile,
      LateBadFile,D12File,MultiFile,BrokenFile:String);
    function ExecuteFile(const Path: String): Boolean;
    procedure SmokeTest(const GoodFile, BadFile, NestedFile,
      EofFile, BrokenFile, Expected: String);
  end;

implementation
uses BaseUnix, wsm.binaryexec, wsm.t5m, wsm.bind,
  wsm.domain, wsm.ukroundtrip;
const
  PhysicalLimit = MAX_T5M_FILE_BYTES;

constructor TSensRunForm.Create(AOwner: TComponent);
var Bar, Footer, SpanPanel, ProjectionPanel: TPanel; Heading: TLabel;
    I:Integer;
begin
  inherited CreateNew(AOwner,1);
  Caption := 'SENS — двійкове виконання';
  Position := poScreenCenter;
  Width := 810;
  Height := 690;
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 180;
  Bar.BevelOuter := bvNone;
  Heading := TLabel.Create(Self);
  Heading.Parent := Bar;
  Heading.SetBounds(14,8,760,22);
  Heading.Caption := 'Фізичний .sens — первинний; українська лише проєкція';
  FOpen := TButton.Create(Self);
  FOpen.Parent := Bar;
  FOpen.SetBounds(14,36,200,31);
  FOpen.Caption := 'Відкрити й виконати .sens…';
  FOpen.OnClick := @OpenClick;
  FChannelClient := nil;
  FChannelPID := -1;
  FChannelLastPhysical := '';
  FChannelRoot := '';
  FProjectionReady:=False;
  FChannelOpen := TButton.Create(Self);
  FChannelOpen.Parent := Bar;
  FChannelOpen.SetBounds(14,72,310,28);
  FChannelOpen.Caption := 'Виконати через постійний D3-канал';
  FChannelOpen.Enabled := False;
  FChannelOpen.OnClick := @ChannelClick;
  FUkrOpen:=TButton.Create(Self);
  FUkrOpen.Parent:=Bar;
  FUkrOpen.SetBounds(338,72,430,28);
  FUkrOpen.Caption:='Виконати українську .lisp через фізичний D3-канал';
  FUkrOpen.Enabled:=False;
  FUkrOpen.OnClick:=@UkrClick;
  FUkrDialog:=TOpenDialog.Create(Self);
  FUkrDialog.Filter:='Українська проєкція SENS (*.lisp)|*.lisp';
  FUkrDialog.Title:='Оберіть звичайну повну укр-проєкцію';
  FSavePhysical:=TButton.Create(Self);
  FSavePhysical.Parent:=Bar;
  FSavePhysical.SetBounds(14,108,405,28);
  FSavePhysical.Caption:='Зберегти фізичну відповідь .sens…';
  FSavePhysical.Enabled:=False;
  FSavePhysical.OnClick:=@SaveClick;
  FSaveDialog:=TSaveDialog.Create(Self);
  FSaveDialog.Filter:='Канонічна двійкова відповідь SENS (*.sens)|*.sens';
  FSaveDialog.DefaultExt:='sens';
  FSaveDialog.Title:='Зберегти перевірену фізичну відповідь у новий .sens';
  FSaveDialog.Options:=FSaveDialog.Options+[ofPathMustExist,ofOverwritePrompt];
  FFileName := TLabel.Create(Self);
  FFileName.Parent := Bar;
  FFileName.SetBounds(14,146,756,25);
  FFileName.Caption := 'Файл ще не вибрано';
  FDialog := TOpenDialog.Create(Self);
  FDialog.Filter := 'Фізичні файли SENS|*.sens';
  FDialog.Title := 'Оберіть фізичну програму SENS';
  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 56;
  Footer.BevelOuter := bvNone;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Footer;
  FStatus.SetBounds(14,5,780,44);
  FStatus.AutoSize := False;
  FStatus.WordWrap := True;
  FStatus.Caption := 'Очікується двійковий файл. Виконується тільки підтримана підмножина D1/D3.';
  { Таблиця показує фактичні напіввідкриті фізичні інтервали.
    Віджети належать Self і звільняються разом із TForm. }
  SpanPanel := TPanel.Create(Self);
  SpanPanel.Parent := Self;
  SpanPanel.Align := alBottom;
  SpanPanel.Height := 120;
  SpanPanel.BevelOuter := bvNone;
  FCoordinates := TStringGrid.Create(Self);
  FCoordinates.Parent := SpanPanel;
  FCoordinates.Align := alClient;
  FCoordinates.FixedCols := 0;
  FCoordinates.ColCount := 3;
  FCoordinates.RowCount := 4;
  FCoordinates.FixedRows := 1;
  FCoordinates.ColWidths[0] := 148;
  FCoordinates.ColWidths[1] := 170;
  FCoordinates.ColWidths[2] := 215;
  FCoordinates.Cells[0,0] := 'Фізична адреса';
  FCoordinates.Cells[1,0] := 'Початок';
  FCoordinates.Cells[2,0] := 'Кінець (виключно)';
  FCoordinates.Cells[0,1] := 'Слово (1-based)';
  FCoordinates.Cells[0,2] := 'Трити (0-based)';
  FCoordinates.Cells[0,3] := 'Байти (0-based)';
  ClearCoordinates;
  { Праворуч — новий справжній LCL Grid: він не бере участі у виконанні.
    Для D7 символи в лапках показуємо БУКВАЛЬНО як дані pinned SENS. }
  ProjectionPanel:=TPanel.Create(Self);
  ProjectionPanel.Parent:=Self;
  ProjectionPanel.Align:=alRight;
  ProjectionPanel.Width:=360;
  ProjectionPanel.BevelOuter:=bvNone;
  FProjectionLabel:=TLabel.Create(Self);
  FProjectionLabel.Parent:=ProjectionPanel;
  FProjectionLabel.Align:=alTop;
  FProjectionLabel.Height:=38;
  FProjectionLabel.AutoSize:=False;
  FProjectionLabel.WordWrap:=True;
  FProjectionGrid:=TStringGrid.Create(Self);
  FProjectionGrid.Parent:=ProjectionPanel;
  FProjectionGrid.Align:=alClient;
  FProjectionGrid.FixedCols:=0;
  FProjectionGrid.FixedRows:=1;
  FProjectionGrid.ColCount:=2;
  FProjectionGrid.RowCount:=7;
  FProjectionGrid.ColWidths[0]:=78;
  FProjectionGrid.ColWidths[1]:=245;
  FProjectionGrid.Cells[0,0]:='Поверхня';
  FProjectionGrid.Cells[1,0]:='Значення з pin';
  FProjectionGrid.Cells[0,1]:='ук';
  FProjectionGrid.Cells[0,2]:='укр';
  FProjectionGrid.Cells[0,3]:='san';
  FProjectionGrid.Cells[0,4]:='en';
  FProjectionGrid.Cells[0,5]:='LISP';
  FProjectionGrid.Cells[0,6]:='sym';
  FProjectionGrid.Options:=FProjectionGrid.Options-[goEditing];
  for I:=1 to 6 do FProjectionGrid.Cells[1,I]:='';
  ClearProjections;
  FOutput := TMemo.Create(Self);
  FOutput.Parent := Self;
  FOutput.Align := alClient;
  FOutput.ReadOnly := True;
  FOutput.ScrollBars := ssVertical;
  FOutput.Lines.Text := '';
end;

{ Фізичний дитячий PID належить одному GUI об'єкту. Жодна форма
  не набуває persistent SENS bindings — збережений тільки transport. }
destructor TSensRunForm.Destroy;
begin
  FreeAndNil(FChannelClient);
  inherited Destroy;
end;

procedure TSensRunForm.ConnectChannel(const Root,Executable:String);
var Candidate:TProektsiiCatalog; D:Integer;
begin
  FChannelOpen.Enabled := False;
  FUkrOpen.Enabled := False;
  FSavePhysical.Enabled := False;
  FChannelRoot := '';
  FChannelLastPhysical := '';
  FOutput.Clear;
  ClearCoordinates;
  ClearProjections;
  FProjectionReady:=False;
  for D:=1 to 10 do SetLength(FProjections[D],0);
  FreeAndNil(FChannelClient);
  FChannelPID := -1;
  { Повний незалежний pinned-каталог допущено ДО появи дитячого PID.
    Кандидат живе лише під час перевірки, FProjections — увесь GUI-сеанс. }
  LoadPinnedProjections(Root,Candidate);
  FChannelClient := TCore4WireClient.Create(Executable,Root,False);
  FChannelPID := FChannelClient.ProcessID;
  if FChannelPID<=0 then begin
    FreeAndNil(FChannelClient);
    raise Exception.Create('дочірній D3-канал не запущено');
  end;
  FProjections:=Candidate;
  FProjectionReady:=True;
  FChannelRoot:=Root;
  FChannelOpen.Enabled := True;
  FUkrOpen.Enabled := True;
  FStatus.Caption := 'Постійний фізичний D3-канал PID='+
    IntToStr(FChannelPID)+'; лише одиничні результати, не REPL.';
end;

{ Path: суто шлях ОС; Result — новий bounded canonical T5M buffer.
  TFileStream живе тільки всередині функції. Ні укр, ні D7, ні
  інші проєкції не використовуються для семантичного dispatch. }
function TSensRunForm.ReadChannelSource(const Path:String):RawByteString;
var Input:TFileStream; Words:TExactWords;
begin
  Result := '';
  if (Path='') or (Length(Path)>4096) or
    (ExtractFileExt(Path)<>'.sens') then
    raise Exception.Create('канал приймає тільки фізичний файл .sens');
  Input := TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Input.Size<1) or (Input.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('порожній або завеликий фізичний файл');
    SetLength(Result,SizeInt(Input.Size));
    Input.ReadBuffer(Result[1],Length(Result));
  finally Input.Free end;
  DecodeT5M(Result,Words);
  if (Length(Words)=0) or (EncodeT5M(Words)<>Result) then
    raise Exception.Create('неканонічний фізичний T5M');
end;

{ Буквальне UTF-8 з повної pinned укр проєкції. Потік належить
  виклику, Result — новий RawByteString до 1 МіБ. Це не код мови. }
function TSensRunForm.ReadUkrSource(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (Length(Path)>4096) or
    (LowerCase(ExtractFileExt(Path))<>'.lisp') then
    raise Exception.Create('потрібний звичайний український файл .lisp');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>1024*1024) then
      raise Exception.Create('укр-файл порожній або понад 1 МіБ');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Тільки вже виконані канонічні T5M bytes із чинного D3 дитячого
  процесу. Wn — точна ширина відповіді, не ратифікований Dn. }
{ Два незалежні подання одного ПОЗИЧЕНОГО exact фізичного слова.
  Bits: RawByteString із вже декодованої успішної T5M-відповіді,
  НЕ людська назва функції та НЕ число D12+.
  TProektsiiRow — тільки pinned таблиця; StringGrid належить Self.
  Якщо довжина >10, шість колонок порожні: не вигадуємо D12+ тексту. }
procedure TSensRunForm.ShowProjectionWord(const Bits:RawByteString);
var Key:TDomainKey;D,I:SizeInt;TextView:array[0..5] of String;
begin
  ClearProjections;
  D:=Length(Bits);
  if (D<1) or (D>10) then begin
    FProjectionLabel.Caption:='W'+IntToStr(D)+
      ': немає pinned D1–D10 проєкції; D12+ не розшифровано.';
    Exit;
  end;
  if not FProjectionReady then
    raise Exception.Create('pinned проєкції ще не завантажено');
  Key:=ExactKey(Bits);
  if (Length(FProjections[D])<>(SizeInt(1) shl D)) or
    (Key.Bits<0) or (Key.Bits>=Length(FProjections[D])) or
    not SameKey(FProjections[D][Key.Bits].Key,Key) then
    raise Exception.Create('розбіжність exact ключа pinned проєкції');
  { Збираємо 6 значень локально, публікуємо лише після повної
    перевірки одного рядка; ніколи не перетворюємо spelling на dispatch. }
  for I:=0 to 5 do
    TextView[I]:=SurfaceForDisplay(FProjections[D][Key.Bits].Surface[I]);
  for I:=0 to 5 do FProjectionGrid.Cells[1,I+1]:=TextView[I];
  FProjectionLabel.Caption:='D'+IntToStr(D)+':'+String(Bits)+
    ' — pinned відображення, НЕ виклик';
end;

function TSensRunForm.DisplayChannelAnswer(const Answer:RawByteString;
  const FromUkr:Boolean):Boolean;
var W:TExactWords;LabelText:String;
begin
  DecodeT5M(Answer,W);
  if (Length(W)<>1) or (EncodeT5M(W)<>Answer) then
    raise Exception.Create('очікується рівно одне канонічне слово');
  if FromUkr then LabelText:='Українська укр → фізичне D3'
  else LabelText:='Фізичне D3';
  ShowProjectionWord(W[0]);
  FChannelLastPhysical:=Answer;
  FSavePhysical.Enabled:=True;
  FOutput.Lines.Text:='W'+IntToStr(Length(W[0]))+':'+String(W[0]);
  FStatus.Caption:=LabelText+', PID='+IntToStr(FChannelClient.ProcessID)+
    '; Wn — ширина, не домен Dn; це не REPL.';
  Result:=True;
end;

{ Source: текстове .lisp лише як pinned укр-проєкція.
  Tables,Longs: локальні керовані масиви D1–D9; lifetime виклику.
  Physical: packed canonical T5M; немає другого evaluator:
  єдиний семантичний шлях — дочірній senspotikd3 --канал. }
function TSensRunForm.ExecuteUkrFile(const Path:String):Boolean;
var Source,Physical,Projected,Again,Answer:RawByteString;
    Tables:TDomainSet;Longs:TLongProjection;
begin
  Result:=False;FOutput.Clear;ClearCoordinates;ClearProjections;
  FSavePhysical.Enabled:=False;
  FChannelLastPhysical:='';
  FFileName.Caption:='Українська проєкція: '+ExtractFileName(Path);
  try
    if (FChannelClient=nil) or (FChannelRoot='') then
      raise Exception.Create('постійний D3-канал не підключений');
    Source:=ReadUkrSource(Path);
    LoadPinnedDomains(RawByteString(FChannelRoot),Tables);
    LoadPinnedLongProjection(RawByteString(FChannelRoot),Tables,Longs);
    Physical:=UkrainianToPhysical(Source,Tables,Longs);
    if (Length(Physical)<1) or (Length(Physical)>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('фізичний T5M поза межею 1..64 КіБ');
    Projected:=PhysicalToUkrainian(Physical,Tables,Longs);
    Again:=UkrainianToPhysical(Projected,Tables,Longs);
    if Again<>Physical then
      raise Exception.Create('побайтовий укр/T5M round-trip не збігся');
    Answer:=FChannelClient.Execute(Physical);
    Result:=DisplayChannelAnswer(Answer,True);
  except on E:Exception do
    Reject('українська укр-проєкція: '+E.Message);
  end;
end;

{ Path — лише host-шлях до НОВОГО .sens, не мовне значення.
  FChannelLastPhysical — копія дійсного canonical T5M від дочірнього
  D3 runtime. Timely TFileStream живе тільки всередині виклику;
  temp створюється в каталозі цілі, fpLink виконує атомарне O_EXCL-подібне
  no-clobber навіть для dangling symlink, temp видаляється у finally.
  Result=true лише після повного запису й hardlink, без echo UTF-8. }
function TSensRunForm.SavePhysicalNew(const Path:String):Boolean;
var TempPath,AbsolutePath:String; F:TFileStream; W:TExactWords;
begin
  Result:=False;
  TempPath:='';
  try
    if (Path='') or (Length(Path)>4096) or
       (LowerCase(ExtractFileExt(Path))<>'.sens') then
      raise Exception.Create('для відповіді потрібен новий .sens');
    if (not FSavePhysical.Enabled) or (FChannelLastPhysical='') then
      raise Exception.Create('немає поточної перевіреної D3-відповіді');
    DecodeT5M(FChannelLastPhysical,W);
    if (Length(W)=0) or
       (EncodeT5M(W)<>FChannelLastPhysical) then
      raise Exception.Create('внутрішня фізична відповідь неканонічна');
    AbsolutePath:=ExpandFileName(Path);
    if not DirectoryExists(ExtractFileDir(AbsolutePath)) then
      raise Exception.Create('не існує каталогу призначення');
    TempPath:=GetTempFileName(ExtractFileDir(AbsolutePath),'sen');
    if TempPath='' then
      raise Exception.Create('не створено приватний тимчасовий файл');
    F:=TFileStream.Create(TempPath,fmCreate);
    try
      F.WriteBuffer(FChannelLastPhysical[1],Length(FChannelLastPhysical));
    finally F.Free end;
    if fpLink(PChar(TempPath),PChar(AbsolutePath))<>0 then
      raise Exception.Create('ціль вже існує або атомарне створення неможливе');
    FStatus.Caption:='Фізичну D3-відповідь збережено в новий .sens: '+
      ExtractFileName(AbsolutePath)+
      ' (канонічних байтів '+IntToStr(Length(FChannelLastPhysical))+')';
    Result:=True;
  except on E:Exception do
    { Не змінюємо довірений фізичний вміст після помилки ШЛЯХУ:
      можна обрати іншу нову назву, але не зберегти старий result
      після пізньої відмови виконання (той стан очищує Reject). }
    FStatus.Caption:='Збереження відхилено: '+E.Message;
  end;
  if TempPath<>'' then DeleteFile(TempPath);
end;

procedure TSensRunForm.SaveClick(Sender:TObject);
begin
  if FSavePhysical.Enabled and FSaveDialog.Execute then
    SavePhysicalNew(FSaveDialog.FileName);
end;

procedure TSensRunForm.UkrClick(Sender:TObject);
begin
  if FUkrDialog.Execute then ExecuteUkrFile(FUkrDialog.FileName);
end;

{ Один запит проходить реальний senspotikd3 --канал в тому самому PID.
  TCore4WireClient позичаємо тільки для існуючого механічного протоколу
  (u32le + T5M, status + u32le + bytes), НЕ для семантики Core4.
  При відмові знищуємо весь попередній GUI результат. }
function TSensRunForm.ExecuteChannelFile(const Path:String):Boolean;
var Request,Answer:RawByteString;
begin
  Result:=False;
  FSavePhysical.Enabled:=False;
  FOutput.Clear;
  ClearCoordinates;
  ClearProjections;
  FChannelLastPhysical:='';
  FFileName.Caption:='Файл: '+ExtractFileName(Path);
  try
    if FChannelClient=nil then
      raise Exception.Create('постійний D3-канал не підключено');
    Request:=ReadChannelSource(Path);
    Answer:=FChannelClient.Execute(Request);
    Result:=DisplayChannelAnswer(Answer,False);
  except on E:Exception do begin
    FChannelLastPhysical:='';
    Reject('постійний D3-канал: '+E.Message);
  end end;
end;

procedure TSensRunForm.ChannelClick(Sender:TObject);
begin
  if FDialog.Execute then ExecuteChannelFile(FDialog.FileName);
end;

procedure TSensRunForm.ClearProjections;
var I:Integer;
begin
  for I:=1 to 6 do FProjectionGrid.Cells[1,I]:='';
  FProjectionLabel.Caption:='Проєкції: очікується виконана фізична відповідь';
end;

procedure TSensRunForm.ClearCoordinates;
var I: Integer;
begin
  for I:=1 to 3 do begin
    FCoordinates.Cells[1,I] := '';
    FCoordinates.Cells[2,I] := '';
  end;
end;

procedure TSensRunForm.Reject(const Reason: String);
begin
  FSavePhysical.Enabled:=False;
  FOutput.Clear;
  ClearCoordinates;
  FChannelLastPhysical:='';
  FStatus.Caption := 'Відхилено: ' + Reason;
end;

procedure TSensRunForm.ShowFault(E: ELocatedExecutionFault);
begin
  Reject(E.Message);
  FCoordinates.Cells[1,1] := IntToStr(E.WordIndex);
  if E.HasPhysicalSpan then begin
    if E.Span.IsEOF then FCoordinates.Cells[2,1] := 'EOF'
    else FCoordinates.Cells[2,1] := 'фізичне слово';
    FCoordinates.Cells[1,2] := IntToStr(E.Span.TritStart);
    FCoordinates.Cells[2,2] := IntToStr(E.Span.TritEnd);
    FCoordinates.Cells[1,3] := IntToStr(E.Span.ByteStart);
    FCoordinates.Cells[2,3] := IntToStr(E.Span.ByteEnd);
    FStatus.Caption := 'Відхилено: слово '+IntToStr(E.WordIndex)+
      ', трити ['+IntToStr(E.Span.TritStart)+','+
      IntToStr(E.Span.TritEnd)+'), байти ['+
      IntToStr(E.Span.ByteStart)+','+IntToStr(E.Span.ByteEnd)+')';
    if E.Span.IsEOF then FStatus.Caption := FStatus.Caption+' EOF';
  end else begin
    FCoordinates.Cells[2,1] := 'адреса невідома';
    FStatus.Caption := 'Відхилено: слово '+IntToStr(E.WordIndex)+
      ', фізична адреса невідома';
  end;
end;

function TSensRunForm.ExecuteFile(const Path: String): Boolean;
var Input: TFileStream; Physical, Answer: RawByteString;
    Executor: TBinaryExecutor;
begin
  Result := False;
  FSavePhysical.Enabled := False;
  FOutput.Clear;
  ClearCoordinates;
  ClearProjections;
  FChannelLastPhysical:='';
  FStatus.Caption := 'Перевіряємо фізичні байти…';
  FFileName.Caption := 'Файл: ' + ExtractFileName(Path);
  try
    if LowerCase(ExtractFileExt(Path)) <> '.sens' then
      raise Exception.Create('очікується двійковий файл .sens');
    Input := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
    try
      if (Input.Size <= 0) or (Input.Size > PhysicalLimit) then
        raise Exception.Create('порожній або завеликий фізичний файл');
      SetLength(Physical,SizeInt(Input.Size));
      Input.ReadBuffer(Physical[1],Length(Physical));
    finally
      Input.Free;
    end;
    { TBinaryExecutor — вже протестований, не пов’язаний із LCL механізм.
      Кожен запуск має окремий обмежений runtime й відпускає його у finally. }
    Executor := TBinaryExecutor.Create('external/sens');
    try
      Answer := ExecuteWithPhysicalLocation(Physical,Executor);
    finally
      Executor.Free;
    end;
    { Результат показуємо тільки після повного успіху фізичного допуску. }
    FOutput.Lines.Text := String(Answer);
    FStatus.Caption := 'Виконано фізичний файл ('+
      IntToStr(Length(Physical))+' байтів). Результат — вид чинного D3-виконавця, не .sens.';
    Result := True;
  except
    on E: ELocatedExecutionFault do ShowFault(E);
    on E: Exception do Reject(E.Message);
  end;
end;

procedure TSensRunForm.OpenClick(Sender: TObject);
begin
  if FDialog.Execute then ExecuteFile(FDialog.FileName);
end;

{ Повна віконна перевірка стану: після успіху й відмов дані
  не залишаються у grid або у виводі від попередньої програми. }
{ Перевіряємо справжню кнопку, той самий дочірній PID, фізичний
  байтовий oracle G3.17, remote відмови та відсутність stale-result. }
{ Порівняння з реальним CLI sensukrvykon: незалежні output .sens
  створено раніше, GUI виконує той самий pinned закон іншим шляхом.
  NegativeDir — фізичні негативні файли, створені shell тестом. }
{ Реальна Lazarus/GTK2 форма і реальне виконання FPC child.
  Positive bytes зі стабільного G3.17 oracle; OutputDir готує shell
  із вже існуючим звичайним файлом і dangling symlink. }
{ Повністю живий GTK2/Xvfb: G3.17 байти із виконаного D3,
  шість проєкцій незалежно беруться з pinned d1.lisp.
  D7 та W12 випробовуються ТІЛЬКИ як read-only host-проєкція:
  вони ніколи не передаються evaluator і не стають результатом D3. }
procedure TSensRunForm.SmokeTestProjections(const Root,Executable,GoodFile,
  ExpectedFile,AtomUkrFile,AtomAnswer,LateBadFile,D12File:String);
var Expected,ExpectedAtom:RawByteString;
  procedure Ensure(OK:Boolean;const Why:String);
  begin
    if not OK then raise Exception.Create('LCL-ШІСТЬ-ПРОЄКЦІЙ: '+Why);
  end;
  procedure Empty(const Why:String);
  var J:Integer;
  begin
    for J:=1 to 6 do Ensure(FProjectionGrid.Cells[1,J]='',
      Why+': застаріла колонка '+IntToStr(J));
    Ensure(not FSavePhysical.Enabled and
      (FChannelLastPhysical=''),Why+': застарілий фізичний стан');
  end;
begin
  Ensure((FProjectionGrid<>nil) and (FProjectionGrid.RowCount=7) and
    (FProjectionGrid.ColCount=2) and
    (FProjectionGrid.Cells[0,1]='ук') and
    (FProjectionGrid.Cells[0,2]='укр') and
    (FProjectionGrid.Cells[0,3]='san') and
    (FProjectionGrid.Cells[0,4]='en') and
    (FProjectionGrid.Cells[0,5]='LISP') and
    (FProjectionGrid.Cells[0,6]='sym') and
    not (goEditing in FProjectionGrid.Options),
    'немає реальної read-only таблиці шести поверхонь');
  Empty('порожній початковий стан');
  ConnectChannel(Root,Executable);
  Ensure(FProjectionReady and (FChannelPID>0),
    'pinned таблиці чи реальний дочірній процес відсутні');
  Expected:=ReadChannelSource(ExpectedFile);
  ExpectedAtom:=ReadChannelSource(AtomAnswer);
  Ensure(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Expected),
    'перший результат не з фізичного D3');
  Ensure((FProjectionGrid.Cells[1,1]='ні') and
    (FProjectionGrid.Cells[1,2]='ні') and
    (FProjectionGrid.Cells[1,3]='na') and
    (FProjectionGrid.Cells[1,4]='no') and
    (FProjectionGrid.Cells[1,5]='NIL') and
    (FProjectionGrid.Cells[1,6]='(відсутня)') and
    (Pos('D1:0',FProjectionLabel.Caption)>0),
    'не збіглися усі шість незалежних pinned D1:0 поверхонь');

  Ensure(ExecuteUkrFile(AtomUkrFile) and
    (FChannelLastPhysical=ExpectedAtom) and
    (FChannelClient.ProcessID=FChannelPID),
    'реальна українська .lisp форма не дала фізичне D1:1');
  Ensure((FProjectionGrid.Cells[1,1]='так') and
    (FProjectionGrid.Cells[1,2]='так') and
    (FProjectionGrid.Cells[1,3]='ām') and
    (FProjectionGrid.Cells[1,4]='yes') and
    (FProjectionGrid.Cells[1,5]='T') and
    (FProjectionGrid.Cells[1,6]='(відсутня)') and
    (Pos('D1:1',FProjectionLabel.Caption)>0),
    'не збіглися усі шість pinned D1:1 поверхонь');

  { Демонстрація D7 тексту " ) " без семантичного виконання. }
  ShowProjectionWord('0101001');
  Ensure((FProjectionGrid.Cells[1,1]='")"') and
    (FProjectionGrid.Cells[1,2]='")"') and
    (FProjectionGrid.Cells[1,5]='(відсутня)') and
    (Pos('D7:0101001',FProjectionLabel.Caption)>0),
    'D7 дужка не є викличністю; LISP колонка повинна бути порожня');
  { Непідтверджена фізична ширина не породжує власного D12 закону. }
  ShowProjectionWord('000000000000');
  Ensure(FProjectionGrid.Cells[1,1]='' and
    (Pos('D12+',FProjectionLabel.Caption)>0),
    'W12 помилково показано як pinned числову/функційну проєкцію');
  { Відновлюємо лише САМЕ виконання; без фальшивої D7/W12 відповіді. }
  Ensure(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Expected) and
    (FChannelClient.ProcessID=FChannelPID),
    'повторне фізичне D3 після read-only огляду');
  Ensure(not ExecuteChannelFile(LateBadFile),
    'пізню D3 помилку помилково виконано');
  Empty('відмова D3');
  Ensure(not ExecuteChannelFile(D12File),
    'невідома числова D12+ форма виконана');
  Empty('D12+ відмова');
  Ensure(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Expected) and
    (FProjectionGrid.Cells[1,1]='ні') and
    (FChannelClient.ProcessID=FChannelPID),
    'відновлення фізичних проєкцій у тому самому PID');
  Show;Repaint;Application.ProcessMessages;
  WriteLn('LCL-ШІСТЬ-ПРОЄКЦІЙ-ГАРАЗД ',
    'Lazarus=GTK2 FPC=справжній D1=фізичне-D3 ',
    'ук/укр/san/en/LISP/sym=pinned D7-дужка=лише-дані ',
    'W12=без-проєкції D12+=не-виконано ',
    'після-відмови=порожньо PID=незмінний REPL=ні');
end;

procedure TSensRunForm.SmokeTestSave(const Root,Executable,GoodFile,
  ExpectedFile,LateBadFile,OutputDir:String);
var Expected,Actual:RawByteString;S:TFileStream;
  procedure Need(OK:Boolean;const Why:String);
  begin if not OK then raise Exception.Create('LCL-D3-ЗБЕРЕЖЕННЯ: '+Why); end;
  function FromFile(const FileName:String):RawByteString;
  var F:TFileStream;
  begin
    Result:='';
    F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
    try
      if (F.Size<1) or (F.Size>MAX_T5M_FILE_BYTES) then
        raise Exception.Create('неприпустимий контрольний T5M');
      SetLength(Result,SizeInt(F.Size));
      F.ReadBuffer(Result[1],Length(Result));
    finally F.Free end;
  end;
begin
  Need(Assigned(FSavePhysical.OnClick) and
    (FSaveDialog.Filter<>'') and (not FSavePhysical.Enabled),
    'немає справжньої кнопки або результат початково доступний');
  Need(not SavePhysicalNew(OutputDir+'/завчасно.sens'),
    'порожній результат збережено до виконання');
  ConnectChannel(Root,Executable);
  Need(not FSavePhysical.Enabled,'підключення опублікувало стару відповідь');
  Expected:=ReadChannelSource(ExpectedFile);
  Need(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Expected) and FSavePhysical.Enabled,
    'справжнє виконання не надало дозволу збереження');
  Need(SavePhysicalNew(OutputDir+'/нова.sens'),
    'реальна фізична відповідь не записана');
  Actual:=FromFile(OutputDir+'/нова.sens');
  Need(Actual=Expected,'фізичний запис відрізняється байтово від G3.17');
  Need(not SavePhysicalNew(OutputDir+'/нова.sens'),
    'наявний .sens перезаписано');
  Need(FromFile(OutputDir+'/нова.sens')=Expected,
    'наявний .sens пошкоджено');
  Need(not SavePhysicalNew(OutputDir+'/зайнята.sens'),
    'зайнятий файл перезаписано');
  Need(not SavePhysicalNew(OutputDir+'/посилання.sens'),
    'dangling symlink прийнято як нову ціль');
  Need(not FileExists(OutputDir+'/відсутня-ціль'),
    'створено ціль під symlink');
  Need(not SavePhysicalNew(OutputDir+'/не-канон.lisp'),
    'текстову .lisp помилково обрано для бінарного результату');
  Need(not SavePhysicalNew(OutputDir+'/відсутня-тека/файл.sens'),
    'відсутній каталог помилково прийнято');
  Need((FChannelLastPhysical=Expected) and FSavePhysical.Enabled,
    'помилка шляху втратила перевірену відповідь');
  Need(not ExecuteChannelFile(LateBadFile),
    'пізню фізичну D3 помилку прийнято');
  Need(not FSavePhysical.Enabled and (FChannelLastPhysical='') and
    (FOutput.Lines.Text=''),
    'пізня помилка залишила стару відповідь або дозволила збереження');
  Need(not SavePhysicalNew(OutputDir+'/після-відмови.sens'),
    'застарілі фізичні байти збережені після відмови');
  Need(not FileExists(OutputDir+'/після-відмови.sens'),
    'створений stale файл після відмови');
  Need(ExecuteChannelFile(GoodFile) and FSavePhysical.Enabled and
    (FChannelClient.ProcessID=FChannelPID),
    'відновлення у тому самому PID не спрацювало');
  Need(SavePhysicalNew(OutputDir+'/відновлена.sens') and
    (FromFile(OutputDir+'/відновлена.sens')=Expected),
    'відновлений фізичний вивід відрізняється від еталона');
  Show;Repaint;Application.ProcessMessages;
  WriteLn('LCL-D3-ЗБЕРЕЖЕННЯ-ГАРАЗД Lazarus=GTK2 ',
    'FPC=справжній T5M=побайтово ',
    'no-clobber=так symlink=відхилено ',
    'неправильне-розширення=відхилено ',
    'після-відмови=порожньо PID=незмінний ',
    'відновлення=так REPL=ні Core4=ні');
end;

procedure TSensRunForm.SmokeTestUkr(const Root,Executable,PhysicalFile,
  OneUkrFile,OneAnswer,AtomUkrFile,AtomAnswer,NegativeDir:String);
var ExpectedOne,ExpectedAtom:RawByteString;
  procedure Need(OK:Boolean;const Why:String);
  begin
    if not OK then raise Exception.Create('LCL-УКР-D3: '+Why);
  end;
  procedure Empty(const Why:String);
  begin
    Need((FChannelLastPhysical='') and (FOutput.Lines.Text='') and
      (FCoordinates.Cells[1,1]='') and
      (FCoordinates.Cells[1,2]='') and
      (FCoordinates.Cells[1,3]=''),Why+': показано стару відповідь');
    Need(FChannelClient.ProcessID=FChannelPID,Why+': PID змінився');
  end;
  procedure Bad(const Name,Why:String);
  begin
    Need(not ExecuteUkrFile(NegativeDir+'/'+Name),Why+' прийнято');
    Empty(Why);
  end;
begin
  Need(Assigned(FUkrOpen.OnClick) and (FUkrDialog.Filter<>'') and
    (not FUkrOpen.Enabled),'відсутня реальна GUI кнопка');
  ConnectChannel(Root,Executable);
  Need(FUkrOpen.Enabled and FChannelOpen.Enabled and (FChannelPID>0),
    'канал не запущений');
  ExpectedOne:=ReadChannelSource(OneAnswer);
  ExpectedAtom:=ReadChannelSource(AtomAnswer);
  Need(ExecuteUkrFile(OneUkrFile) and
    (FChannelLastPhysical=ExpectedOne) and
    (Trim(FOutput.Lines.Text)='W1:0'),
    'укр ні не збігається з реальним CLI');
  Need(ExecuteUkrFile(AtomUkrFile) and
    (FChannelLastPhysical=ExpectedAtom) and
    (Trim(FOutput.Lines.Text)='W1:1') and
    (FChannelClient.ProcessID=FChannelPID),
    'укр атом? так не збігається з реальним CLI');
  Need(ExecuteChannelFile(PhysicalFile) and
    (FChannelLastPhysical=ExpectedOne) and
    (FChannelClient.ProcessID=FChannelPID),
    'після укр фізична форма має виконатись у тому самому PID');
  Need(ExecuteUkrFile(AtomUkrFile) and
    (FChannelLastPhysical=ExpectedAtom) and
    (FChannelClient.ProcessID=FChannelPID),
    'після фізичної форми укр не відновлено');
  Bad('англійська.lisp','англійську назву');
  Bad('число.lisp','числове D12+');
  Bad('невідома.lisp','невідому укр-назву');
  Bad('пошкоджена.lisp','некоректний UTF-8');
  Bad('порожня.lisp','порожню проєкцію');
  Bad('дві.lisp','дві відповіді у одноформовому каналі');
  Bad('пізня.lisp','пізню невиконувану D3');
  Bad('нефізична.sens','неправильне розширення');
  Need(not ExecuteUkrFile(NegativeDir+'/відсутня.lisp'),
    'відсутній файл прийнято');
  Empty('відсутній файл');
  Need(ExecuteUkrFile(OneUkrFile) and
    (FChannelLastPhysical=ExpectedOne) and
    (FChannelClient.ProcessID=FChannelPID),
    'після всіх відмов відновлення не відбулось');
  Show;Repaint;Application.ProcessMessages;
  WriteLn('LCL-УКР-ФІЗИЧНЕ-D3-ГАРАЗД ',
    'Lazarus=GTK2 проєкція=укр pin=D1-D9 ',
    'oracle=дійсний-FPC-T5M PID=незмінний ',
    'D7=дані D12+=відхилено UTF8=суворо ',
    'пакет=відхилено пізня-відмова=очищено ',
    'відновлення=так REPL=ні Core4=ні');
end;

procedure TSensRunForm.SmokeTestChannel(const Root,Executable,GoodFile,
  ExpectedFile,LateBadFile,D12File,MultiFile,BrokenFile:String);
var Expected,Again:RawByteString; W:TExactWords;
  procedure Ensure(OK:Boolean;const Why:String);
  begin
    if not OK then raise Exception.Create('LCL-D3-КАНАЛ: '+Why);
  end;
  procedure EmptyAfterFailure(const Why:String);
  begin
    Ensure((FChannelLastPhysical='') and (FOutput.Lines.Text='') and
      (FCoordinates.Cells[1,1]='') and
      (FCoordinates.Cells[1,2]='') and
      (FCoordinates.Cells[1,3]=''),Why+': залишився старий результат');
    Ensure(FChannelClient.ProcessID=FChannelPID,
      Why+': дочірній PID змінився');
  end;
begin
  Ensure(Assigned(FChannelOpen.OnClick) and
    (FChannelOpen.Caption<>'') and (FChannelClient=nil),
    'немає справжньої кнопки або стан початково забруднений');
  ConnectChannel(Root,Executable);
  Ensure(FChannelOpen.Enabled and (FChannelPID>0),
    'не запущено реальний канал');
  Expected:=ReadChannelSource(ExpectedFile);
  DecodeT5M(Expected,W);
  Ensure(Length(W)=1,'незалежний очікуваний T5M не є одним словом');
  Ensure(ExecuteChannelFile(GoodFile),'перша фізична D3 форма не виконалась');
  Ensure((FChannelLastPhysical=Expected) and
    (Trim(FOutput.Lines.Text)='W'+IntToStr(Length(W[0]))+':'+String(W[0])),
    'відповідь не збігається з незалежним G3.17 T5M oracle');
  Again:=FChannelLastPhysical;
  Ensure(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Again) and
    (FChannelClient.ProcessID=FChannelPID),
    'повторний фізичний запит у тому самому PID');
  Ensure(not ExecuteChannelFile(LateBadFile),'пізня D3 помилка прийнята');
  EmptyAfterFailure('пізня remote відмова');
  Ensure(not ExecuteChannelFile(D12File),'D12+ помилково виконано як D3');
  EmptyAfterFailure('D12+');
  Ensure(not ExecuteChannelFile(MultiFile),
    'багатослівна відповідь пройшла одноформовий host-режим');
  EmptyAfterFailure('багато відповідей');
  Ensure(not ExecuteChannelFile(BrokenFile),'пошкоджений T5M прийнято');
  EmptyAfterFailure('невалідний T5M');
  Ensure(not ExecuteChannelFile(GoodFile+'.lisp'),
    'текстова проєкція помилково прийнята як фізична');
  EmptyAfterFailure('неправильне розширення');
  Ensure(not ExecuteChannelFile('відсутній-D3-файл.sens'),
    'відсутній файл помилково виконано');
  EmptyAfterFailure('відсутній файл');
  Ensure(ExecuteChannelFile(GoodFile) and
    (FChannelLastPhysical=Expected) and
    (FChannelClient.ProcessID=FChannelPID),
    'відновлення після всіх відмов без зміни PID');
  Ensure((FCoordinates.Cells[1,1]='') and
    (FCoordinates.Cells[1,2]='') and (FCoordinates.Cells[1,3]=''),
    'remote успіх залишив фізичні адреси старого локального режиму');
  Show;
  Repaint;
  Application.ProcessMessages;
  WriteLn('LCL-Д3-ПОСТІЙНИЙ-КАНАЛ-ГАРАЗД ', 
    'Lazarus=GTK2 PID=незмінний T5M=побайтово ', 
    'пізня-відмова=очищено D12+=відхилено пакет=відхилено ', 
    'лісп=відхилено несправний-T5M=відхилено ',
    'відновлення=так REPL=ні Core4=не-виконується');
end;

procedure TSensRunForm.SmokeTest(const GoodFile, BadFile, NestedFile,
  EofFile, BrokenFile, Expected: String);
  procedure Ensure(Ok:Boolean; const Why:String);
  begin
    if not Ok then raise Exception.Create('самоперевірка LCL: '+Why);
  end;
  procedure CheckSpan(const Word, TStart, TEnd, BStart, BEnd: String);
  begin
    Ensure((FOutput.Lines.Text='') and
      (FCoordinates.Cells[1,1]=Word) and
      (FCoordinates.Cells[1,2]=TStart) and
      (FCoordinates.Cells[2,2]=TEnd) and
      (FCoordinates.Cells[1,3]=BStart) and
      (FCoordinates.Cells[2,3]=BEnd),
      'помилкова фізична адреса або старий результат');
  end;
begin
  Ensure((FOutput<>nil) and (FCoordinates<>nil) and
    (FStatus<>nil) and (FOpen<>nil) and Assigned(FOpen.OnClick),
    'відсутні справжні графічні віджети');
  Ensure((FCoordinates.ColCount=3) and (FCoordinates.RowCount=4),
    'таблиця координат не створена');
  Ensure(ExecuteFile(GoodFile),'чинний фізичний D1/D3 не виконався');
  Ensure(Trim(FOutput.Lines.Text)=Expected,'розбіжність із нативним CLI');
  Ensure(FCoordinates.Cells[1,1]='','після успіху залишилася стара адреса');
  Ensure(not ExecuteFile(BadFile),'непідтверджена D3 цитата прийнята');
  CheckSpan('2','3','6','0','2');
  Ensure(not ExecuteFile(NestedFile),'вкладена непідтверджена голова прийнята');
  CheckSpan('6','16','17','3','4');
  Ensure(not ExecuteFile(EofFile),'незакритий D2 список прийнято');
  CheckSpan('3','4','4','1','1');
  Ensure(FCoordinates.Cells[2,1]='EOF','втрачено фізичний EOF');
  Ensure(not ExecuteFile(BrokenFile),'пошкоджений T5M прийнято');
  Ensure((FCoordinates.Cells[1,1]='0') and
    (FCoordinates.Cells[2,1]='адреса невідома') and
    (FCoordinates.Cells[1,2]='') and (FCoordinates.Cells[1,3]='') and
    (FOutput.Lines.Text=''),
    'для невалідного T5M вигадано адресу');
  Ensure(not ExecuteFile('відсутній-файл.sens'),'відсутній файл прийнято');
  Ensure((FOutput.Lines.Text='') and (FCoordinates.Cells[1,1]=''),
    'відсутній файл залишив попередній результат/адресу');
  Ensure(not ExecuteFile('документ.lisp'),'текст помилково прийнято як .sens');
  Ensure((FOutput.Lines.Text='') and (FCoordinates.Cells[1,1]=''),
    'нефізичний текст залишив попередній результат/адресу');
  Ensure(ExecuteFile(GoodFile),'повторний нативний запуск не виконався');
  Ensure(Trim(FOutput.Lines.Text)=Expected,
    'повторний запуск не збігся з чинним CLI');
  Ensure((FCoordinates.Cells[1,1]='') and
    (FCoordinates.Cells[1,2]='') and (FCoordinates.Cells[1,3]=''),
    'новий успіх не прибрав стару фізичну адресу');
  WriteLn('LCL-ФІЗИЧНА-ПОМИЛКА-ГАРАЗД GTK2=справжній ',
    'D3=наявний word=точний trit-byte=half-open EOF=явний ',
    'T5M-corrupt=без-адреси після-помилки=чисто CLI-паритет=так ',
    'Core4=НЕ_ВИКОНУЄТЬСЯ REPL=НЕ_ГОТОВИЙ');
end;
end.
