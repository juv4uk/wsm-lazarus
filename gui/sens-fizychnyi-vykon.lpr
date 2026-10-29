{ G3.40: справжня LCL поверхня для існуючого binary D3 evaluator.
  Жодних локальних законів: exact слова T5M -> TBinaryExecutor.
  D7 — лише pinned текстові ДАНІ, не dispatch і не числа. }
program sens_fizychnyi_vykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls, Dialogs,
  Grids, wsm.t5m, wsm.binaryexec, wsm.proektsii, wsm.domain;

const MaxGUIBytes = 65536;
      MaxShownWords = 128;

type
  TPhysicalWindow = class(TForm)
  private
    FPath: TEdit;
    FPicker: TOpenDialog;
    FRun, FPick: TButton;
    FInput, FOutput: TStringGrid;
    FSurfaces: TMemo;
    FStatus: TLabel;
    FAnswer: RawByteString;
    FCatalog: TProektsiiCatalog;
    procedure ClearResults;
    procedure PickClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    function ReadPhysical(const Path: String): RawByteString;
    procedure FillGrid(Grid: TStringGrid; const Words: TExactWords);
    procedure ShowD7(const Bits: RawByteString);
    procedure Need(OK: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    function ExecuteFile(const Path: String): Boolean;
    procedure SelfTest(const Good, Quoted, Bad, EmptyFile,
      Multi, Wrong: String);
  end;

var Window: TPhysicalWindow;

procedure PrintUTF8(const MessageText: UnicodeString);
const LF: AnsiChar = #10;
var Bytes: UTF8String; S: THandleStream;
begin
  Bytes:=UTF8Encode(MessageText);
  S:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Bytes<>'' then S.WriteBuffer(Bytes[1],Length(Bytes));
    S.WriteBuffer(LF,1);
  finally S.Free end;
end;

constructor TPhysicalWindow.Create(AOwner: TComponent);
var L: TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — фізичне виконання D3';
  Width:=980; Height:=760; Position:=poScreenCenter;
  LoadPinnedProjections(IncludeTrailingPathDelimiter(GetCurrentDir)+
    'external/sens',FCatalog);
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(16,12,935,30);
  L.Caption:='Канонічний двійковий .sens; виконання тільки через pinned D3';
  FPath:=TEdit.Create(Self); FPath.Parent:=Self;
  FPath.SetBounds(16,50,740,32);
  FPick:=TButton.Create(Self); FPick.Parent:=Self;
  FPick.SetBounds(770,50,185,32);
  FPick.Caption:='Обрати файл .sens';
  FPick.OnClick:=@PickClick;
  FRun:=TButton.Create(Self); FRun.Parent:=Self;
  FRun.SetBounds(16,95,310,36);
  FRun.Caption:='Виконати фізичну форму';
  FRun.OnClick:=@RunClick;
  FPicker:=TOpenDialog.Create(Self);
  FPicker.Filter:='Фізичні програми (*.sens)|*.sens';
  FPicker.Options:=[ofFileMustExist];
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(16,148,900,24);
  L.Caption:='Допущені фізичні слова входу (не текстова проєкція):';
  FInput:=TStringGrid.Create(Self); FInput.Parent:=Self;
  FInput.SetBounds(16,176,938,185);
  FInput.FixedCols:=0; FInput.FixedRows:=1;
  FInput.ColCount:=3; FInput.RowCount:=2;
  FInput.ColWidths[0]:=100; FInput.ColWidths[1]:=120;
  FInput.ColWidths[2]:=690;
  FInput.Options:=FInput.Options+[goRowSelect,goColSizing];
  FInput.Cells[0,0]:='№ слова';FInput.Cells[1,0]:='Ширина Wn';
  FInput.Cells[2,0]:='Фізичні біти';
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(16,372,900,24);
  L.Caption:='Реально обчислена канонічна T5M-відповідь:';
  FOutput:=TStringGrid.Create(Self); FOutput.Parent:=Self;
  FOutput.SetBounds(16,398,938,155);
  FOutput.FixedCols:=0; FOutput.FixedRows:=1;
  FOutput.ColCount:=3; FOutput.RowCount:=2;
  FOutput.ColWidths[0]:=100; FOutput.ColWidths[1]:=120;
  FOutput.ColWidths[2]:=690;
  FOutput.Options:=FOutput.Options+[goRowSelect,goColSizing];
  FOutput.Cells[0,0]:='№ слова';FOutput.Cells[1,0]:='Ширина Wn';
  FOutput.Cells[2,0]:='Фізичні біти';
  L:=TLabel.Create(Self); L.Parent:=Self;
  L.SetBounds(16,564,930,22);
  L.Caption:='Шість pinned D7-проєкцій W7 (як дані, лише якщо відповідь W7):';
  FSurfaces:=TMemo.Create(Self); FSurfaces.Parent:=Self;
  FSurfaces.SetBounds(16,592,938,97);
  FSurfaces.ReadOnly:=True;
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(16,698,938,48);
  ClearResults;
end;

{ FAnswer — власні exact-байти відповіді попереднього запуску.
  Скидання включає керовані клітинки обох TStringGrid і D7-віджет:
  помилка або нове виконання не залишають старого успіху.
  Питання: чи є клітинка SENS-словом? Хто володіє FAnswer?
  Чому помилка має стерти старий результат? Чи є D7 callable? }
procedure TPhysicalWindow.ClearResults;
var G:TStringGrid;I,J,K:Integer;
begin
  FAnswer:='';
  for K:=0 to 1 do begin
    if K=0 then G:=FInput else G:=FOutput;
    G.RowCount:=2;
    for I:=1 to G.RowCount-1 do
      for J:=0 to 2 do G.Cells[J,I]:='';
  end;
  FSurfaces.Clear;
  FStatus.Caption:='Виберіть фізичний .sens і натисніть «Виконати».';
end;

{ Borrowed Words — допущені фізичним DecodeT5M біти RawByteString,
  не числові значення, не текст. Показуємо лише перші 128 Wn.
  Усі таблиці належать TForm; знищуються LCL автоматично.
  Питання: навіщо зберігати провідні нулі? Що означає Wn?
  Чому ширина не є доменом? Чи можна виконати рядок grid? }
procedure TPhysicalWindow.FillGrid(Grid:TStringGrid;
  const Words:TExactWords);
var I,N:SizeInt;
begin
  N:=Length(Words);
  if N>MaxShownWords then N:=MaxShownWords;
  Grid.RowCount:=N+1;
  if N=0 then Grid.RowCount:=2;
  for I:=0 to N-1 do begin
    Grid.Cells[0,I+1]:=IntToStr(I+1);
    Grid.Cells[1,I+1]:='W'+IntToStr(Length(Words[I]));
    Grid.Cells[2,I+1]:=String(Words[I]);
  end;
end;

{ Тільки pinned catalog D7 із шістьма поверхнями; індекс шукаємо
  exact-domain ключем, а не за написанням/ASCII чи порядком рядка.
  Borrowed Bits містить рівно 7 бітів W7; ніколи не викликається
  як функція. FSurfaces — лише read-only host-відображення.
  Питання: чому 7 бітів не визначають callable? Як перевірити ключ?
  Чому LISP може бути порожній? Чи змінює проєкція T5M? }
procedure TPhysicalWindow.ShowD7(const Bits:RawByteString);
const Names:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var I,J:SizeInt; Key:TDomainKey;
begin
  FSurfaces.Clear;
  if Length(Bits)<>7 then Exit;
  Key:=ExactKey(Bits);
  for I:=0 to High(FCatalog[7]) do
    if SameKey(FCatalog[7][I].Key,Key) then begin
      for J:=0 to 5 do
        FSurfaces.Lines.Add(Names[J]+': '+
          SurfaceForDisplay(FCatalog[7][I].Surface[J]));
      Exit;
    end;
  raise Exception.Create('немає pinned D7-координати відповіді');
end;

{ Path — тільки шлях host-файлу, НЕ SENS-ім'я. RawByteString
  містить фактичні байти T5M (включно з 0), без UTF-8 конверсії.
  TFileStream належить одному виклику та звільняється у finally.
  Питання: чому .lisp не приймається? Навіщо 64 KiB GUI межа?
  Чому FPC ReadBuffer замість ReadLn? Що стається при EOF? }
function TPhysicalWindow.ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise Exception.Create('потрібен канонічний двійковий файл .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxGUIBytes) then
      raise Exception.Create('порожній або завеликий фізичний файл');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

function TPhysicalWindow.ExecuteFile(const Path:String):Boolean;
var Physical,Answer:RawByteString; WIn,WOut:TExactWords;
    Engine:TBinaryExecutor;
begin
  Result:=False;
  ClearResults;
  FPath.Text:=Path;
  Engine:=nil;
  try
    Physical:=ReadPhysical(Path);
    DecodeT5M(Physical,WIn);
    Engine:=TBinaryExecutor.Create('external/sens');
    try
      Answer:=Engine.ExecutePhysicalT5M(Physical);
    finally FreeAndNil(Engine) end;
    DecodeT5M(Answer,WOut);
    if Length(WOut)<1 then
      raise Exception.Create('виконавець не повернув фізичних слів');
    { Жодного UI publish до виконання та повного decode відповіді. }
    FillGrid(FInput,WIn);
    FillGrid(FOutput,WOut);
    if Length(WOut)=1 then ShowD7(WOut[0]);
    FAnswer:=Answer;
    FStatus.Caption:='ВИКОНАНО: відповідь T5M '+IntToStr(Length(Answer))+
      ' байт; слів '+IntToStr(Length(WOut))+
      '. Показано не більш як 128 слів.';
    Result:=True;
  except
    on E:EBinaryExecutionError do begin
      ClearResults;
      FStatus.Caption:='ВІДХИЛЕНО, слово='+IntToStr(E.WordIndex)+': '+E.Message;
    end;
    on E:Exception do begin
      ClearResults;
      FStatus.Caption:='ВІДХИЛЕНО: '+E.Message;
    end;
  end;
end;

procedure TPhysicalWindow.PickClick(Sender:TObject);
begin
  if FPicker.Execute then begin
    FPath.Text:=FPicker.FileName;
    ClearResults;
  end;
end;

procedure TPhysicalWindow.RunClick(Sender:TObject);
begin
  ExecuteFile(FPath.Text);
end;

procedure TPhysicalWindow.Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('LCL-ПЕРЕВІРКА: '+Why);
end;

{ Тест натискає реальну LCL TButton.Click та перевіряє стан
  TEdit/TStringGrid/TMemo. Файли генерує чинний pinned T5M codec.
  Жодних SENS-законів з умов тесту не запроваджено.
  Питання: що доводить побайтовий cmp? Чому Grid не oracle?
  Чому відмова має очищати FAnswer? Яка межа цього runtime? }
procedure TPhysicalWindow.SelfTest(const Good,Quoted,Bad,EmptyFile,
  Multi,Wrong:String);
var Exact:RawByteString;
  procedure Run(const Path:String);
  begin
    FPath.Text:=Path;
    FRun.Click;
    Application.ProcessMessages;
  end;
  procedure Rejected(const Path:String);
  begin
    Run(Path);
    Need(FAnswer='','старі фізичні байти після відмови');
    Need(FInput.Cells[2,1]='','старий grid входу після відмови');
    Need(FOutput.Cells[2,1]='','старий grid виходу після відмови');
    Need(FSurfaces.Lines.Count=0,'старі pinned D7 дані після відмови');
    Need(Pos('ВІДХИЛЕНО',FStatus.Caption)=1,'втрачена видима помилка');
  end;
begin
  Exact:=ReadPhysical(Good);
  Run(Good);
  Need(FAnswer=Exact,'D1 відповідь не byte-exact');
  Need(FInput.Cells[2,1]='1','вхід D1 не фізичний');
  Need(FOutput.Cells[1,1]='W1','вихід D1 має неправильну ширину');
  Run(Quoted);
  Need(FAnswer=Exact,'D3 цитата повернула інші фізичні байти');
  Need(FInput.Cells[1,2]='W3','D3 head не exact W3');
  Need(FOutput.Cells[2,1]='1','D3 цитата не виконується');
  Rejected(Bad);
  Rejected(EmptyFile);
  Rejected(Multi);
  Rejected(Wrong);
  Run(Good);
  Need(FAnswer=Exact,'після помилок виконання не відновилось');
  ShowD7('0100001');
  Need(FSurfaces.Lines.Count=6,'шість pinned D7 проєкцій не відображено');
  Need(Pos('ук:',FSurfaces.Lines[0])=1,'немає ук');
  Need(Pos('укр:',FSurfaces.Lines[1])=1,'немає укр');
  Need(Pos('san:',FSurfaces.Lines[2])=1,'немає san');
  Need(Pos('en:',FSurfaces.Lines[3])=1,'немає en');
  Need(Pos('LISP:',FSurfaces.Lines[4])=1,'немає LISP');
  Need(Pos('sym:',FSurfaces.Lines[5])=1,'немає sym');
  PrintUTF8('LCL-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД FPC=реальний'+
    ' D1=так D3=так T5M=побайтово негативи=4 відновлення=так');
  PrintUTF8('LCL-ФІЗИЧНИЙ-D7-ГАРАЗД шість=pinned ук-укр-san-en-LISP-sym'+
    ' значення=тільки-дані callable=ні');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — фізичне виконання D3';
    Application.CreateForm(TPhysicalWindow,Window);
    if (ParamCount=7) and (ParamStr(1)='--самоперевірка') then begin
      Window.Show; Application.ProcessMessages;
      Window.SelfTest(ParamStr(2),ParamStr(3),ParamStr(4),
        ParamStr(5),ParamStr(6),ParamStr(7));
      Window.Free;
    end else if ParamCount=0 then Application.Run
    else begin
      WriteLn(StdErr,'Використання: sens-fizychnyi-vykon [--самоперевірка 6 файлів]');
      ExitCode:=64;
      Window.Free;
    end;
  except
    on E:Exception do begin
      WriteLn(StdErr,'LCL-ФІЗИЧНЕ-ВИКОНАННЯ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
end.
