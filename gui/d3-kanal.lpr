{ G5.35 — Lazarus GTK2-клієнт справжнього фізичного D3 каналу.
  Підтримує лише packed .sens, без власного evaluator, без Core4.
  Wn — фізична ширина слова, не семантичний домен Dn. }
program d3_kanal;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids, Dialogs,
  wsm.d3wireclient, wsm.t5m;
type
  TD3Window=class(TForm)
  private
    FClient:TD3WireClient; { owned: один FPC senspotikd3 }
    FPath:TEdit;
    FPick,FRun:TButton;
    FRows:TStringGrid;
    FStatus:TLabel;
    FDialog:TOpenDialog;
    FCount:SizeInt;
    FAnswer:RawByteString; { owned: лише ПОВНІ успішні фізичні байти }
    FInitialPID:Int64;
    procedure ClearAnswer;
    function ReadPhysical(const Path:String):RawByteString;
    function ExecuteFile(const Path:String):Boolean;
    procedure PickClick(Sender:TObject);
    procedure PathChanged(Sender:TObject);
    procedure RunClick(Sender:TObject);
    procedure Need(Condition:Boolean;const Reason:String);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure Connect(const AuthorityRoot,ExecutablePath:String);
    procedure SelfTest(const AuthorityRoot,ExecutablePath:String);
  end;
var Window:TD3Window;

constructor TD3Window.Create(AOwner:TComponent);
var Note:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — фізичний D3-канал у Lazarus';
  Position:=poScreenCenter;
  Width:=1020; Height:=730;
  FClient:=nil; FAnswer:=''; FCount:=0; FInitialPID:=-1;
  Note:=TLabel.Create(Self); Note.Parent:=Self;
  Note.SetBounds(16,12,980,47); Note.AutoSize:=False; Note.WordWrap:=True;
  Note.Caption:='Канонічний .sens (packed T5M) виконує постійний Free Pascal D3-процес. '+
    'Український .lisp — людська проєкція укр; D7 — текстові дані. '+
    'Це не повний REPL/Core4 і не арифметика D12+.';
  FPath:=TEdit.Create(Self); FPath.Parent:=Self;
  FPath.SetBounds(16,69,690,32); FPath.Text:='';
  FPick:=TButton.Create(Self); FPick.Parent:=Self;
  FPick.SetBounds(718,69,122,32); FPick.Caption:='Обрати .sens';
  FPick.OnClick:=@PickClick;
  FRun:=TButton.Create(Self); FRun.Parent:=Self;
  FRun.SetBounds(852,69,142,32); FRun.Caption:='Виконати D3';
  FRun.Enabled:=False; FRun.OnClick:=@RunClick;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичні програми (*.sens)|*.sens';
  FRows:=TStringGrid.Create(Self); FRows.Parent:=Self;
  FRows.SetBounds(16,120,978,487);
  FRows.ColCount:=3; FRows.RowCount:=2;
  FRows.FixedCols:=0; FRows.FixedRows:=1;
  FRows.ColWidths[0]:=125; FRows.ColWidths[1]:=115; FRows.ColWidths[2]:=710;
  FRows.Cells[0,0]:='Слово відповіді';
  FRows.Cells[1,0]:='Ширина Wn';
  FRows.Cells[2,0]:='Фізичні біти (не домен)';
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(16,625,978,72); FStatus.AutoSize:=False;
  FStatus.WordWrap:=True;
  FPath.OnChange:=@PathChanged;
  ClearAnswer;
end;

destructor TD3Window.Destroy;
begin
  FreeAndNil(FClient);
  inherited Destroy;
end;

procedure TD3Window.Need(Condition:Boolean;const Reason:String);
begin
  if not Condition then raise Exception.Create('LCL-D3-ПОМИЛКА: '+Reason);
end;

procedure TD3Window.ClearAnswer;
var I,J:SizeInt;
begin
  FAnswer:=''; FCount:=0;
  for I:=1 to FRows.RowCount-1 do
    for J:=0 to 2 do FRows.Cells[J,I]:='';
  FRows.RowCount:=2;
end;

function TD3Window.ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise Exception.Create('Потрібен лише двійковий файл .sens, не .lisp');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxD3WireBytes) then
      raise Exception.Create('Фізичний файл поза межею 1..65536');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

