{ G3.10: справжня фізична D3:001, без українського відновлення синтаксису. }
program test_native_quote;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.binaryexec;
var Engine:TBinaryExecutor; Checks:SizeInt;

procedure Must(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create('ЦИТАТА-ПРОВАЛ: '+Why);
end;

function Bytes(const A:array of RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(A));
  for I:=0 to High(A) do W[I]:=A[I];
  Result:=EncodeT5M(W);
end;

procedure Expect(const A:array of RawByteString; const Expected:RawByteString);
var Actual:RawByteString;
begin
  Actual:=Engine.ExecutePhysical(Bytes(A));
  Must(Actual=Expected,'неправильні exact біти: '+String(Actual));
end;

procedure Reject(const A:array of RawByteString; AtWord:SizeInt);
var Failed:Boolean;
begin
  Failed:=False;
  try
    Engine.ExecutePhysical(Bytes(A));
  except on E:EBinaryExecutionError do begin
    Failed:=True;
    Must(E.WordIndex=AtWord,'неправильна фізична позиція: '+IntToStr(E.WordIndex));
  end; end;
  Must(Failed,'заборонену форму прийнято');
end;

var Failed:Boolean;
begin
  Checks:=0;
  Engine:=TBinaryExecutor.Create('external/sens');
  try
    Expect(['10','001','1','01'],'1');
    Expect(['10','001','0','01'],'0');
    Expect(['10','001','000','01'],'()'); { empty не false }
    Expect(['10','001','001','01'],'001'); { функція як непрозорі дані }
    Expect(['10','001','111111111','01'],'111111111'); { усі 9 бітів }
    Expect(['10','001','10','1','0','01','01'],'(1 0)');
    Expect(['10','001','10','111','1','000','01','01'],
      '(111 1 ())'); { жодного виклику D3:111 }
    Expect(['10','001','10','100','10','111','1','000','01','01','01'],
      '(100 (111 1 ()))'); { quote не виконує CAR }
    Expect(['10','001','10','01','01'],'()'); { empty list }

    Reject(['10','001','01'],1); { немає аргументу }
    Reject(['10','001','1','0','01'],1); { два аргументи }
    { Це точні фізичні T5M слова одного D3:001 кореня; pinned SENS
      повертає крапкову пару як значення, а не виконує її. Очікуємо
      українську проєкцію native-відповіді, зберігаючи D2 форму у тестовому
      масиві лише до синхронного виклику. Питання: що саме цитує D3:001?
      Чому D2 пара лишається даними? Де забороняється виконання пари? }
    Expect(['10','001','10','1','11','0','01','01'],'(1 . 0)');
    Reject(['10','001','000000000000','01'],3); { W12 поза binder }
    Failed:=False;
    try Engine.ExecutePhysical(#243);
    except on E:EBinaryExecutionError do begin
      Failed:=True;
      Must(E.WordIndex=0,'неправильна позиція T5M');
    end; end;
    Must(Failed,'T5M 243 прийнято');
    Expect(['10','001','10','0','1','01','01'],'(0 1)');
    Expect(['1'],'1'); { recovery після відмов }
    WriteLn('ЦИТАТА-ДВІЙКОВА-ГАРАЗД перевірок=',Checks,
      ' pinned=D3:001 exact=D1-D9, D3:000=структура',
      ' proper-list=так bounded=так W12=відмова oracle=окремо');
  finally
    Engine.Free;
  end;
end.
