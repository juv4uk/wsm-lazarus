{ G6.139 — свідки цілісних pinned D5:10111 фізичних програм.
  Тестові десяткові значення — тільки індекси; у .sens записуються
  повні exact 12-бітні числові слова через wsm.numericplane.
  Вхід: borrowed шлях до каталогу, результати: owned .sens і TSV.
  1) Чому 10111 не ASCII? 2) Хто визначає D12?
  3) Чому 10/01 є D2, а не текстовими дужками?
  4) Навіщо перевіряти oracle окремо?
  5) Хто звільняє TFileStream та TStringList? }
program test_irwidequot;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Directory:String;Manifest:TStringList;Count:SizeInt;
    A,B,N24:TExplicitNumeric;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Directory+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for I:=0 to High(Tokens) do Words[I]:=Tokens[I];
  Result:=EncodeT5M(Words);
end;

function Bits12(const Decimal:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Result:=N.ExactBits;
end;

procedure Positive(const LabelText,Decimal:RawByteString);
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Save(String(LabelText)+'.sens',
    Pack(['10','10111',N.ExactBits,N.ExactBits,'01']));
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(Decimal,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(Decimal,12));
  Save(String(LabelText)+'.expected.sens',EncodeNumericDecimal('1',12));
  Manifest.Add(String(LabelText)+#9+String(Decimal));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Directory:=ParamStr(1);
  if not ForceDirectories(Directory) then Halt(2);
  Manifest:=TStringList.Create;
  try
    Count:=0;
    Positive('01','1');   Positive('02','2');
    Positive('03','3');   Positive('04','7');
    Positive('05','13');  Positive('06','31');
    Positive('07','64');  Positive('08','127');
    Positive('09','255'); Positive('10','512');
    Positive('11','997'); Positive('12','1024');
    Positive('13','1536');Positive('14','2047');
    A:=ReadNumericPhysical(EncodeNumericDecimal('7',12),12);
    B:=ReadNumericPhysical(EncodeNumericDecimal('3',12),12);
    N24:=ReadNumericPhysical(EncodeNumericDecimal('7',24),24);
    Save('wrong-d5.sens',Pack(['10','01010',A.ExactBits,A.ExactBits,'01']));
    Save('wrong-d6.sens',Pack(['10','010100',A.ExactBits,A.ExactBits,'01']));
    Save('wrong-d7.sens',Pack(['10','0010110',A.ExactBits,A.ExactBits,'01']));
    Save('wrong-width.sens',Pack(['10','10111',N24.ExactBits,A.ExactBits,'01']));
    Save('d1.sens',Pack(['10','10111','1',A.ExactBits,'01']));
    Save('d3-empty.sens',Pack(['10','10111','000',A.ExactBits,'01']));
    Save('d7.sens',Pack(['10','10111','0010110',A.ExactBits,'01']));
    Save('missing.sens',Pack(['10','10111',A.ExactBits,'01']));
    Save('extra.sens',Pack(['10','10111',A.ExactBits,A.ExactBits,A.ExactBits,'01']));
    Save('nested.sens',Pack(['10','10111','10',A.ExactBits,'01',A.ExactBits,'01']));
    Save('two-roots.sens',Pack(['10','10111',A.ExactBits,A.ExactBits,'01','0']));
    Save('dotted.sens',Pack(['11','10111',A.ExactBits,A.ExactBits,'01']));
    Save('root-atom.sens',Pack([A.ExactBits]));
    Save('unclosed.sens',Pack(['10','10111',A.ExactBits,A.ExactBits]));
    Save('close-only.sens',Pack(['01']));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','10111',A.ExactBits,A.ExactBits,'01']));
    Save('zero.sens',Pack(['10','10111',Bits12('0'),Bits12('0'),'01']));
    Save('negative.sens',Pack(['10','10111',Bits12('-1'),Bits12('-1'),'01']));
    Save('unequal.sens',Pack(['10','10111',A.ExactBits,B.ExactBits,'01']));
    Save('unequal-left.sens',Pack(['10','10111',B.ExactBits,A.ExactBits,'01']));
    Manifest.SaveToFile(Directory+'/cases.tsv');
    if Count<>14 then Halt(3);
    WriteLn('G6.139-QUOT-FIXTURES-OK cases=14 negatives=22');
  finally Manifest.Free end;
end.