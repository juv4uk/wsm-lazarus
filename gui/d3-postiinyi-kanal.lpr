{ G5.35 — справжнє вікно Lazarus для вже злитого постійного D3 host-каналу.
  Код виконує лише фізичне кадрування та візуалізацію результату.
  Закони SENS живуть у pinned external/sens, а виконання — у senspotikd3.
  Wn — ширина слова, не семантична ідентичність Dn. }
program d3_postiinyi_kanal;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Grids, Dialogs,
  Process, wsm.t5m;

type
  TD3Window = class(TForm)
  private
    FProcess:TProcess;
    FInitialPID:Int64;
    FPath:TEdit;
    FPick,FRun:TButton;
    FGrid:TStringGrid;
    FStatus:TLabel;
    FDialog:TOpenDialog;
    FLastAnswer:RawByteString;
    procedure ClearAnswer;
    procedure ReadExact(var Buf;N:SizeInt);
    function ReadPhysical(const TargetPath:String):RawByteString;
    function ExecutePhysical(const Physical:RawByteString):Boolean;
    function RunFile(const TargetPath:String):Boolean;
    procedure PickClick(Sender:TObject);
    procedure RunClick(Sender:TObject);
    procedure Need(Condition:Boolean;const MessageText:String);
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    procedure Connect(const Root,Executable:String);
    procedure SelfTest(const Fixtures:String);
  end;

var Window:TD3Window;

constructor TD3Window.Create(AOwner:TComponent);
var Note:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Width:=1080;Height:=740;Position:=poScreenCenter;
  Caption:='SENS — постійний двійковий D3-канал у Lazarus';
  FProcess:=nil;FInitialPID:=-1;FLastAnswer:='';
  Note:=TLabel.Create(Self);Note.Parent:=Self;
  Note.SetBounds(18,12,1035,52);Note.AutoSize:=False;Note.WordWrap:=True;
  Note.Caption:='Лише фізичний .sens (канонічний T5M). Один дочірній PID; '+
    'ук/укр/san/en/LISP/sym — людські проєкції, D7 — текст, D12+ — числа. '+
    'Жодного текстового dispatch, повного Core4 або REPL.';
  FPath:=TEdit.Create(Self);FPath.Parent:=Self;
  FPath.SetBounds(18,76,704,32);FPath.Text:='';
  FPick:=TButton.Create(Self);FPick.Parent:=Self;
  FPick.SetBounds(732,76,132,32);FPick.Caption:='Обрати .sens';
  FPick.OnClick:=@PickClick;
  FRun:=TButton.Create(Self);FRun.Parent:=Self;
  FRun.SetBounds(874,76,179,32);FRun.Caption:='Виконати в PID';
  FRun.OnClick:=@RunClick;FRun.Enabled:=False;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Оберіть канонічний фізичний SENS';
  FDialog.Filter:='Фізичний SENS (*.sens)|*.sens';
  FGrid:=TStringGrid.Create(Self);FGrid.Parent:=Self;
  FGrid.SetBounds(18,124,1035,494);
  FGrid.ColCount:=3;FGrid.RowCount:=2;
  FGrid.FixedCols:=0;FGrid.FixedRows:=1;
  FGrid.ColWidths[0]:=105;
  FGrid.ColWidths[1]:=155;
  FGrid.ColWidths[2]:=735;
  FGrid.Cells[0,0]:='№ слова';
  FGrid.Cells[1,0]:='Ширина Wn';
  FGrid.Cells[2,0]:='Точні біти результату (не назва функції)';
  FStatus:=TLabel.Create(Self);FStatus.Parent:=Self;
  FStatus.SetBounds(18,632,1035,85);
  FStatus.AutoSize:=False;FStatus.WordWrap:=True;
  ClearAnswer;
  FStatus.Caption:='Підключення до постійного фізичного каналу відсутнє.';
end;

destructor TD3Window.Destroy;
begin
  if FProcess<>nil then begin
    if FProcess.Running then begin
      FProcess.Terminate(0);
      FProcess.WaitOnExit;
    end;
    FreeAndNil(FProcess);
  end;
  inherited Destroy;
end;

procedure TD3Window.Need(Condition:Boolean;const MessageText:String);
begin
  if not Condition then
    raise Exception.Create('LCL-D3-ПОМИЛКА: '+MessageText);
end;

procedure TD3Window.ClearAnswer;
var I:SizeInt;
begin
  FLastAnswer:='';
  FGrid.RowCount:=2;
  for I:=0 to FGrid.ColCount-1 do FGrid.Cells[I,1]:='';
end;

