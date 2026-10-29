{ G5.35: постійний фізичний D3-канал, незалежний від Core4.
  Host-рамка НЕ є мовою SENS. Закони виконує тільки pinned D3 backend
  у дочірньому senspotikd3 --канал. }
unit wsm.d3wireclient;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, Classes, Process;
const MaxD3WireBytes=65536; { приватна транспортна квота, НЕ домен D12 }
type
  ED3WireError=class(Exception);
  ED3RemoteError=class(ED3WireError);
  TD3WireClient=class
  private
    FProcess:TProcess; { owned: рівно один дочірній FPC процес }
    procedure ReadExact(var Buffer; Count:SizeInt);
  public
    constructor Create(const ExecutablePath,AuthorityRoot:String);
    destructor Destroy; override;
    function Execute(const Physical:RawByteString):RawByteString;
    function ProcessID:Int64;
  end;
implementation
uses wsm.t5m;

constructor TD3WireClient.Create(const ExecutablePath,AuthorityRoot:String);
begin
  inherited Create;
  FProcess:=nil;
  if (ExecutablePath='') or (AuthorityRoot='') then
    raise ED3WireError.Create('Потрібні виконуваний D3-канал та pinned SENS');
  FProcess:=TProcess.Create(nil);
  try
    FProcess.Executable:=ExecutablePath;
    FProcess.Options:=[poUsePipes];
    FProcess.Parameters.Add('--канал');
    FProcess.Parameters.Add(AuthorityRoot);
    FProcess.Execute;
  except
    FreeAndNil(FProcess);
    raise;
  end;
end;

destructor TD3WireClient.Destroy;
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

function TD3WireClient.ProcessID:Int64;
begin
  if FProcess=nil then Result:=-1
  else Result:=Int64(FProcess.ProcessID);
end;

procedure TD3WireClient.ReadExact(var Buffer;Count:SizeInt);
var P:PByte; Got,Done:SizeInt;
begin
  P:=@Buffer; Done:=0;
  while Done<Count do begin
    Got:=FProcess.Output.Read(P[Done],Count-Done);
    if Got<=0 then
      raise ED3WireError.Create('Дочірній D3-канал обірвав відповідь');
    Inc(Done,Got);
  end;
end;

function TD3WireClient.Execute(const Physical:RawByteString):RawByteString;
var H:array[0..4] of Byte; N:LongWord; Status:Byte;
  Payload:RawByteString; Words:TExactWords;
begin
  Result:='';
  if (Length(Physical)<1) or (Length(Physical)>MaxD3WireBytes) then
    raise ED3WireError.Create('Фізичний запит поза host-межею 1..65536 байтів');
  DecodeT5M(Physical,Words);
  if (Length(Words)=0) or (EncodeT5M(Words)<>Physical) then
    raise ED3WireError.Create('Запит не є канонічним T5M');
  if (FProcess=nil) or (not FProcess.Running) then
    raise ED3WireError.Create('Постійний D3-канал завершився');
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
  if (Status>1) or (N<1) or (N>MaxD3WireBytes) or
     ((Status=1) and (N>4096)) then
    raise ED3WireError.Create('Непридатний host-заголовок відповіді');
  SetLength(Payload,N);
  ReadExact(Payload[1],N);
  if Status=1 then
    raise ED3RemoteError.Create(String(Payload));
  DecodeT5M(Payload,Words);
  if (Length(Words)=0) or (EncodeT5M(Words)<>Payload) then
    raise ED3WireError.Create('Дочірній D3-канал повернув неканонічний T5M');
  Result:=Payload;
end;

{ Типи та життя: Physical borrowed RawByteString, Payload owned локально,
  TExactWords owned локально; TProcess owned клієнтом, звільняється в Destroy.
  Status/u32le — тільки host framing; результат — канонічний packed T5M.
  Питання: 1) Чому однакові біти W1 і D1 не є автоматично тотожністю?
  2) Чому помилка не перетворюється на порожній успішний .sens?
  3) Хто встановлює закон виклику D3?
  4) Чому українська .lisp не є byte stream цього каналу?
  5) Чому один PID не означає повний REPL зі станом визначень? }
end.
