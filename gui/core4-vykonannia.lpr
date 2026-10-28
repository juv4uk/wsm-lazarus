{ G4.9 — справжнє вікно виконання вузького pinned Core4 binary.
  Мовні закони належать SENS; усе виконання делегується TCore4Runtime.
  Людський .lisp тут не приймається за канонічну програму. }
program core4_vykonannia;
{$mode objfpc}{$H+}{$codepage utf8}
uses Interfaces, Forms, Classes, SysUtils, Controls, StdCtrls, Dialogs,
  wsm.core4runtime, wsm.t5m;
const MaxCallBytes=1024*1024;
type
  TCore4Window=class(TForm)
  private
    FRuntime:TCore4Runtime;
    FOpen:TButton;
    FDialog:TOpenDialog;
    FStatus,FFile,FAnswer:TLabel;
    FResultBits:RawByteString;
    procedure OpenClick(Sender:TObject);
    procedure ClearResult;
    procedure Need(Condition:Boolean;const Why:String);
    procedure SavePhysical(const Path:String;const Data:RawByteString);
    function MakeCall(const Id,Arg:RawByteString;IncludeArg:Boolean=True):RawByteString;
    function MakeIdentifier(const Id:RawByteString):RawByteString;
  public
    constructor Create(AOwner:TComponent);override;
    destructor Destroy;override;
    function LoadAuthority(const Root:String):Boolean;
    function ExecuteFile(const Path:String):Boolean;
    procedure SelfCheck(const Root,TempDir:String);
  end;
var Window:TCore4Window;

constructor TCore4Window.Create(AOwner:TComponent);
var Note:TLabel;
begin
  inherited CreateNew(AOwner,1);
  Caption:='SENS — виконання початкового Core4';
  Width:=780; Height:=300; Position:=poScreenCenter;
  FRuntime:=nil;
  FOpen:=TButton.Create(Self); FOpen.Parent:=Self;
  FOpen.SetBounds(14,14,340,38);
  FOpen.Caption:='Виконати двійковий файл .sens';
  FOpen.OnClick:=@OpenClick; FOpen.Enabled:=False;
  FDialog:=TOpenDialog.Create(Self);
  FDialog.Title:='Фізична програма SENS';
  FDialog.Filter:='Двійковий SENS (*.sens)|*.sens';
  FFile:=TLabel.Create(Self); FFile.Parent:=Self;
  FFile.SetBounds(14,66,742,26); FFile.Caption:='Файл не вибрано';
  FAnswer:=TLabel.Create(Self); FAnswer.Parent:=Self;
  FAnswer.SetBounds(14,105,742,35); FAnswer.Caption:='';
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Self;
  FStatus.SetBounds(14,148,742,54);
  FStatus.AutoSize:=False; FStatus.WordWrap:=True;
  Note:=TLabel.Create(Self); Note.Parent:=Self;
  Note.SetBounds(14,222,742,45);
  Note.AutoSize:=False; Note.WordWrap:=True;
  Note.Caption:='Лише перші три визначення pinned core4.sens. '+
    'Результат — точні біти, не десяткове число D12+; '+
    'це не повний Core4, не REPL і не семантичний oracle.';
  ClearResult;
end;

destructor TCore4Window.Destroy;
begin
  FRuntime.Free;
  inherited Destroy;
end;

procedure TCore4Window.ClearResult;
begin
  FResultBits:='';
  FAnswer.Caption:='';
  FFile.Caption:='Файл не вибрано';
  FStatus.Caption:='Немає виконаного фізичного виклику.';
end;

procedure TCore4Window.Need(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('перевірка Lazarus Core4: '+Why);
end;

function TCore4Window.LoadAuthority(const Root:String):Boolean;
var Candidate:TCore4Runtime;
begin
  Result:=False;
  ClearResult;
  FreeAndNil(FRuntime);
  FOpen.Enabled:=False;
  Candidate:=nil;
  try
    Candidate:=TCore4Runtime.Create(Root);
    if Candidate.BindingCount<>3 then
      raise Exception.Create('очікувалися три перевірені початкові визначення');
    FRuntime:=Candidate;
    Candidate:=nil;
    FOpen.Enabled:=True;
    FStatus.Caption:='Pinned Core4: завантажено три початкові визначення.';
    Result:=True;
  except on E:Exception do begin
    FStatus.Caption:='Core4 не завантажено: '+E.Message;
  end end;
  Candidate.Free;
end;

function TCore4Window.ExecuteFile(const Path:String):Boolean;
var Stream:TFileStream; Physical,Answer:RawByteString;
    Words:TExactWords;
begin
  Result:=False;
  ClearResult;
  try
    if FRuntime=nil then raise Exception.Create('спочатку потрібен pinned Core4');
    if LowerCase(ExtractFileExt(Path))<>'.sens' then
      raise Exception.Create('виконуються лише фізичні .sens');
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MaxCallBytes) then
        raise Exception.Create('файл порожній або завеликий');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    { Єдиний виконавець мовних форм — уже перевірений Core4 runtime. }
    Answer:=FRuntime.ExecutePhysicalCall(Physical);
    DecodeT5M(Answer,Words);
    if (Length(Words)<>1) or (EncodeT5M(Words)<>Answer) then
      raise Exception.Create('невідомий формат фізичної відповіді');
    FResultBits:=Words[0];
    FFile.Caption:='Виконано файл: '+ExtractFileName(Path);
    FAnswer.Caption:='Результат: D'+IntToStr(Length(FResultBits))+
      ' · '+String(FResultBits);
    FStatus.Caption:='Фізичне виконання одного підтриманого Core4-виклику; '+
      'жодного текстового семантичного dispatch.';
    Result:=True;
  except on E:Exception do begin
    ClearResult;
    FStatus.Caption:='Відмова виконання: '+E.Message;
  end end;
