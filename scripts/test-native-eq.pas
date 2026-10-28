{ G3.8: фізичне виконання D3:101 над D1, без host-оракула.
  Pinned SENS Contract 12 визначає закон; нативний FPC лише механізм. }
program test_native_eq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.binaryexec, wsm.nativeeval, wsm.t5m;
var
  Engine:TBinaryExecutor;
  Native:TNativeEvaluator;
  Checks:SizeInt;
procedure Require(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create('ТОТОЖНІСТЬ-ПРОВАЛ: '+Why);
end;
function Physical(const Source:array of RawByteString):RawByteString;
var Words:TExactWords; I:SizeInt;
begin
  SetLength(Words,Length(Source));
  for I:=0 to High(Source) do Words[I]:=Source[I];
  Result:=EncodeT5M(Words);
end;
procedure Expect(const Source:array of RawByteString; const Expected:RawByteString);
var Actual:RawByteString;
begin
  Actual:=Engine.ExecutePhysical(Physical(Source));
  Require(Actual=Expected,'точне фізичне виконання');
end;
procedure Reject(const Source:array of RawByteString; WordAt:SizeInt);
var Rejected:Boolean;
begin
  Rejected:=False;
  try Engine.ExecutePhysical(Physical(Source));
  except on E:EBinaryExecutionError do begin
    Rejected:=True;
    if WordAt>=0 then
      Require(E.WordIndex=WordAt,'точна 1-based позиція фізичної помилки');
  end; end;
  Require(Rejected,'непідтверджений D3:101 був прийнятий');
end;
procedure Save(const Name:String;const Source:array of RawByteString);
var Bytes:RawByteString; Stream:TFileStream;
begin
  Bytes:=Physical(Source);
  Stream:=TFileStream.Create(Name,fmCreate);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free; end;
end;
var Rejected:Boolean;
begin
  Checks:=0; Engine:=TBinaryExecutor.Create('external/sens');
  try
    { Усі чотири D1 пари через справжні T5M/D2/binder/evaluator. }
    Expect(['10','101','0','0','01'],'1');
    Expect(['10','101','1','1','01'],'1');
    Expect(['10','101','0','1','01'],'0');
    Expect(['10','101','1','0','01'],'0');
    Expect(['10','101','10','010','000','01','1','01'],'1');
    Expect(['10','010','10','101','0','1','01','01'],'1');
    Expect(['10','101','10','101','1','0','01','0','01'],'1');
    { Невідповідні значення або форма не створюють D1 результат. }
    Reject(['10','101','000','1','01'],3);
    Reject(['10','101','1','000','01'],4);
    Reject(['10','101','10','111','1','000','01','1','01'],3);
    Reject(['10','101','1','10','111','1','000','01','01'],4);
    Reject(['10','101','1111111','1','01'],3);
    Reject(['10','101','1','1111111','01'],4);
    Reject(['10','101','1','01'],1); { недостатньо аргументів }
    Reject(['10','101','0','1','1','01'],1);
    Reject(['10','110','1','01'],3); { невалідна атомна гілка D3:110 досі BLOCKED }
    Expect(['10','001','1','01'],'1'); { фізична D3:001 тепер виконується }
    Expect(['10','101','0','0','01'],'1'); { відновлення після відмов }
    Rejected:=False;
    try Engine.ExecutePhysical(#243);
    except on E:EBinaryExecutionError do begin
      Rejected:=True;
      Require(E.WordIndex=0,'зіпсований фізичний байт не має адреси слова');
    end; end;
    Require(Rejected,'пошкоджений T5M прийнято');
    Expect(['10','101','1','0','01'],'0');
    Save('build/m0.2/native-eq-positive.sens',['10','101','1','1','01']);
    Save('build/m0.2/native-eq-negative.sens',['10','101','000','1','01']);
  finally Engine.Free end;
  Native:=TNativeEvaluator.Create('external/sens');
  try
    Require(Native.EvaluateSource('(тотожне? так так)')='1','укр позитив');
    Require(Native.EvaluateSource('(тотожне? так ні)')='0','укр негатив');
    Require(Native.EvaluateSource('(тотожне? (атом? ()) так)')='1',
      'укр обчислений атом');
    Rejected:=False;
    try Native.EvaluateSource('(тотожне? () так)');
    except on E:Exception do Rejected:=True; end;
    Require(Rejected,'неприпустимий порожній атом');
  finally Native.Free end;
  WriteLn('ТОТОЖНІСТЬ-ГАРАЗД перевірок=',Checks,
    ' фізичний=T5M/D2 exact=D3:101+D1 негативні=так Core4=не-виконується');
end.
