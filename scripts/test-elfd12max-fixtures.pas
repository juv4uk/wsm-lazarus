{ G6.87 — canonical T5M свідки signed D12 MAX, без host-оркестрації законів.
  EncodeNumericDecimal задає фізичну W12, expected перевіряє
  незалежний pinned SENS CLI у shell тесті; decimal лишень host fixture.
  1) Чому explicit 12, не decimal-derived width?
  2) Чому raw .sens із точним padded T5M?
  3) Хто володіє відкритим файлом?
  4) Чому цей генератор не є мовним oracle? }
program test_elfd12max_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String;Cases:SizeInt;
procedure Save(const Name:String;const Content:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Content)>0 then F.WriteBuffer(Content[1],Length(Content));
  finally F.Free end;
end;
procedure Row(const LabelText,Left,Right,Expected:RawByteString);
begin
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(Left,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(Right,12));
  Save(String(LabelText)+'-expected.sens',EncodeNumericDecimal(Expected,12));
  WriteLn(LabelText,#9,Left,#9,Right,#9,Expected);
  Inc(Cases);
end;
var W:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);Cases:=0;
  if not ForceDirectories(Dir) then Halt(2);
  Row('01','0','0','0');
  Row('02','0','1','1');
  Row('03','1','0','1');
  Row('04','31','42','42');
  Row('05','42','31','42');
  Row('06','2047','2047','2047');
  Row('07','2046','2047','2047');
  Row('08','2047','2046','2047');
  Row('09','-1','0','0');
  Row('10','0','-1','0');
  Row('11','-7','-3','-3');
  Row('12','-3','-7','-3');
  Row('13','-2048','2047','2047');
  Row('14','2047','-2048','2047');
  Row('15','-2048','-2048','-2048');
  Row('16','-2047','-2048','-2047');
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  SetLength(W,1);W[0]:='1';Save('bad1.sens',EncodeT5M(W));
  W[0]:='0101010';Save('bad7.sens',EncodeT5M(W));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  Save('projection.lisp','(найбільше -7 -3)'+#10);
  if Cases<>16 then Halt(3);
  WriteLn(StdErr,'D12-MAX-FIXTURES-OK cases=',Cases);
end.
