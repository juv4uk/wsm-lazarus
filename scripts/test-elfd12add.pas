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
  Save(String(LabelText)+'-ліве.sens',EncodeNumericDecimal(L,12));
  Save(String(LabelText)+'-праве.sens',EncodeNumericDecimal(R,12));
  Save(String(LabelText)+'-результат.sens',EncodeNumericDecimal(Sum,12));
  Inc(Checks);
end;
var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);Checks:=0;
  if not ForceDirectories(Dir) then Halt(2);
  Pair('нуль','0','0','0');
  Pair('плюс','31','42','73');
  Pair('мінус','-12','7','-5');
  Pair('два-мінус','-1024','-1024','-2048');
  Pair('край','-2048','2047','-1');
  Pair('перенесення','1023','1','1024');
  Pair('скасування','2047','-2048','-1');
  Pair('максимум','2046','1','2047');
  Pair('мінімум','-2047','-1','-2048');
  Save('переповнення-ліве.sens',EncodeNumericDecimal('2047',12));
  Save('переповнення-праве.sens',EncodeNumericDecimal('1',12));
  Save('під-межею-ліве.sens',EncodeNumericDecimal('-2048',12));
  Save('під-межею-праве.sens',EncodeNumericDecimal('-1',12));
  Save('чужий-d24.sens',EncodeNumericDecimal('1',24));
  Save('пошкоджений.sens',#$FF);
  Save('порожній.sens','');
  SetLength(Words,1);Words[0]:='1';Save('чужий-d1.sens',EncodeT5M(Words));
  SetLength(Words,1);Words[0]:='0010110';Save('чужий-d7.sens',EncodeT5M(Words));
  WriteLn('ELF-D12-СВІДКИ-ПЕРЕВІРЕНО випадків=',Checks,' негативів=7');
end.
