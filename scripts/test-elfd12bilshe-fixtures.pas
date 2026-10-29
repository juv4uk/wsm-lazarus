{ G6.78: вузькі парні фізичні свідки D12/D1; НЕ semantic oracle. }
program test_elfd12bilshe_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String;Count:Integer;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Pair(const ID,Left,Right:RawByteString;Greater:Boolean);
var W:TExactWords;
begin
  Save(String(ID)+'-a.sens',EncodeNumericDecimal(Left,12));
  Save(String(ID)+'-b.sens',EncodeNumericDecimal(Right,12));
  SetLength(W,1);
  if Greater then W[0]:='1' else W[0]:='0';
  Save(String(ID)+'-expected.sens',EncodeT5M(W));
  if Greater then WriteLn(ID,#9,Left,#9,Right,#9,'так')
  else WriteLn(ID,#9,Left,#9,Right,#9,'ні');
  Inc(Count);
end;
var W:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);Count:=0;
  if not ForceDirectories(Dir) then Halt(2);
  Pair('01','0','0',False);
  Pair('02','1','0',True);
  Pair('03','0','1',False);
  Pair('04','-1','-2',True);
  Pair('05','-2','-1',False);
  Pair('06','-2048','2047',False);
  Pair('07','2047','-2048',True);
  Pair('08','-2048','-2048',False);
  Pair('09','2047','2047',False);
  Pair('10','2047','2046',True);
  Pair('11','-2047','-2048',True);
  Pair('12','-2048','-2047',False);
  Pair('13','-1','0',False);
  Pair('14','0','-1',True);
  SetLength(W,1);
  W[0]:='1';Save('bad1.sens',EncodeT5M(W));
  W[0]:='0010110';Save('bad7.sens',EncodeT5M(W));
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  WriteLn(StdErr,'D12-БІЛЬШЕ-СВІДКИ-ГОТОВО позитивів=',Count);
end.
{ TExactWords W temporary managed array; files own fixed packed words.
  Questions: why physical D1 expected? why independent REPL needed?
  why does generator never establish SENS law? why exactly D12? }