{ G6.99 — фізичні canonical D2/T5M свідки pinned D6:010100.
  Лише тестовий генератор: десяткові fixture не є SENS кодом.
  Вхід: borrowed каталог; вихід: owned файли та TSV, lifetime
  TFileStream/TStringList обмежено finally.
  1) Чому Д12 кодується через EncodeNumericDecimal?
  2) Чому root D2 має окремі слова "10" і "01"?
  3) Чому ділене не виводить домен із довжини .sens файла?
  4) Чому expected потребує незалежного pinned REPL? }
program test_irwiderest;
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

procedure Positive(const LabelText:RawByteString;Dividend,Divisor:LongInt);
var LeftBits,RightBits:TExplicitNumeric;
    E:LongInt;
begin
  if (Dividend<0) or (Dividend>2047) or
     (Divisor<1) or (Divisor>2047) then Halt(20);
  LeftBits:=ReadNumericPhysical(EncodeNumericDecimal(IntToStr(Dividend),12),12);
  RightBits:=ReadNumericPhysical(EncodeNumericDecimal(IntToStr(Divisor),12),12);
  Save(String(LabelText)+'.sens',
    Pack(['10','010100',LeftBits.ExactBits,RightBits.ExactBits,'01']));
  E:=Dividend mod Divisor; { тестовий прогноз, НЕ мовний закон }
  Save(String(LabelText)+'.expected.sens',EncodeNumericDecimal(IntToStr(E),12));
  Manifest.Add(String(LabelText)+#9+IntToStr(Dividend)+#9+
    IntToStr(Divisor)+#9+IntToStr(E));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Directory:=ParamStr(1);
  if not ForceDirectories(Directory) then Halt(2);
  Manifest:=TStringList.Create;
  try
    Count:=0;
    Positive('01',0,1);
    Positive('02',1,1);
    Positive('03',2,3);
    Positive('04',7,3);
    Positive('05',15,4);
    Positive('06',17,5);
    Positive('07',1024,31);
    Positive('08',2047,2);
    Positive('09',2047,2047);
    Positive('10',2046,2047);
    Positive('11',127,7);
    Positive('12',1234,17);
    Positive('13',1999,100);
    Positive('14',2000,64);
    A:=ReadNumericPhysical(EncodeNumericDecimal('7',12),12);
    B:=ReadNumericPhysical(EncodeNumericDecimal('3',12),12);
    N24:=ReadNumericPhysical(EncodeNumericDecimal('3',24),24);
    Save('other-d6.sens',Pack(['10','010011',A.ExactBits,B.ExactBits,'01']));
    Save('other-d5.sens',Pack(['10','01010',A.ExactBits,B.ExactBits,'01']));
    Save('other-d7.sens',Pack(['10','0010110',A.ExactBits,B.ExactBits,'01']));
    Save('d1.sens',Pack(['10','010100','1',B.ExactBits,'01']));
    Save('d3-empty.sens',Pack(['10','010100','000',B.ExactBits,'01']));
    Save('d7.sens',Pack(['10','010100','0010110',B.ExactBits,'01']));
    Save('d24.sens',Pack(['10','010100',N24.ExactBits,B.ExactBits,'01']));
    Save('missing.sens',Pack(['10','010100',A.ExactBits,'01']));
    Save('extra.sens',Pack(['10','010100',A.ExactBits,B.ExactBits,B.ExactBits,'01']));
    Save('nested.sens',Pack(['10','010100','10',A.ExactBits,'01',B.ExactBits,'01']));
    Save('two-roots.sens',Pack(['10','010100',A.ExactBits,B.ExactBits,'01','0']));
    Save('dotted.sens',Pack(['10','010100','11',A.ExactBits,B.ExactBits,'01']));
    Save('root-atom.sens',Pack([A.ExactBits]));
    Save('unclosed.sens',Pack(['10','010100',A.ExactBits,B.ExactBits]));
    Save('close-only.sens',Pack(['01']));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','010100',A.ExactBits,B.ExactBits,'01']));
    Save('div-zero.sens',Pack(['10','010100',A.ExactBits,
      ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits,'01']));
    Save('negative-left.sens',Pack(['10','010100',
      ReadNumericPhysical(EncodeNumericDecimal('-1',12),12).ExactBits,
      B.ExactBits,'01']));
    Save('negative-right.sens',Pack(['10','010100',A.ExactBits,
      ReadNumericPhysical(EncodeNumericDecimal('-3',12),12).ExactBits,'01']));
    Manifest.SaveToFile(Directory+'/cases.tsv');
    if Count<>14 then Halt(3);
    WriteLn('G6.99-REST-FIXTURES-OK cases=14');
  finally Manifest.Free end;
end.