procedure TD3Window.Connect(const Root,Executable:String);
begin
  Need(FProcess=nil,'повторний запуск окремого каналу заборонено');
  Need((Root<>'') and (Executable<>''),'немає root або виконавця');
  FProcess:=TProcess.Create(nil);
  try
    FProcess.Executable:=Executable;
    FProcess.Options:=[poUsePipes];
    FProcess.Parameters.Add('--канал');
    FProcess.Parameters.Add(Root);
    FProcess.Execute;
    FInitialPID:=Int64(FProcess.ProcessID);
    Need(FInitialPID>0,'PID не створено');
    FRun.Enabled:=True;
    FStatus.Caption:='Підключено до фізичного D3-каналу, PID='+
      IntToStr(FInitialPID)+'; без збереження мовних визначень.';
  except
    FreeAndNil(FProcess);
    raise;
  end;
end;

{ N — точна кількість host-байтів відповіді; FProcess — borrowed
  дочірній процес, життєвий цикл належить формі. }
procedure TD3Window.ReadExact(var Buf;N:SizeInt);
var P:PByte;Got,Total:SizeInt;
begin
  P:=@Buf;Total:=0;
  while Total<N do begin
    Got:=FProcess.Output.Read(P[Total],N-Total);
    if Got<=0 then
      raise Exception.Create('дочірній канал обірвав фізичну відповідь');
    Inc(Total,Got);
  end;
end;

{ Локальний host-файл — лише transport packed T5M, без тлумачення
  укр, D7 чи D12+. Результат: новий managed RawByteString. }
function TD3Window.ReadPhysical(const TargetPath:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(TargetPath))<>'.sens' then
    raise Exception.Create('лише канонічний фізичний .sens, не .lisp');
  F:=TFileStream.Create(TargetPath,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<0) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('фізичний файл перевищує межу 64 КіБ');
    SetLength(Result,SizeInt(F.Size));
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free; end;
end;

{ Запит — host u32le + raw T5M. Точну семантику і допустимість
  кожної D3 форми перевіряє лише зовнішній існуючий evaluator.
  Вихід — GUI Boolean (не D1), фізичні байти зберігаються тільки
  після успішного canonical T5M+length admission. }
function TD3Window.ExecutePhysical(const Physical:RawByteString):Boolean;
var H:array[0..4] of Byte;
    N:LongWord;Status:Byte;
    Candidate:RawByteString;
    Words:TExactWords;
    I:SizeInt;
