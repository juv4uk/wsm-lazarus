program test_elfd12sub_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericsub,wsm.elfd12sub;
procedure Save(const Name:string;const Bytes:RawByteString);
var F:TFileStream;
begin F:=TFileStream.Create(Name,fmCreate);try if Bytes<>'' then F.WriteBuffer(Bytes[1],Length(Bytes)) finally F.Free end end;
procedure Pair(const Dir,Name,L,R:RawByteString);
var A,B,O:RawByteString; W:SizeInt; N:TExplicitNumeric;
begin
  A:=EncodeNumericDecimal(L,12); B:=EncodeNumericDecimal(R,12);
  O:=SubtractNumericPhysical(A,B,12); W:=12;
  try N:=ReadNumericPhysical(O,12); except on E:ENumericPlaneError do W:=24 end;
  N:=ReadNumericPhysical(O,W);
  Save(Dir+'/'+String(Name)+'-a.sens',A); Save(Dir+'/'+String(Name)+'-b.sens',B);
  Save(Dir+'/'+String(Name)+'-expected.sens',O);
  if N.DomainWidth<>W then raise Exception.Create('ширина відповіді не збіглася');
  WriteLn(Name,#9,W,#9,L,#9,R);
end;
procedure MustReject(const L,R:RawByteString);
var Rejected:Boolean;
begin
  Rejected:=False;
  try BuildD12SubELF(L,R); except on E:Exception do Rejected:=True end;
  if not Rejected then raise Exception.Create('negative input accepted');
end;
var D:string; Words:TExactWords;
begin
  SetTextCodePage(Output,CP_UTF8); if ParamCount<>1 then Halt(2);
  D:=ParamStr(1); ForceDirectories(D);
  Pair(D,'positive','7','-7'); Pair(D,'negative','-7','7');
  Pair(D,'upper-overflow','2047','-1'); Pair(D,'lower-overflow','-2048','1');
  Pair(D,'equal','5','5'); Pair(D,'minimum-equal','-2048','-2048');
  SetLength(Words,1); Words[0]:='1'; Save(D+'/d1.sens',EncodeT5M(Words));
  Save(D+'/corrupt.sens',#$FF); Save(D+'/projection.lisp','(відняти 7 -7)'+#10);
  Save(D+'/bad-d24.sens',EncodeNumericDecimal('1',24));
  MustReject(EncodeT5M(Words),EncodeNumericDecimal('1',12));
  MustReject(EncodeNumericDecimal('1',24),EncodeNumericDecimal('1',12));
  MustReject(#$FF,EncodeNumericDecimal('1',12));
  WriteLn(StdErr,'D12-SUB-UNIT-NEGATIVE-OK cases=3');
end.
