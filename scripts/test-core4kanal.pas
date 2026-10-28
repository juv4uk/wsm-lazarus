{ G5.22: байтові свідки реальних pinned Core4-викликів.
  Тест перевіряє host framing, не створює локальний реєстр мовних законів. }
program test_core4kanal;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core4runtime, wsm.t5m;
var Root,Dir:String; Runtime:TCore4Runtime;

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(B:Boolean;const Why:String);
begin if not B then raise Exception.Create('КАНАЛ-ТЕСТ: '+Why); end;

function FileName(const S:String):String;
begin Result:=IncludeTrailingPathDelimiter(Dir)+S end;

function OneWord(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W);
end;

function Identifier(const Id:RawByteString):TExactWords;
var I,N:SizeInt;
begin
  Need((Length(Id)>0) and (Length(Id) mod 7=0),'D7 exact ключ');
  N:=Length(Id) div 7;
  SetLength(Result,N+2);Result[0]:='10';
  for I:=0 to N-1 do Result[I+1]:=Copy(Id,I*7+1,7);
  Result[N+1]:='01';
end;

function Call(const Id,Arg:RawByteString; HasArg:Boolean=True):RawByteString;
var NameWords,Words:TExactWords; I,N:SizeInt;
begin
  NameWords:=Identifier(Id);
  SetLength(Words,Length(NameWords)+3);
  N:=0;Words[N]:='10';Inc(N);
  for I:=0 to High(NameWords) do begin Words[N]:=NameWords[I];Inc(N) end;
  if HasArg then begin Words[N]:=Arg;Inc(N) end;
  Words[N]:='01';Inc(N);SetLength(Words,N);
  Result:=EncodeT5M(Words);
end;

procedure Header(S:TStream; N:LongWord);
var H:array[0..3] of Byte;
begin
  H[0]:=Byte(N and $FF);H[1]:=Byte((N shr 8) and $FF);
  H[2]:=Byte((N shr 16) and $FF);H[3]:=Byte((N shr 24) and $FF);
  S.WriteBuffer(H,4);
end;

procedure Frame(S:TStream;const Physical:RawByteString);
begin
  Header(S,LongWord(Length(Physical)));
  if Length(Physical)>0 then S.WriteBuffer(Physical[1],Length(Physical));
end;

procedure Generate;
var F:TFileStream; First,Second,GlobalWord,Name:RawByteString; H:array[0..3] of Byte;
begin
  Runtime:=TCore4Runtime.Create(Root);
  try
    Name:=Runtime.FirstDefinitionIdentifier;
    First:=Call(Name,'1');
    Second:=Call(Name,'0');
    GlobalWord:=EncodeT5M(Identifier(Runtime.BindingIdentifier(2)));

    F:=TFileStream.Create(FileName('запити.bin'),fmCreate);
    try
      Frame(F,First);Frame(F,Chr(243));Frame(F,Second);
      Frame(F,Call(Name,'',False));
      Frame(F,GlobalWord);
      Frame(F,Call(Name,'000000000000000000000001'));
      Frame(F,'');
      Frame(F,First);
    finally F.Free end;

    F:=TFileStream.Create(FileName('один.bin'),fmCreate);
    try Frame(F,First); finally F.Free end;

    F:=TFileStream.Create(FileName('обрізано-заголовок.bin'),fmCreate);
    try
      Frame(F,First);
      H[0]:=4;H[1]:=0;
      F.WriteBuffer(H,2);
    finally F.Free end;

    F:=TFileStream.Create(FileName('обрізано-дані.bin'),fmCreate);
    try
      Frame(F,First); Header(F,10);
      F.WriteBuffer(First[1],1);
    finally F.Free end;

    F:=TFileStream.Create(FileName('завеликий.bin'),fmCreate);
    try Header(F,1024*1024+1); finally F.Free end;
    F:=TFileStream.Create(FileName('неповний.bin'),fmCreate);
    try Header(F,200);F.WriteBuffer(First[1],1);finally F.Free end;
    F:=TFileStream.Create(FileName('пустий.bin'),fmCreate);F.Free;
    WriteLn(Ukr('КАНАЛ-СВІДКИ-ГОТОВО pinned=core4.sens запитів=8 негативні=3'));
  finally Runtime.Free end;
end;

function ReadN(S:TStream;var Buf;N:SizeInt):Boolean;
var P:PByte;Total,Got:SizeInt;
begin
  Result:=False;Total:=0;P:=@Buf;
  while Total<N do begin
    Got:=S.Read(P[Total],N-Total);
    if Got<=0 then Exit;
    Inc(Total,Got);
  end;
  Result:=True;
end;

function VerifyOne(S:TStream;ExpectedStatus:Byte;
  const ExpectedBits:RawByteString):Boolean;
var H:array[0..4] of Byte;N:LongWord;Payload:RawByteString;
begin
  Result:=False;
  if not ReadN(S,H,5) then Exit;
  N:=LongWord(H[1]) or (LongWord(H[2]) shl 8) or
     (LongWord(H[3]) shl 16) or (LongWord(H[4]) shl 24);
  if (H[0]<>ExpectedStatus) or (N=0) or (N>4096) then Exit;
  SetLength(Payload,N);
  if not ReadN(S,Payload[1],N) then Exit;
  if ExpectedStatus=0 then
    Result:=Payload=OneWord(ExpectedBits)
  else
    Result:=Payload<>'';
end;

procedure Verify;
var F:TFileStream;B:Byte; I:Integer;Path:String;
begin
  F:=TFileStream.Create(FileName('відповіді.bin'),fmOpenRead);
  try
    Need(VerifyOne(F,0,'1'),'перший exact W1');
    Need(VerifyOne(F,1,''),'неправильний T5M не відхилено');
    Need(VerifyOne(F,0,'0'),'відновлення після T5M помилки');
    Need(VerifyOne(F,1,''),'арність не відхилено');
    Need(VerifyOne(F,0,'000000000000000000000001'),
      'первинний pinned глобал W24');
    Need(VerifyOne(F,0,'000000000000000000000001'),
      'exact W24 аргумент замикання');
    Need(VerifyOne(F,1,''),'нульовий кадр прийнято');
    Need(VerifyOne(F,0,'1'),'виконання після трьох відмов');
    Need(F.Read(B,1)=0,'після 8 фреймів зайві байти');
  finally F.Free end;

  F:=TFileStream.Create(FileName('один-відповідь.bin'),fmOpenRead);
  try
    Need(VerifyOne(F,0,'1'),'чистий кадр');
    Need(F.Read(B,1)=0,'зайві байти чистої відповіді');
  finally F.Free end;

  for I:=1 to 2 do begin
    if I=1 then Path:='обрізано-заголовок-відповідь.bin'
    else Path:='обрізано-дані-відповідь.bin';
    F:=TFileStream.Create(FileName(Path),fmOpenRead);
    try
      Need(VerifyOne(F,0,'1'),'завершена відповідь перед обривом');
      Need(F.Read(B,1)=0,'не можна публікувати неповну відповідь');
    finally F.Free end;
  end;
  WriteLn(Ukr('КАНАЛ-ПЕРЕВІРЕНО T5M=побайтово відповіді=8 помилки=3 відновлення=так обрив=без-часткової-відповіді'));
end;

begin
  Need(ParamCount=3,'використання: generate|verify КОРІНЬ КАТАЛОГ');
  Root:=ParamStr(2);Dir:=ParamStr(3);
  if ParamStr(1)='generate' then Generate
  else if ParamStr(1)='verify' then Verify
  else raise Exception.Create('невідомий режим тестування');
end.
