{ G5.33 — справжнє LCL-вікно пакета з канонічного фізичного .sens.
  Жодного власного evaluator: TCore4WireClient запускає окремий pinned
  Core4 runtime, а UI показує тільки підтверджені точні T5M відповіді.
  Wn позначає фізичну ширину, НЕ семантичний домен Dn. }
program core4_paket_okno;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids, Dialogs,
  wsm.core4wireclient, wsm.core4runtime, wsm.t5m;

type
  TBatchWindow = class(TForm)
  private
    FClient: TCore4WireClient;          { owned: один дочірній процес }
    FPath: TEdit;
    FPick, FRun: TButton;
    FResults: TStringGrid;
    FStatus: TLabel;
    FDialog: TOpenDialog;
    FRows: SizeInt;
    FInitialPID: Int64;
    procedure ClearResults;
    function ReadPhysical(const Path: String): RawByteString;
    function ExecuteFile(const Path: String): Boolean;
    procedure PickClick(Sender: TObject);
    procedure RunClick(Sender: TObject);
    procedure Need(OK: Boolean; const Why: String);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Connect(const Root, Executable: String);
    procedure SelfTest(const Root, Executable: String);
  end;

var Window: TBatchWindow;

constructor TBatchWindow.Create(AOwner: TComponent);
var Note: TLabel;
begin
  inherited CreateNew(AOwner,1);
  Width:=1050; Height:=730; Position:=poScreenCenter;
  Caption:='SENS — фізичний пакет Core4 у Lazarus';
  FClient:=nil; FRows:=0; FInitialPID:=-1;
  Note:=TLabel.Create(Self); Note.Parent:=Self;
  Note.SetBounds(16,12,1000,48); Note.AutoSize:=False; Note.WordWrap:=True;
  Note.Caption:='Лише канонічний двійковий .sens (T5M). '+
    'Усі форми виконує окремий постійний Core4-процес; '+
    'імена ук/укр/san/en/LISP/sym тут не визначають семантики.';
  FPath:=TEdit.Create(Self); FPath.Parent:=Self;
  FPath.SetBounds(16,68,705,32); FPath.Text:='';
  FPick:=TButton.Create(Self); FPick.Parent:=Self;
  FPick.SetBounds(734,68,120,32); FPick.Caption:='Обрати .sens';
  FPick.OnClick:=@PickClick;
  FRun:=TButton.Create(Self); FRun.Parent:=Self;
  FRun.SetBounds(867,68,160,32); FRun.Caption:='Виконати пакет';
  FRun.Enabled:=False; FRun.OnClick:=@RunClick;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Filter:='Фізичні SENS (*.sens)|*.sens';
  FResults:=TStringGrid.Create(Self); FResults.Parent:=Self;
  FResults.SetBounds(16,119,1011,490);
  FResults.ColCount:=3; FResults.RowCount:=2;
  FResults.FixedCols:=0; FResults.FixedRows:=1;
  FResults.ColWidths[0]:=95;
  FResults.ColWidths[1]:=120;
  FResults.ColWidths[2]:=760;
  FResults.Cells[0,0]:='Форма';
  FResults.Cells[1,0]:='Ширина Wn';
  FResults.Cells[2,0]:='Точні біти фізичної відповіді';
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(16,625,1010,70); FStatus.AutoSize:=False;
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

procedure TBatchWindow.ClearResults;
var I,J:SizeInt;
begin
  FRows:=0;
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
function TBatchWindow.ExecuteFile(const Path:String):Boolean;
var Physical,Answer:RawByteString; Words:TExactWords; I:SizeInt;
begin
  Result:=False; ClearResults;
  try
    if FClient=nil then raise Exception.Create('немає живого Core4-каналу');
    Physical:=ReadPhysical(Path);
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
    FStatus.Caption:='Виконано '+IntToStr(FRows)+
      ' фізичних форм у незмінному PID='+IntToStr(FClient.ProcessID)+
      '. Wn — фізична ширина, а не домен Dn. Core4 не є загальним REPL.';
    Result:=True;
  except on E:Exception do begin
    ClearResults;
    FStatus.Caption:='Відмова без часткових результатів: '+E.Message;
  end end;
end;

procedure TBatchWindow.PickClick(Sender:TObject);
begin
  if FDialog.Execute then begin
    ClearResults;
    FPath.Text:=FDialog.FileName;
    FStatus.Caption:='Файл обрано; ще не виконано.';
  end;
end;

procedure TBatchWindow.RunClick(Sender:TObject);
begin ExecuteFile(FPath.Text) end;

procedure TBatchWindow.Connect(const Root,Executable:String);
begin
  ClearResults; FRun.Enabled:=False;
  FreeAndNil(FClient); FInitialPID:=-1;
  FClient:=TCore4WireClient.Create(Executable,Root,True);
  FInitialPID:=FClient.ProcessID;
  Need(FInitialPID>0,'дочірній Core4-процес не запущено');
  FRun.Enabled:=True;
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
  Valid,Invalid,Combined:RawByteString;
  Temporary,Path:String;
  F:TFileStream;

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
    try F.WriteBuffer(Payload[1],Length(Payload))
    finally F.Free end;
  end;
begin
  Need(Assigned(FRun.OnClick) and Assigned(FPick.OnClick) and
    (FResults.ColCount=3),'відсутні справжні LCL-контроли');
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
    Need(FClient.ProcessID=FInitialPID,'змінений PID після пакета');

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
      (FClient.ProcessID=FInitialPID),'частковий результат або інший PID');

    Combined:=Pack([PhysicalD7Call(Key0,'0'),
      PhysicalD7Call(Key0,'1')]);
    Put(Combined);
    Need(ExecuteFile(Path) and (FRows=2) and
      (FResults.Cells[2,1]='0') and (FResults.Cells[2,2]='1') and
      (FClient.ProcessID=FInitialPID),
      'відновлення після remote-відмови в тому самому процесі');
    Window.Show; Application.ProcessMessages;
    WriteLn('LCL-CORE4-ПАКЕТ-ГАРАЗД ',
      'Lazarus=GTK2 реальний-PID=один пакет=3 ',
      'W1-W24=побайтово пізня-помилка=атомарна ',
      'T5M=відхилено lisp=відхилено відновлення=так ',
      'D12+=без-вгадування REPL=ні');
  finally
    if FileExists(Path) then DeleteFile(Path);
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
