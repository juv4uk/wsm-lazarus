{ G3.32: справжня Lazarus/LCL лабораторія виконаного D3:101.
  Лише точні D1 або ЦИТОВАНІ D7, обидві цитати фізично T5M.
  Закони та шість людських проєкцій — тільки pinned SENS Contract 12.0.
  Це не повний REPL, loader Core4, арифметика D12+ чи компілятор. }
program sens_d7_totozhnist;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Dialogs,
  wsm.domain, wsm.proektsii, wsm.t5m, wsm.binaryexec,
  wsm.bind, wsm.binarytree, wsm.d2source;

type
  TD7EqualityForm = class(TForm)
  private
    FDomains:array[0..1] of TComboBox;
    FBits:array[0..1] of TEdit;
    FRun,FImportButton:TButton;
    FImportDialog:TOpenDialog;
    FTestImportPath:String; { лише для справжнього GUI самотесту }
    FUpdating:Boolean; { захищає цілісний commit стану від LCL OnChange }
    FLog:TMemo;
    FStatus:TLabel;
    FCatalog:TProektsiiCatalog;
    FTables:TDomainSet; { чинний pinned binder, не місцевий реєстр законів }
    FExecutor:TBinaryExecutor;
    FSource,FAnswer:RawByteString;
    procedure ClearSnapshot;
    procedure Changed(Sender:TObject);
    procedure RunClick(Sender:TObject);
    procedure ImportClick(Sender:TObject);
    procedure PublishExecuted(const Physical:RawByteString;
      const Keys:array of TDomainKey);
    function ReadPhysicalFile(const Path:String):Boolean;
    procedure Demand(OK:Boolean; const Why:String);
    function InputKey(Index:Integer):TDomainKey;
    procedure AddAtom(var Words:TExactWords; const Key:TDomainKey);
    function LoadBytes(const Path:String):RawByteString;
    procedure SelectOperand(Index,Domain:Integer;const Bits:String);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure ConnectPinned(const Root:String);
    procedure SelfTest(const Same,Other,Mixed,Corrupt,NotEq,Wide,
      TextFile,Multi,Bare:String);
  end;

var Window:TD7EqualityForm;

constructor TD7EqualityForm.Create(AOwner:TComponent);
var I:Integer; Help:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — виконана двійкова тотожність D1 / D7';
  Width:=1020;Height:=740;Position:=poScreenCenter;
  FExecutor:=nil;FSource:='';FAnswer:='';
  FTestImportPath:='';FUpdating:=False;
  Help:=TLabel.Create(Self);Help.Parent:=Self;
  Help.SetBounds(16,12,970,40);
  Help.Caption:='Рівність визначають точний домен і біти. D7 — тільки цитовані дані; D12+ не є D1.';
  for I:=0 to 1 do begin
    FDomains[I]:=TComboBox.Create(Self);
    FDomains[I].Parent:=Self;
    FDomains[I].SetBounds(16+I*498,68,130,30);
    FDomains[I].Style:=csDropDownList;
    FDomains[I].Items.Add('D1');
    FDomains[I].Items.Add('D7');
    FDomains[I].ItemIndex:=1;
    FDomains[I].OnChange:=@Changed;
    FBits[I]:=TEdit.Create(Self);
    FBits[I].Parent:=Self;
    FBits[I].SetBounds(154+I*498,68,335,30);
    FBits[I].Text:='0010110';
    FBits[I].OnChange:=@Changed;
  end;
  FRun:=TButton.Create(Self);FRun.Parent:=Self;
  FRun.SetBounds(16,120,540,43);
  FRun.Caption:='Виконати фізичний D3:101 із точних бітів';
  FRun.Enabled:=False;
  FRun.OnClick:=@RunClick;
  FImportButton:=TButton.Create(Self);
  FImportButton.Parent:=Self;
  FImportButton.SetBounds(566,120,422,43);
  FImportButton.Caption:='Відкрити й виконати справжній .sens';
  FImportButton.Enabled:=False;
  FImportButton.OnClick:=@ImportClick;
  FImportDialog:=TOpenDialog.Create(Self);
  FImportDialog.Title:='Лише канонічна двійкова D3:101 програма';
  FImportDialog.Filter:='Фізична SENS (*.sens)|*.sens';
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(16,177,976,30);
  FStatus.Caption:='Немає перевіреного виконання.';
  FLog:=TMemo.Create(Self);FLog.Parent:=Self;
  FLog.SetBounds(16,213,970,472);
  FLog.ReadOnly:=True;FLog.WordWrap:=False;
  FLog.ScrollBars:=ssBoth;
