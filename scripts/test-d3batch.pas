{ G3.16: справжні незалежні D3 форми → одна фізична T5M відповідь. }
program test_d3batch;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.d3batch;
var Checks, Negatives: SizeInt;

procedure Check(Value:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Value then raise Exception.Create('ПАКЕТ-D3-ПОМИЛКА: '+Why);
end;

function Pack(const W:array of RawByteString):RawByteString;
var V:TExactWords; I:SizeInt;
begin
  SetLength(V,Length(W));
  for I:=0 to High(W) do V[I]:=W[I];
  Result:=EncodeT5M(V);
end;

procedure Good(const Source,Expected:RawByteString;
  Count:SizeInt; const Why:String);
var Actual:RawByteString; Forms:SizeInt; W:TExactWords; Doc:TD2Document;
begin
  Actual:='зіпсований'; Forms:=99;
  ExecutePhysicalD3Batch(Source,'external/sens',Actual,Forms);
  Check(Forms=Count,Why+': кількість реально виконаних D3 форм');
  Check(Actual=Expected,Why+': фізична відповідь побайтово');
  DecodeT5M(Actual,W);
  Check(EncodeT5M(W)=Actual,Why+': зворотна канонічність');
  Doc:=ReadD2T5M(Actual);
  try Check(Length(Doc.Roots)=Count,Why+': D2 root результату');
  finally Doc.Free; end;
end;

procedure Bad(const Source:RawByteString; FormIndex, WordIndex:SizeInt;
  const Why:String);
var Actual:RawByteString; Forms:SizeInt; Failed:Boolean;
begin
  Actual:='старий результат'; Forms:=90; Failed:=False;
  try
    ExecutePhysicalD3Batch(Source,'external/sens',Actual,Forms);
  except
    on E:ED3BatchError do begin
      Failed:=True;
      Check(E.FormIndex=FormIndex,Why+': неправильна форма відмови');
      Check(E.WordIndex=WordIndex,Why+': неправильне фізичне слово');
    end;
  end;
  Check(Failed,Why+': помилковий пакет було виконано');
  Check((Actual='') and (Forms=0),
    Why+': видано часткову відповідь після відмови');
  Inc(Negatives);
end;

function Many(Count:SizeInt):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Count);
  for I:=0 to Count-1 do
    if (I and 1)=0 then W[I]:='0' else W[I]:='1';
  Result:=EncodeT5M(W);
end;

begin
  Checks:=0; Negatives:=0;
  Good(Pack(['0']),Pack(['0']),1,'один реальний D1');
  Good(Pack(['000']),Pack(['000']),1,
    'порожнє D3:000 не тотожне D1:0');
  Good(Pack(['0','00','10','001','000','01','00',
      '10','111','1','0','01','111111111']),
      Pack(['0','000','10','1','11','0','01','111111111']),4,
      'чотири незалежні pinned D3 форми з D2:00 і W9');
  Good(Pack(['10','101','1','1','01','0']),
       Pack(['1','0']),2,'справжня D3:101 і D1:0');
  Good(Many(64),Many(64),64,'граничні 64 D1 форми');
  Bad(Many(65),0,0,'65 окремих коренів заборонено');
  Bad('',0,0,'порожній фізичний файл');
  Bad(#243,0,0,'неканонічний T5M');
  Bad(Pack(['0','10','001','1','0','01']),2,2,
    'пізня D3:001 з хибною арністю');
  Bad(Pack(['0','10','1','11','0','01']),2,2,
    'пізня вхідна D2 крапкова пара');
  Bad(Pack(['0','10','001','000000000000','01']),2,2,
    'пізній D12+ без допуску');
  Good(Pack(['10','001','000','01','1']),
       Pack(['000','1']),2,
       'відновлення без старої відповіді після відмов');
  WriteLn('ПАКЕТ-D3-ГАРАЗД перевірок=',Checks,
    ' негативних=',Negatives,' максимум=64',
    ' відмова=атомарна T5M=побайтово pinned=так',
    ' Core4=НЕ-ДОВЕДЕНО REPL=НЕ-ДОВЕДЕНО');
end.
