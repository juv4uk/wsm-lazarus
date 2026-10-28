{ G5.3 transport framing for an already existing native session.
  Wire format: u32 little-endian byte length + exactly that many raw bytes.
  This is a PRIVATE host transport, NOT a canonical SENS .sens format,
  SENS D2 syntax, a language evaluator, or a functioning SENS REPL.
  One packet is passed byte-for-byte to TNativeSession.Submit.
  The session is borrowed (caller owns its lifetime). }
unit wsm.sessionwire;
{$mode objfpc}{$H+}
{$codepage utf8}
interface
uses SysUtils, wsm.session;

const
  MaxWirePayload = 16 * 1024 * 1024;
  MaxQueuedBatches = 64;       { межа очікування без Drain }
  MaxConfiguredBatches = 1024; { захист від безмежної черги }
  MaxQueuedInputBytes = 16 * 1024 * 1024; { бюджет непрочитаних джерел }
  MaxConfiguredInputBytes = 64 * 1024 * 1024;
  MaxQueuedReplyBytes = 16 * 1024 * 1024; { вихідні Output + Diagnostic }
  MaxConfiguredReplyBytes = 64 * 1024 * 1024;

type
  EWireError = class(Exception);
  TWireBatches = array of TSessionReplies;

  TSessionWire = class
  private
    FSession: TNativeSession;
    FHeader: array[0..3] of Byte;
    FHeaderUsed: SizeInt;
    FExpected: SizeInt; { -1 until four header bytes received }
    FCollected: SizeInt;
    FPayload: RawByteString;
    FQueued: TWireBatches;
    FQueueLimit: SizeInt;
    FInputByteLimit: SizeInt;
    FQueuedInputBytes: SizeInt;
    FReplyByteLimit: SizeInt;
    FQueuedReplyBytes: SizeInt;
    FPackets: QWord;
    FClosed: Boolean;
    FBroken: Boolean;
    FInFeed: Boolean;
    procedure Fail(const Reason: String);
    procedure QueuePayload;
  public
    constructor Create(ASession: TNativeSession;
      AMaxQueuedBatches: SizeInt = MaxQueuedBatches;
      AMaxQueuedInputBytes: SizeInt = MaxQueuedInputBytes;
      AMaxQueuedReplyBytes: SizeInt = MaxQueuedReplyBytes);
    procedure Feed(const Bytes: RawByteString);
    procedure Finish;
    procedure Reset; { reset wire decoder, NEVER reset session lexical frame }
    function Drain: TWireBatches; { surviving replies even after wire failure }
    function PacketCount: QWord;
    function PendingBatches: SizeInt;
    function PendingInputBytes: SizeInt;
    function PendingReplyBytes: SizeInt;
    function IsBroken: Boolean;
    function IsClosed: Boolean;
  end;

implementation

constructor TSessionWire.Create(ASession: TNativeSession;
  AMaxQueuedBatches, AMaxQueuedInputBytes,
  AMaxQueuedReplyBytes: SizeInt);
begin
  inherited Create;
  if ASession = nil then raise EWireError.Create(RawByteString(UTF8Encode(UnicodeString('відсутня нативна сесія'))));
  if (AMaxQueuedBatches < 1) or (AMaxQueuedBatches > MaxConfiguredBatches) then
    raise EWireError.Create(RawByteString(UTF8Encode(UnicodeString('неприпустима межа черги відповідей'))));
  if (AMaxQueuedInputBytes < 1) or
     (AMaxQueuedInputBytes > MaxConfiguredInputBytes) then
    raise EWireError.Create(RawByteString(UTF8Encode(UnicodeString(
      'неприпустима байтова межа черги пакетів'))));
  if (AMaxQueuedReplyBytes < 1) or
     (AMaxQueuedReplyBytes > MaxConfiguredReplyBytes) then
    raise EWireError.Create(RawByteString(UTF8Encode(UnicodeString(
      'неприпустима байтова межа відповідей'))));
  FSession := ASession;
  FQueueLimit := AMaxQueuedBatches;
  FInputByteLimit := AMaxQueuedInputBytes;
  FQueuedInputBytes := 0;
  FReplyByteLimit := AMaxQueuedReplyBytes;
  FQueuedReplyBytes := 0;
  FExpected := -1;
  FHeaderUsed := 0;
  FCollected := 0;
  FPackets := 0;
  FClosed := False;
  FBroken := False;
  FInFeed := False;
end;

procedure TSessionWire.Fail(const Reason: String);
begin
  FBroken := True;
  raise EWireError.Create(Reason);
end;

procedure TSessionWire.QueuePayload;
var
  Responses: TSessionReplies;
  N, I, Available, AddedReplyBytes: SizeInt;
