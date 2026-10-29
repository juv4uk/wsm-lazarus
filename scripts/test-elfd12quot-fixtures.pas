{ G6.78 — фізичні D12-атоми, тільки transport fixtures, не семантичний oracle.
  Borrowed decimal input — лише host fixture конструктор; Output: exact
  канонічні .sens T5M байти з єдиного wsm.numericplane.
  1) Чому human decimal тільки в test fixture? 2) Чому D12 не D1?
  3) Хто звільняє stream? 4) Чому від'ємні — негативи?
  5) Чи створюється повторно готовий ELF у цьому генераторі? (ні) }
program test_elfd12quot_fixtures;
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
procedure Pair(const LabelText,Decimal:RawByteString);
begin
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(Decimal,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(Decimal,12));
  Save(String(LabelText)+'-expected.sens',EncodeNumericDecimal('1',12));
  Inc(Cases);
end;
var W:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);Cases:=0;
  if not ForceDirectories(Dir) then Halt(2);
  Pair('01','1');Pair('02','2');Pair('03','7');
  Pair('04','31');Pair('05','1024');Pair('06','2047');
  Save('zero.sens',EncodeNumericDecimal('0',12));
  Save('negative.sens',EncodeNumericDecimal('-1',12));
  Save('unequal.sens',EncodeNumericDecimal('6',12));
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  SetLength(W,1);W[0]:='0';Save('bad1.sens',EncodeT5M(W));
  W[0]:='0000000';Save('bad7.sens',EncodeT5M(W));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  WriteLn('D12-IDIV-СВІДКИ-ГАРАЗД позитивів=',Cases,
    ' негативних=8 домен=D12 не-семантичний-оракул');
end.
