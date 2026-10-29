{ G5.55 — постійний процес ВЖЕ чинного обмеженого D3-оцінювача.
  На вході — ПРИВАТНИЙ HOST-КАДР u32le + UTF-8 «ук»-проєкція.
  На виході — ПРИВАТНИЙ HOST-КАДР:
    u32le count, потім для кожної форми:
    status:u8 (0/1), form:u64le, offset:u32le,
    line:u32le, column:u32le, length:u32le, payload:utf8.
  Це не фізична програма .sens і не нативний SENS REPL. status не D1.
  Закони D3 залишаються тільки у pinned SENS / wsm.nativeeval. }
program sensseansd3;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.session,wsm.sessionwire,wsm.sessiond3;

const MaxRequestBytes=65536;
      MaxAnswerFrameBytes=1024*1024;
type ESeansD3Error=class(Exception);

function UA(const Text:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Text)) end;

function ReadExactly(S:TStream;var Dest;Count:SizeInt;
  PermitCleanEOF:Boolean):Boolean;
var P:PByte;Got,Used:SizeInt;
begin
  P:=@Dest;Used:=0;
  while Used<Count do begin
    Got:=S.Read(P[Used],Count-Used);
    if Got<=0 then begin
      if PermitCleanEOF and (Used=0) then Exit(False);
      raise ESeansD3Error.Create(UA('обірвано заголовок або тіло host-кадру'));
    end;
    Inc(Used,Got);
  end;
  Result:=True;
end;

function Little32(const H:array of Byte):QWord;
begin
  Result:=QWord(H[0]) or (QWord(H[1]) shl 8) or
    (QWord(H[2]) shl 16) or (QWord(H[3]) shl 24);
end;

procedure WriteLE(S:TStream;Number:QWord;Bytes:SizeInt);
var I:SizeInt;B:Byte;
begin
  for I:=1 to Bytes do begin
    B:=Byte(Number and $FF);
    S.WriteBuffer(B,1);
    Number:=Number shr 8;
  end;
end;

procedure EncodeReplies(const Replies:TSessionReplies;
  out Physical:RawByteString);
var Buffer:TMemoryStream;I:SizeInt;Payload:RawByteString;Status:Byte;
    R:TSessionReply;
begin
  Physical:='';
  if Length(Replies)>4096 then
    raise ESeansD3Error.Create(UA('забагато відповідей в одному host-кадрі'));
  Buffer:=TMemoryStream.Create;
  try
    WriteLE(Buffer,Length(Replies),4);
    for I:=0 to High(Replies) do begin
      R:=Replies[I];
      if R.Ok then begin
        Status:=0;Payload:=R.Output;
      end else begin
        Status:=1;Payload:=R.Diagnostic;
        if Payload='' then Payload:=UA('виконання відхилено');
      end;
      if (R.ByteOffset<0) or (R.Line<0) or (R.ByteColumn<0) or
         (QWord(R.ByteOffset)>High(LongWord)) or
         (QWord(R.Line)>High(LongWord)) or
         (QWord(R.ByteColumn)>High(LongWord)) then
        raise ESeansD3Error.Create(UA('недопустима фізична позиція відповіді'));
      if (Length(Payload)>MaxAnswerFrameBytes-25-Buffer.Size) then
        raise ESeansD3Error.Create(UA('відповіді перевищують host-бюджет'));
      Buffer.WriteBuffer(Status,1);
      WriteLE(Buffer,R.FormNumber,8);
      WriteLE(Buffer,QWord(R.ByteOffset),4);
      WriteLE(Buffer,QWord(R.Line),4);
      WriteLE(Buffer,QWord(R.ByteColumn),4);
      WriteLE(Buffer,Length(Payload),4);
      if Payload<>'' then Buffer.WriteBuffer(Payload[1],Length(Payload));
    end;
    SetLength(Physical,SizeInt(Buffer.Size));
    Buffer.Position:=0;
    Buffer.ReadBuffer(Physical[1],Length(Physical));
  finally Buffer.Free end;
end;

{ Транспорт приймає один повний кадр за раз, одразу Drain.
  Типи: Source/Sink — запозичені дескриптори stdin/stdout.
  TNativeSession володіє середовищем; TSessionWire лише запозичує сесію.
  Physical не переживає чергову відповідь; на помилці нічого
  від поточного кадру не потрапляє до stdout. ОС може частково
  записати уже допущену відповідь при розриві pipe — це не rollback.
  Питання: 1) Чому status не D1? 2) Чому тут не .sens?
  3) Де зберігається середовище? 4) Що відбувається при обірваному EOF? }
procedure Run(const Root:RawByteString);
var Source,Sink:THandleStream;Session:TNativeSession;Wire:TSessionWire;
    Header:array[0..3] of Byte;Size:QWord;Incoming,Frame,Reply:RawByteString;
    Batches:TWireBatches;
begin
  Session:=TNativeSession.Create(NewNativeD3Executor(Root));
  try
    Wire:=TSessionWire.Create(Session,1,MaxRequestBytes,MaxRequestBytes);
    try
      Source:=THandleStream.Create(TextRec(Input).Handle);
      try
        Sink:=THandleStream.Create(TextRec(Output).Handle);
        try
          while ReadExactly(Source,Header,4,True) do begin
            Size:=Little32(Header);
            if Size>MaxRequestBytes then
              raise ESeansD3Error.Create(UA('вхідний host-кадр перевищує 65536 байтів'));
            SetLength(Incoming,SizeInt(Size));
            if Size>0 then ReadExactly(Source,Incoming[1],SizeInt(Size),False);
            SetLength(Frame,SizeInt(Size)+4);
            Move(Header[0],Frame[1],4);
            if Size>0 then Move(Incoming[1],Frame[5],SizeInt(Size));
            Wire.Feed(Frame);
            Batches:=Wire.Drain;
            if Length(Batches)<>1 then
              raise ESeansD3Error.Create(UA('порушено одне обрамлення запиту'));
            EncodeReplies(Batches[0],Reply);
            { Спершу повне обчислення й кодування, потім тільки binary stdout. }
            Sink.WriteBuffer(Reply[1],Length(Reply));
            Incoming:='';Frame:='';Reply:='';
          end;
          Wire.Finish;
        finally Sink.Free end;
      finally Source.Free end;
    finally Wire.Free end;
  finally Session.Free end;
end;

begin
  if (ParamCount<>1) or (ParamStr(1)='') then begin
    WriteLn(StdErr,UA('Використання: sensseansd3 каталог-pinned-sens; stdin/stdout=приватний-кадр-ук'));
    Halt(64);
  end;
  try
    Run(RawByteString(ParamStr(1)));
  except
    on E:Exception do begin
      WriteLn(StdErr,UA('СЕАНС-Д3-ПОМИЛКА: '),E.Message);
      Halt(2);
    end;
  end;
end.
