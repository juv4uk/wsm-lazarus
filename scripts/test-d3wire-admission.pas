{ G5.40: тільки фізичний admission відповіді постійного D3 каналу.
  Не обчислює SENS семантику; справжній runtime перевіряє чинний LCL CI. }
program test_d3wire_admission;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.d3wireclient;
var Tested,Rejected:SizeInt;

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
      Need(Pos(Expected,E.Message)>0,Why+': втрачено діагностику '+E.Message);
    end;
  end;
  Need(Got,Why+': помилково допущено');
  Inc(Rejected);
end;

var Single,Two,Four,SixtyFour,Wide,Opening,Closing,OneList:RawByteString;
begin
  Tested:=0;Rejected:=0;
  Single:=Pack(['1']);
  Two:=Pack(['1','0']);
  Four:=ManyRoots(4);
  SixtyFour:=ManyRoots(64);
  Wide:=Pack(['000000000000000000000001']);
  Opening:=Pack(['10','1']);
  Closing:=Pack(['01']);
  OneList:=Pack(['10','1','01']);
  Good(Single,Pack(['0']),'одна D1 форма');
  Good(Two,Pack(['0','1']),'дві незалежні D1 форми');
  Good(Four,ManyRoots(4),'чотири форми');
  Good(SixtyFour,ManyRoots(64),'64 форми');
  Good(Single,Wide,'непрозорий W24 результат, не D12 числова семантика');
  Good(OneList,Single,'одна повністю закрита D2 форма');

  Bad(Two,Single,'загублено другу відповідь','кількість коренів');
  Bad(Single,Two,'зайва відповідь','кількість коренів');
  Bad(Single,Closing,'D2 CLOSE без OPEN','слово=1');
  Bad(Single,Opening,'D2 незакрита','слово=3');
  Bad(Single,#$F3,'недозволений T5M байт','T5M');
  Bad(Single,'','порожня фізична відповідь','довжина');
  Bad('',Single,'порожній запит','довжина');
  Bad(Closing,Single,'некоректний запит','слово=1');
  Bad(ManyRoots(65),ManyRoots(65),'більше 64 коренів','1..64');
  Bad(Single,Pack(['11']),'D2 крапка без списку','слово=1');
  WriteLn('Д3-КАНАЛ-ДОПУСК-ГАРАЗД FPC=так позитиви=',Tested,
    ' негативи=',Rejected,' W24=непрозоро D2=повністю');
end.
