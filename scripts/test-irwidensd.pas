{ G6.105 — фізичні D2/T5M свідки цілісного НСД D6:010101.
  Очікувані числа — тестова матриця, не мовні закони;
  незалежний pinned SENS REPL порівнюється окремо.
  Вихід: owned файли .sens + TSV; тимчасові потоки закриває finally.
  1) Навіщо D2 слова 10/01? 2) Де exact W12?
  3) Чому тестові десяткові числа не є кодом SENS?
  4) Хто закриває TFileStream? 5) Як перевіряється oracle? }
program test_irwidensd;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Directory:String; Manifest:TStringList; Count:SizeInt;
    A,B,N24:TExplicitNumeric;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Directory+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;

function Bits12(const Decimal:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Result:=N.ExactBits;
end;

procedure Positive(const LabelText:RawByteString;Left,Right,Expected:LongInt);
var L,R:TExplicitNumeric;
begin
  if (Left<1) or (Left>2047) or (Right<1) or (Right>2047) or
     (Expected<1) or (Expected>2047) then Halt(20);
  L:=ReadNumericPhysical(EncodeNumericDecimal(IntToStr(Left),12),12);
  R:=ReadNumericPhysical(EncodeNumericDecimal(IntToStr(Right),12),12);
  Save(String(LabelText)+'.sens',
    Pack(['10','010101',L.ExactBits,R.ExactBits,'01']));
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(IntToStr(Left),12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(IntToStr(Right),12));
  Save(String(LabelText)+'.expected.sens',
    EncodeNumericDecimal(IntToStr(Expected),12));
  Manifest.Add(String(LabelText)+#9+IntToStr(Left)+#9+
    IntToStr(Right)+#9+IntToStr(Expected));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Directory:=ParamStr(1);
  if not ForceDirectories(Directory) then Halt(2);
  Manifest:=TStringList.Create;
  try
    Count:=0;
    Positive('01',12,18,6);
    Positive('02',24,54,6);
    Positive('03',13,17,1);
    Positive('04',21,21,21);
    Positive('05',2047,2046,1);
    Positive('06',2047,2047,2047);
    Positive('07',144,36,36);
    Positive('08',987,610,1);
    Positive('09',2046,1023,1023);
    Positive('10',1024,256,256);
    Positive('11',999,27,27);
    Positive('12',157,31,1);
    Positive('13',55,89,1);
    Positive('14',1800,420,60);
    A:=ReadNumericPhysical(EncodeNumericDecimal('7',12),12);
    B:=ReadNumericPhysical(EncodeNumericDecimal('3',12),12);
    N24:=ReadNumericPhysical(EncodeNumericDecimal('3',24),24);
    Save('other-d6.sens',Pack(['10','010011',A.ExactBits,B.ExactBits,'01']));
    Save('other-d5.sens',Pack(['10','01010',A.ExactBits,B.ExactBits,'01']));
    Save('other-d7.sens',Pack(['10','0010110',A.ExactBits,B.ExactBits,'01']));
    Save('d1.sens',Pack(['10','010101','1',B.ExactBits,'01']));
    Save('d3-empty.sens',Pack(['10','010101','000',B.ExactBits,'01']));
    Save('d7.sens',Pack(['10','010101','0010110',B.ExactBits,'01']));
    Save('d24.sens',Pack(['10','010101',N24.ExactBits,B.ExactBits,'01']));
    Save('missing.sens',Pack(['10','010101',A.ExactBits,'01']));
    Save('extra.sens',Pack(['10','010101',A.ExactBits,B.ExactBits,B.ExactBits,'01']));
    Save('nested.sens',Pack(['10','010101','10',A.ExactBits,'01',B.ExactBits,'01']));
    Save('two-roots.sens',Pack(['10','010101',A.ExactBits,B.ExactBits,'01','0']));
    Save('dotted.sens',Pack(['10','010101','11',A.ExactBits,B.ExactBits,'01']));
    Save('root-atom.sens',Pack([A.ExactBits]));
    Save('unclosed.sens',Pack(['10','010101',A.ExactBits,B.ExactBits]));
    Save('close-only.sens',Pack(['01']));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','010101',A.ExactBits,B.ExactBits,'01']));
    Save('zero-right.sens',Pack(['10','010101',A.ExactBits,
      Bits12('0'),'01']));
    Save('zero-left.sens',Pack(['10','010101',Bits12('0'),
      B.ExactBits,'01']));
    Save('negative-left.sens',Pack(['10','010101',
      Bits12('-1'),
      B.ExactBits,'01']));
    Save('negative-right.sens',Pack(['10','010101',A.ExactBits,
      Bits12('-3'),'01']));
    Manifest.SaveToFile(Directory+'/cases.tsv');
    if Count<>14 then Halt(3);
    WriteLn('G6.105-NSD-FIXTURES-OK cases=14');
  finally Manifest.Free end;
end.
