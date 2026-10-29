{ G5.30 — тривалий host-клієнт до чинного Core4 binary channel.
  Статусні кадри НЕ є канонічним .sens і НЕ породжують мовних законів.
  Точні імена — ЛИШЕ повні 7-бітові D7 слова pinned Core4.
  Клієнт не вирішує, яка D7 форма семантично допустима:
  це робить фактичний дочірній TCore4Runtime. }
unit wsm.core4wireclient;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, Classes, Process;
const MaxCore4WireBytes=1024*1024;
type
  ECore4WireError=class(Exception);
  ECore4RemoteError=class(ECore4WireError);
  TCore4WireClient=class
  private
    FProcess:TProcess;          { owned, один дитячий процес на об'єкт }
    FBatch:Boolean;
    procedure ReadExact(var Buf; N:SizeInt);
  public
    constructor Create(const ExecutablePath,RepoRoot:String; Batch:Boolean=False);
    destructor Destroy;override;
    function Execute(const Physical:RawByteString):RawByteString;
    function ProcessID:Int64;
  end;

{ МЕХАНІЧНА D2 оболонка exact D7 (7 біт на гліф, 1..256 гліфів).
  Result — канонічні байти T5M; жодного декодера українських назв. }
function PhysicalD7Name(const Bits:RawByteString):RawByteString;
function PhysicalD7Call(const Bits,ArgumentBits:RawByteString):RawByteString;

{ Механічний допуск вже ОТРИМАНОЇ фізичної відповіді: T5M, D2
  та рівно одна відповідь на одну кореневу форму. Batch — host-режим,
  а не SENS закон. Не вирішує семантику виконання чи D7-викличність. }
procedure ValidateCore4WireReply(const Request,Reply:RawByteString;
  Batch:Boolean);

implementation
uses wsm.t5m, wsm.d2source;

{ Borrowed фізичні T5M кадри; Words/Document — локально власні.
  Парсер із pinned D2-правил дає точний 1-based WordIndex при відмові.
  Ні проєкцій ук/укр, ні англійських імен, ні арифметики D12+ тут нема. }
procedure ValidateCore4WireReply(const Request,Reply:RawByteString;
  Batch:Boolean);
var Expected,Actual:SizeInt;

  function CheckedRoots(const Frame:RawByteString;const Role:String):SizeInt;
  var Words:TExactWords; Doc:TD2Document;
  begin
    Result:=0; Doc:=nil;
    if (Length(Frame)<1) or (Length(Frame)>MaxCore4WireBytes) then
      raise ECore4WireError.Create(Role+': фізичний кадр поза 1..1 МіБ');
    try
      DecodeT5M(Frame,Words);
      if (Length(Words)<1) or (EncodeT5M(Words)<>Frame) then
        raise ECore4WireError.Create(Role+': неканонічний T5M');
      Doc:=ParseD2WordsWide(Words);
      Result:=Length(Doc.Roots);
    except
      on E:ED2SourceError do
        raise ECore4WireError.Create(Role+': некоректний D2 слово=' +
          IntToStr(E.WordIndex)+': '+E.Message);
      on E:ET5MError do
        raise ECore4WireError.Create(Role+': некоректні байти T5M: '+
          E.Message);
    finally
      Doc.Free;
    end;
  end;
begin
  Expected:=CheckedRoots(Request,'запит');
  if (Expected<1) or (Expected>64) or ((not Batch) and (Expected<>1)) then
    raise ECore4WireError.Create('запит: single=1 або batch=1..64 коренів D2');
  Actual:=CheckedRoots(Reply,'відповідь');
  if Actual<>Expected then
    raise ECore4WireError.Create('відповідь: D2 коренів='+IntToStr(Actual)+
      ', у запиті='+IntToStr(Expected));
end;

procedure ValidateD7(const Bits:RawByteString);
var I:SizeInt;
begin
  if (Length(Bits)<7) or (Length(Bits)>7*256) or
     (Length(Bits) mod 7<>0) then
    raise ECore4WireError.Create('D7: очікується 1..256 повних семибітних слів');
  for I:=1 to Length(Bits) do
    if (Bits[I]<>'0') and (Bits[I]<>'1') then
      raise ECore4WireError.Create('D7: ідентифікатор має лише точні біти 0/1');
end;

function D7Words(const Bits:RawByteString):TExactWords;
var I,N:SizeInt;
begin
  ValidateD7(Bits);
  N:=Length(Bits) div 7;
  SetLength(Result,N+2);
  Result[0]:='10';
  for I:=0 to N-1 do Result[I+1]:=Copy(Bits,I*7+1,7);
  Result[N+1]:='01';
end;

function PhysicalD7Name(const Bits:RawByteString):RawByteString;
begin
  Result:=EncodeT5M(D7Words(Bits));
end;

function PhysicalD7Call(const Bits,ArgumentBits:RawByteString):RawByteString;
var W,Id:TExactWords;I,N:SizeInt;
begin
  { ArgumentBits — одне opaque exact слово. Значення/домен не вгадувати. }
  if Length(ArgumentBits)<1 then
    raise ECore4WireError.Create('порожнє фізичне слово аргументу');
  for I:=1 to Length(ArgumentBits) do
    if not (ArgumentBits[I] in ['0','1']) then
      raise ECore4WireError.Create('аргумент має бути точними двійковими бітами');
  Id:=D7Words(Bits);
  N:=Length(Id);
  SetLength(W,N+3);
  W[0]:='10';
  for I:=0 to N-1 do W[I+1]:=Id[I];
  W[N+1]:=ArgumentBits;
  W[N+2]:='01';
  Result:=EncodeT5M(W);
end;

constructor TCore4WireClient.Create(const ExecutablePath,RepoRoot:String;
  Batch:Boolean);
begin
  inherited Create;
  FProcess:=nil;
  FBatch:=Batch;
  if (ExecutablePath='') or (RepoRoot='') then
    raise ECore4WireError.Create('бракує шляху host-каналу чи authority');
  FProcess:=TProcess.Create(nil);
  try
    FProcess.Executable:=ExecutablePath;
    FProcess.Options:=[poUsePipes];
    if Batch then FProcess.Parameters.Add('--канал-пакет')
    else FProcess.Parameters.Add('--канал');
    FProcess.Parameters.Add(RepoRoot);
    FProcess.Execute;
  except
    FreeAndNil(FProcess);
    raise;
  end;
end;

destructor TCore4WireClient.Destroy;
begin
  if FProcess<>nil then begin
    { Життєвий цикл належить клієнту; не лишати підвішений REPL-процес.
      Закриття/kill — host-механізм, не стан SENS. }
    if FProcess.Running then begin
      FProcess.Terminate(0);
      FProcess.WaitOnExit;
    end;
    FreeAndNil(FProcess);
  end;
  inherited Destroy;
end;

function TCore4WireClient.ProcessID:Int64;
begin
  if FProcess=nil then Result:=-1
  else Result:=Int64(FProcess.ProcessID);
end;

procedure TCore4WireClient.ReadExact(var Buf;N:SizeInt);
var P:PByte;Got,Total:SizeInt;
begin
  P:=@Buf;Total:=0;
  while Total<N do begin
    Got:=FProcess.Output.Read(P[Total],N-Total);
    if Got<=0 then
      raise ECore4WireError.Create('дочірній канал обірвав фізичну відповідь');
    Inc(Total,Got);
  end;
end;

function TCore4WireClient.Execute(const Physical:RawByteString):RawByteString;
var
  W:TExactWords;
  H:array[0..4] of Byte;
  N:LongWord;
  Status:Byte;
  Payload:RawByteString;
begin
  Result:='';
  if (Length(Physical)<1) or (Length(Physical)>MaxCore4WireBytes) then
    raise ECore4WireError.Create('фізичний запит поза межею 1..1 МіБ');
  { Локальний preflight перевіряє ТІЛЬКИ транспорт; remote вирішує
    допустимість повного D7 ключа/виклику з pinned SENS. }
  DecodeT5M(Physical,W);
  if (Length(W)<1) or (EncodeT5M(W)<>Physical) then
    raise ECore4WireError.Create('неканонічний T5M у запиті');
  if (FProcess=nil) or (not FProcess.Running) then
    raise ECore4WireError.Create('постійний канал завершився');
  N:=LongWord(Length(Physical));
  H[0]:=Byte(N and $ff);
  H[1]:=Byte((N shr 8) and $ff);
  H[2]:=Byte((N shr 16) and $ff);
  H[3]:=Byte((N shr 24) and $ff);
  FProcess.Input.WriteBuffer(H,4);
  FProcess.Input.WriteBuffer(Physical[1],N);
  ReadExact(H,5);
  Status:=H[0];
  N:=LongWord(H[1]) or (LongWord(H[2]) shl 8) or
    (LongWord(H[3]) shl 16) or (LongWord(H[4]) shl 24);
  if (Status>1) or (N<1) or (N>MaxCore4WireBytes) then
    raise ECore4WireError.Create('пошкоджений заголовок відповіді Core4');
  SetLength(Payload,N);
  ReadExact(Payload[1],N);
  if Status=1 then
    raise ECore4RemoteError.Create(String(Payload));
  DecodeT5M(Payload,W);
  if (Length(W)<1) or (EncodeT5M(W)<>Payload) or
    ((not FBatch) and (Length(W)<>1)) or
    (FBatch and (Length(W)>64)) then
    raise ECore4WireError.Create('неканонічна фізична відповідь Core4');
  { Після transport preflight тільки повна D2 структура й число коренів
    можуть дозволити оприлюднити Result. Status=1 вище залишається
    окремою host-діагностикою, не фізичним SENS-значенням. }
  ValidateCore4WireReply(Physical,Payload,FBatch);
  Result:=Payload;
end;
end.
