{ G6.101 — physical D2/T5M fixtures for signed D6 min/max.
  Expected decimal text is host test data; pinned SENS oracle runs
  independently. D12 identity is never inferred from numeric spelling. }
program test_irwideextrema;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;M:TStringList;Count:Integer;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

{ Borrowed binary words -> owned canonical T5M. 10/01 are D2 framing;
  no ASCII Lisp source, and all leading D12 zeros are preserved.
  Питання: 1) Чому потрібні 10/01? 2) Де захищена exact width?
  3) Хто звільнить Words? }
function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for I:=0 to High(Tokens) do Words[I]:=Tokens[I];
  Result:=EncodeT5M(Words);
end;

{ One pair -> two native input programs and two expected D12 packed
  answers. Expected values check machine output; the SENS oracle is
  evaluated separately, not substituted by the fixture.
  Питання: 1) Чому дві форми мають різні D6 ключі?
  2) Де числа отримують явний D12? 3) Чому потрібні граничні -2048/2047? }
procedure Pair(const LabelText,L,R,MinExpected,MaxExpected:RawByteString);
var A,B:TExplicitNumeric;Key,Expected,Mode:RawByteString;I:Integer;
begin
  A:=ReadNumericPhysical(EncodeNumericDecimal(L,12),12);
  B:=ReadNumericPhysical(EncodeNumericDecimal(R,12),12);
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(L,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(R,12));
  for I:=0 to 1 do begin
    if I=0 then begin Mode:='min'; Key:='110101';Expected:=MinExpected end
    else begin Mode:='max';Key:='110111';Expected:=MaxExpected end;
    Save(String(LabelText)+'-'+String(Mode)+'.sens',
      Pack(['10',Key,A.ExactBits,B.ExactBits,'01']));
    Save(String(LabelText)+'-'+String(Mode)+'.expected.sens',
      EncodeNumericDecimal(Expected,12));
    M.Add(String(LabelText)+'-'+String(Mode)+#9+String(Mode)+#9+
      String(L)+#9+String(R)+#9+String(Expected));
    Inc(Count);
  end;
end;

var Z,Q:TExplicitNumeric;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  M:=TStringList.Create;
  try
    Count:=0;
    Pair('01','0','0','0','0');
    Pair('02','0','1','0','1');
    Pair('03','1','0','0','1');
    Pair('04','31','42','31','42');
    Pair('05','42','31','31','42');
    Pair('06','2047','2047','2047','2047');
    Pair('07','2046','2047','2046','2047');
    Pair('08','2047','2046','2046','2047');
    Pair('09','-1','0','-1','0');
    Pair('10','0','-1','-1','0');
    Pair('11','-7','-3','-7','-3');
    Pair('12','-3','-7','-7','-3');
    Pair('13','-2048','2047','-2048','2047');
    Pair('14','2047','-2048','-2048','2047');
    Pair('15','-2048','-2048','-2048','-2048');
    Pair('16','-2047','-2048','-2048','-2047');
    Z:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12);
    Q:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24);
    Save('bad-d5.sens',Pack(['10','10101',Z.ExactBits,Z.ExactBits,'01']));
    Save('bad-d6.sens',Pack(['10','110100',Z.ExactBits,Z.ExactBits,'01']));
    Save('bad-d7.sens',Pack(['10','0010110',Z.ExactBits,Z.ExactBits,'01']));
    Save('bad-arity.sens',Pack(['10','110101',Z.ExactBits,'01']));
    Save('bad-extra.sens',Pack(['10','110111',Z.ExactBits,Z.ExactBits,Z.ExactBits,'01']));
    Save('bad-d1.sens',Pack(['10','110101','1',Z.ExactBits,'01']));
    Save('bad-d7arg.sens',Pack(['10','110101','0010110',Z.ExactBits,'01']));
    Save('bad-d24.sens',Pack(['10','110111',Q.ExactBits,Z.ExactBits,'01']));
    Save('bad-nested.sens',Pack(['10','110101','10',Z.ExactBits,'01',Z.ExactBits,'01']));
    Save('two-roots.sens',Pack(['10','110101',Z.ExactBits,Z.ExactBits,'01','0']));
    Save('unclosed.sens',Pack(['10','110101',Z.ExactBits,Z.ExactBits]));
    Save('root-atom.sens',Pack([Z.ExactBits]));
    Save('corrupt.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','110101',Z.ExactBits,Z.ExactBits,'01']));
    M.SaveToFile(Dir+'/cases.tsv');
    if Count<>32 then Halt(3);
    WriteLn('G6.101-FIXTURES-OK cases=32');
  finally M.Free end;
end.
