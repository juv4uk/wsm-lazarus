{ G5.51: реальний Free Pascal-клієнт проти контрольованого ФІЗИЧНО
  пошкодженого дочірнього pipe та проти СПРАВЖНЬОГО senspotikd3.
  Fake-сервер не виконує жодного SENS закону: тільки host-framing.
  Оракулом семантики лишається pinned SENS, не цей тест. }
program test_d3wireclient;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, {$IFDEF UNIX}cwstring,{$ENDIF} BaseUnix,
  wsm.t5m, wsm.d3wireclient;

procedure Need(OK:Boolean; const Why:String);
begin
  if not OK then begin
    WriteLn(StdErr,'D3-КАНАЛ-БЛОК: ',Why);
    Halt(1);
  end;
end;

function WordsOf(const A:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;

procedure RawRead(var Buffer;Count:SizeInt);
var P:PByte;Done,Got:SizeInt;
begin
  P:=@Buffer;Done:=0;
  while Done<Count do begin
    Got:=fpRead(0,P[Done],Count-Done);
    if Got<=0 then Halt(31);
    Inc(Done,Got);
  end;
end;

procedure RawWrite(const Buffer;Count:SizeInt);
var P:PByte;Done,Written:SizeInt;
begin
  P:=@Buffer;Done:=0;
  while Done<Count do begin
    Written:=fpWrite(1,P[Done],Count-Done);
    if Written<=0 then Halt(32);
    Inc(Done,Written);
  end;
end;

procedure FakeServer(const Mode:String);
var Header:array[0..4] of Byte;
    N:LongWord; Payload:RawByteString;
    InputBytes:RawByteString; Status:Byte;
begin
  { Прочитати ПОВНУ фактично надіслану FPC транзакцію, не фальшивий
    echo loop. Повний чи неповний reply генерується ТІЛЬКИ далі. }
  RawRead(Header,4);
  N:=LongWord(Header[0]) or (LongWord(Header[1]) shl 8) or
    (LongWord(Header[2]) shl 16) or (LongWord(Header[3]) shl 24);
  if (N<1) or (N>MaxD3WireBytes) then Halt(33);
  SetLength(InputBytes,N);
  RawRead(InputBytes[1],N);
  if Mode='probe-short-header' then begin
    Header[0]:=0;Header[1]:=1;
    RawWrite(Header,2);
    Halt(0);
  end;
  Status:=0;
  if Mode='probe-bad-status' then Payload:=#0
  else if Mode='probe-bad-length' then Payload:=''
  else if Mode='probe-short-body' then Payload:=#0
  else if Mode='probe-bad-t5m' then Payload:=#243
  else if Mode='probe-bad-d2' then
    Payload:=EncodeT5M(WordsOf(['10','0']))
  else if Mode='probe-bad-roots' then
    Payload:=EncodeT5M(WordsOf(['0','1']))
  else if Mode='probe-good' then
    Payload:=EncodeT5M(WordsOf(['0']))
  else Halt(34);
  if Mode='probe-bad-status' then Status:=9;
  N:=Length(Payload);
  if Mode='probe-bad-length' then N:=MaxD3WireBytes+1;
  if Mode='probe-short-body' then N:=4;
  Header[0]:=Status;
  Header[1]:=Byte(N and $ff);
  Header[2]:=Byte((N shr 8) and $ff);
  Header[3]:=Byte((N shr 16) and $ff);
  Header[4]:=Byte((N shr 24) and $ff);
  RawWrite(Header,5);
  if Length(Payload)>0 then RawWrite(Payload[1],Length(Payload));
end;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>=1) and (F.Size<=MaxD3WireBytes),
      'реальна fixture поза фізичною межею');
    SetLength(Result,F.Size);
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure CheckPoison(const Mode:String);
var Client:TD3WireClient; Physical,Reply:RawByteString;
    PID:Int64;Failed,Poisoned:Boolean;
