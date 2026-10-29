{ Механічні позитиви/негативи точного порівняння двох фізичних T5M. }
program test_t5mdiff;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.t5mdiff;
var D:TPhysicalDifference;
    L,R,E,Extra,Bad:RawByteString;
    Positives,Negatives:SizeInt;
function W(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;
procedure WriteFile(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
procedure Demand(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('РІЗНИЦЯ-ТЕСТ-ПОМИЛКА: '+Why) end;
procedure Negative(const A,B:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try ComparePhysical(A,B,D)
  except on X:Exception do Rejected:=True end;
  Demand(Rejected,Why);
  Demand((not D.Equal) and (D.WordIndex=0) and
    (D.LeftBits='') and (D.RightBits=''),
    'відмова залишила попередні дані');
  Inc(Negatives);
end;
begin
  if ParamCount<>1 then Halt(64);
  Positives:=0;Negatives:=0;
  L:=EncodeT5M(W(['10','0','1111111']));
  R:=EncodeT5M(W(['10','000','1111111']));
  E:=L;
  Extra:=EncodeT5M(W(['10','0','1111111','1']));
  Bad:=#$F3;
  WriteFile(ParamStr(1)+'/left.sens',L);
  WriteFile(ParamStr(1)+'/right.sens',R);
  WriteFile(ParamStr(1)+'/bad.sens',Bad);
  ComparePhysical(L,E,D);
  Demand(D.Equal and (D.WordIndex=0),'рівні файли');
  Inc(Positives);
  ComparePhysical(L,R,D);
  Demand((not D.Equal) and (D.WordIndex=2) and
    D.LeftPresent and D.RightPresent and
    (D.LeftBits='0') and (D.RightBits='000'),
    'префікс бітів не означає однакову ширину');
  Demand((D.LeftSpan.TritStart=3) and (D.LeftSpan.TritEnd=4) and
    (D.RightSpan.TritStart=3) and (D.RightSpan.TritEnd=6) and
    (D.LeftSpan.WordIndex=2) and (D.RightSpan.WordIndex=2),
    'помилкові фізичні координати');
  Inc(Positives);
  ComparePhysical(L,Extra,D);
  Demand((not D.Equal) and (D.WordIndex=4) and
    (not D.LeftPresent) and D.RightPresent and
    (D.RightBits='1') and D.LeftSpan.IsEOF,
    'додане слово на EOF');
  Inc(Positives);
  Negative(Bad,L,'недопустимий перший T5M');
  Negative(L,Bad,'недопустимий другий T5M');
  Negative('',L,'порожній фізичний документ');
  Negative(L,#$F4,'неканонічний фізичний байт');
  Demand((Positives=3) and (Negatives=4),'кількість перевірок');
  WriteLn('T5M-РІЗНИЦЯ-ГАРАЗД позитивних=',Positives,
    ' негативних=',Negatives,' відмова=атомарна EOF=точний');
end.
