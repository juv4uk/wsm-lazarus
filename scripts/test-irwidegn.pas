{ G6.91 — synthetic canonical T5M programs only: D5:10110 (D12:-1 D12:x).
  Decimal у TSV лише людський свідок для незалежного SENS REPL.
  Жодної локальної інтерпретації/нового SENS математичного закону. }
program test_irwidegn;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String; Manifest:TStringList;Count:SizeInt;
procedure Save(const Name:String;const Physical:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Physical)>0 then F.WriteBuffer(Physical[1],Length(Physical))
  finally F.Free end;
end;
{ Words: owned managed array of exact physical D2/5/12 words.
  Кожне source має D2 OPEN(10) і CLOSE(01); жодних текстових дужок.
  1) Чому D2 10/01 — фізичне обрамлення?
  2) Чому голова з 5 біт — це D5, а не 5-бітове число?
  3) Чому -1 має зберігати усі 12 одиниць?
  4) Хто володіє RawByteString Result? }
function Packed(const Items:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Items));
  for I:=0 to High(Items) do Words[I]:=Items[I];
  Result:=EncodeT5M(Words);
end;
procedure Positive(const LabelText,InputDecimal,AnswerDecimal:RawByteString;
  OutWidth:SizeInt);
var N:TExplicitNumeric;Expected:RawByteString;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(InputDecimal,12),12);
  Save(String(LabelText)+'.sens',
    Packed(['10','10110','111111111111',N.ExactBits,'01']));
  Save(String(LabelText)+'.atom.sens',EncodeNumericDecimal(InputDecimal,12));
  Expected:=EncodeNumericDecimal(AnswerDecimal,OutWidth);
  Save(String(LabelText)+'.expected.sens',Expected);
  Manifest.Add(String(LabelText)+#9+String(InputDecimal)+#9+
    String(AnswerDecimal)+#9+IntToStr(OutWidth));
  Inc(Count);
end;
var One,Zero,Two,Any,Wide:RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
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
    One:=ReadNumericPhysical(EncodeNumericDecimal('-1',12),12).ExactBits;
    Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
    Two:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
    Any:=ReadNumericPhysical(EncodeNumericDecimal('17',12),12).ExactBits;
    Wide:=ReadNumericPhysical(EncodeNumericDecimal('17',24),24).ExactBits;
    Save('wrong-head.sens',Packed(['10','10111',One,Any,'01']));
    Save('wrong-head-domain.sens',Packed(['10','001110',One,Any,'01']));
    Save('first-zero.sens',Packed(['10','10110',Zero,Any,'01']));
    Save('first-one.sens',Packed(['10','10110',Two,Any,'01']));
    Save('first-D1.sens',Packed(['10','10110','1',Any,'01']));
    Save('first-D24.sens',Packed(['10','10110',Wide,Any,'01']));
    Save('second-D1.sens',Packed(['10','10110',One,'1','01']));
    Save('second-D3.sens',Packed(['10','10110',One,'000','01']));
    Save('second-D7.sens',Packed(['10','10110',One,'0010110','01']));
    Save('second-D24.sens',Packed(['10','10110',One,Wide,'01']));
    Save('missing.sens',Packed(['10','10110',One,'01']));
    Save('extra.sens',Packed(['10','10110',One,Any,Any,'01']));
    Save('two-roots.sens',Packed(['10','10110',One,Any,'01','0']));
    Save('nested.sens',Packed(['10','10110',One,'10',Any,'01','01']));
    Save('unclosed.sens',Packed(['10','10110',One,Any]));
    Save('bare.sens',Packed([One]));
    Save('corrupt.sens',#$FF);
    Save('empty.sens','');
    Save('projection.lisp',Packed(['10','10110',One,Any,'01']));
    Manifest.SaveToFile(Dir+'/cases.tsv');
    if Count<>10 then Halt(1);
    WriteLn('IR-D5-NEG-СВІДКИ=10');
  finally Manifest.Free end;
end.