begin
  Client:=TD3WireClient.Create(ExpandFileName(ParamStr(0)),Mode);
  try
    PID:=Client.ProcessID;
    Need(PID>0,'контрольований дочірній FPC-процес не запущено');
    Physical:=EncodeT5M(WordsOf(['0']));
    Failed:=False;Reply:='';
    try Reply:=Client.Execute(Physical);
    except on E:ED3WireError do Failed:=True end;
    Need(Failed and (Reply=''),'пошкоджений reply прийнято: '+Mode);
    Poisoned:=False;
    try Reply:=Client.Execute(Physical);
    except on E:ED3WireError do
      Poisoned:=Pos('недоступний',E.Message)>0;
    end;
    Need(Poisoned and (Reply='') and (Client.ProcessID=PID),
      'після фізичного пошкодження дозволено новий wire-запит: '+Mode);
  finally Client.Free end;
end;

procedure CheckLocalPreflight;
var Client:TD3WireClient;Physical,Reply:RawByteString;
    PID:Int64;Rejected:Boolean;
begin
  Client:=TD3WireClient.Create(ExpandFileName(ParamStr(0)),'probe-good');
  try
    PID:=Client.ProcessID;
    Rejected:=False;
    try
      Client.Execute(EncodeT5M(WordsOf(['01'])));
    except on E:ED3WireError do Rejected:=True end;
    Need(Rejected,'локальна D2-помилка прийнята');
    Physical:=EncodeT5M(WordsOf(['0']));
    Reply:=Client.Execute(Physical);
    Need((Reply=Physical) and (Client.ProcessID=PID),
      'локальний preflight помилково отруїв ще не використаний pipe');
  finally Client.Free end;
end;

procedure CheckRealChild(const Child,Authority:String);
var Client:TD3WireClient;
    Fixture,Answer:RawByteString;
    PID:Int64;Remote:Boolean;
begin
  Client:=TD3WireClient.Create(Child,Authority);
  try
    PID:=Client.ProcessID;
    Fixture:=ReadPhysical('build/paketd3-cli/fixtures/one.sens');
    Answer:=ReadPhysical('build/paketd3-cli/fixtures/one-answer.sens');
    Need(Client.Execute(Fixture)=Answer,'справжній pinned D3 не виконав 1 форму');
    Remote:=False;
    try
      Client.Execute(ReadPhysical('build/paketd3-cli/fixtures/late-bad.sens'));
    except on E:ED3RemoteError do
      Remote:=Pos('форма=2 слово=2',E.Message)>0;
    end;
    Need(Remote,'втрачено фізичну адресу справжньої пізньої remote-помилки');
    Need((Client.Execute(Fixture)=Answer) and
      (Client.ProcessID=PID),
      'штатний remote status=1 помилково отруїв/перезапустив канал');
  finally Client.Free end;
end;

var Mode:String;
begin
  { У FakeServer лише ASCII host-маркер: ParamStr Unicode у FPC/Unix
    може бути не 1:1 без cwstring. Жодних SENS функцій за іменем. }
  if (ParamCount=2) and (Copy(ParamStr(2),1,6)='probe-') then begin
    FakeServer(ParamStr(2));
    Halt(0);
  end;
  Need(ParamCount=2,
    'використання: test-d3wireclient файл-senspotikd3 pinned-root');
  for Mode in ['probe-bad-status','probe-bad-length',
    'probe-short-header','probe-short-body','probe-bad-t5m',
    'probe-bad-d2','probe-bad-roots'] do
    CheckPoison(Mode);
  CheckLocalPreflight;
  CheckRealChild(ParamStr(1),ParamStr(2));
  WriteLn('D3-КАНАЛ-ОТРУЄННЯ-ГАРАЗД ',
    'FPC=реальний malformed=7 повтор=відхилено ',
    'local-preflight=відновлюваний status1=відновлюваний ',
    'PID=незмінний D2/T5M=точний D7=дані D12+=не-виконується');
end.

{ Типи й життя: FakeServer запозичує тільки fd0/fd1 OS pipe та виділяє
  bounded RawByteString; тест TD3WireClient володіє TProcess і через
  Free звільняє його навіть після відмови; Reply локальний managed.
  Питання: 1) Чим remote status=1 відрізняється від пошкодженого
  header? 2) Чому FUsable має стати False до Terminate?
  3) Чому локальне D2 відхилення не робить write?
  4) Які дані є packed T5M, а які host framing?
  5) Чому цей фізичний тест не є семантичним REPL oracle? }
