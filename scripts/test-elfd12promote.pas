{ G6.71 — лише генератор канонічних фізичних свідків D12/D24.
  Це НЕ семантичний оракул, відповіді перевіряє pinned SENS REPL. }
program test_elfd12promote;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.numericplane, wsm.t5m;
var Dir:String; Count:SizeInt;

procedure Save(const Name:String;const Physical:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Physical)>0 then F.WriteBuffer(Physical[1],Length(Physical));
  finally F.Free end;
end;

{ Exact D12/D24 — лише вже чинний codec; Output є власним RawByteString.
  1) Чому expected D24, а не розширений host int?
  2) Чому генератор не є REPL-оракулом?
  3) Хто закриває фізичні файли?
  4) Чому D1/ D7 negatives не стають D12? }
procedure CasePositive(const Name,L,R,Sum:RawByteString);
begin
  Save(String(Name)+'-left.sens',EncodeNumericDecimal(L,12));
  Save(String(Name)+'-right.sens',EncodeNumericDecimal(R,12));
  Save(String(Name)+'-expected.sens',EncodeNumericDecimal(Sum,24));
  Inc(Count);
end;

var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1); Count:=0;
  if not ForceDirectories(Dir) then Halt(2);
  CasePositive('01','2047','1','2048');
  CasePositive('02','-2048','-1','-2049');
  CasePositive('03','1800','450','2250');
  CasePositive('04','-1500','-600','-2100');
  CasePositive('05','2047','2047','4094');
  CasePositive('06','-2048','-2048','-4096');
  CasePositive('07','-1024','-1025','-2049');
  Save('fits-left.sens',EncodeNumericDecimal('10',12));
  Save('fits-right.sens',EncodeNumericDecimal('20',12));
  Save('mixed-left.sens',EncodeNumericDecimal('2047',12));
  Save('mixed-right.sens',EncodeNumericDecimal('-2048',12));
  Save('invalid-d24.sens',EncodeNumericDecimal('1',24));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  SetLength(Words,1); Words[0]:='1';
  Save('invalid-d1.sens',EncodeT5M(Words));
  Words[0]:='0010110';
  Save('invalid-d7.sens',EncodeT5M(Words));
  if Count<>7 then Halt(2);
  WriteLn('Д24-ПРОСУВАННЯ-СВІДКИ-ГОТОВІ позитивів=',Count);
end.
