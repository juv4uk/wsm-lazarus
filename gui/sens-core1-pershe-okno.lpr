{ G3.43: графічний СВІДОК живого виклику першого сучасного Core1.
  Єдиний evaluator — вже злитий wsm.core1first.TCore1FirstRuntime;
  DEFINE/LAMBDA/селектор беремо з pinned lib/core1.sens, НЕ з тексту.
  Ввід/вивід — фізичний T5M, D7 ім'я — точні біти з DEFINE.
  Це не повний Core1, не постійний REPL і не GC інтеграція. }
program sens_core1_pershe_okno;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Dialogs,
  wsm.t5m, wsm.core1first
  {$IFDEF UNIX}, BaseUnix{$ENDIF};

const MaxCallBytes = 65536;
type
  TFirstWindow = class(TForm)
  private
    FRuntime: TCore1FirstRuntime; { owned: один між усіма кліками }
    FPath: TEdit;
    FChoose, FRun, FSave: TButton;
    FInput, FResult: TMemo;
    FState, FName: TLabel;
    FDialog: TOpenDialog;
    FSaveDialog: TSaveDialog;
    FLastPhysical: RawByteString; { owned exact packed T5M; NOT D1 bool }
    FClicks: SizeInt;
    procedure Require(Condition:Boolean;const Why:String);
    procedure ChooseClick(Sender:TObject);
    procedure RunClick(Sender:TObject);
    procedure SaveClick(Sender:TObject);
    function ExportAnswer(const Path:String):Boolean;
    procedure PublishPhysical(const Path:String;
      const Physical:RawByteString);
    function RunCurrent:Boolean;
    function ReadPhysical(const Path:String):RawByteString;
    function RenderWord(const WordBits:RawByteString):String;
    procedure Publish(const Incoming,Outgoing:RawByteString);
    function PhysicalFixture(const Key:RawByteString;
      const Values:TExactWords):RawByteString;
    procedure WriteFixture(const Path:String;const Physical:RawByteString);
    procedure SetInputPath(const Path:String);
    procedure InputPathChanged(Sender:TObject);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure Connect(const PinnedRoot,WorkspaceRoot:String);
    procedure SelfCheck(const TemporaryDirectory:String);
  end;
var Window:TFirstWindow;

{$IFDEF UNIX}
{ Наявний у Core4 POSIX-механізм: власний fd, тимчасова назва
  замінюється mkstemp випадковим суфіксом, режим 0600. }
function CreatePrivateTemp(Template:PChar):cint; cdecl; external 'c' name 'mkstemp';
{$ENDIF}

constructor TFirstWindow.Create(AOwner:TComponent);
var L:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — перше живе замикання Core1 (фізичний T5M)';
  Position:=poScreenCenter; Width:=1100;Height:=720;
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(12,8,1050,25);
  L.Caption:='Виконання pinned фізичного Core1. Українська .lisp — людська проєкція, не виконуваний файл.';
  FName:=TLabel.Create(Self);FName.Parent:=Self;
  FName.SetBounds(12,37,1050,24);
  FName.Caption:='Точний D7 ключ ще не завантажений';
  FPath:=TEdit.Create(Self);FPath.Parent:=Self;
  FPath.SetBounds(12,70,755,30);
  FChoose:=TButton.Create(Self);FChoose.Parent:=Self;
  FChoose.SetBounds(774,69,138,32);
  FChoose.Caption:='Обрати .sens';FChoose.OnClick:=@ChooseClick;
  FRun:=TButton.Create(Self);FRun.Parent:=Self;
  FRun.SetBounds(921,69,156,32);
  FRun.Caption:='Виконати фізично';
  FRun.Enabled:=False;FRun.OnClick:=@RunClick;
  FState:=TLabel.Create(Self);FState.Parent:=Self;
  FState.SetBounds(12,112,900,25);
  FSave:=TButton.Create(Self);FSave.Parent:=Self;
  FSave.SetBounds(921,111,156,32);
  FSave.Caption:='Зберегти відповідь';
  FSave.Enabled:=False;FSave.OnClick:=@SaveClick;
  FState.Caption:='Очікується pinned фізичний Core1';
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(12,147,1050,23);L.Caption:='Вхід: точні фізичні слова';
  FInput:=TMemo.Create(Self);FInput.Parent:=Self;
  FInput.SetBounds(12,175,1064,184);
  FInput.ReadOnly:=True;FInput.ScrollBars:=ssBoth;FInput.WordWrap:=False;
  L:=TLabel.Create(Self);L.Parent:=Self;
  L.SetBounds(12,375,1050,23);L.Caption:='Вихід: канонічні слова та байти T5M';
  FResult:=TMemo.Create(Self);FResult.Parent:=Self;
  FResult.SetBounds(12,403,1064,260);
  FResult.ReadOnly:=True;FResult.ScrollBars:=ssBoth;FResult.WordWrap:=False;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичний двійковий SENS|*.sens';
  FDialog.Options:=FDialog.Options+[ofFileMustExist];
  FSaveDialog:=TSaveDialog.Create(Self);
  FSaveDialog.DefaultExt:='sens';
  FSaveDialog.Filter:='Канонічна двійкова відповідь SENS (*.sens)|*.sens';
  { Підписуємося лише після створення обох memo, labels та діалогу. }
  FPath.OnChange:=@InputPathChanged;
