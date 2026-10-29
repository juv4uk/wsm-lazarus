{ G6.147 — канонічні негативні D6 форми, у яких є D6 residence,
  але pinned SENS ВІДМОВЛЯЄ у callability (попередній PR #743).
  Positive D5 форми і очікувані значення з існуючого test-elfd12mulpotik.
  Тут немає SENS predicate evaluator, лише exact physical T5M fixture.
  1) Чому немає local таблиці дозволених функцій?
  2) Чому D7 поверхня не створює право виклику D6?
  3) Чому повний D2 root зберігається фізично?
  4) Чому signed D12 число має явний контекст?
  5) Хто володіє тимчасовими RawByteString та потоком файлу? }
program test_oracle_first_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;

function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for I:=0 to High(Tokens) do Words[I]:=Tokens[I];
  Result:=EncodeT5M(Words);
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(ParamStr(1)+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

var A,B,Physical:RawByteString;D12:TExplicitNumeric;
begin
  if (ParamCount<>1) or (not DirectoryExists(ParamStr(1))) then Halt(64);
  D12:=ReadNumericPhysical(EncodeNumericDecimal('7',12),12);
  A:=D12.ExactBits;
  D12:=ReadNumericPhysical(EncodeNumericDecimal('-3',12),12);
  B:=D12.ExactBits;
  Save('not-callable-110100.sens',Pack(['10','110100',A,B,'01']));
  Save('not-callable-110110.sens',Pack(['10','110110',A,B,'01']));
  Save('wrong-domain-d7.sens',Pack(['10','0010110',A,B,'01']));
  Save('bad-root.sens',Pack(['01',A,B]));
  Save('bad-t5m.sens',#$FF);
  Save('empty.sens','');
  Physical:=Pack(['10','10110',A,B,'01']);
  Save('projection.lisp',Physical);
  WriteLn('ORACLE-FIRST-FIXTURES-OK negative-heads=2 malformed=5');
end.
