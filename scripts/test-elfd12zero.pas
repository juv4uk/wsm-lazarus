{ G6.77: механічний генератор фізичних T5M із чинного numeric codec.
  Це НЕ SENS semantic oracle: незалежний pinned REPL перевіряє нуль?.
  Файли-дані .sens, людська .lisp виникає тільки в oracle тесті. }
program test_elfd12zero;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;

var Dir:String;Manifest:TStringList;Count:SizeInt;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

{ In: owned host-decimal fixture and explicit D12 domain.
  Out: canonical packed exact D12, expected exact D1 via T5M.
  НІКОЛИ не використовує host integers як джерело законів.
  1) Чому fixture не є незалежним семантичним оракулом?
  2) Чому expected фізичний D1, а не host boolean?
  3) Хто звільняє TFileStream?
  4) Чому валідний D24 вхід у негативних свідках? }
procedure CasePositive(const LabelText,Decimal,Truth:RawByteString);
var Words:TExactWords;
begin
  Save(String(LabelText)+'.sens',EncodeNumericDecimal(Decimal,12));
  SetLength(Words,1); Words[0]:=Truth;
  Save(String(LabelText)+'.expected.sens',EncodeT5M(Words));
  Manifest.Add(String(LabelText)+#9+String(Decimal)+#9+String(Truth));
  Inc(Count);
end;

var Words:TExactWords;F:TFileStream;S:RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Manifest:=TStringList.Create;
  try
    Count:=0;
    CasePositive('01','0','1');
    CasePositive('02','1','0');
    CasePositive('03','-1','0');
    CasePositive('04','2047','0');
    CasePositive('05','-2048','0');
    CasePositive('06','1024','0');
    CasePositive('07','-1024','0');
    CasePositive('08','17','0');
    CasePositive('09','-17','0');
    CasePositive('10','2','0');
    Save('wrong-d24.sens',EncodeNumericDecimal('0',24));
    SetLength(Words,1);Words[0]:='1';
    Save('wrong-d1.sens',EncodeT5M(Words));
    Words[0]:='0010110';
    Save('wrong-d7.sens',EncodeT5M(Words));
    SetLength(Words,2);Words[0]:='000000000000';
    Words[1]:='000000000000';
    Save('two-atoms.sens',EncodeT5M(Words));
    S:=EncodeNumericDecimal('0',12);
    Save('trailing.sens',S+#$FF);
    Save('corrupt.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',EncodeNumericDecimal('0',12));
    Manifest.SaveToFile(Dir+'/cases.tsv');
    if Count<>10 then Halt(3);
    WriteLn('D12-ZERO-FIXTURES-OK canonical=10 negatives=8');
  finally Manifest.Free end;
end.
