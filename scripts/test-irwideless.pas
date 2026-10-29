{ G6.91 — T5M/D2 фізичні свідки, не власні закони мови.
  Десяткові host fixtures лише для незалежного REPL; source — binary.
  Точність signed D12 перевіряє чинний numeric-plane. }
program test_irwideless;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;Count:SizeInt;M:TStringList;
    Zero,Bits24:RawByteString;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

{ Input Items are exact binary tokens (D2 10/01, D5 head, numeric words).
  Result is canonical owned packed T5M, NOT textual Lisp parentheses.
  1) Чому D2 10 та 01 є structural, а не D2-valued literals?
  2) Чому W12 зберігає провідні нулі при пакуванні?
  3) Хто звільняє Words після повернення? }
function PhysicalForm(const Items:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Items));
  for I:=0 to High(Items) do W[I]:=Items[I];
  Result:=EncodeT5M(W);
end;

{ Test fixtures are NOT semantic oracle. Independent pinned CLI
  must confirm every witness expected bit. Preserves exact W12.
  1) Чому тут не використовуємо host Boolean?
  2) Чому кожен аргумент має власний canonical .sens?
  3) Чому packed D1 output — не ASCII 1/0? }
procedure Pair(const LabelText,L,R,Truth:RawByteString);
var A,B:TExplicitNumeric;W:TExactWords;
begin
  A:=ReadNumericPhysical(EncodeNumericDecimal(L,12),12);
  B:=ReadNumericPhysical(EncodeNumericDecimal(R,12),12);
  Save(String(LabelText)+'.sens',
    PhysicalForm(['10','11010',A.ExactBits,B.ExactBits,'01']));
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(L,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(R,12));
  SetLength(W,1);W[0]:=Truth;
  Save(String(LabelText)+'.expected.sens',EncodeT5M(W));
  M.Add(String(LabelText)+#9+String(L)+#9+String(R)+#9+String(Truth));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  M:=TStringList.Create;
  try
    Count:=0;
    Pair('01','-2048','-2047','1');
    Pair('02','-1','0','1');
    Pair('03','0','-1','0');
    Pair('04','-12','7','1');
    Pair('05','7','-12','0');
    Pair('06','31','42','1');
    Pair('07','42','31','0');
    Pair('08','2047','2047','0');
    Pair('09','2046','2047','1');
    Pair('10','-2048','2047','1');
    Pair('11','0','0','0');
    Pair('12','-2048','-2048','0');
    Pair('13','2047','-2048','0');
    Pair('14','-2047','-2048','0');
    Pair('15','-17','-17','0');
    Pair('16','17','-17','0');
    Pair('17','-1','1','1');
    Pair('18','1','-1','0');
    Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
    Bits24:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24).ExactBits;
    Save('other-head.sens',PhysicalForm(['10','11011',Zero,Zero,'01']));
    Save('other-d5.sens',PhysicalForm(['10','01010',Zero,Zero,'01']));
    Save('other-d6.sens',PhysicalForm(['10','001110',Zero,Zero,'01']));
    Save('bad-d1-left.sens',PhysicalForm(['10','11010','1',Zero,'01']));
    Save('bad-d1-right.sens',PhysicalForm(['10','11010',Zero,'0','01']));
    Save('bad-d7.sens',PhysicalForm(['10','11010','0010110',Zero,'01']));
    Save('bad-d24.sens',PhysicalForm(['10','11010',Zero,Bits24,'01']));
    Save('head-d7.sens',PhysicalForm(['10','0010110',Zero,Zero,'01']));
    Save('missing-left.sens',PhysicalForm(['10','11010','01']));
    Save('missing-right.sens',PhysicalForm(['10','11010',Zero,'01']));
    Save('extra-right.sens',PhysicalForm(['10','11010',Zero,Zero,Zero,'01']));
    Save('nested-right.sens',PhysicalForm(['10','11010',Zero,'10',Zero,'01','01']));
    Save('two-roots.sens',PhysicalForm(['10','11010',Zero,Zero,'01','1']));
    Save('dotted-pair.sens',PhysicalForm(['10','11010','11',Zero,'01']));
    Save('wrong-root.sens',PhysicalForm([Zero]));
    Save('unclosed.sens',PhysicalForm(['10','11010',Zero,Zero]));
    Save('bad-byte.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',PhysicalForm(['10','11010',Zero,Zero,'01']));
    M.SaveToFile(Dir+'/cases.tsv');
    if Count<>18 then Halt(2);
    WriteLn('G6.91-WIDE-LESS-FIXTURES=18');
  finally M.Free end;
end.
