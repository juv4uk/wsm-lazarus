{ G6.56: графічний Lazarus/LCL місток від ПЕРЕВІРЕНОГО EIR1 до
  канонічного фізичного D3 через існуючий sensirvykon.
  EIR1 — приватний структурний свідок, НЕ програма, НЕ executable IR. }
program sens_ir_vykonannia;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, SysUtils, Classes, Controls, StdCtrls,
  Dialogs, Process, Pipes, wsm.t5m, wsm.proektsii, wsm.domain;

const MaxDiagnostic=8192;
      MaxVisibleWords=1024;
type
  TIRWindow=class(TForm)
  private
    FPhysical:TEdit;
    FWire:TEdit;
    FRun:TButton;
    FJournal:TMemo;
    FStatus:TLabel;
    FPhysicalDialog,FWireDialog:TOpenDialog;
    FRunner:String;
    FCatalog:TProektsiiCatalog;
    FLast:RawByteString;
    FSuccess,FRejected:Integer;
    procedure ClickRun(Sender:TObject);
    procedure ClickPhysical(Sender:TObject);
    procedure ClickWire(Sender:TObject);
    procedure Demand(OK:Boolean;const Why:String);
    function RunChecked(const Source,Wire:String;
      out PhysicalResult,Diagnostic:RawByteString):Boolean;
    procedure RenderPhysical(const Physical:RawByteString);
  public
    constructor Create(AOwner:TComponent);override;
    procedure Connect(const Runner:String);
    procedure Execute(const Source,Wire:String);
    procedure SelfCheck(const Good,GoodIR,Expected,
      D7,D7IR,ExpectedD7,WrongIR,Bad,BadIR,TextFile,MissingIR:String);
  end;
var Window:TIRWindow;

constructor TIRWindow.Create(AOwner:TComponent);
var SelectPhysical,SelectWire:TButton;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — перевірений EIR1 перед фізичним виконанням';
  Width:=1100;Height:=700;Position:=poScreenCenter;
  FRunner:=''; FLast:='';FSuccess:=0;FRejected:=0;
  FPhysical:=TEdit.Create(Self);
  FPhysical.Parent:=Self;FPhysical.SetBounds(12,14,750,28);
  FPhysical.Text:='програма.sens';
  SelectPhysical:=TButton.Create(Self);
  SelectPhysical.Parent:=Self; SelectPhysical.SetBounds(778,14,286,28);
  SelectPhysical.Caption:='Вибрати двійковий .sens';
  SelectPhysical.OnClick:=@ClickPhysical;
  FWire:=TEdit.Create(Self);
  FWire.Parent:=Self;FWire.SetBounds(12,50,750,28);
  FWire.Text:='свідок.eir';
  SelectWire:=TButton.Create(Self);
  SelectWire.Parent:=Self;SelectWire.SetBounds(778,50,286,28);
  SelectWire.Caption:='Вибрати приватний EIR1';
  SelectWire.OnClick:=@ClickWire;
  FRun:=TButton.Create(Self);
  FRun.Parent:=Self;FRun.SetBounds(12,88,370,38);
  FRun.Caption:='Перевірити EIR1 і виконати фізичний SENS';
  FRun.Enabled:=False;FRun.OnClick:=@ClickRun;
  FStatus:=TLabel.Create(Self);
  FStatus.Parent:=Self;FStatus.SetBounds(400,95,650,25);
  FStatus.Caption:='Немає нативного перевіряльника';
  FJournal:=TMemo.Create(Self);
  FJournal.Parent:=Self; FJournal.SetBounds(12,144,1052,500);
  FJournal.ReadOnly:=True;FJournal.WordWrap:=False;
  FJournal.ScrollBars:=ssBoth;
  FPhysicalDialog:=TOpenDialog.Create(Self);
  FPhysicalDialog.Filter:='Канонічні двійкові SENS|*.sens';
  FWireDialog:=TOpenDialog.Create(Self);
  FWireDialog.Filter:='Приватний структурний свідок EIR1|*.eir';
end;

