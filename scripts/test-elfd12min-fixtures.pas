{ G6.84 — фізичні D12 T5M свідки для signed min.
  Decimal only test host projection; semantic oracle separately pinned SENS.
  Результат порівнюється як exact packed T5M, не Unicode. }
program test_elfd12min_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;

var Dir:String; Cases:SizeInt;

{ Destination file owned by TFileStream; Bytes — borrowed raw T5M.
  1) Чому .sens саме packed? 2) Де explicit D12?
  3) Чому цей тест не визначає закон min? }
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Pair(const LabelText,L,R,Expected:RawByteString);
begin
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(L,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(R,12));
  Save(String(LabelText)+'-expected.sens',EncodeNumericDecimal(Expected,12));
  WriteLn(LabelText,#9,L,#9,R,#9,Expected);
  Inc(Cases);
end;
var W:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Cases:=0;
  Pair('01','0','0','0');
  Pair('02','0','1','0');
  Pair('03','1','0','0');
  Pair('04','31','42','31');
  Pair('05','42','31','31');
  Pair('06','2047','2047','2047');
  Pair('07','2046','2047','2046');
  Pair('08','2047','2046','2046');
  Pair('09','-1','0','-1');
  Pair('10','0','-1','-1');
  Pair('11','-7','-3','-7');
  Pair('12','-3','-7','-7');
  Pair('13','-2048','2047','-2048');
  Pair('14','2047','-2048','-2048');
  Pair('15','-2048','-2048','-2048');
  Pair('16','-2047','-2048','-2048');
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  SetLength(W,1); W[0]:='1'; Save('bad1.sens',EncodeT5M(W));
  W[0]:='0101010'; Save('bad7.sens',EncodeT5M(W));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  Save('projection.lisp','(найменше -7 -3)'+#10);
  if Cases<>16 then Halt(3);
  WriteLn(StdErr,'D12-MIN-FIXTURES-OK cases=',Cases);
end.
