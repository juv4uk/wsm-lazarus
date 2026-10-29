{ G6.85 — механічні фізичні D12/D1 свідки. НЕ semantic oracle.
  Canonical T5M формує лише чинний wsm.numericplane/wsm.t5m.
  Питання: чому Truth є точним D1 словом, не host Boolean?
  Чому ширина D12 ніколи не виводиться з довжини file?
  Чому текстові числа у manifest — лише очікування тесту?
  Як негативний D24 input не перетворюється неявно на D12? }
program test_elfd12addzero_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;Total:SizeInt;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

{ Values — borrowed host test literals; Truth — already determined D1
  expected from pinned cases (SENS REPL independently decides parity).
  Result files — owned physical buffers created by EncodeT5M. }
procedure Pair(const Name:String;const A,B,Truth:RawByteString);
var Words:TExactWords;
begin
  Save(Name+'-a.sens',EncodeNumericDecimal(A,12));
  Save(Name+'-b.sens',EncodeNumericDecimal(B,12));
  SetLength(Words,1);
  Words[0]:=Truth;
  Save(Name+'-expected.sens',EncodeT5M(Words));
  WriteLn(Name,#9,A,#9,B,#9,Truth);
  Inc(Total);
end;

var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Dir) then Halt(2);
  Total:=0;
  Pair('01','0','0','1');
  Pair('02','1','-1','1');
  Pair('03','-2048','2047','0');
  Pair('04','2047','-2047','1');
  Pair('05','2047','0','0');
  Pair('06','-2048','0','0');
  Pair('07','-200','200','1');
  Pair('08','-1','2','0');
  Pair('09','42','-42','1');
  Pair('10','2046','1','0');
  Pair('11','-2047','-1','0');
  Pair('12','1024','-1024','1');
  Pair('13','511','512','0');
  Pair('14','-100','99','0');
  Save('one.sens',EncodeNumericDecimal('1',12));
  Save('minus-one.sens',EncodeNumericDecimal('-1',12));
  Save('overflow-up.sens',EncodeNumericDecimal('2047',12));
  Save('overflow-down.sens',EncodeNumericDecimal('-2048',12));
  Save('bad-d24.sens',EncodeNumericDecimal('0',24));
  SetLength(Words,1);Words[0]:='1';
  Save('bad-d1.sens',EncodeT5M(Words));
  Words[0]:='0010110';
  Save('bad-d7.sens',EncodeT5M(Words));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  Save('fake.lisp',UA('(нуль? (додати 1 -1))')+#10);
  if Total<>14 then Halt(4);
  WriteLn(StdErr,UA('D12-ДОДАТИ-НУЛЬ-СВІДКИ-ГАРАЗД випадків='),Total);
end.
