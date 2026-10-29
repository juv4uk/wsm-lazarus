{ G6.63: фізичні свідки точних двійкових атомів.
  Генератор не є semantic oracle; тільки canonical pinned D12 codec. }
program test_elfd12add;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String;Checks:SizeInt;
procedure Save(const Path:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Path,fmCreate);
  try if Length(B)>0 then F.WriteBuffer(B[1],Length(B));
  finally F.Free end;
end;
procedure Pair(const LabelText,L,R,Sum:RawByteString);
begin
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(L,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(R,12));
  Save(String(LabelText)+'-expected.sens',EncodeNumericDecimal(Sum,12));
  Inc(Checks);
end;
var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);Checks:=0;
  if not ForceDirectories(Dir) then Halt(2);
  Pair('01','0','0','0');
  Pair('02','31','42','73');
  Pair('03','-12','7','-5');
  Pair('04','-1024','-1024','-2048');
  Pair('05','-2048','2047','-1');
  Pair('06','1023','1','1024');
  Pair('07','2047','-2048','-1');
  Pair('08','2046','1','2047');
  Pair('09','-2047','-1','-2048');
  Save('overplus-l.sens',EncodeNumericDecimal('2047',12));
  Save('overplus-r.sens',EncodeNumericDecimal('1',12));
  Save('overminus-l.sens',EncodeNumericDecimal('-2048',12));
  Save('overminus-r.sens',EncodeNumericDecimal('-1',12));
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  SetLength(Words,1);Words[0]:='1';Save('bad1.sens',EncodeT5M(Words));
  SetLength(Words,1);Words[0]:='0010110';Save('bad7.sens',EncodeT5M(Words));
  WriteLn('ELF-D12-СВІДКИ-ПЕРЕВІРЕНО випадків=',Checks,' негативів=7');
end.
