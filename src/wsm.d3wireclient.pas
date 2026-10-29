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
{ Суворий механічний admission пари T5M кадрів:
  запит і відповідь мають рівно 1..64 цілі D2 корені, кількість
  відповідає кількості запиту. Не здійснює SENS обчислення. }
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
procedure ValidateD3WireReply(const Request,Reply:RawByteString);
implementation
uses wsm.t5m, wsm.d2source;


{ Request/Reply — borrowed packed T5M RawByteString; decoded Words are owned
  locally, DocIn/DocOut own their D2 AST and are always freed. No authority
  names or spellings are consulted. This guards physical protocol only. }
procedure ValidateD3WireReply(const Request,Reply:RawByteString);
var
  Words:TExactWords;
  DocIn,DocOut:TD2Document;
  Expected:SizeInt;

  function ReadCheckedRoots(const Physical:RawByteString;
    const Role:String):TD2Document;
  begin
    Result:=nil;
    if (Length(Physical)<1) or (Length(Physical)>MaxD3WireBytes) then
      raise ED3WireError.Create(Role+': фізична довжина поза межею');
    try
      DecodeT5M(Physical,Words);
      if (Length(Words)<1) or (EncodeT5M(Words)<>Physical) then
        raise ED3WireError.Create(Role+': неканонічний T5M');
      Result:=ParseD2WordsWide(Words);
    except
      on E:ED2SourceError do
        raise ED3WireError.Create(Role+': некоректна D2 структура слово='+
          IntToStr(E.WordIndex)+': '+E.Message);
      on E:ET5MError do
        raise ED3WireError.Create(Role+': недопустимі фізичні байти T5M: '+
          E.Message);
    end;
  end;
begin
  DocIn:=nil;DocOut:=nil;
  try
    DocIn:=ReadCheckedRoots(Request,'запит');
    Expected:=Length(DocIn.Roots);
    if (Expected<1) or (Expected>64) then
      raise ED3WireError.Create('запит: потрібно 1..64 незалежних коренів D2');
    DocOut:=ReadCheckedRoots(Reply,'відповідь');
    if Length(DocOut.Roots)<>Expected then
      raise ED3WireError.Create('відповідь: кількість коренів D2 '+
        IntToStr(Length(DocOut.Roots))+' не збігається із запитом '+
        IntToStr(Expected));
  finally
    DocOut.Free;
    DocIn.Free;
  end;
end;

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
  { Навіть канонічні T5M байти можуть містити обірвану D2 форму,
    або повернути неповне число коренів. Не публікуємо такий успіх. }
  ValidateD3WireReply(Physical,Payload);
  Result:=Payload;
end;

{ Типи та життя: Physical borrowed RawByteString, Payload owned локально,
  TExactWords owned локально; TProcess owned клієнтом, звільняється в Destroy.
  Status/u32le — тільки host framing; результат — канонічний packed T5M
  із повною D2 структурою та точною кількістю коренів.
  Питання: 1) Чому однакові біти W1 і D1 не є автоматично тотожністю?
  2) Чому помилка не перетворюється на порожній успішний .sens?
  3) Хто встановлює закон виклику D3?
  4) Чому українська .lisp не є byte stream цього каналу?
  5) Чому один PID не означає повний REPL зі станом визначень? }
end.
