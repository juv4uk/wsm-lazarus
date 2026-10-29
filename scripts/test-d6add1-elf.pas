program test_d6add1_elf_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.elfd6add1;
procedure Save(const Name:string;const Bytes:RawByteString);
var F:TFileStream;
begin F:=TFileStream.Create(Name,fmCreate);try if Bytes<>'' then F.WriteBuffer(Bytes[1],Length(Bytes)) finally F.Free end end;
function Form(const Head,Value:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,5); W[0]:='10'; W[1]:=Head; W[2]:='00';
  W[3]:=Value; W[4]:='01'; Result:=EncodeT5M(W);
end;
function NumericBits(const Decimal:RawByteString):RawByteString;
var W:TExactWords;
begin DecodeT5M(EncodeNumericDecimal(Decimal,12),W); Result:=W[0] end;
procedure Fixture(const Dir,Name,Value:RawByteString);
var Input,Expected:RawByteString;
begin
  Input:=Form('001110',NumericBits(Value));
  Expected:=EncodeNumericDecimal(RawByteString(IntToStr(StrToInt(String(Value))+1)),12);
  Save(Dir+'/'+String(Name)+'.sens',Input); Save(Dir+'/'+String(Name)+'-expected.sens',Expected);
  WriteLn(Name,#9,Value);
end;
var D:string; W:TExactWords; Rejected:Boolean;
begin
  SetTextCodePage(Output,CP_UTF8); if ParamCount<>1 then Halt(2); D:=ParamStr(1); ForceDirectories(D);
  Fixture(D,'zero','0'); Fixture(D,'one','1'); Fixture(D,'ordinary','42'); Fixture(D,'upper-safe','2045');
  Save(D+'/profile-bound.sens',Form('001110',NumericBits('2046')));
  Save(D+'/overflow.sens',Form('001110',NumericBits('2047')));
  Save(D+'/wrong-head.sens',Form('001111',NumericBits('1')));
  DecodeT5M(EncodeNumericDecimal('1',24),W);
  Save(D+'/d24.sens',Form('001110',W[0]));
  SetLength(W,5); W[0]:='10'; W[1]:='001110'; W[2]:='00'; W[3]:='0000001'; W[4]:='01'; Save(D+'/d7.sens',EncodeT5M(W));
  SetLength(W,7); W[0]:='10'; W[1]:='001110'; W[2]:='00'; W[3]:=NumericBits('1'); W[4]:='00'; W[5]:=NumericBits('2'); W[6]:='01'; Save(D+'/arity.sens',EncodeT5M(W));
  SetLength(W,5); W[0]:='10'; W[1]:='001110'; W[2]:='00'; W[3]:='0001'; W[4]:='01'; Save(D+'/d1.sens',EncodeT5M(W));
  Save(D+'/corrupt.sens',#$FF); Save(D+'/projection.lisp','(додати-1 1)'+#10);
  Rejected:=False; try BuildD6Add1ELF(Form('001110',NumericBits('2046')), 'external/sens/lib/machine/profile/current-domain-x86-64.lisp'); except on E:Exception do Rejected:=True end;
  if not Rejected then raise Exception.Create('pinned ADD profile boundary admitted');
  WriteLn(StdErr,'D6-ADD1-UNIT-NEGATIVE-OK cases=5');
end.
