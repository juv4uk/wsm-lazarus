{ G6.75: фізичні D12 пари й точні D1 expected через чинний T5M.
  Тестові десяткові значення — лише фіксовані host свідки,
  незалежний SENS REPL перевіряє семантику кожної пари. }
program test_elfd12menshe_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;Count:Integer;

procedure Save(const FileName:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+FileName,fmCreate);
  try if Bytes<>'' then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

{ Вихід Words — owned managed array точних D1 бітів.
  Тестовий expected не є мовним оракулом; точність підтверджує
  незалежний SENS CLI. Записуємо той самий packed T5M, що й ELF.
  1) Чому expected не Unicode '1'?
  2) Де обирається числовий домен?
  3) Чому негативні тести потрібні окремо? }
procedure Pair(const LabelText,L,R,Bit:RawByteString);
var Words:TExactWords;
begin
  Save(String(LabelText)+'-l.sens',EncodeNumericDecimal(L,12));
  Save(String(LabelText)+'-r.sens',EncodeNumericDecimal(R,12));
  SetLength(Words,1);Words[0]:=Bit;
  Save(String(LabelText)+'-expected.sens',EncodeT5M(Words));
  WriteLn(LabelText,#9,L,#9,R,#9,Bit);
  Inc(Count);
end;

var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
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
  Save('bad-d24.sens',EncodeNumericDecimal('1',24));
  SetLength(Words,1);Words[0]:='1';
  Save('bad-d1.sens',EncodeT5M(Words));
  Words[0]:='0010110';
  Save('bad-d7.sens',EncodeT5M(Words));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  Save('projection.lisp','(менше? -12 7)'+#10);
  if Count<>14 then Halt(3);
  WriteLn(StdErr,'D12-LESS-FIXTURES-OK cases=',Count);
end.
