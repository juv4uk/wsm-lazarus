{ G3.12 — амортизований вивід exact native cells; не новий SENS закон. }
program test_native_render;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.binaryexec, wsm.nativeeval;
var E:TBinaryExecutor; Native:TNativeEvaluator; Checks:SizeInt;

procedure Require(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create('NATIVE-RENDER-FAIL '+Why);
end;

function Physical(const Values:array of RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Values));
  for I:=0 to High(Values) do W[I]:=Values[I];
  Result:=EncodeT5M(W);
end;

function FlatQuote(Atoms:SizeInt):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Atoms+5);
  W[0]:='10'; W[1]:='001'; W[2]:='10';
  for I:=0 to Atoms-1 do W[I+3]:='1';
  W[Atoms+3]:='01'; W[Atoms+4]:='01';
  Result:=EncodeT5M(W);
end;

procedure CheckQuote(Atoms:SizeInt);
var Answer,Expected:RawByteString; I:SizeInt;
begin
  Expected:='(';
  for I:=1 to Atoms do begin
    if I>1 then Expected:=Expected+' ';
    Expected:=Expected+'1';
  end;
  Expected:=Expected+')';
  Answer:=E.ExecutePhysical(FlatQuote(Atoms));
  Require(Answer=Expected,'плоский список N='+IntToStr(Atoms));
  Require(Length(Answer)=Length(Expected),'змінено довжину exact тексту');
end;

procedure CheckReject(const Payload:RawByteString; const Why:String);
var Failed:Boolean; Answer:RawByteString;
begin
  Failed:=False; Answer:='';
  try Answer:=E.ExecutePhysical(Payload);
  except on X:EBinaryExecutionError do Failed:=True; end;
  Require(Failed,Why+' було прийнято');
  Require(Answer='',Why+' залишило частковий результат');
end;

begin
  Checks:=0;
  E:=TBinaryExecutor.Create('external/sens');
  Native:=TNativeEvaluator.Create('external/sens');
  try
    CheckQuote(0);
    CheckQuote(1);
    CheckQuote(2);
    CheckQuote(65);   { перший перехід ємності 64 байти }
    CheckQuote(100);
    CheckQuote(1024);
    CheckQuote(2000); { 4001 output bytes, ~4001 native cells }
    Require(E.ExecutePhysical(Physical([
      '10','001','10','1','10','0','1','01','01','01']))=
      '(1 (0 1))','вкладене цитування');
    Require(E.ExecutePhysical(Physical([
      '10','001','10','000','1','01','01']))=
      '(() 1)','D3:000 не має стати D1:0');
    Require(E.ExecutePhysical(Physical([
      '10','001','111111111','01']))=
      '111111111','не збережено дев’ять точних бітів');
    Require(Native.EvaluateSource('(сполучити так ні)')='(1 . 0)',
      'крапкова пара через чинний D3:111');
    Require(Native.EvaluateSource('(сполучити (сполучити так ні) ні)')=
      '((1 . 0) . 0)','вкладена крапкова пара');
    CheckReject(#243,'неприпустимий байт T5M');
    CheckReject(Physical(['10','001','1','0','01']),
      'помилкова арність D3:001');
    CheckReject(FlatQuote(2050),'перевищення ліміту native arena');
    CheckQuote(1024); { той самий executor після кількох відмов }
    WriteLn('NATIVE-RENDER-OK checks=',Checks,
      ' FPC=реальний exact=побітовий вивід',
      ' flat=2000 nested=так dotted=так',
      ' empty=D3:000 failclosed=так heaptrc=перевіряє-CI');
  finally
    Native.Free;
    E.Free;
  end;
end.
