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
    FUsable:Boolean; { irreversible false після фізичного збою pipe }
    procedure PoisonChannel;
    procedure ReadExact(var Buffer; Count:SizeInt);
  public
    constructor Create(const ExecutablePath,AuthorityRoot:String);
    destructor Destroy; override;
    function Execute(const Physical:RawByteString):RawByteString;
    function ProcessID:Int64;
  end;
procedure ValidateD3WireReply(const Request,Reply:RawByteString);
{ Локальний preflight до будь-яких записів у pipe; лише канонічні
  фізичні T5M/D2 з 1..64 коренями, без мовного dispatch. }
procedure ValidateD3WireRequest(const Physical:RawByteString);
implementation
uses wsm.t5m, wsm.d2source;


{ Повертаємо тільки host SizeInt кількості повних top-level D2 коренів.
  Frame — borrowed канонічний packed T5M, Words — локальні managed
  exact слова, Doc — owned дерево, звільнене у try/finally. Декодер
  і reader ОДНІ існуючі; жодного SENS eval чи D12+ припущень. }
function CountD3WireRoots(const Frame:RawByteString;
  const Role:String):SizeInt;
var Words:TExactWords;Doc:TD2Document;
begin
  Result:=0;
  Doc:=nil;
  if (Length(Frame)<1) or (Length(Frame)>MaxD3WireBytes) then
    raise ED3WireError.Create(Role+': фізична довжина поза межею');
  try
    try
      DecodeT5M(Frame,Words);
      if (Length(Words)<1) or (EncodeT5M(Words)<>Frame) then
        raise ED3WireError.Create(Role+': неканонічний T5M');
      Doc:=ParseD2WordsWide(Words);
      Result:=Length(Doc.Roots);
    except
      on E:ED2SourceError do
        raise ED3WireError.Create(Role+': некоректна D2 структура слово='+
          IntToStr(E.WordIndex)+': '+E.Message);
      on E:ET5MError do
        raise ED3WireError.Create(Role+': недопустимі фізичні байти T5M: '+
          E.Message);
    end;
  finally
    Doc.Free;
  end;
end;

{ ЖОДНОГО запису FProcess.Input до цього admission.
  D2 кількість коренів — private host quota, не числовий закон. }
procedure ValidateD3WireRequest(const Physical:RawByteString);
var Roots:SizeInt;
begin
  Roots:=CountD3WireRoots(Physical,'запит');
  if (Roots<1) or (Roots>64) then
    raise ED3WireError.Create('запит: потрібно 1..64 незалежних коренів D2');
end;

{ Postflight зберігає окремий захист reply: канонічний T5M, D2
  цілісний, число відповідей точно дорівнює кількості запитів.
  Відмови не оприлюднюють Payload. }
procedure ValidateD3WireReply(const Request,Reply:RawByteString);
var Expected,Actual:SizeInt;
begin
  Expected:=CountD3WireRoots(Request,'запит');
  if (Expected<1) or (Expected>64) then
    raise ED3WireError.Create('запит: потрібно 1..64 незалежних коренів D2');
  Actual:=CountD3WireRoots(Reply,'відповідь');
  if Actual<>Expected then
    raise ED3WireError.Create('відповідь: кількість коренів D2 '+
      IntToStr(Actual)+' не збігається із запитом '+
      IntToStr(Expected));
end;

constructor TD3WireClient.Create(const ExecutablePath,AuthorityRoot:String);
begin
  inherited Create;
  FProcess:=nil;
  FUsable:=False;
  if (ExecutablePath='') or (AuthorityRoot='') then
    raise ED3WireError.Create('Потрібні виконуваний D3-канал та pinned SENS');
  FProcess:=TProcess.Create(nil);
  try
    FProcess.Executable:=ExecutablePath;
    FProcess.Options:=[poUsePipes];
    FProcess.Parameters.Add('--канал');
    FProcess.Parameters.Add(AuthorityRoot);
    FProcess.Execute;
    FUsable:=True;
  except
    FreeAndNil(FProcess);
    raise;
  end;
end;

{ Host-канал після неповного/пошкодженого reply не має надійної
  межі наступного кадру. FUsable=false встановлюється ПЕРШИМ;
  навіть збій OS cleanup не дозволяє новий WriteBuffer. Дочірній
  TProcess належить TD3WireClient, не є lexical environment SENS. }
procedure TD3WireClient.PoisonChannel;
begin
  FUsable:=False;
  if FProcess<>nil then
    try
      if FProcess.Running then begin
        FProcess.Terminate(0);
        FProcess.WaitOnExit;
      end;
    except on E:Exception do begin
      { Не приховуємо первинну помилку wire reply помилкою cleanup. }
    end end;
end;

destructor TD3WireClient.Destroy;
begin
  PoisonChannel;
  FreeAndNil(FProcess);
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
  if not FUsable then
    raise ED3WireError.Create('D3: фізичний канал недоступний після пошкодження');
  { G5.49: весь канонічний D2 + 1..64 корені ДО першого write.
    Ніякого remote side effect на неповних чи зіпсованих формах. }
  ValidateD3WireRequest(Physical);
  if (FProcess=nil) or (not FProcess.Running) then begin
    PoisonChannel;
    raise ED3WireError.Create('Постійний D3-канал завершився');
  end;
  N:=LongWord(Length(Physical));
  H[0]:=Byte(N and $ff);
  H[1]:=Byte((N shr 8) and $ff);
  H[2]:=Byte((N shr 16) and $ff);
  H[3]:=Byte((N shr 24) and $ff);
  { Від першого байта write — фізична транзакція у pipe. Лише
    завершений bounded remote status=1 є відновлюваною відмовою.
    Будь-який інший exception (включно з bad T5M/D2 та read EOF)
    незворотно отруює саме ЦЕЙ PID, без повторної синхронізації. }
  try
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
    try
      DecodeT5M(Payload,Words);
    except on E:ET5MError do
      raise ED3WireError.Create('Дочірній D3-канал повернув пошкоджений T5M: '+
        E.Message);
    end;
    if (Length(Words)=0) or (EncodeT5M(Words)<>Payload) then
      raise ED3WireError.Create('Дочірній D3-канал повернув неканонічний T5M');
    { Навіть канонічний reply може не мати цілісної D2 форми. }
    ValidateD3WireReply(Physical,Payload);
    Result:=Payload;
  except
    on E:ED3RemoteError do raise; { штатна semantic відмова: 1 PID }
    on E:Exception do begin
      PoisonChannel;
      if E is ED3WireError then raise;
      raise ED3WireError.Create('D3: пошкоджена фізична відповідь: '+E.Message);
    end;
  end;
end;

{ Типи та життя: Physical borrowed RawByteString, Payload owned локально,
  TExactWords owned локально; TProcess owned клієнтом, PoisonChannel
  завершує child і Destroy звільняє handle; FUsable host Boolean.
  Status/u32le — тільки host framing; результат — канонічний packed T5M
  із повною D2 структурою та точною кількістю коренів.
  Питання: 1) Чому однакові біти W1 і D1 не є автоматично тотожністю?
  2) Чому помилка не перетворюється на порожній успішний .sens?
  3) Хто встановлює закон виклику D3?
  4) Чому українська .lisp не є byte stream цього каналу?
  5) Чому один PID не означає повний REPL зі станом визначень? }
end.