end;

procedure TCore4Window.OpenClick(Sender:TObject);
begin
  if FDialog.Execute then ExecuteFile(FDialog.FileName);
end;

procedure TCore4Window.SavePhysical(const Path:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then Stream.WriteBuffer(Data[1],Length(Data));
  finally Stream.Free end;
end;

function TCore4Window.MakeCall(const Id,Arg:RawByteString;
  IncludeArg:Boolean):RawByteString;
var Words:TExactWords; I,N:SizeInt;
begin
  if (Length(Id)=0) or ((Length(Id) mod 7)<>0) then
    raise Exception.Create('некоректний фізичний D7-ідентифікатор');
  SetLength(Words,Length(Id) div 7+5);
  N:=0;Words[N]:='10';Inc(N);Words[N]:='10';Inc(N);
  for I:=0 to (Length(Id) div 7)-1 do begin
    Words[N]:=Copy(Id,I*7+1,7);Inc(N);
  end;
  Words[N]:='01';Inc(N);
  if IncludeArg then begin Words[N]:=Arg;Inc(N) end;
  Words[N]:='01';Inc(N);SetLength(Words,N);
  Result:=EncodeT5M(Words);
end;

function TCore4Window.MakeIdentifier(const Id:RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  if (Length(Id)=0) or ((Length(Id) mod 7)<>0) then
    raise Exception.Create('некоректне фізичне ім’я');
  SetLength(Words,Length(Id) div 7+2);
  Words[0]:='10';
  for I:=0 to (Length(Id) div 7)-1 do
    Words[I+1]:=Copy(Id,I*7+1,7);
  Words[High(Words)]:='01';
  Result:=EncodeT5M(Words);
end;

procedure TCore4Window.SelfCheck(const Root,TempDir:String);
var Id,Path:RawByteString;
begin
  Need(LoadAuthority(Root),'завантаження справжнього pinned core4.sens');
  Id:=FRuntime.FirstDefinitionIdentifier;
  Need(Length(Id)>0,'точне ім’я із pinned Core4');
  Path:=IncludeTrailingPathDelimiter(TempDir)+'виклик.sens';
  SavePhysical(String(Path),MakeCall(Id,'1'));
  Need(ExecuteFile(String(Path)) and (FResultBits='1'),
    'реальне виконання D1:1');
  SavePhysical(String(Path),MakeCall(Id,'0'));
  Need(ExecuteFile(String(Path)) and (FResultBits='0'),
    'повторний виклик D1:0 у тому самому runtime');
  SavePhysical(String(Path),MakeCall(Id,'000000000000000000000001'));
  Need(ExecuteFile(String(Path)) and
    (FResultBits='000000000000000000000001'),
    'точний opaque D24:1 через замикання');
  SavePhysical(String(Path),MakeIdentifier(FRuntime.BindingIdentifier(2)));
  Need(ExecuteFile(String(Path)) and
    (FResultBits='000000000000000000000001'),
    'читання реального pinned D24-глобала');
  SavePhysical(String(Path),MakeCall(Id,'',False));
  Need(not ExecuteFile(String(Path)) and (FResultBits='') and
    (FAnswer.Caption=''),'відмова за неправильною арністю очищає результат');
  SavePhysical(String(Path),Chr(243));
  Need(not ExecuteFile(String(Path)) and (FResultBits=''),
    'зіпсований фізичний T5M не дає відповіді');
  SavePhysical(String(Path),'');
  Need(not ExecuteFile(String(Path)) and (FResultBits=''),
    'порожній фізичний файл не дає відповіді');
  SavePhysical(IncludeTrailingPathDelimiter(TempDir)+'людський.lisp',
    MakeCall(Id,'1'));
  Need(not ExecuteFile(IncludeTrailingPathDelimiter(TempDir)+'людський.lisp'),
    'людський .lisp не є фізичним викликом');
  Need(not ExecuteFile(IncludeTrailingPathDelimiter(TempDir)+'немає.sens'),
    'відсутній файл відхилено');
  SavePhysical(String(Path),MakeCall(Id,'1'));
  Need(ExecuteFile(String(Path)) and (FResultBits='1'),
    'відновлення після помилок у тій самій LCL-сесії');
  WriteLn('LCL-CORE4-ГАРАЗД Lazarus=GTK2 pinned=core4.sens ',
    'визначень=3 викликів=5 відмов=4 відновлення=так ',
    'D24=точні-біти REPL=ні');
end;

begin
  Application.Initialize;
  Application.Title:='SENS — виконання початкового Core4';
  Application.CreateForm(TCore4Window,Window);
  if (ParamCount>0) and (ParamStr(1)='--самоперевірка') then begin
    if ParamCount<>3 then Halt(64);
    try
      Window.Show;Application.ProcessMessages;
      Window.SelfCheck(ParamStr(2),ParamStr(3));
    except on E:Exception do begin
      WriteLn(StdErr,'LCL-CORE4-ПОМИЛКА ',E.Message);
      Halt(1);
    end end;
  end else begin
    if ParamCount=0 then Window.LoadAuthority(GetCurrentDir)
    else Window.LoadAuthority(ParamStr(1));
    Application.Run;
  end;
end.