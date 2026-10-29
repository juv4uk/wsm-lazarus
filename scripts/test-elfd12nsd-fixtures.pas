{ G6.101 — лише фізичні fixtures D12 для перевірки НСД.
  Людські десяткові числа використовуються ТІЛЬКИ в тестовому генераторі.
  Канонічні W12 T5M байти створює pinned-compatible wsm.numericplane.
  1) Чому fixture — не джерело мовного закону? 2) Де exact width?
  3) Чому окреме очікуване фізичне слово? 4) Кому належить FileStream?
  5) Чому негативи не створюють ELF? }
program test_elfd12nsd_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String; Cases:SizeInt;
procedure Save(const FileName:String;const Value:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+FileName,fmCreate);
  try
    if Length(Value)>0 then F.WriteBuffer(Value[1],Length(Value));
  finally F.Free end;
end;
procedure Pair(const LabelText,LeftDecimal,RightDecimal,ExpectedDecimal:RawByteString);
begin
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(LeftDecimal,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(RightDecimal,12));
  Save(String(LabelText)+'-expected.sens',EncodeNumericDecimal(ExpectedDecimal,12));
  Inc(Cases);
end;
var W:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);Cases:=0;
  if not ForceDirectories(Dir) then Halt(2);
  Pair('01','12','18','6');
  Pair('02','24','54','6');
  Pair('03','13','17','1');
  Pair('04','21','21','21');
  Pair('05','2047','2046','1');
  Pair('06','2047','2047','2047');
  Pair('07','144','36','36');
  Pair('08','987','610','1');
  Save('zero.sens',EncodeNumericDecimal('0',12));
  Save('negative.sens',EncodeNumericDecimal('-1',12));
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  SetLength(W,1);W[0]:='0';Save('bad1.sens',EncodeT5M(W));
  W[0]:='0000000';Save('bad7.sens',EncodeT5M(W));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  { Machine sentinel ASCII: FPC WriteLn може перетворити кирилицю
    через системну кодову сторінку; закони й фізичні байти не зачеплено. }
  WriteLn('D12-НСД-ФІКСТУРИ-ГОТОВО cases=',Cases,' negatives=8 width=D12');
end.