end;

destructor TFirstWindow.Destroy;
begin
  FRuntime.Free; { держить pinned AST + evaluator протягом роботи GUI }
  inherited Destroy;
end;

procedure TFirstWindow.Require(Condition:Boolean;const Why:String);
begin if not Condition then raise Exception.Create(Why) end;

procedure TFirstWindow.Connect(const PinnedRoot,WorkspaceRoot:String);
var Key:RawByteString;
begin
  Require(FRuntime=nil,'повторне завантаження Core1 заборонено');
  FRuntime:=TCore1FirstRuntime.Create(PinnedRoot,WorkspaceRoot);
  Key:=FRuntime.FirstIdentifier;
  Require((Length(Key)>0) and ((Length(Key) mod 7)=0),
    'немає точного D7 ідентифікатора замикання');
  FName.Caption:='Перший pinned DEFINE, D7-бітів='+IntToStr(Length(Key))+
    '; виклик за exact координатою, не за назвою «укр»';
  FRun.Enabled:=True;
  FState.Caption:='Виконавець першого Core1 збережено між натисканнями';
end;

procedure TFirstWindow.ChooseClick(Sender:TObject);
begin if FDialog.Execute then SetInputPath(FDialog.FileName) end;

{ Подія TEdit.OnChange: ні шлях, ні текст не є доказом виконання.
  Sender — host-поле TEdit; FLastPhysical — managed owned T5M-байти.
  Не міняємо FRuntime: pinned Core1 closure живе до Destroy.
  Результат — порожній UI snapshot, без нової алокації чи eval.
  Питання: чому TEdit.Text не може бути семантичним oracle?
  Що відбувається з попередніми packed байтами?
  Чому не перестворюємо єдине замикання Core1?
  Коли наступний реальний фізичний результат знову стає видимим? }
procedure TFirstWindow.InputPathChanged(Sender:TObject);
begin
  FSave.Enabled:=False;
  FInput.Clear; FResult.Clear; FLastPhysical:='';
  FState.Caption:='Шлях змінено: попередню фізичну відповідь очищено; '+
    'новий файл ще не виконано';
end;

procedure TFirstWindow.SetInputPath(const Path:String);
begin
  FPath.Text:=Path;
  { Очистити також якщо повторно вибрано ТЕ САМЕ ім'я файла:
    OnChange тоді може не спрацювати. Повторне очищення безпечне. }
  InputPathChanged(FPath);
end;

{ Позичений filename, власний byte buffer; ніякого .lisp→код переходу.
  Усі перевірки до алокації видимого виходу. }