procedure TIRWindow.Demand(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ЛКЛ-EIR1-ПОМИЛКА: '+Why);
end;

procedure TIRWindow.Connect(const Runner:String);
begin
  Demand(FRunner='','повторне підключення');
  Demand(FileExists(Runner),'немає фізичного CLI sensirvykon');
  LoadPinnedProjections('external/sens',FCatalog);
  FRunner:=Runner;
  FRun.Enabled:=True;
  FStatus.Caption:='Підключено зовнішній нативний D3-виконавець';
end;

procedure TIRWindow.ClickPhysical(Sender:TObject);
begin
  if FPhysicalDialog.Execute then FPhysical.Text:=FPhysicalDialog.FileName;
end;
procedure TIRWindow.ClickWire(Sender:TObject);
begin
  if FWireDialog.Execute then FWire.Text:=FWireDialog.FileName;
end;
procedure TIRWindow.ClickRun(Sender:TObject);
begin
  Execute(FPhysical.Text,FWire.Text);
end;

{ Source та Wire — запозичені лише host-шляхи; дочірній FPC виконавець
  перевіряє pinned provenance EIR1 перед виконанням ОРИГІНАЛЬНОГО .sens.
  Out — власний повністю сформований T5M, Error — власні байти
  української діагностики. Жодного stdout у GUI до успіху ExitStatus=0.
  Питання: чому EIR1 не запускається як програма?
  Хто володіє накопиченими байтами? Що обмежує час/пам'ять процесу?
  Чому відмова після часткового pipe не стає успіхом? }
function TIRWindow.RunChecked(const Source,Wire:String;
  out PhysicalResult,Diagnostic:RawByteString):Boolean;
var P:TProcess; Buffer:array[0..4095] of Byte;
    Available,Got,Take:SizeInt; Deadline:QWord;
    Chunk:RawByteString;
  procedure Drain(Stream:TInputPipeStream;var Data:RawByteString;
    MaxBytes:SizeInt);
  begin
    Available:=Stream.NumBytesAvailable;
    while Available>0 do begin
      Take:=Available;
      if Take>SizeOf(Buffer) then Take:=SizeOf(Buffer);
      if Length(Data)+Take>MaxBytes then
        raise Exception.Create('порушено межу приватного процесного виводу');
      Got:=Stream.Read(Buffer,Take);
      if Got<=0 then Break;
      SetLength(Chunk,Got);
      Move(Buffer[0],Chunk[1],Got);
      Data:=Data+Chunk;
      Available:=Stream.NumBytesAvailable;
    end;
  end;
begin
  Result:=False; PhysicalResult:=''; Diagnostic:='';
  P:=TProcess.Create(nil);
  try
    P.Executable:=FRunner;
    P.CurrentDirectory:=GetCurrentDir;
    P.Parameters.Add('--перевірити-та-виконати');
    P.Parameters.Add(Source);
    P.Parameters.Add(Wire);
    P.Options:=[poUsePipes];
    P.Execute;
    Deadline:=GetTickCount64+10000;
    repeat
      Drain(P.Output,PhysicalResult,MAX_T5M_FILE_BYTES);
      Drain(P.Stderr,Diagnostic,MaxDiagnostic);
      if not P.Running then Break;
      if GetTickCount64>=Deadline then
        raise Exception.Create('перевищено час нативного EIR1-виконання');
      Sleep(5);
    until False;
    P.WaitOnExit;
    Drain(P.Output,PhysicalResult,MAX_T5M_FILE_BYTES);
    Drain(P.Stderr,Diagnostic,MaxDiagnostic);
    Result:=(P.ExitStatus=0) and (Length(PhysicalResult)>0) and
      (Length(Diagnostic)=0);
  finally
    if P.Running then begin P.Terminate(1); P.WaitOnExit; end;
    P.Free;
  end;
end;

{ Вже перевірені нативним виконавцем canonical T5M байти
  знову допускаються чинним DecodeT5M у власний масив слів.
  Людські поверхні D7 беруться тільки з pinned таблиці:
  uk/ukr/san/en/LISP/sym — не синтаксичні адреси виклику.
  Питання: чому числова D12 тут не обчислюється?
  Чи може SYN стати callable? Як зберігається ширина W7? }
procedure TIRWindow.RenderPhysical(const Physical:RawByteString);
const Names:array[0..5] of String=('ук','укр','san','en','LISP','sym');
var Words:TExactWords;I,J,K:SizeInt;Bits:String; Key:TDomainKey;
begin
  DecodeT5M(Physical,Words);
  Demand((Length(Words)>0) and (Length(Words)<=MaxVisibleWords),
    'надмірний результат для графічного огляду');
  Bits:='';
  for I:=0 to High(Words) do begin
    if I>0 then Bits:=Bits+' ';
    Bits:=Bits+String(Words[I]);
  end;
  FJournal.Lines.Add('Фізична відповідь: '+Bits);
  for I:=0 to High(Words) do if Length(Words[I])=7 then begin
    Key:=ExactKey(Words[I]);K:=Key.Bits;
    Demand((K>=0) and (K<Length(FCatalog[7])) and
      SameKey(Key,FCatalog[7][K].Key),'невідома D7 координата');
    FJournal.Lines.Add('D7:'+String(Words[I])+' — лише дані');
    for J:=0 to 5 do
      FJournal.Lines.Add(Names[J]+'='+
        SurfaceForDisplay(FCatalog[7][K].Surface[J]));
  end;
end;

procedure TIRWindow.Execute(const Source,Wire:String);
var Payload,Diagnostic:RawByteString; Words:TExactWords;
begin
  FLast:='';
  if (LowerCase(ExtractFileExt(Source))<>'.sens') or
     (LowerCase(ExtractFileExt(Wire))<>'.eir') then begin
    Inc(FRejected);
    FJournal.Lines.Add('Відхилено: потрібні двійкові .sens та EIR1 .eir');
    Exit;
  end;
  try
    if not RunChecked(Source,Wire,Payload,Diagnostic) then begin
      Inc(FRejected);
      FJournal.Lines.Add('Відхилено EIR1/виконання: '+
        String(Diagnostic));
      Exit;
    end;
    { Спробу декодувати відповідь робимо ДО публікації snapshot.
      Непідтримана кількість фізичних слів також не повинна залишати
      успішної часткової відповіді у журналі. }
    DecodeT5M(Payload,Words);
    Demand((Length(Words)>0) and (Length(Words)<=MaxVisibleWords),
      'недопустима фізична відповідь');
    FLast:=Payload;
    RenderPhysical(FLast);
    Inc(FSuccess);
    FStatus.Caption:='Виконано='+IntToStr(FSuccess)+
      '; відхилено='+IntToStr(FRejected)+
      '; EIR1=лише передумова';
  except on E:Exception do begin
    FLast:='';Inc(FRejected);
    FJournal.Lines.Add('Відхилено/пошкоджено: '+E.Message);
  end;end;
end;

{ Перевірка реально натискає LCL-кнопку сім разів, а не викликає
  метод RunChecked без UI. Фізичний очікуваний результат наданий
  НЕ текстовою проєкцією, а окремим packed T5M файлом. }
procedure TIRWindow.SelfCheck(const Good,GoodIR,Expected,
  D7,D7IR,ExpectedD7,WrongIR,Bad,BadIR,TextFile,MissingIR:String);
var F:TFileStream; Want,WantD7,Before:RawByteString;
  function Load(const Path:String):RawByteString;
  begin
    F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try SetLength(Result,F.Size); if Result<>'' then
      F.ReadBuffer(Result[1],Length(Result));finally F.Free;end;
  end;
begin
  Want:=Load(Expected);WantD7:=Load(ExpectedD7);
  Demand((Want<>'') and (WantD7<>''),'немає фізичних очікуваних значень');
  FPhysical.Text:=Good;FWire.Text:=GoodIR;FRun.Click;
  Demand((FSuccess=1) and (FLast=Want),
    'не виконано реальне D1 з EIR1');
  Before:=FLast;
  FPhysical.Text:=Good;FWire.Text:=WrongIR;FRun.Click;
  Demand((FRejected=1) and (FLast=''),'чужий EIR1 помилково прийнято');
  FPhysical.Text:=D7;FWire.Text:=D7IR;FRun.Click;
  Demand((FSuccess=2) and (FLast=WantD7) and
    (Pos('D7:0010110',FJournal.Text)>0) and
    (Pos('ук=(відсутня)',FJournal.Text)>0) and
    (Pos('LISP=(відсутня)',FJournal.Text)>0),
    'D7 SYN не показано як pinned дані');
  FPhysical.Text:=Bad;FWire.Text:=BadIR;FRun.Click;
  Demand((FRejected=2) and (FLast=''),'пошкоджені T5M/EIR1 не відхилено');
  FPhysical.Text:=TextFile;FWire.Text:=GoodIR;FRun.Click;
  Demand((FRejected=3) and (FLast='') and
    (Pos('потрібні двійкові .sens',FJournal.Text)>0),
    'текстовий .lisp прийнято як фізичну форму');
  FPhysical.Text:=Good;FWire.Text:=MissingIR;FRun.Click;
  Demand((FRejected=4) and (FLast=''),
    'відсутній EIR1 не відхилено');
  FPhysical.Text:=Good;FWire.Text:=GoodIR;FRun.Click;
  Demand((FSuccess=3) and (FRejected=4) and (FLast=Before),
    'немає відновлення точного T5M після чотирьох відмов');
  WriteLn('ЛКЛ-ПЕРЕВІРЕНИЙ-IR-ГАРАЗД Lazarus=GTK2',
    ' кліків=7 виконано=3 відхилено=4',
    ' EIR1=до-виконання T5M=байт-в-байт D7=SYN',
    ' проєкцій=6 IR-compiler=НЕ-ГОТОВИЙ REPL=НЕ-ГОТОВИЙ');
end;

begin
  Application.Initialize;
  Window:=TIRWindow.Create(nil);
  try
    if (ParamCount=13) and (ParamStr(1)='--самоперевірка') then begin
      Window.Connect(ParamStr(2));
      Window.SelfCheck(ParamStr(3),ParamStr(4),ParamStr(5),
        ParamStr(6),ParamStr(7),ParamStr(8),ParamStr(9),
        ParamStr(10),ParamStr(11),ParamStr(12),ParamStr(13));
    end else if ParamCount=0 then begin
      Window.Connect('build/m0.2/bin/sensirvykon');
      Window.Show;Application.Run;
    end else
      raise Exception.Create('використання: --самоперевірка runner .sens .eir очікувано.sens D7.sens D7.eir очікувано-D7.sens чужий.eir поганий.sens поганий.eir текст.lisp відсутній.eir');
  except on E:Exception do begin
    WriteLn(StdErr,'ЛКЛ-ПЕРЕВІРЕНИЙ-IR-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end;end;
  Window.Free;
end.