end;

destructor TD7EqualityForm.Destroy;
begin
  FreeAndNil(FExecutor);
  inherited Destroy;
end;

procedure TD7EqualityForm.Demand(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ДВІЙКОВА-ТОТОЖНІСТЬ: '+Why);
end;

{ Snapshot — лише ref-counted фізичні байти T5M, збережені на життя
  форми. Очищаємо ДО кожного запуску, щоби жоден провал не показував
  старий результат. D1:0 тут не host False.
  Питання: хто володіє FAnswer? Коли зникає старий snapshot?
  Чи має FStatus право бути мовним результатом SENS? }
procedure TD7EqualityForm.ClearSnapshot;
begin
  FSource:='';FAnswer:='';
  FLog.Clear;
  FStatus.Caption:='Немає перевіреного фізичного виконання.';
end;

procedure TD7EqualityForm.Changed(Sender:TObject);
begin
  if not FUpdating then ClearSnapshot;
end;

procedure TD7EqualityForm.ConnectPinned(const Root:String);
begin
  Demand(FExecutor=nil,'підключення pinned SENS повторно заборонено');
  LoadPinnedProjections(Root,FCatalog);
  LoadPinnedDomains(RawByteString(Root),FTables);
  FExecutor:=TBinaryExecutor.Create(RawByteString(Root));
  FRun.Enabled:=True;
  FImportButton.Enabled:=True;
  ClearSnapshot;
end;

{ InputKey: тільки два явно обрані домени D1/D7; кожна координата
  проходить вже злитий ExactKey і повний pinned-каталог. Параметр
  Index — індекс host-віджета, НЕ SENS слот. Result — TDomainKey
  (Width,Bits), без алокації та без text-dispatch.
  Питання: чому D7:0000001 <> D1:1? Що перевіряє ExactKey?
  Чи може Unicode-напис визначити викличність? }
function TD7EqualityForm.InputKey(Index:Integer):TDomainKey;
var DomainWidth:SizeInt;
begin
  Demand((Index>=0) and (Index<2),'відсутній операнд');
  case FDomains[Index].ItemIndex of
    0:DomainWidth:=1;
    1:DomainWidth:=7;
    else raise Exception.Create('Виберіть D1 або D7 без неявного D12');
  end;
  Result:=ExactKey(RawByteString(FBits[Index].Text));
  Demand(Result.Width=DomainWidth,
    'неправильна точна ширина D'+IntToStr(DomainWidth));
  Demand(Length(FCatalog[DomainWidth])=(SizeInt(1) shl DomainWidth),
    'pinned таблиця неповна');
  Demand(SameKey(Result,FCatalog[DomainWidth][Result.Bits].Key),
    'pinned домен не підтвердив точну координату');
end;

{ AddAtom: вхід — уже pinned exact-key; D7 завжди додається як
  фізична цитата (D2:10 D3:001 D7:bbbbbbb D2:01).
  Двійкові слова належать тимчасовому динамічному масиву Words;
  повернення не містить .lisp чи нового правила EQ.
  Питання: навіщо D7 цитувати? Чому D1 залишається атомом?
  Де D12 був би явно відхилений? }
procedure TD7EqualityForm.AddAtom(var Words:TExactWords;const Key:TDomainKey);
  procedure Put(const Bits:RawByteString);
  var N:SizeInt;
  begin
    N:=Length(Words);SetLength(Words,N+1);Words[N]:=Bits;
  end;
begin
  if Key.Width=1 then Put(KeyBits(Key))
  else if Key.Width=7 then begin
    Put('10');Put('001');Put(KeyBits(Key));Put('01');
  end else Demand(False,'непідтверджений домен операнда');
end;

{ G3.34: ЄДИНИЙ шлях виконання і публікації для полів та файла.
  Physical — власна/позичена ref-counted копія canonical T5M; Keys —
  лише два вже pinned exact-key операнди. Всі відповіді перевіряються
  до commit віджетів; відмова не зберігає попереднього результату.
  Питання: хто обчислює D3:101? Чому D7 не є виконуваною головою?
  Чому D1:0 не є host False? Де починається публікація snapshot?
  Як зберігається походження початкових .sens байтів? }
procedure TD7EqualityForm.PublishExecuted(const Physical:RawByteString;
  const Keys:array of TDomainKey);
const Names:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var Answer:RawByteString; OutWords:TExactWords;
    I,J:Integer; DomainWidth:SizeInt; Lines:TStringList; LabelText:String;
begin
  Demand(FExecutor<>nil,'немає pinned виконавця');
  Demand(Length(Keys)=2,'не два exact операнди');
  Demand((Length(Physical)>0) and (Length(Physical)<=65536),
    'фізичні байти за межами');
  Answer:=FExecutor.ExecutePhysicalT5M(Physical);
  DecodeT5M(Answer,OutWords);
  Demand((Length(OutWords)=1) and
         ((OutWords[0]='0') or (OutWords[0]='1')),
    'фізична відповідь має бути рівно D1:0 або D1:1');
  Demand(EncodeT5M(OutWords)=Answer,'необоротна відповідь T5M');
  Lines:=TStringList.Create;
  try
    Lines.Add('Виконано фізичний D3:101: '+String(OutWords[0]));
    Lines.Add('Канонічне джерело .sens: '+IntToStr(Length(Physical))+' байтів');
    Lines.Add('Канонічна відповідь .sens: '+IntToStr(Length(Answer))+' байтів');
    for I:=0 to 1 do begin
      DomainWidth:=Keys[I].Width;
      Demand((DomainWidth=1) or (DomainWidth=7),
        'непідтверджений точний домен аргумента');
      Demand(SameKey(Keys[I],FCatalog[DomainWidth][Keys[I].Bits].Key),
        'підміна pinned координати аргумента');
      if I=0 then LabelText:='Лівий' else LabelText:='Правий';
      Lines.Add(LabelText+': D'+IntToStr(DomainWidth)+':'+String(KeyBits(Keys[I])));
      for J:=0 to 5 do
        Lines.Add('  '+Names[J]+': '+
          SurfaceForDisplay(FCatalog[DomainWidth][Keys[I].Bits].Surface[J]));
    end;
    FSource:=Physical;FAnswer:=Answer;
    FLog.Lines.Assign(Lines);
    FStatus.Caption:='Фізична D3:101 підтверджена; результат D1:'+String(OutWords[0]);
  finally Lines.Free end;
end;

procedure TD7EqualityForm.RunClick(Sender:TObject);
var Keys:array[0..1] of TDomainKey;Words:TExactWords;
    Physical:RawByteString;
begin
  ClearSnapshot;
  try
    Keys[0]:=InputKey(0);Keys[1]:=InputKey(1);
    SetLength(Words,2);Words[0]:='10';Words[1]:='101';
    AddAtom(Words,Keys[0]);AddAtom(Words,Keys[1]);
    SetLength(Words,Length(Words)+1);Words[High(Words)]:='01';
    Physical:=EncodeT5M(Words);
    PublishExecuted(Physical,Keys);
  except on E:Exception do begin
    ClearSnapshot;
    FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
  end end;
end;

{ Кількість нащадків у pinned фізичному TBinaryTree — host structural
  proof, не викличність. ParentIndex/ChildIndex утворені наявним D2
  reader; вузли живуть до виходу з ReadPhysicalFile.
  Питання: чому не можна сканувати текст .lisp? Де перевірено межу?
  Чому childIndex не є мовним opcode? }
function ChildCount(const Items:TBinaryTreeEntries; Parent:SizeInt):SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=0 to High(Items) do
    if Items[I].ParentIndex=Parent then Inc(Result);
end;

function ChildIndex(const Items:TBinaryTreeEntries;
  Parent,Ordinal:SizeInt):SizeInt;
var I:SizeInt;
begin
  Result:=-1;
  for I:=0 to High(Items) do
    if (Items[I].ParentIndex=Parent) and
       (Items[I].ChildIndex=Ordinal) then begin
      if Result>=0 then raise Exception.Create('дубль індексу нащадка');
      Result:=I;
    end;
  if Result<0 then raise Exception.Create('немає обов’язкового дочірнього вузла');
end;

{ Визнання двох операндів — ЛИШЕ з verified TBinaryTree:
  1) D1 листок; 2) список (D3:001 D7:xxxxxxx).
  Жодного case за українським/англійським текстом, жодних D12 чисел.
  Питання: як підтверджується цитата D7? Чи можна знімати ширину?
  Чому D3:000 не є атомом D1? }
