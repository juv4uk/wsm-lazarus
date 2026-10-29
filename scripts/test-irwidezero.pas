{ G6.86 — генератор тільки canonical D2/T5M фізичних програм.
  Десяткові числа лише у тестовому маніфесті, не в канонічній програмі.
  Семантичний оракул — незалежний pinned SENS REPL. }
program test_irwidezero;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;M:TStringList;Count:SizeInt;BitsZero,Bits24:RawByteString;

procedure Save(const Name:String;const Physical:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Physical)>0 then F.WriteBuffer(Physical[1],Length(Physical));
  finally F.Free end;
end;

{ TExactWords contains domain-framed physical bits including D2 10/01.
  Не перетворювати D2 маркери на текстові дужки в source.
  1) Чому T5M D2 OPEN='10', CLOSE='01'?
  2) Чому W12 ширина фіксується як 12, а не inferred host int?
  3) Який об'єкт звільняє managed Words після return? }
function PackedForm(const Items:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Items));
  for I:=0 to High(Items) do Words[I]:=Items[I];
  Result:=EncodeT5M(Words);
end;

procedure CasePositive(const LabelText,Decimal,Truth:RawByteString);
var A:TExplicitNumeric;V:TExactWords;
begin
  A:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Save(String(LabelText)+'.sens',PackedForm(['10','01000',A.ExactBits,'01']));
  Save(String(LabelText)+'.atom.sens',EncodeNumericDecimal(Decimal,12));
  SetLength(V,1);V[0]:=Truth;
  Save(String(LabelText)+'.expected.sens',EncodeT5M(V));
  M.Add(String(LabelText)+#9+String(Decimal)+#9+String(Truth));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  M:=TStringList.Create;
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
    BitsZero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
    Bits24:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24).ExactBits;
    Save('other-head.sens',PackedForm(['10','01001',BitsZero,'01']));
    Save('other-domain.sens',PackedForm(['10','001110',BitsZero,'01']));
    Save('D1-argument.sens',PackedForm(['10','01000','0','01']));
    Save('D3-empty.sens',PackedForm(['10','01000','000','01']));
    Save('D7-argument.sens',PackedForm(['10','01000','0010110','01']));
    Save('D24-argument.sens',PackedForm(['10','01000',Bits24,'01']));
    Save('missing-argument.sens',PackedForm(['10','01000','01']));
    Save('extra-argument.sens',PackedForm(['10','01000',BitsZero,BitsZero,'01']));
    Save('nested-argument.sens',PackedForm(['10','01000','10',BitsZero,'01','01']));
    Save('two-roots.sens',PackedForm(['10','01000',BitsZero,'01','0']));
    Save('dot-pair.sens',PackedForm(['10','01000','11',BitsZero,'01']));
    Save('unclosed.sens',PackedForm(['10','01000',BitsZero]));
    Save('bare-atom.sens',PackedForm([BitsZero]));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',PackedForm(['10','01000',BitsZero,'01']));
    M.SaveToFile(Dir+'/cases.tsv');
    if Count<>10 then Halt(1);
    WriteLn('D5-НУЛЬ-ШИРОКИЙ-IR-СВІДКИ-ГОТОВІ десять=10');
  finally M.Free end;
end.
