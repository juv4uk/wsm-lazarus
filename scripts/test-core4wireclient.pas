{ G5.30 — справжній клієнт довгоживучого Core4 з pinned D7.
  Три початкові DEFINE та їхні ключі читаємо лише з core4.sens;
  людське написання «укр» тут не потрібне для dispatch. }
program test_core4wireclient;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.core4wireclient, wsm.core4runtime, wsm.t5m;
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

begin
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
      Expect(Client.Execute(PhysicalD7Call(Keys[0],'1')),
        ExactWord('1'),'справжнє виконання після 10 негативних перевірок');

      { Чинний режим --канал приймає ЛИШЕ одну форму. }
      Physical:=Combine([PhysicalD7Call(Keys[0],'1'),
        PhysicalD7Call(Keys[0],'0')]);
      ExpectRemote(Client,Physical,'дві форми в single-mode');
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
      Expect(Batch.Execute(Physical),Expected,
        'відновити пакет у тому самому FPC процесі');
    finally Batch.Free end;
    WriteLn(RawByteString(UTF8Encode(UnicodeString(
      'D7-КЛІЄНТ-ГАРАЗД pinned=core4.sens визначень=3 '+
      'колізії=ні exact-D7=так W1-W24=побайтово '+
      'негативи='+IntToStr(Failed)+
      ' один-PID=так пакет=3 відновлення=так REPL=ні'))));
  finally Runtime.Free end;
end.