function PhysicalOperand(const Items:TBinaryTreeEntries;
  N:SizeInt):TDomainKey;
var H,V:SizeInt;
begin
  if (Items[N].Kind=dkIdentity) and
     (Items[N].Key.Width=1) then Exit(Items[N].Key);
  if (Items[N].Kind<>dkList) or (ChildCount(Items,N)<>2) then
    raise Exception.Create('операнд — не D1 або точна цитата D7');
  H:=ChildIndex(Items,N,0);
  V:=ChildIndex(Items,N,1);
  if (Items[H].Kind<>dkIdentity) or
     not SameKey(Items[H].Key,ExactKey('001')) or
     (Items[V].Kind<>dkIdentity) or (Items[V].Key.Width<>7) then
    raise Exception.Create('D7 дозволено тільки всередині D3:001');
  Result:=Items[V].Key;
end;

{ G3.34: читаємо ОРИГІНАЛЬНІ фізичні packed .sens bytes.
  ReadBinaryTree = чинний T5M/D2/exact-domain binder; відтворення
  T5M та повний кореневий shape guard попереду ExecutePhysicalT5M.
  Створені TBinaryTreeEntries і TExactWords — короткоживучі власні
  масиви; FSource/FAnswer отримують тільки повністю виконані байти.
  Питання: що відхиляє другий корінь? Що відхиляє bare D7?
  Чому один D1 результат не доводить REPL? Де очищуються старі дані?
  Хто володіє тимчасовим файловим дескриптором? }
