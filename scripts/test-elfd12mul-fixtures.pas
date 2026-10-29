program test_elfd12mul_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.numericplane, wsm.numericmul, wsm.elfd12mul;
procedure Save(const Name: string; const Bytes: RawByteString);
var F: TFileStream;
begin
  F:=TFileStream.Create(Name,fmCreate);
  try if Bytes<>'' then F.WriteBuffer(Bytes[1],Length(Bytes)) finally F.Free end;
end;
procedure Pair(const Dir,Name,L,R:RawByteString);
var A,B,OutBits:RawByteString; Width:SizeInt; N:TExplicitNumeric;
begin
  A:=EncodeNumericDecimal(L,12); B:=EncodeNumericDecimal(R,12);
  OutBits:=MultiplyNumericPhysical(A,B,12);
  Width:=12;
  try N:=ReadNumericPhysical(OutBits,12);
  except on E:ENumericPlaneError do Width:=24 end;
  Save(IncludeTrailingPathDelimiter(Dir)+String(Name)+'-a.sens',A);
  Save(IncludeTrailingPathDelimiter(Dir)+String(Name)+'-b.sens',B);
  Save(IncludeTrailingPathDelimiter(Dir)+String(Name)+'-expected.sens',OutBits);
  N:=ReadNumericPhysical(OutBits,Width);
  if N.DomainWidth<>Width then raise Exception.Create('ширина результату не збіглася');
  WriteLn(Name,#9,Width,#9,L,#9,R);
end;
procedure MustReject(const L,R,LabelText:RawByteString);
var Rejected:Boolean;
begin
  Rejected:=True;
  try
    if BuildD12MulELF(L,R)<>'' then Rejected:=False;
  except on E:Exception do Rejected:=True end;
  if not Rejected then raise Exception.Create('прийнято негативний випадок '+LabelText);
end;
var D:string; Words:TExactWords; D1:RawByteString;
begin
  SetTextCodePage(Output,CP_UTF8);
  if ParamCount<>1 then Halt(2);
  D:=ParamStr(1); ForceDirectories(D);
  Pair(D,'negative','7','-7');
  Pair(D,'boundary','2047','1');
  Pair(D,'widened','-2048','-1');
  Pair(D,'positive','12','12');
  SetLength(Words,1); Words[0]:='1'; Save(D+'/d1.sens',EncodeT5M(Words));
  Save(D+'/corrupt.sens',#$FF);
  Save(D+'/projection.lisp','(помножити 7 -7)'+#10);
  Save(D+'/bad-d24.sens',EncodeNumericDecimal('1',24));
  SetLength(Words,1); Words[0]:='1'; D1:=EncodeT5M(Words);
  MustReject(D1,EncodeNumericDecimal('1',12),'D1');
  MustReject(#$FF,EncodeNumericDecimal('1',12),'пошкоджений T5M');
  MustReject(EncodeNumericDecimal('1',24),EncodeNumericDecimal('1',12),'D24');
  WriteLn(StdErr,'D12-MUL-UNIT-NEGATIVE-OK cases=3');
end.