begin
  if FPackets = High(QWord) then Fail(RawByteString(UTF8Encode(UnicodeString('переповнення лічильника пакетів'))));
  { Перевірка ДО Submit: переповнений пакет не виконує форми,
    не збільшує FPackets і не змінює стан спільної сесії. }
  if Length(FQueued) >= FQueueLimit then
    Fail(RawByteString(UTF8Encode(UnicodeString('черга відповідей заповнена: прочитайте відповіді через Drain'))));
  if (FExpected < 0) or (FExpected > FInputByteLimit - FQueuedInputBytes) then
    Fail(RawByteString(UTF8Encode(UnicodeString('переповнення байтової квоти черги'))));
  try
    Responses := FSession.Submit(FPayload);
  except
    on E: Exception do Fail('wire session dispatch error: ' + E.Message);
  end;
  { Вкладений callback міг спробувати Drain або Reset і зламати канал.
    Навіть якщо виконавець перехопив EWireError, відповідь цього пакета
    НЕ можна додавати до FIFO після FBroken. Старі пакети доступні ззовні. }
  if FBroken then
    Fail('канал зламано під час виконання пакета; відповідь не прийнято');
  { Після Submit знаємо точну довжину відповіді. Тут уже МОГЛИ
    виконатися форми та змінитися лексичний frame; відкоту НЕМАЄ.
    Відхиляємо переповнення до додавання в FIFO. Всі обчислення
    у межах SizeInt через доступний залишок, без переповнення сум. }
  Available := FReplyByteLimit - FQueuedReplyBytes;
  for I := 0 to High(Responses) do begin
    if Length(Responses[I].Output) > Available then
      Fail(RawByteString(UTF8Encode(UnicodeString(
        'квота вихідних байтів: пакет уже виконано, відповідь не додано'))));
    Dec(Available, Length(Responses[I].Output));
    if Length(Responses[I].Diagnostic) > Available then
      Fail(RawByteString(UTF8Encode(UnicodeString(
        'квота вихідних байтів: пакет уже виконано, відповідь не додано'))));
    Dec(Available, Length(Responses[I].Diagnostic));
  end;
  AddedReplyBytes := FReplyByteLimit - FQueuedReplyBytes - Available;
  N := Length(FQueued);
  SetLength(FQueued, N + 1);
  FQueued[N] := Responses;
  Inc(FQueuedReplyBytes,AddedReplyBytes);
  Inc(FQueuedInputBytes,FExpected);
  Inc(FPackets);
  FHeaderUsed := 0;
  FExpected := -1;
  FCollected := 0;
  FPayload := '';
end;

procedure TSessionWire.Feed(const Bytes: RawByteString);
var
  I, Take, Remaining: SizeInt;
  Declared: QWord;
begin
  if FBroken then raise EWireError.Create('wire decoder broken: call Reset');
  if FClosed then raise EWireError.Create('wire decoder closed: call Reset');
  if FInFeed then Fail('reentrant wire feed');
  FInFeed := True;
  try
    I := 1;
    while I <= Length(Bytes) do begin
      if FExpected < 0 then begin
        FHeader[FHeaderUsed] := Ord(Bytes[I]);
        Inc(FHeaderUsed);
        Inc(I);
        if FHeaderUsed = 4 then begin
          Declared := QWord(FHeader[0]) or
             (QWord(FHeader[1]) shl 8) or
             (QWord(FHeader[2]) shl 16) or
             (QWord(FHeader[3]) shl 24);
          if Declared > MaxWirePayload then
            Fail('wire packet exceeds 16 MiB');
          { На межі заголовка: до алокації FPayload та до Submit.
            Бюджет відповідає байтам вхідних пакетів, не RSS/Output. }
          if Declared > QWord(FInputByteLimit - FQueuedInputBytes) then
            Fail(RawByteString(UTF8Encode(UnicodeString(
              'переповнення байтової квоти черги'))));
          FExpected := SizeInt(Declared);
          FCollected := 0;
          SetLength(FPayload, FExpected);
          if FExpected = 0 then QueuePayload;
        end;
      end else begin
        Remaining := FExpected - FCollected;
        Take := Length(Bytes) - I + 1;
        if Take > Remaining then Take := Remaining;
        if Take <= 0 then Fail('wire payload accounting error');
        Move(Bytes[I], FPayload[FCollected + 1], Take);
        Inc(FCollected, Take);
        Inc(I, Take);
        if FCollected = FExpected then QueuePayload;
      end;
    end;
  finally
    FInFeed := False;
  end;
end;

procedure TSessionWire.Finish;
begin
  if FBroken then raise EWireError.Create('wire decoder broken: call Reset');
  if FClosed then raise EWireError.Create('wire EOF already received');
  if (FHeaderUsed <> 0) or (FExpected >= 0) then begin
    FClosed := True;
    Fail('wire truncated header or payload at EOF');
  end;
  FClosed := True;
end;

procedure TSessionWire.Reset;
begin
  if FInFeed then Fail('cannot reset during wire feed');
  FHeaderUsed := 0;
  FExpected := -1;
  FCollected := 0;
  FPayload := '';
  FClosed := False;
  FBroken := False;
  { FQueued intentionally survives Reset until Drain; FSession is untouched. }
end;

function TSessionWire.Drain: TWireBatches;
begin
  { У середині Feed виконавець може реентрантно спробувати забрати
    попередні відповіді; це порушило б межу квот/FIFO ще до commit. }
  if FInFeed then
    Fail('заборонено читати чергу під час виконання пакета');
  Result := FQueued;
  SetLength(FQueued, 0);
  FQueuedInputBytes := 0;
  FQueuedReplyBytes := 0;
end;

function TSessionWire.PacketCount: QWord;
begin Result := FPackets; end;

function TSessionWire.PendingBatches: SizeInt;
begin Result := Length(FQueued); end;

function TSessionWire.PendingInputBytes: SizeInt;
begin Result := FQueuedInputBytes; end;

function TSessionWire.PendingReplyBytes: SizeInt;
begin Result := FQueuedReplyBytes; end;

function TSessionWire.IsBroken: Boolean;
begin Result := FBroken; end;

function TSessionWire.IsClosed: Boolean;
begin Result := FClosed; end;

end.