function TFirstWindow.ReadPhysical(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Require(LowerCase(ExtractFileExt(Path))='.sens',
    'відмова: лише двійковий канонічний .sens, не .lisp');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Require((Stream.Size>0) and (Stream.Size<=MaxCallBytes),
      'порожній/завеликий фізичний файл');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

function TFirstWindow.RenderWord(const WordBits:RawByteString):String;
begin
  if Length(WordBits)<=2048 then Result:='W'+IntToStr(Length(WordBits))+':'+String(WordBits)
  else Result:='W'+IntToStr(Length(WordBits))+':'+
    String(Copy(WordBits,1,2048))+' ... [показ скорочений; фізичне слово збережено]';
end;

{ Публікація — лише після успішного pinned evaluator і повного round-trip.
  UI-мемо НЕ є канонічним .sens; FLastPhysical зберігає всі байти.
  Питання: чому UI не тлумачить D1 як host bool?
  Чому width тут тільки показ, а не закон? Хто звільняє AST?
  Чому негативна помилка не повинна лишати старий результат? }
procedure TFirstWindow.Publish(const Incoming,Outgoing:RawByteString);
var InWords,OutWords:TExactWords; I,N:SizeInt; InView,OutView,Hex:String;
begin
  DecodeT5M(Incoming,InWords);
  Require(EncodeT5M(InWords)=Incoming,'вхід не канонічний T5M');
  DecodeT5M(Outgoing,OutWords);
  Require((Length(OutWords)=1) and
    (EncodeT5M(OutWords)=Outgoing),
    'вихід не є одним канонічним фізичним словом');
  InView:='';
  for I:=0 to High(InWords) do begin
    if I>0 then InView:=InView+#10;
    if I<64 then InView:=InView+RenderWord(InWords[I])
    else if I=64 then InView:=InView+'... решту слів не показано';
  end;
  OutView:=RenderWord(OutWords[0]);
  Hex:='';
  N:=Length(Outgoing);if N>128 then N:=128;
  for I:=1 to N do begin
    if I>1 then Hex:=Hex+' ';
    Hex:=Hex+IntToHex(Ord(Outgoing[I]),2);
  end;
  if Length(Outgoing)>N then Hex:=Hex+' ... [показ скорочений]';
  FLastPhysical:=Outgoing; { один commit фізичних байтів }
  FInput.Text:=InView;
  FResult.Text:=OutView+#10+'T5M: '+IntToStr(Length(Outgoing))+
    ' байтів: '+Hex;
  FSave.Enabled:=True;
  FState.Caption:='Виконано справжній Core1 у цьому runtime; байтів='+
    IntToStr(Length(Outgoing));
end;

function TFirstWindow.RunCurrent:Boolean;
var Incoming,Outgoing:RawByteString;Words:TExactWords;
begin
  Result:=False;FSave.Enabled:=False;
  FInput.Clear;FResult.Clear;FLastPhysical:='';
  try
    Require(FRuntime<>nil,'Core1 ще не завантажено');
    Incoming:=ReadPhysical(FPath.Text);
    DecodeT5M(Incoming,Words);
    Require(EncodeT5M(Words)=Incoming,'фізичний виклик не канонічний');
    Outgoing:=FRuntime.ExecutePhysicalCall(Incoming); { не echo, не GUI evaluator }
    Publish(Incoming,Outgoing);
    Result:=True;
  except on E:Exception do begin
    FSave.Enabled:=False;
    FInput.Clear;FResult.Clear;FLastPhysical:='';
    FState.Caption:='ВІДМОВА: '+E.Message;
  end end;
end;

procedure TFirstWindow.RunClick(Sender:TObject);
begin
  if not FRun.Enabled then Exit;
  FRun.Enabled:=False;Inc(FClicks);
  try RunCurrent;finally FRun.Enabled:=True end;
end;


{ Відтворюємо лише транспортний механізм із чинного Core4-вікна:
  physical — власні байти T5M, жодного ASCII, D7 чи D12+ dispatch.
  Path — host-шлях, 0600 temp створюється у ТІЙ САМІЙ теці;
  fpLink публікує вже закритий фізичний файл атомарно і без заміни.
  Ні вікно, ні процедурний результат не є новим мовним законом.
  Питання: чому проміжний файл має бути в цільовій теці?
  Чому fpLink не підмінює наявний файл чи symlink?
  Де фізичні bytes зберігаються після невдалого експорту?
  Хто звільняє fd і приватний temp після будь-якої помилки? }
procedure TFirstWindow.PublishPhysical(const Path:String;
  const Physical:RawByteString);
{$IFDEF UNIX}
var Temp:RawByteString;FD:cint;Offset,Written:SizeInt;Created:Boolean;
{$ENDIF}
begin
  Require((Path<>'') and (Length(Path)<=4096) and
    (LowerCase(ExtractFileExt(Path))='.sens'),
    'експорт дозволено лише в новий двійковий .sens');
  Require((Length(Physical)>0) and
    (Length(Physical)<=MaxCallBytes),
    'недопустимий розмір фізичної відповіді');
  {$IFDEF UNIX}
  Temp:='';FD:=-1;Created:=False;
  try
    Temp:=RawByteString(IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(Path)))+'c1eXXXXXX');
    UniqueString(Temp);
    FD:=CreatePrivateTemp(PChar(Temp));
    if FD<0 then
      raise Exception.Create('не створено приватний тимчасовий файл');
    Created:=True;
    Offset:=0;
    while Offset<Length(Physical) do begin
      Written:=fpWrite(FD,Physical[Offset+1],Length(Physical)-Offset);
      if Written<=0 then
        raise Exception.Create('фізична відповідь записана не повністю');
      Inc(Offset,Written);
    end;
    if fpClose(FD)<>0 then begin
      FD:=-1;
      raise Exception.Create('не закрито фізичну відповідь');
    end;
    FD:=-1;
    if fpLink(Temp,RawByteString(Path))<>0 then
      raise Exception.Create('файл уже існує або ціль недоступна');
  finally
    if FD>=0 then fpClose(FD);
    if Created then fpUnlink(Temp);
  end;
  {$ELSE}
  raise Exception.Create('безпечний фізичний експорт на цій ОС недоступний');
  {$ENDIF}