function TD3Window.ExecuteFile(const Path:String):Boolean;
var InputBytes,Answer:RawByteString;
    Words:TExactWords;
    I:SizeInt;
begin
  { Публікація результату лише ПІСЛЯ повного успіху host-запиту.
    Будь-яка відмова прибирає весь попередній фізичний snapshot. }
  ClearAnswer; Result:=False;
  try
    if FClient=nil then raise Exception.Create('D3-канал не підключено');
    InputBytes:=ReadPhysical(Path);
    Answer:=FClient.Execute(InputBytes);
    DecodeT5M(Answer,Words);
    if (Length(Words)<1) or (Length(Words)>4096) or
       (EncodeT5M(Words)<>Answer) then
      raise Exception.Create('Неканонічна або завелика D3-відповідь');
    FRows.RowCount:=Length(Words)+1;
    for I:=0 to High(Words) do begin
      FRows.Cells[0,I+1]:=IntToStr(I+1);
      FRows.Cells[1,I+1]:='W'+IntToStr(Length(Words[I]));
      FRows.Cells[2,I+1]:=String(Words[I]);
    end;
    FCount:=Length(Words);
    FAnswer:=Answer;
    FStatus.Caption:='Фізичне виконання D3 успішне: слів='+
      IntToStr(FCount)+' байтів='+IntToStr(Length(FAnswer))+
      '; PID='+IntToStr(FClient.ProcessID)+
      '; тільки точні Wn, не Dn';
    Result:=True;
  except on E:Exception do begin
    ClearAnswer;
    FStatus.Caption:='Відмова фізичного D3-каналу: '+E.Message;
  end end;
end;

{ Після ручного редагування хостового шляху попередня фізична
  відповідь більше не належить вибраному вводу. OnChange працює до
  нового execution; ніякі біти/закони SENS тут не перетворюються. }
procedure TD3Window.PathChanged(Sender:TObject);
begin
  ClearAnswer;
  FStatus.Caption:='Фізичний шлях змінено; стару D3-відповідь очищено. '+
    'Натисніть «Виконати D3» для нового .sens.';
end;

procedure TD3Window.PickClick(Sender:TObject);
begin
  if FDialog.Execute then begin
    ClearAnswer;
    FPath.Text:=FDialog.FileName;
    FStatus.Caption:='Обрано фізичний шлях; виконання ще не здійснено';
  end;
end;

procedure TD3Window.RunClick(Sender:TObject);
begin
  ExecuteFile(FPath.Text);
end;

procedure TD3Window.Connect(const AuthorityRoot,ExecutablePath:String);
begin
  FreeAndNil(FClient);
  ClearAnswer;
  FClient:=TD3WireClient.Create(ExecutablePath,AuthorityRoot);
  FInitialPID:=FClient.ProcessID;
  FRun.Enabled:=True;
  FStatus.Caption:='Постійний фізичний D3-канал PID='+IntToStr(FInitialPID);
end;

procedure TD3Window.SelfTest(const AuthorityRoot,ExecutablePath:String);
var Fixture:String;
    PID:Int64;
    function Item(const Name:String):String;
    begin Result:=Fixture+'/'+Name+'.sens' end;
    procedure CheckSuccess(const Name:String);
    var Expected:RawByteString; OK:Boolean;
    begin
      Expected:=ReadPhysical(Fixture+'/'+Name+'-answer.sens');
      OK:=ExecuteFile(Item(Name));
      Need(OK,'D3 не виконав '+Name+'; '+FStatus.Caption);
      Need((FAnswer=Expected) and (FCount>0) and
           (FClient.ProcessID=PID),'непобайтовий результат або інший PID: '+Name);
    end;
    procedure CheckFailure(const Name:String);
    begin
      Need(not ExecuteFile(Item(Name)),'помилково прийнято '+Name);
      Need((FAnswer='') and (FCount=0) and
           (FRows.Cells[2,1]='') and
           (FClient.ProcessID=PID),'залишились байти або змінився PID: '+Name);
    end;
