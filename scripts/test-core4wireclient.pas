{ G5.30 — справжній клієнт довгоживучого Core4 з pinned D7.
  Три початкові DEFINE та їхні ключі читаємо лише з core4.sens;
  людське написання «укр» тут не потрібне для dispatch. }
program test_core4wireclient;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core4wireclient, wsm.core4runtime, wsm.t5m;
var
  Root,Executable:String;
  Runtime:TCore4Runtime;
  Client,Batch:TCore4WireClient;
  Keys:array[0..2] of RawByteString;
  I,J,PID,Failed:SizeInt;
  Candidate,Physical,Expected:RawByteString;
  Words,Additional:TExactWords;

procedure Need(B:Boolean;const Why:String);
begin
  if not B then raise Exception.Create('КЛІЄНТ-НЕПРАВИЛЬНО: '+Why);
end;

function ExactWord(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W) end;

procedure Expect(const Actual,ExpectedPhysical:RawByteString;
  const Why:String);
begin
  Need(Actual=ExpectedPhysical,'побайтовий T5M: '+Why);
end;

procedure ExpectRemote(C:TCore4WireClient;
  const Frame:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try C.Execute(Frame);
  except on E:ECore4RemoteError do
    Rejected:=Length(E.Message)>0;
  end;
  Need(Rejected,'remote мав відхилити '+Why);
  Inc(Failed);
end;

procedure ExpectLocalD7(const Bits:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try PhysicalD7Name(Bits)
  except on E:ECore4WireError do Rejected:=True end;
  Need(Rejected,'D7 preflight '+Why);
  Inc(Failed);
end;

procedure ExpectLocalFrame(C:TCore4WireClient;
  const Frame:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try C.Execute(Frame)
  except
    on E:ECore4RemoteError do Rejected:=False;
    on E:Exception do Rejected:=True;
  end;
  Need(Rejected,'локально відхилити T5M '+Why);
  Inc(Failed);
end;

function Combine(const Forms:array of RawByteString):RawByteString;
var I,J,N:SizeInt;One,All:TExactWords;
begin
  SetLength(All,0);
  for I:=0 to High(Forms) do begin
    DecodeT5M(Forms[I],One);
    N:=Length(All);SetLength(All,N+Length(One));
    for J:=0 to High(One) do All[N+J]:=One[J];
  end;
  Result:=EncodeT5M(All);
end;

{ Штучний дочірній FPC процес тільки для host protocol fault injection.
  НІКОЛИ не обчислює SENS-форм: зчитує 4+N позичених wire bytes,
  після чого відправляє навмисно пошкоджений HOST-кадр. Це не evaluator.
  Source/Sink — owned THandleStream над inherited stdin/stdout handles. }
procedure ReadFakeRequest(Source:TStream);
var H:array[0..3] of Byte;N:LongWord;Bytes:RawByteString;
begin
  Source.ReadBuffer(H,4);
  N:=LongWord(H[0]) or (LongWord(H[1]) shl 8) or
    (LongWord(H[2]) shl 16) or (LongWord(H[3]) shl 24);
  if (N<1) or (N>MaxCore4WireBytes) then Halt(61);
  SetLength(Bytes,N);
  Source.ReadBuffer(Bytes[1],N);
end;

procedure FakeReply(Sink:TStream;Status:Byte;
  const Body:RawByteString; Declared:LongWord);
var H:array[0..4] of Byte;
begin
  H[0]:=Status;
  H[1]:=Byte(Declared and $ff);
  H[2]:=Byte((Declared shr 8) and $ff);
  H[3]:=Byte((Declared shr 16) and $ff);
  H[4]:=Byte((Declared shr 24) and $ff);
  Sink.WriteBuffer(H,5);
  if Length(Body)>0 then Sink.WriteBuffer(Body[1],Length(Body));
end;

procedure RunFakeChild(const Mode:String);
var Source,Sink:THandleStream;
  Words:TExactWords; B:RawByteString;
begin
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Sink:=THandleStream.Create(TextRec(Output).Handle);
    try
      ReadFakeRequest(Source);
      if Mode='fault-status' then
        FakeReply(Sink,2,'X',1)
      else if Mode='fault-diagnostic' then begin
        B:=StringOfChar('X',MaxCore4WireDiagnosticBytes+1);
        FakeReply(Sink,1,B,Length(B));
      end else if Mode='fault-truncated-payload' then
        FakeReply(Sink,0,'X',4)
      else if Mode='fault-truncated-header' then begin
        B:=#0#1;
        Sink.WriteBuffer(B[1],Length(B));
      end else if Mode='fault-malformed-t5m' then
        FakeReply(Sink,0,Chr(243),1)
      else if Mode='fault-d2-open' then begin
        SetLength(Words,2);Words[0]:='10';Words[1]:='1';
        B:=EncodeT5M(Words);
        FakeReply(Sink,0,B,Length(B));
      end else if Mode='fault-two-roots' then begin
        SetLength(Words,2);Words[0]:='1';Words[1]:='0';
        B:=EncodeT5M(Words);
        FakeReply(Sink,0,B,Length(B));
      end else if Mode='fault-overlong' then
        FakeReply(Sink,0,'',MaxCore4WireBytes+1)
      else if Mode='fault-remote-recover' then begin
        B:='REMOTE-EXPECTED';
        FakeReply(Sink,1,B,Length(B));
        ReadFakeRequest(Source);
        SetLength(Words,1);Words[0]:='1';
        B:=EncodeT5M(Words);
        FakeReply(Sink,0,B,Length(B));
      end else Halt(62);
    finally Sink.Free end;
  finally Source.Free end;
end;

{ Test-only wire corruption MUST NOT corrupt user-visible SENS replies.
  After first corrupted response, owned process becomes unusable; all
  future requests must fail LOCALLY, without launching or retrying a child. }
procedure WirePoisonTests;
const
  Broken:array[0..7] of String=(
    'fault-status','fault-diagnostic','fault-truncated-payload',
    'fault-truncated-header','fault-malformed-t5m','fault-d2-open',
    'fault-two-roots','fault-overlong');
var I:SizeInt; C:TCore4WireClient; OldPID:Int64;
  Frame:RawByteString; FailedFirst,FailedSecond,RemoteSeen:Boolean;
begin
  Frame:=PhysicalD7Call(Keys[0],'1');
  for I:=0 to High(Broken) do begin
    C:=TCore4WireClient.Create(ExpandFileName(ParamStr(0)),Broken[I],False);
    try
      OldPID:=C.ProcessID;
      Need(OldPID>0,'штучний фізичний дочірній FPC процес');
      FailedFirst:=False;FailedSecond:=False;
      try C.Execute(Frame)
      except
        on E:ECore4RemoteError do
          raise Exception.Create('ПОМИЛКА-КАНАЛУ: пошкодження стало штатним remote '+Broken[I]);
        on E:ECore4WireError do FailedFirst:=True;
      end;
      Need(FailedFirst,'пошкоджений кадр не відхилено: '+Broken[I]);
      try C.Execute(Frame)
      except on E:ECore4WireError do begin
        FailedSecond:=Pos('Core4:',E.Message)=1;
      end end;
      Need(FailedSecond,'повторний виклик мав відхилитися локально: '+Broken[I]);
      Need(C.ProcessID=OldPID,'пошкоджений канал автоматично замінив PID');
      Inc(Failed);
    finally C.Free end;
  end;
  C:=TCore4WireClient.Create(ExpandFileName(ParamStr(0)),
    'fault-remote-recover',False);
  try
    OldPID:=C.ProcessID;RemoteSeen:=False;
    try C.Execute(Frame)
    except on E:ECore4RemoteError do
      RemoteSeen:=Pos('REMOTE-EXPECTED',E.Message)>0;
    end;
    Need(RemoteSeen,'штатна bounded remote відмова має зберегти тип');
    Expect(C.Execute(Frame),ExactWord('1'),
      'після справжнього status=1 той самий wire PID повертає W1:1');
    Need(C.ProcessID=OldPID,'штатна semantic remote-відмова змінила PID');
    Inc(Failed);
  finally C.Free end;
  WriteLn('CORE4-ОТРУЄНИЙ-КАНАЛ-ГАРАЗД шкідливі-кадри=8 ',
    'повторний-запис=відхилено штатна-відмова=відновлення PID=той-самий');
end;

{ G5.47 — ті самі exact bytes у двох процесних режимах.
  Локальна D2-відмова не повинна записати навіть header у pipe:
  наступна СПРАВЖНЯ форма у тому самому PID мусить отримати свою,
  а не попередню remote-відповідь. }
function RepeatPhysical(const Physical:RawByteString;Count:SizeInt):RawByteString;
var One,All:TExactWords;I,J,K:SizeInt;
begin
  DecodeT5M(Physical,One);
  SetLength(All,Length(One)*Count);
  K:=0;
  for I:=1 to Count do
    for J:=0 to High(One) do begin All[K]:=One[J];Inc(K) end;
  Result:=EncodeT5M(All);
end;

procedure ExpectLocalPreflight(C:TCore4WireClient;
  const BadFrame:RawByteString;const Marker,Why:String);
var Refused:Boolean; OldPID:Int64;
begin
  OldPID:=C.ProcessID;Refused:=False;
  try C.Execute(BadFrame)
  except
    on E:ECore4RemoteError do
      raise Exception.Create('PRE-FLIGHT-ПОМИЛКА: пакет пішов у remote: '+Why);
    on E:ECore4WireError do begin
      Refused:=True;
      Need(Pos(Marker,E.Message)>0,
        'preflight '+Why+' діагностика '+Marker+': '+E.Message);
    end
  end;
  Need(Refused,'preflight мав відхилити '+Why);
  Need(C.ProcessID=OldPID,'preflight змінив PID: '+Why);
  Expect(C.Execute(PhysicalD7Call(Keys[0],'1')),ExactWord('1'),
    'після локальної відмови '+Why+' немає залишкового remote кадру');
  Need(C.ProcessID=OldPID,'після відновлення інший PID: '+Why);
  Inc(Failed);
end;

procedure LocalD2Tests(C:TCore4WireClient; BatchMode:Boolean);
var W:TExactWords; Valid,Invalid:RawByteString;
begin
  Valid:=PhysicalD7Call(Keys[0],'1');
  SetLength(W,2);W[0]:='10';W[1]:='1';
  Invalid:=EncodeT5M(W);
  ExpectLocalPreflight(C,Invalid,'=3:','D2 OPEN без CLOSE');
  SetLength(W,1);W[0]:='01';
  ExpectLocalPreflight(C,EncodeT5M(W),'=1:','D2 CLOSE без OPEN');
  W[0]:='11';
  ExpectLocalPreflight(C,EncodeT5M(W),'=1:','D2 DOT поза списком');
  ExpectLocalPreflight(C,Chr(243),'T5M','байт поза T5M');
  if BatchMode then begin
    ExpectLocalPreflight(C,RepeatPhysical(Valid,65),
      'batch=1..64','65 D2 коренів у пакеті');
  end else begin
    ExpectLocalPreflight(C,RepeatPhysical(Valid,2),
      'single=1','два D2 корені у single');
  end;
end;

{ G5.43 — незалежні фізичні перевірки host-каналу, не другий evaluator.
  Обидва параметри borrowed packed T5M; усі TExactWords локальні managed,
  TD2Document всередині guard звільняється після успіху чи виключення. }
procedure GuardTests;
var
  Single,Two,Many,TooMany,Incomplete,WrongClose,WrongDot:RawByteString;
  Req,Answer:RawByteString;
  W,Part:TExactWords;
  I,J,N:SizeInt;

  function RepeatExact(const Physical:RawByteString; Count:SizeInt):RawByteString;
  var One,All:TExactWords; A,B,K:SizeInt;
  begin
    DecodeT5M(Physical,One);
    SetLength(All,Length(One)*Count);
    K:=0;
    for A:=1 to Count do
      for B:=0 to High(One) do begin All[K]:=One[B];Inc(K) end;
    Result:=EncodeT5M(All);
  end;

  procedure Reject(const Request,Reply:RawByteString;Batch:Boolean;
    const Fragment,Why:String);
  var Refused:Boolean;
  begin
    Refused:=False;
    try ValidateCore4WireReply(Request,Reply,Batch)
    except on E:ECore4WireError do begin
      Refused:=True;
      { FPC host codepage у CI може транслітерувати кирилицю як ?.
        ASCII D2/word-index залишається фізично точним і обов'язковим. }
      Need((Pos(Fragment,E.Message)>0) and
        ((Pos('=',Fragment)=0) or (Pos('D2',E.Message)>0)),
        'guard '+Why+' мав діагностувати '+Fragment+', отримано: '+E.Message);
    end end;
    Need(Refused,'guard помилково прийняв '+Why);
    Inc(Failed);
  end;

begin
  Req:=PhysicalD7Call(Keys[0],'1');
  Single:=ExactWord('1');
  ValidateCore4WireReply(Req,Single,False);
  ValidateCore4WireReply(Req,ExactWord('000000000000000000000001'),False);
  ValidateCore4WireReply(Req,ExactWord(StringOfChar('0',192)),False);
  { У структурному guard один D2 root може бути складеним,
    хоча чинний Core4 виконавчий канал повертає лише атоми. }
  SetLength(W,3);W[0]:='10';W[1]:='1';W[2]:='01';
  ValidateCore4WireReply(Req,EncodeT5M(W),False);

  Two:=Combine([Req,PhysicalD7Call(Keys[0],'0')]);
  SetLength(W,2); W[0]:='1';W[1]:='0';
  Answer:=EncodeT5M(W);
  ValidateCore4WireReply(Two,Answer,True);

  Many:=RepeatExact(Req,64);
  TooMany:=RepeatExact(Req,65);
  SetLength(W,64);
  for I:=0 to 63 do
    if I mod 2=0 then W[I]:='1' else W[I]:='0';
  ValidateCore4WireReply(Many,EncodeT5M(W),True);

  SetLength(Part,2);Part[0]:='10';Part[1]:='1';
  Incomplete:=EncodeT5M(Part);
  SetLength(Part,1);Part[0]:='01';
  WrongClose:=EncodeT5M(Part);
  Part[0]:='11';WrongDot:=EncodeT5M(Part);

  Reject(Req,'',False,'відповідь','порожню відповідь');
  Reject(Req,Chr(243),False,'T5M','некоректний packed byte');
  Reject(Req,Incomplete,False,'=3:','обірваний D2 у відповіді');
  Reject(Req,WrongClose,False,'=1:','зайве D2-закриття');
  Reject(Req,WrongDot,False,'=1:','крапку D2 без списку');
  Reject(Req,Answer,False,'=2,','два результати single');
  Reject(Two,Single,True,'=1,','відсутню відповідь batch');
  Reject(Two,Incomplete,True,'=3:','пізню незакриту D2 відповідь');
  Reject(Two,Answer,False,'single=1','пакетний запит у single');
  Reject(TooMany,Single,True,'batch=1..64','65 коренів запиту');
  Reject(Incomplete,Single,False,'=3:','неповний D2 запит');
  Reject(WrongClose,Single,False,'=1:','зайве закриття запиту');
  Reject(Chr(243),Single,False,'T5M','неправильні T5M байти запиту');
  Reject(Req,TooMany,True,'=65,','65 результатів на одну форму');
  WriteLn('CORE4-WIRE-D2-ГАРАЗД single=1 batch=2/64 ',
    'W24/W192=opaque D2=exact-negative 14=відхилено');
end;

begin
  if (ParamCount=2) and (Copy(ParamStr(2),1,6)='fault-') then begin
    RunFakeChild(ParamStr(2));
    Halt(0);
  end;
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Використання: test-core4wireclient ROOT BINARY');Halt(64);
  end;
  Root:=ParamStr(1);
  Executable:=ParamStr(2);
  Failed:=0;
  Runtime:=TCore4Runtime.Create(Root);
  try
    Need(Runtime.BindingCount=3,
      'реально завантажено рівно три початкові pinned Core4 DEFINE');
    for I:=0 to 2 do begin
      Keys[I]:=Runtime.BindingIdentifier(I);
      Need((Length(Keys[I])>=7) and (Length(Keys[I]) mod 7=0),
        'повне exact D7 ім’я '+IntToStr(I));
      for J:=1 to Length(Keys[I]) do
        Need(Keys[I][J] in ['0','1'],'кожен D7 гліф має 7 біт');
      for J:=0 to I-1 do
        Need(Keys[I]<>Keys[J],'колізія повних pinned D7 ключів');
      DecodeT5M(PhysicalD7Name(Keys[I]),Words);
      Need((Length(Words)=Length(Keys[I]) div 7+2) and
        (Words[0]='10') and (Words[High(Words)]='01'),
        'фізична D2 оболонка exact D7');
    end;

    { Для фізичних W24 із pinned Core4 не робимо D12+ admission. }
    GuardTests;
    WirePoisonTests;
    Client:=TCore4WireClient.Create(Executable,Root,False);
    try
      PID:=Client.ProcessID;
      Need(PID>0,'реальний дочірній FPC процес');
      Expect(Client.Execute(PhysicalD7Call(Keys[0],'1')),
        ExactWord('1'),'D7 замикання отримує D1:1');
      Expect(Client.Execute(PhysicalD7Call(Keys[0],'0')),
        ExactWord('0'),'те саме замикання отримує D1:0');
      Expect(Client.Execute(PhysicalD7Call(Keys[0],
        '000000000000000000000001')),
        ExactWord('000000000000000000000001'),
        'exact W24 opaque аргумент, не D24-допуск');
      Expect(Client.Execute(PhysicalD7Name(Keys[1])),
        ExactWord('000000000000000000000000'),
        'перший pinned Core4 глобал W24');
      Expect(Client.Execute(PhysicalD7Name(Keys[2])),
        ExactWord('000000000000000000000001'),
        'другий pinned Core4 глобал W24');

      Candidate:=Keys[0];
      if Candidate[1]='0' then Candidate[1]:='1'
      else Candidate[1]:='0';
      for I:=0 to 2 do
        Need(Candidate<>Keys[I],'одно-бітова зміна D7 не є чужим ключем');
      ExpectRemote(Client,PhysicalD7Call(Candidate,'1'),
        'пошкоджений один D7-біт');

      Need(Length(Keys[0])>=14,'префіксний D7-негатив');
      ExpectRemote(Client,PhysicalD7Call(
        Copy(Keys[0],1,Length(Keys[0])-7),'1'),
        'втрачений повний D7 гліф');
      ExpectRemote(Client,PhysicalD7Call(Keys[0]+'0000000','1'),
        'зайвий повний D7 гліф');
      ExpectRemote(Client,PhysicalD7Call(Keys[1],'1'),
        'Core4 глобал не замикання');
      ExpectRemote(Client,PhysicalD7Name(Keys[0]),
        'Core4 замикання не глобал');

      ExpectLocalD7(Copy(Keys[0],1,Length(Keys[0])-1),
        'неповний 6-бітовий останній гліф');
      ExpectLocalD7(Keys[0]+'2','трійкова пауза — не D7 біт');
      ExpectLocalD7('','порожній D7 ключ');
      ExpectLocalFrame(Client,Chr(243),'байт поза T5M base-3');
      ExpectLocalFrame(Client,StringOfChar(#0,1024*1024+1),
        'межа 1 МіБ до алокації відповіді');
      Need(Client.ProcessID=PID,'всі відмови у тому самому PID');
      LocalD2Tests(Client,False);
      Expect(Client.Execute(PhysicalD7Call(Keys[0],'1')),
        ExactWord('1'),'справжнє виконання після 10 негативних перевірок');

      { Чинний режим --канал приймає ЛИШЕ одну форму. }
      Physical:=Combine([PhysicalD7Call(Keys[0],'1'),
        PhysicalD7Call(Keys[0],'0')]);
      { Тепер два цілі D2 корені відхиляються ЛОКАЛЬНО до pipe,
        а не remote Core4: без залишкової відповіді в процесі. }
      ExpectLocalPreflight(Client,Physical,'single=1',
        'дві форми в single-mode');
      Need(Client.ProcessID=PID,'single-mode дочірній процес зберігся');
    finally Client.Free end;

    Batch:=TCore4WireClient.Create(Executable,Root,True);
    try
      PID:=Batch.ProcessID;
      Physical:=Combine([PhysicalD7Call(Keys[0],'1'),
        PhysicalD7Call(Keys[0],'0'),
        PhysicalD7Name(Keys[2])]);
      SetLength(Words,3);
      Words[0]:='1';Words[1]:='0';
      Words[2]:='000000000000000000000001';
      Expected:=EncodeT5M(Words);
      Expect(Batch.Execute(Physical),Expected,
        '3 реальні pinned фізичні форми одним пакетом');
      Candidate:=Keys[0];
      if Candidate[1]='0' then Candidate[1]:='1'
      else Candidate[1]:='0';
      ExpectRemote(Batch,Combine([
        PhysicalD7Call(Keys[0],'1'),
        PhysicalD7Call(Candidate,'0')]),
        'пізня неіснуюча D7 форма без часткового результату');
      Need(Batch.ProcessID=PID,'пакетна відмова не перезапустила PID');
      LocalD2Tests(Batch,True);
      Expect(Batch.Execute(Physical),Expected,
        'відновити пакет у тому самому FPC процесі');
      { Реальне виконання 64 pinned Core4 замикань, а не тільки
        структурне читання 64 форм; результат має 64 фізичні W1. }
      Expect(Batch.Execute(RepeatPhysical(PhysicalD7Call(Keys[0],'1'),64)),
        RepeatPhysical(ExactWord('1'),64),
        '64 реальних Core4 форм одним фізичним кадром');
      Need(Batch.ProcessID=PID,'64 виконання не перезапустило процес');
    finally Batch.Free end;
    WriteLn('CORE4-ПОПЕРЕДНІЙ-D2-ГАРАЗД local=11 ',
      'remote-не-зачеплено=так same-PID=так batch64=реально ',
      'T5M/D2=канонічно');
    WriteLn(RawByteString(UTF8Encode(UnicodeString(
      'D7-КЛІЄНТ-ГАРАЗД pinned=core4.sens визначень=3 '+
      'колізії=ні exact-D7=так W1-W24=побайтово '+
      'негативи='+IntToStr(Failed)+
      ' один-PID=так пакет=3 відновлення=так REPL=ні'))));
  finally Runtime.Free end;
end.