function TD7EqualityForm.ReadPhysicalFile(const Path:String):Boolean;
var Physical:RawByteString; Words:TExactWords;
    Tree:TBinaryTreeEntries; Keys:array[0..1] of TDomainKey;
    H,I,RootCount:SizeInt;
begin
  Result:=False;
  ClearSnapshot;
  try
    Demand(LowerCase(ExtractFileExt(Path))='.sens',
      'фізичним входом може бути тільки .sens, не .lisp');
    Physical:=LoadBytes(Path);
    DecodeT5M(Physical,Words);
    Demand((Length(Words)>0) and (EncodeT5M(Words)=Physical),
      'не канонічний фізичний T5M');
    ReadBinaryTree(Physical,FTables,Tree);
    Demand((Length(Tree)>=4) and (Length(Tree)<=8),
      'поза вузькою D3:101 фізичною формою');
    RootCount:=0;
    for I:=0 to High(Tree) do begin
      if Tree[I].ParentIndex<0 then Inc(RootCount);
      Demand(Tree[I].RootIndex=0,'зайвий фізичний корінь');
    end;
    Demand((RootCount=1) and (Tree[0].Kind=dkList) and
      (Tree[0].ParentIndex<0) and (ChildCount(Tree,0)=3),
      'очікується один список з трьома членами D3:101');
    H:=ChildIndex(Tree,0,0);
    Demand((Tree[H].Kind=dkIdentity) and
      SameKey(Tree[H].Key,ExactKey('101')),
      'перша фізична голова повинна бути D3:101');
    Keys[0]:=PhysicalOperand(Tree,ChildIndex(Tree,0,1));
    Keys[1]:=PhysicalOperand(Tree,ChildIndex(Tree,0,2));
    PublishExecuted(Physical,Keys); { виконує ТІ САМІ file bytes }
    FUpdating:=True;
    try
      for I:=0 to 1 do begin
        if Keys[I].Width=1 then FDomains[I].ItemIndex:=0
        else FDomains[I].ItemIndex:=1;
        FBits[I].Text:=String(KeyBits(Keys[I]));
      end;
    finally FUpdating:=False end;
    Result:=True;
  except on E:Exception do begin
    ClearSnapshot;
    FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
  end end;