begin
  Connect(AuthorityRoot,ExecutablePath);
  PID:=FClient.ProcessID;
  Need(PID>0,'немає дочірнього процесу');
  Fixture:='build/paketd3-cli/fixtures';
  CheckSuccess('one');
  CheckSuccess('four');
  CheckSuccess('64');

  { Справжній TEdit.OnChange: зміна шляху НЕ може залишати
    64 попередні фізичні результати на екрані як чинні. }
  FPath.Text:=Item('four');
  Need((FAnswer='') and (FCount=0) and
       (FRows.RowCount=2) and (FRows.Cells[2,1]=''),
       'ручна зміна шляху не очистила старий фізичний snapshot');
  Need(Pos('шлях змінено',FStatus.Caption)>0,
       'відсутня діагностика зміни шляху');
  { Не mock і не прямий ExecuteFile: реальна Lazarus кнопка та
    вже злитий дочірній FPC D3 з pinned T5M. }
  FRun.Click;
  Need((FAnswer=ReadPhysical(Fixture+'/four-answer.sens')) and
       (FClient.ProcessID=PID),
       'натискання LCL кнопки не виконало новий фізичний D3 пакет');
  FPath.Text:=Item('late-bad');
  Need((FAnswer='') and (FCount=0) and (FRows.Cells[2,1]=''),
       'зміна шляху на помилковий лишила успішний D3 snapshot');
  FRun.Click;
  Need((FAnswer='') and (Pos('форма=2 слово=2',FStatus.Caption)>0) and
       (FClient.ProcessID=PID),
       'реальна LCL кнопка не зберегла точну пізню D3 помилку');
  CheckSuccess('one'); { реальне відновлення у тому самому PID }

  CheckFailure('late-bad');
  Need(Pos('форма=2 слово=2',FStatus.Caption)>0,
    'втрачено фізичну адресу пізньої D3-помилки');
  CheckFailure('bad-t5m');
  CheckFailure('d12');
  CheckFailure('65');
  Need(not ExecuteFile(Fixture+'/not-program.lisp'),
    'людська .lisp помилково допущена як машинний T5M');
  Need((FAnswer='') and (FCount=0),'стара відповідь після .lisp');
  CheckSuccess('one');
  Need(FClient.ProcessID=PID,'змінено PID після негативних запитів');
  Window.Show;
  Application.ProcessMessages;
  WriteLn('LCL-D3-КАНАЛ-ГАРАЗД ',
    'Lazarus=GTK2 один-PID=так ',
    '1/4/64=побайтово late=форма2-слово2 ',
    'D12=відхилено 65=відхилено bad-T5M=відхилено ',
    'lisp=відхилено відновлення=так REPL/Core4=ні');
  WriteLn('LCL-D3-ШЛЯХ-ГАРАЗД OnChange=очищує-stale '+
    'Click=фізичне-виконання T5M=побайтово PID=незмінний '+
    'пізня-помилка=адресована');
end;

begin
  try
    Application.Initialize;
    Application.Title:='SENS — фізичний D3-канал';
    Application.CreateForm(TD3Window,Window);
    if (ParamCount=3) and (ParamStr(1)='--самоперевірка') then begin
      Window.SelfTest(ParamStr(2),ParamStr(3));
      Window.Free;
    end else if ParamCount=2 then begin
      Window.Connect(ParamStr(1),ParamStr(2));
      Application.Run;
    end else begin
      WriteLn(StdErr,'Використання: d3-kanal корінь-sens senspotikd3 ',
        'або --самоперевірка корінь-sens senspotikd3');
      Halt(64);
    end;
  except on E:Exception do begin
    WriteLn(StdErr,'LCL-D3-ПОМИЛКА: ',E.Message);
    Halt(2);
  end end;
end.

{ Типи: FAnswer owned packed T5M, InputBytes borrowed під час Execute;
  UI Grid — лише Wn/біти, без типового висновку про Dn. Дочірній процес
  належить TD3WireClient і звільняється разом із формою.
  Питання: 1) Чому 64 форми — host quota, а не семантика?
  2) Чому ми не показуємо рядки, коли пізніша форма відхилена?
  3) Чим W24 відрізняється від D24?
  4) Чому шість pinned проєкцій не стають семантичним dispatch?
  5) Чому збережений PID не дорівнює збереженим Lisp визначенням? }
