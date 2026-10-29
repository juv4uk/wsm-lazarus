{ G6.158 — тестові ДВІЙКОВІ свідки: D2 рамка та точний D5:01001.
  Десяткові числа існують лише в host-маніфесті, не в .sens;
  D12/D24 — explicit signed numeric admission.
  Жодної функції Core1 не копіюємо в тестовий генератор. }
program test_irwidenumberp;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;M:TStringList;Count:SizeInt;Zero12,Zero24,Zero48:RawByteString;

{ Name: host filename, Physical: borrowed canonical bytes.
  F: owned stream; all bytes persisted exactly once.
  1) Чому текстова проєкція не є джерелом фізичних .sens?
  2) Де звільняється F у разі помилки?
  3) Що зберігає провідні нулі? }
procedure Save(const Name:String;const Physical:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Physical)>0 then F.WriteBuffer(Physical[1],Length(Physical));
  finally F.Free end;
end;

{ Items: borrowed exact bitwords, з D2 10/01, не text syntax.
  Words: managed owned FPC array; Result: packed T5M bytes.
  1) Яке слово є OPEN, а яке CLOSE?
  2) Чому W24 не зводимо до W12?
  3) Чому T5M «2» не є мовним числом? }
function Pack(const Items:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Items));
  for I:=0 to High(Items) do Words[I]:=Items[I];
  Result:=EncodeT5M(Words);
end;

procedure Positive(const LabelText,Decimal:RawByteString;Width:SizeInt);
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,Width),Width);
  Save(String(LabelText)+'.sens',Pack(['10','01001',N.ExactBits,'01']));
  Save(String(LabelText)+'.expected.sens',Pack(['1']));
  M.Add(String(LabelText)+#9+String(Decimal)+#9+IntToStr(Width));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  M:=TStringList.Create;
  try
    Count:=0;
    Positive('01','0',12);
    Positive('02','1',12);
    Positive('03','-1',12);
    Positive('04','2047',12);
    Positive('05','-2048',12);
    Positive('06','2048',24);
    Positive('07','-8388608',24);
    Positive('08','8388607',24);
    Zero12:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
    Zero24:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24).ExactBits;
    Zero48:=ReadNumericPhysical(EncodeNumericDecimal('0',48),48).ExactBits;
    Save('wrong-head.sens',Pack(['10','01000',Zero12,'01']));
    Save('wrong-domain.sens',Pack(['10','010010',Zero12,'01']));
    Save('d1.sens',Pack(['10','01001','1','01']));
    Save('d3.sens',Pack(['10','01001','000','01']));
    Save('d7.sens',Pack(['10','01001','0010110','01']));
    Save('d48.sens',Pack(['10','01001',Zero48,'01']));
    Save('missing.sens',Pack(['10','01001','01']));
    Save('extra.sens',Pack(['10','01001',Zero12,Zero24,'01']));
    Save('nested.sens',Pack(['10','01001','10',Zero12,'01','01']));
    Save('two-roots.sens',Pack(['10','01001',Zero12,'01','0']));
    Save('dotted.sens',Pack(['10','01001','11',Zero12,'01']));
    Save('unclosed.sens',Pack(['10','01001',Zero12]));
    Save('root-atom.sens',Pack([Zero12]));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','01001',Zero12,'01']));
    M.SaveToFile(Dir+'/cases.tsv');
    if Count<>8 then Halt(1);
    WriteLn('G6.158-ЧИСЛО-СВІДКИ-ГОТОВО physical=8');
  finally M.Free end;
end.