end;

procedure TD7EqualityForm.ImportClick(Sender:TObject);
begin
  if FTestImportPath<>'' then ReadPhysicalFile(FTestImportPath)
  else if FImportDialog.Execute then ReadPhysicalFile(FImportDialog.FileName);
end;

function TD7EqualityForm.LoadBytes(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Demand((F.Size>0) and (F.Size<=65536),'пошкоджений тестовий .sens');
    SetLength(Result,F.Size);
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Канонічна відповідь одного D1 слова. Тимчасовий TExactWords
  звільняється після EncodeT5M; результат — власні packed байти.
  Питання: чому точно одна ширина D1? Хто пакує T5M?
  Чи можна порівнювати тільки десятковий запис біта? }
function OneD1(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=Bits;
  Result:=EncodeT5M(W);
end;

procedure TD7EqualityForm.SelectOperand(Index,Domain:Integer;const Bits:String);
begin
  FDomains[Index].ItemIndex:=Domain;
  FBits[Index].Text:=Bits;
end;

procedure TD7EqualityForm.SelfTest(const Same,Other,Mixed,Corrupt,NotEq,
  Wide,TextFile,Multi,Bare:String);
  procedure CheckImportRefused(const Path,Why:String);
  begin
    FTestImportPath:=Path;
    FImportButton.Click;
    Demand((FSource='') and (FAnswer='') and (FLog.Lines.Count=0)
      and (Pos('ВІДХИЛЕНО',FStatus.Caption)>0),
      Why+': відмова залишила старі байти або не відбулась');
  end;
begin
  Demand(FExecutor<>nil,'self-test потребує pinned SENS');
  { SYN — точні дані D7 з шістьма pinned проєкціями, не callable. }
  SelectOperand(0,1,'0010110');
  SelectOperand(1,1,'0010110');
  FRun.Click;
  Demand((FAnswer=OneD1('1')) and (FSource=LoadBytes(Same)),
    'реальні кліки LCL не виконали однаковий D7 SYN з фізичного свідка');
  Demand((Pos('san:',FLog.Text)>0) and (Pos('LISP:',FLog.Text)>0)
    and (Pos('укр:',FLog.Text)>0),
    'не показано всіх pinned поверхонь D7');
  SelectOperand(1,1,'0000000');FRun.Click;
  Demand((FAnswer=OneD1('0')) and (FSource=LoadBytes(Other)),
    'різні D7 фізичні слова були помилково зрівняні');
  { D1:1 та D7:0000001 чисельно схожі, але домени РІЗНІ. }
  SelectOperand(0,0,'1');SelectOperand(1,1,'0000001');FRun.Click;
  Demand((FAnswer=OneD1('0')) and
    (Pos('Лівий: D1:1',FLog.Text)>0) and
    (Pos('Правий: D7:0000001',FLog.Text)>0),
    'колізія D1/D7 за числовим змістом бітів');
  SelectOperand(1,0,'1');FRun.Click;
  Demand(FAnswer=OneD1('1'),'старий D1/D1 результат зламано');
  SelectOperand(0,1,'001011');FRun.Click;
  Demand((FAnswer='') and (FSource='') and (FLog.Lines.Count=0),
    'коротке D7 залишило попередній snapshot');
  SelectOperand(0,1,'00101x0');FRun.Click;
  Demand((FAnswer='') and (FSource='') and
    (Pos('ВІДХИЛЕНО',FStatus.Caption)>0),
    'небінарне D7 було прийняте');
  SelectOperand(0,1,'000000000000');FRun.Click;
  Demand((FAnswer='') and (FSource=''),'D12 стало D7');
  SelectOperand(0,1,'0010110');SelectOperand(1,1,'0010110');FRun.Click;
  Demand((FAnswer=OneD1('1')) and (FSource=LoadBytes(Same)),
    'немає відновлення після послідовних негативних запитів');
  { Перехід із ЗОВНІШНІХ .sens, не повторний mint із FBits. }
  FTestImportPath:=Same;FImportButton.Click;
  Demand((FSource=LoadBytes(Same)) and (FAnswer=OneD1('1')) and
    (FBits[0].Text='0010110') and (FBits[1].Text='0010110'),
    'реальний імпорт однакових SYN не виконав фізичні байти');
  FTestImportPath:=Other;FImportButton.Click;
  Demand((FSource=LoadBytes(Other)) and (FAnswer=OneD1('0')) and
    (FBits[1].Text='0000000'),
    'імпорт різних D7 утратив pinned координату');
  FTestImportPath:=Mixed;FImportButton.Click;
  Demand((FSource=LoadBytes(Mixed)) and (FAnswer=OneD1('0')) and
    (FDomains[0].ItemIndex=0) and (FDomains[1].ItemIndex=1) and
    (FBits[0].Text='1') and (FBits[1].Text='0000001'),
    'імпорт сплутав домени D1:1 / D7:0000001');
  CheckImportRefused(Corrupt,'пізнє пошкодження T5M');
  CheckImportRefused(NotEq,'не EQ фізична голова');
  CheckImportRefused(Wide,'W12 не є допущеним D7');
  CheckImportRefused(TextFile,'.lisp не є фізичним .sens');
  CheckImportRefused(Multi,'другий корінь');
  CheckImportRefused(Bare,'голий D7 без цитати');
  FTestImportPath:=Same;FImportButton.Click;
  Demand((FSource=LoadBytes(Same)) and (FAnswer=OneD1('1')) and
    (Pos('укр:',FLog.Text)>0) and (Pos('LISP:',FLog.Text)>0),
    'не відновлено фізичну відповідь/проєкції після відмов');
  WriteLn('LCL-Д7-ІМПОРТ-ГАРАЗД реальний-файл=так ',
    'T5M=без-рекодування pinned-D2=так ',
    'D1-D7=точні негативи=шість recovery=так');
  WriteLn('LCL-Д3-Д7-ТОТОЖНІСТЬ-ГАРАЗД ',
    'FPC=справжній Lazarus=GTK2 T5M=точний ',
    'SYN=дані шість-проєкцій=pinned D1/D7=без-колізії ',
    'негативи=так recovery=так Core4=НЕ_ВИКОНУЄТЬСЯ');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — виконана тотожність D1 / D7';
    Application.CreateForm(TD7EqualityForm,Window);
    Window.ConnectPinned('external/sens');
    if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
      if ParamCount<>10 then Halt(64);
      Window.Show;
      Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7),ParamStr(8),
        ParamStr(9),ParamStr(10));
      Window.Free;
      Halt(0);
    end;
    if ParamCount<>0 then Halt(64);
    Application.Run;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-Д3-Д7-ПОМИЛКА: ',E.Message);
      Halt(2);
    end;
  end;
end.
