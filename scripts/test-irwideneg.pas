{ G6.133 — фізичні packed D2/T5M форми D6 «змінити-знак», не oracle.
  Десяткові значення тільки fixture для незалежного pinned SENS REPL. }
program test_irwideneg;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Directory:String;Manifest:TStringList;Count:SizeInt;
    Zero,Bits24:TExplicitNumeric;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Directory+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

{ Tokens are exact binary words incl. D2 open/close. Result is owned
  canonical packed T5M, never ASCII Lisp source.
  1) Чому '10'/'01' є структурними D2?
  2) Хто забезпечує точну ширину W12?
  3) Де вивільняється managed TExactWords? }
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;

{ Expected is ONLY a mechanical reference fixture — independent pinned
  SENS REPL must confirm semantic neg, incl. -2048→D24.
  1) Чому D24 ніколи не перетворюємо назад у D12?
  2) Чому ExpectedWidth потрібно передати явно?
  3) Чому одиночний atom не заміняє whole D2 program?
  4) Де машина реально виконує NEG? }
procedure Positive(const LabelText,Decimal,Expected:RawByteString;ExpectedWidth:SizeInt);
var InValue:TExplicitNumeric;
begin
  InValue:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Save(String(LabelText)+'.sens',Pack(['10','010010',InValue.ExactBits,'01']));
  Save(String(LabelText)+'.atom.sens',EncodeNumericDecimal(Decimal,12));
  Save(String(LabelText)+'.expected.sens',EncodeNumericDecimal(Expected,ExpectedWidth));
  Manifest.Add(String(LabelText)+#9+String(Decimal)+#9+
    String(Expected)+#9+IntToStr(ExpectedWidth));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Directory:=ParamStr(1);
  if not ForceDirectories(Directory) then Halt(2);
  Manifest:=TStringList.Create;
  try
    Count:=0;
    Positive('01','0','0',12);
    Positive('02','1','-1',12);
    Positive('03','-1','1',12);
    Positive('04','17','-17',12);
    Positive('05','-17','17',12);
    Positive('06','2047','-2047',12);
    Positive('07','-2047','2047',12);
    Positive('08','-2048','2048',24);
    Positive('09','1024','-1024',12);
    Positive('10','-1024','1024',12);
    Positive('11','-2','2',12);
    Positive('12','2','-2',12);
    Positive('13','-1234','1234',12);
    Positive('14','1234','-1234',12);
    Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12);
    Bits24:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
    Save('other-d6.sens',Pack(['10','010011',Zero.ExactBits,'01']));
    Save('other-d5.sens',Pack(['10','01000',Zero.ExactBits,'01']));
    Save('other-d7.sens',Pack(['10','0010110',Zero.ExactBits,'01']));
    Save('d1.sens',Pack(['10','010010','1','01']));
    Save('d3-empty.sens',Pack(['10','010010','000','01']));
    Save('d7.sens',Pack(['10','010010','0010110','01']));
    Save('d24.sens',Pack(['10','010010',Bits24.ExactBits,'01']));
    Save('missing.sens',Pack(['10','010010','01']));
    Save('extra.sens',Pack(['10','010010',Zero.ExactBits,Zero.ExactBits,'01']));
    Save('nested.sens',Pack(['10','010010','10',Zero.ExactBits,'01','01']));
    Save('two-roots.sens',Pack(['10','010010',Zero.ExactBits,'01','0']));
    Save('dotted.sens',Pack(['10','010010','11',Zero.ExactBits,'01']));
    Save('root-atom.sens',Pack([Zero.ExactBits]));
    Save('unclosed.sens',Pack(['10','010010',Zero.ExactBits]));
    Save('close-only.sens',Pack(['01']));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','010010',Zero.ExactBits,'01']));
    Manifest.SaveToFile(Directory+'/cases.tsv');
    if Count<>14 then Halt(3);
    WriteLn('G6.133-NEG-FIXTURES-OK cases=14 негативів=18');
  finally Manifest.Free end;
end.
