{ G6.76: фізичні packed D12/D24 свідки; генератор не є оракулом.
  Числа виключно через уже чинний pinned numericplane/T5M codec. }
program test_elfd12neg;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Directory:String; N:SizeInt; Words:TExactWords;

{ Directory — позичена host-тека; S — owned канонічні фізичні байти.
  Потік звільняється навіть при помилці. Жодних власних законів.
  Питання: чому .sens не має бути текстом? Де задається width?
  Чому очікуване значення не вважаємо SENS oracle? }
procedure Save(const Name:String;const S:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Directory+'/'+Name,fmCreate);
  try if Length(S)>0 then Stream.WriteBuffer(S[1],Length(S));
  finally Stream.Free end;
end;

procedure CasePositive(const LabelText,Input,Negative:RawByteString;Width:SizeInt);
begin
  Save(String(LabelText)+'-in.sens',EncodeNumericDecimal(Input,12));
  Save(String(LabelText)+'-expected.sens',EncodeNumericDecimal(Negative,Width));
  Inc(N);
end;

begin
  if ParamCount<>1 then Halt(64);
  Directory:=ParamStr(1);N:=0;
  if not ForceDirectories(Directory) then Halt(2);
  CasePositive('01','0','0',12);
  CasePositive('02','1','-1',12);
  CasePositive('03','-1','1',12);
  CasePositive('04','17','-17',12);
  CasePositive('05','-17','17',12);
  CasePositive('06','2047','-2047',12);
  CasePositive('07','-2047','2047',12);
  CasePositive('08','-2048','2048',24);
  CasePositive('09','1024','-1024',12);
  CasePositive('10','-1024','1024',12);
  Save('bad-d24.sens',EncodeNumericDecimal('1',24));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  SetLength(Words,1); Words[0]:='1';
  Save('bad-d1.sens',EncodeT5M(Words));
  Words[0]:='0010110';
  Save('bad-d7.sens',EncodeT5M(Words));
  if N<>10 then Halt(2);
  WriteLn('Д12-ЗНАК-СВІДКИ-ГОТОВІ позитивів=',N);
end.

{ Це тестовий генератор, а не виконавець або семантичний oracle.
  Питання: чому -2048 потребує D24? Чому один байт D1 не є D12?
  Хто виконує машинну інструкцію NEG у цьому сценарії? }