end;

{ Єдина точка експорту і GUI-кнопки, і Xvfb selftest.
  FLastPhysical — owned packed відповідь, не поле показу.
  Decode/Encode перед записом засвідчують точні біти і провідні нулі.
  Після TEdit.OnChange або невдалого виконання немає права публікації.
  Питання: чому не можна зібрати байти із FResult.Text?
  Чому disabled Save означає також відсутність допущеної відповіді?
  Чому відмова не видаляє початкову успішну відповідь з пам'яті? }
function TFirstWindow.ExportAnswer(const Path:String):Boolean;
var W:TExactWords;
begin
  Result:=False;
  try
    Require(FSave.Enabled and (FLastPhysical<>''),
      'немає чинної виконаної фізичної відповіді');
    DecodeT5M(FLastPhysical,W);
    Require((Length(W)=1) and
      (EncodeT5M(W)=FLastPhysical),
      'виконана відповідь не є одним канонічним T5M словом');
    PublishPhysical(Path,FLastPhysical);
    FState.Caption:='Збережено канонічний фізичний .sens; байтів='+
      IntToStr(Length(FLastPhysical));
    Result:=True;
  except on E:Exception do
    FState.Caption:='ВІДМОВА ЗБЕРЕЖЕННЯ: '+E.Message;
  end;
end;

procedure TFirstWindow.SaveClick(Sender:TObject);
begin
  if FSave.Enabled and FSaveDialog.Execute then
    ExportAnswer(FSaveDialog.FileName);
end;

{ Тільки тестова побудова ФІЗИЧНОГО виклику, за D7 з pinned AST.
  Справжнє виконання делегується злитому runtime, без дубля «друге».
  Результат: owned canonical T5M. Значення W24 opaque, НЕ D12+ число. }
function TFirstWindow.PhysicalFixture(const Key:RawByteString;
  const Values:TExactWords):RawByteString;
var W:TExactWords;I,P,C:SizeInt;
begin
  Require((Length(Key)>0) and ((Length(Key) mod 7)=0),'хибний D7 ключ');
  C:=Length(Key) div 7;
  SetLength(W,C+Length(Values)+8);P:=0;
  W[P]:='10';Inc(P);{ початок виклику }
  W[P]:='10';Inc(P);{ початок ідентифікатора }
  for I:=0 to C-1 do begin W[P]:=Copy(Key,I*7+1,7);Inc(P) end;
  W[P]:='01';Inc(P);{ кінець ідентифікатора }
  W[P]:='10';Inc(P);{ початок аргумента }
  W[P]:='1110';Inc(P);{ чинний D4:1110 list }
  for I:=0 to High(Values) do begin W[P]:=Values[I];Inc(P) end;
  W[P]:='01';Inc(P);{ кінець аргумента }
  W[P]:='01';Inc(P);{ кінець виклику }
  SetLength(W,P);
  Result:=EncodeT5M(W);
end;

procedure TFirstWindow.WriteFixture(const Path:String;
  const Physical:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try if Length(Physical)>0 then Stream.WriteBuffer(Physical[1],Length(Physical));
  finally Stream.Free end;
end;

{ Реальне TButton.Click під GTK2/Xvfb; той самий об'єкт FRuntime.
  Відмови не можуть лишити старі побайтові відповіді у видимому UI.
  Незалежний SENS CLI перевіряє той самий (1 0 1) у .sh gate. }
procedure TFirstWindow.SelfCheck(const TemporaryDirectory:String);
var Values,Expected:TExactWords;Key,BadKey,Path,GoodPath,Raw:RawByteString;
    KeepRuntime:TCore1FirstRuntime;
    procedure Trial(const Filename,ExpectWord:RawByteString;ShouldWork:Boolean);
    begin
      SetInputPath(String(Filename));FRun.Click;
      if ShouldWork then begin
        Require(FLastPhysical=EncodeT5M(Expected),'GUI втратив byte-exact T5M');
        Require((Length(Expected)=1) and
          (Pos('W'+IntToStr(Length(Expected[0]))+':'+String(ExpectWord),
               FResult.Text)>0),'GUI показав невірне фізичне слово');
        Require(Pos('Виконано',FState.Caption)>0,'не було реального натискання');
      end else begin
        Require((FLastPhysical='') and (FResult.Lines.Count=0) and
          (FInput.Lines.Count=0) and
          (Pos('ВІДМОВА',FState.Caption)>0),
          'після відмови лишилися старі фізичні байти/вивід');
      end;
    end;
begin
  Require(FRun.Enabled,'GUI не підключено до справжнього Core1');
  Require(not FSave.Enabled,'експорт доступний до першого Core1 виконання');
  Require(not ExportAnswer(String(IncludeTrailingPathDelimiter(
    TemporaryDirectory)+'core1-absent.sens')),
    'порожню відповідь вдалося експортувати');
  Require(not FileExists(IncludeTrailingPathDelimiter(
    TemporaryDirectory)+'core1-absent.sens'),
    'порожній експорт створив фізичний файл');
  KeepRuntime:=FRuntime;
  Key:=FRuntime.FirstIdentifier;
  Require(Length(Key) mod 7=0,'пошкоджений pinned D7');
  Path:=IncludeTrailingPathDelimiter(TemporaryDirectory);
  SetLength(Expected,1);
  SetLength(Values,3);Values[0]:='1';Values[1]:='0';Values[2]:='1';
  Expected[0]:='0';
  GoodPath:=Path+'core1-0.sens';
  WriteFixture(String(GoodPath),PhysicalFixture(Key,Values));
  Trial(GoodPath,'0',True);
  Require(FSave.Enabled,'після реального виклику не доступне збереження');
  Require(ExportAnswer(String(Path+'core1-export-0.sens')),
    'не вдалося зберегти справжню Core1 відповідь');
  Require(ReadPhysical(String(Path+'core1-export-0.sens'))=
    EncodeT5M(Expected),'експорт змінив фізичні біти T5M');
  Require(not ExportAnswer(String(Path+'core1-export-0.sens')),
    'експорт перезаписав наявний фізичний файл');
  Require(ReadPhysical(String(Path+'core1-export-0.sens'))=
    EncodeT5M(Expected),'фізичний файл змінився після no-clobber відмови');
  Require(not ExportAnswer(String(Path+'core1-existing-symlink.sens')),
    'експорт перезаписав існуюче symlink');
  Require(not ExportAnswer(String(Path+'core1-projection.lisp')),
    'фізичну відповідь вдалося зберегти як .lisp');
  Require(not FileExists(String(Path+'core1-projection.lisp')),
    'невірна проєкція створила файл');
  { Реальний результат вже присутній. Пряма правка TEdit БЕЗ FRun.Click
    має негайно прибрати саме старі фізичні байти й обидва мемо. }
  FPath.Text:=Path+'core1-nevykonanyi.sens';
  Require((FLastPhysical='') and (not FSave.Enabled) and
    (FInput.Lines.Count=0) and
    (FResult.Lines.Count=0) and
    (Pos('Шлях змінено',FState.Caption)=1),
    'стара фізична відповідь Core1 лишилась після ручного редагування шляху');
  Require(FRuntime=KeepRuntime,
    'ручне редагування шляху знищило спільне Core1 замикання');
  Require(not ExportAnswer(String(Path+'core1-stale.sens')),
    'експорт допустив стару відповідь після зміни шляху');
  Require(not FileExists(String(Path+'core1-stale.sens')),
    'після редагування записані застарілі фізичні байти');
  Values[0]:='0';Values[1]:='1';Values[2]:='0';Expected[0]:='1';
  WriteFixture(String(Path+'core1-1.sens'),PhysicalFixture(Key,Values));
  Trial(Path+'core1-1.sens','1',True);
  Values[0]:='1';Values[1]:='000000000000000000000001';
  Values[2]:='0';Expected[0]:=Values[1];
  WriteFixture(String(Path+'core1-24.sens'),PhysicalFixture(Key,Values));
  Trial(Path+'core1-24.sens',Expected[0],True);
  Require(ExportAnswer(String(Path+'core1-export-w24.sens')),
    'не вдалося зберегти фізичне W24 значення');
  Require(ReadPhysical(String(Path+'core1-export-w24.sens'))=
    EncodeT5M(Expected),'W24 втратило ширину або провідні нулі');
  BadKey:=Key;
  if BadKey[1]='0' then BadKey[1]:='1' else BadKey[1]:='0';
  WriteFixture(String(Path+'core1-d7-bad.sens'),PhysicalFixture(BadKey,Values));
  Trial(Path+'core1-d7-bad.sens','',False);
  Require((not FSave.Enabled) and
    (not ExportAnswer(String(Path+'core1-bad-export.sens'))) and
    (not FileExists(String(Path+'core1-bad-export.sens'))),
    'неправильний D7 дозволив експорт минулої відповіді');
  SetLength(Values,1);Values[0]:='1';
  WriteFixture(String(Path+'core1-short.sens'),PhysicalFixture(Key,Values));
  Trial(Path+'core1-short.sens','',False);
  Raw:=AnsiChar(243);
  WriteFixture(String(Path+'core1-broken.sens'),Raw);
  Trial(Path+'core1-broken.sens','',False);
  WriteFixture(String(Path+'core1-text.lisp'),'(визначити ядро1-другий-елемент)');
  Trial(Path+'core1-text.lisp','',False);
  Trial(Path+'core1-missing.sens','',False);
  Expected[0]:='0';Trial(GoodPath,'0',True);
  Require(FSave.Enabled and (FRuntime=KeepRuntime) and (FClicks=9),
    'повторні виклики не зберегли один і той самий runtime Core1');
  Show;Repaint;Application.ProcessMessages;
  WriteLn('ЛКЛ-ПЕРШИЙ-CORE1-ГАРАЗД GTK2=так FPC=справжній',
    ' виклики=9 D1:0=так D1:1=так W24=opaque',
    ' D7-негатив=так T5M-негатив=так lisp-відхилено',
    ' після-помилки=відновлено runtime=той-самий',
    ' редагування-шляху=очищено',
    ' експорт=байт-в-байт no-clobber=так W24=точний',
    ' GC=НЕ-ІНТЕГРОВАНО REPL=НЕ-ПОВНИЙ');
end;

begin
  Application.Initialize;
  try
    Window:=TFirstWindow.Create(nil);
    try
      if (ParamCount=4) and
        (ParamStr(1)='--самоперевірка') then begin
        Window.Connect(ParamStr(2),ParamStr(3));
        Window.SelfCheck(ParamStr(4));
      end else if ParamCount=0 then begin
        Window.Connect('external/sens','.');
        Window.Show;Application.Run;
      end else
        raise Exception.Create('використання: --самоперевірка pin-root workspace-root temp-dir');
    finally Window.Free end;
  except on E:Exception do begin
    WriteLn(StdErr,'ЛКЛ-ПЕРШИЙ-CORE1-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end end;
end.