begin
  Result:=False;ClearAnswer;
  try
    if (FProcess=nil) or (not FProcess.Running) then
      raise Exception.Create('дочірній D3-канал уже завершився');
    if Length(Physical)>MAX_T5M_FILE_BYTES then
      raise Exception.Create('фізичний вхід поза квотою T5M');
    N:=LongWord(Length(Physical));
    H[0]:=Byte(N and $ff);
    H[1]:=Byte((N shr 8) and $ff);
    H[2]:=Byte((N shr 16) and $ff);
    H[3]:=Byte((N shr 24) and $ff);
    FProcess.Input.WriteBuffer(H,4);
    if N>0 then FProcess.Input.WriteBuffer(Physical[1],N);
    ReadExact(H,5);
    Status:=H[0];
    N:=LongWord(H[1]) or (LongWord(H[2]) shl 8) or
      (LongWord(H[3]) shl 16) or (LongWord(H[4]) shl 24);
    if (Status>1) or (N<1) or (N>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('дочірній канал повернув пошкоджений header');
    SetLength(Candidate,N);
    ReadExact(Candidate[1],N);
    if Status=1 then begin
      FStatus.Caption:='Відхилено у PID='+IntToStr(FInitialPID)+
        ': '+String(Candidate);
      Exit(False);
    end;
    DecodeT5M(Candidate,Words);
    if (Length(Words)<1) or (Length(Words)>64) or
       (EncodeT5M(Words)<>Candidate) then
      raise Exception.Create('неканонічна D3-відповідь');
    for I:=0 to High(Words) do
      if (Length(Words[I])<1) or (Length(Words[I])>4096) then
        raise Exception.Create('неприпустима ширина фізичної відповіді');
    { Публікуємо всі значення лише після успішної перевірки всіх слів. }
    FGrid.RowCount:=Length(Words)+1;
    for I:=0 to High(Words) do begin
      FGrid.Cells[0,I+1]:=IntToStr(I+1);
      FGrid.Cells[1,I+1]:='W'+IntToStr(Length(Words[I]));
      FGrid.Cells[2,I+1]:=String(Words[I]);
    end;
    FLastAnswer:=Candidate;
    FStatus.Caption:='Реально виконано '+IntToStr(Length(Words))+
      ' фізичних слів у тому самому PID='+IntToStr(FInitialPID)+
      '; Wn не доводить Dn, Core4/REPL/D12+ не заявлено.';
    Result:=True;
  except
    on E:Exception do begin
      ClearAnswer;
      FStatus.Caption:='D3 канал відхилив запит: '+E.Message;
    end;
  end;
end;

function TD3Window.RunFile(const TargetPath:String):Boolean;
var Physical:RawByteString;
begin
  Result:=False;ClearAnswer;
  try
    Physical:=ReadPhysical(TargetPath);
    Result:=ExecutePhysical(Physical);
  except
    on E:Exception do begin
      ClearAnswer;
      FStatus.Caption:='Фізичний файл відхилено: '+E.Message;
    end;
  end;
end;

procedure TD3Window.PickClick(Sender:TObject);
begin
  if FDialog.Execute then FPath.Text:=FDialog.FileName;
  { Раніше показаний результат не є результатом нового вибору. }
  ClearAnswer;
end;

procedure TD3Window.RunClick(Sender:TObject);
begin
  RunFile(FPath.Text);
end;

{ Справжні LCL події та постійний дочірній процес, не mock.
  Фізичні expected беруться з попередніх незалежних G3.17 fixtures. }
procedure TD3Window.SelfTest(const Fixtures:String);
const Names:array[0..2] of String=('one','four','64');
      Counts:array[0..2] of SizeInt=(1,4,64);
var Path,Answer:RawByteString;I:SizeInt;
begin
  Need((FProcess<>nil) and FProcess.Running,'канал не запущено');
  Need((FGrid.RowCount=2) and (FLastAnswer=''),'початкова GUI відповідь не порожня');
  for I:=0 to High(Names) do begin
    FPath.Text:=Fixtures+'/'+Names[I]+'.sens';
    FRun.Click;
    Answer:=ReadPhysical(Fixtures+'/'+Names[I]+'-answer.sens');
    Need(FLastAnswer=Answer,'LCL відповідь не дорівнює фізичним fixture '+Names[I]);
    Need(FGrid.RowCount=Counts[I]+1,'втрачено число відповідей '+Names[I]);
    Need((FGrid.Cells[1,1]='W'+IntToStr(Length(FGrid.Cells[2,1]))) and
      (FGrid.Cells[2,1]<>''),'немає фізичної ширини');
    Need(Int64(FProcess.ProcessID)=FInitialPID,'GUI замінив дочірній процес');
  end;
  { Пізня D3-відмова не має права залишити останню відповідь із 64 слів. }
  FPath.Text:=Fixtures+'/late-bad.sens';FRun.Click;
  Need((FLastAnswer='') and (FGrid.RowCount=2) and
    (FGrid.Cells[2,1]=''),'пізня D3 відмова залишила stale відповіді');
  Need(Pos('форма=2 слово=2',FStatus.Caption)>0,
    'втрачено фізичну адресу пізньої помилки');
  FPath.Text:=Fixtures+'/65.sens';FRun.Click;
  Need((FLastAnswer='') and (FGrid.Cells[2,1]=''),'65 форм не очищено');
  FPath.Text:=Fixtures+'/bad-t5m.sens';FRun.Click;
  Need((FLastAnswer='') and (FGrid.Cells[2,1]=''),'пошкоджений T5M опубліковано');
  FPath.Text:=Fixtures+'/d12.sens';FRun.Click;
  Need((FLastAnswer='') and (FGrid.Cells[2,1]=''),'D12+ помилково виконано');
  Need(not ExecutePhysical(''),'порожній фізичний кадр виконано');
  Need((FLastAnswer='') and (FGrid.Cells[2,1]=''),
    'порожній фізичний кадр залишив stale дані');
  FPath.Text:=Fixtures+'/not-program.lisp';FRun.Click;
  Need((FLastAnswer='') and (Pos('.lisp',FStatus.Caption)>0),
    'людську проєкцію .lisp прийнято як двійкову програму');
  FPath.Text:=Fixtures+'/one.sens';FRun.Click;
  Path:=ReadPhysical(Fixtures+'/one-answer.sens');
  Need((FLastAnswer=Path) and (FGrid.RowCount=2),
    'GUI не відновився у тому самому PID після фізичних відмов');
  Need(Int64(FProcess.ProcessID)=FInitialPID,'PID змінився після помилки');
  WriteLn('LCL-D3-ПОСТІЙНИЙ-КАНАЛ-ГАРАЗД Lazarus=GTK2 FPC=справжній PID=незмінний Wn=точні T5M=побайтово 1/4/64=так');
  WriteLn('LCL-D3-ПОМИЛКИ-ГАРАЗД пізня-форма=2-слово=2 stale=відсутній 65=відхилено D12+=відхилено lisp=відхилено відновлення=так Core4/REPL=НЕ-ДОВЕДЕНО');
end;

begin
  Application.Initialize;
  Application.CreateForm(TD3Window,Window);
  if (ParamCount=4) and (ParamStr(1)='--самоперевірка') then begin
    try
      Window.Connect(ParamStr(2),ParamStr(3));
      Window.SelfTest(ParamStr(4));
    except
      on E:Exception do begin
        WriteLn(StdErr,'LCL-D3-ПОМИЛКА: ',E.Message);
        Halt(2);
      end;
    end;
  end else if ParamCount=2 then begin
    Window.Connect(ParamStr(1),ParamStr(2));
    Application.Run;
  end else begin
    WriteLn(StdErr,'Використання: d3-postiinyi-kanal ROOT senspotikd3 | --самоперевірка ROOT senspotikd3 fixtures');
    Halt(64);
  end;
end.
