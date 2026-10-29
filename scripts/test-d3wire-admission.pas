{ G5.40: тільки фізичний admission відповіді постійного D3 каналу.
  Не обчислює SENS семантику; справжній runtime перевіряє чинний LCL CI. }
program test_d3wire_admission;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.d3wireclient;
var Tested,Rejected,CheckedRequest,BlockedRequest:SizeInt;
function Ua(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('ТЕСТ-Д3-КАНАЛ: '+Why) end;

function Pack(const Parts:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Parts));
  for I:=0 to High(Parts) do Words[I]:=Parts[I];
  Result:=EncodeT5M(Words);
end;

function ManyRoots(N:SizeInt):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,N);
  for I:=0 to N-1 do begin
    if (I mod 2)=0 then Words[I]:='1' else Words[I]:='0';
  end;
  Result:=EncodeT5M(Words);
end;

procedure Good(const Request,Reply:RawByteString;const Why:String);
var OldRequest,OldReply:RawByteString;
begin
  OldRequest:=Request;OldReply:=Reply;
  ValidateD3WireReply(Request,Reply);
  Need((Request=OldRequest) and (Reply=OldReply),Why+': фізичні байти змінилися');
  Inc(Tested);
end;

procedure Bad(const Request,Reply:RawByteString;
  const Why,Expected:String);
var Got:Boolean;
begin
  Got:=False;
  try ValidateD3WireReply(Request,Reply);
  except
    on E:ED3WireError do begin
      Got:=True;
      if Expected<>'' then
        Need(Pos(Expected,E.Message)>0,Why+': втрачено діагностику '+E.Message);
    end;
  end;
  Need(Got,Why+': помилково допущено');
  Inc(Rejected);
end;


{ Окремий host admission запиту — без запуску зовнішнього процесу.
  Це гарантує, що синтаксична відмова стається ДО WriteBuffer. }
procedure GoodRequest(const Physical:RawByteString;const Why:String);
var CopyOfInput:RawByteString;
begin
  CopyOfInput:=Physical;
  ValidateD3WireRequest(Physical);
  Need(Physical=CopyOfInput,Why+': пошкоджено фізичні байти');
  Inc(CheckedRequest);
end;

procedure BadRequest(const Physical:RawByteString;
  const Why,Expected:String);
var RejectedInput:Boolean;
begin
  RejectedInput:=False;
  try ValidateD3WireRequest(Physical);
  except
    on E:ED3WireError do begin
      RejectedInput:=True;
      if Expected<>'' then
        Need(Pos(Expected,E.Message)>0,Why+': втрачено позицію '+E.Message);
    end;
  end;
  Need(RejectedInput,Why+': фізичний запит помилково прийнято');
  Inc(BlockedRequest);
end;

var Single,Two,Four,SixtyFour,Wide,Opening,Closing,OneList:RawByteString;
begin
  Tested:=0;Rejected:=0;CheckedRequest:=0;BlockedRequest:=0;
  Single:=Pack(['1']);
  Two:=Pack(['1','0']);
  Four:=ManyRoots(4);
  SixtyFour:=ManyRoots(64);
  Wide:=Pack(['000000000000000000000001']);
  Opening:=Pack(['10','1']);
  Closing:=Pack(['01']);
  OneList:=Pack(['10','1','01']);
  GoodRequest(Single,'одна D1 форма на вході');
  GoodRequest(Two,'дві форми на вході');
  GoodRequest(Four,'чотири форми на вході');
  GoodRequest(SixtyFour,'64 форми на вході');
  GoodRequest(Wide,'непрозорий W24 на вході');
  GoodRequest(OneList,'повністю закрита D2 форма на вході');
  BadRequest('', 'порожній запит', '');
  BadRequest(#$F3, 'неприпустимий T5M', 'T5M');
  BadRequest(Closing,'D2 CLOSE без OPEN','слово=1');
  BadRequest(Opening,'незакритий D2 OPEN','слово=3');
  BadRequest(Pack(['11']),'D2 крапка без списку','слово=1');
  BadRequest(Pack(['0','11']),'крапка після атома','слово=2');
  BadRequest(ManyRoots(65),'65 коренів запиту','1..64');
  BadRequest(StringOfChar(#0,MaxD3WireBytes+1),
    'перевищений обсяг фізичного кадру','');
  Good(Single,Pack(['0']),'одна D1 форма');
  Good(Two,Pack(['0','1']),'дві незалежні D1 форми');
  Good(Four,ManyRoots(4),'чотири форми');
  Good(SixtyFour,ManyRoots(64),'64 форми');
  Good(Single,Wide,'непрозорий W24 результат, не D12 числова семантика');
  Good(OneList,Single,'одна повністю закрита D2 форма');

  Bad(Two,Single,'загублено другу відповідь','D2 1');
  Bad(Single,Two,'зайва відповідь','D2 2');
  Bad(Single,Closing,'D2 CLOSE без OPEN','=1');
  Bad(Single,Opening,'D2 незакрита','=3');
  Bad(Single,#$F3,'недозволений T5M байт','T5M');
  Bad(Single,'','порожня фізична відповідь','');
  Bad('',Single,'порожній запит','');
  Bad(Closing,Single,'некоректний запит','=1');
  Bad(ManyRoots(65),ManyRoots(65),'більше 64 коренів','1..64');
  Bad(Single,Pack(['11']),'D2 крапка без списку','=1');
  WriteLn(Ua('Д3-КАНАЛ-ЗАПИТ-ГАРАЗД FPC=так позитиви='),CheckedRequest,
    Ua(' негативи='),BlockedRequest,Ua(' до-pipe=так D2=повністю'));
  WriteLn(Ua('Д3-КАНАЛ-ДОПУСК-ГАРАЗД FPC=так позитиви='),Tested,
    Ua(' негативи='),Rejected,Ua(' W24=непрозоро D2=повністю'));
end.
