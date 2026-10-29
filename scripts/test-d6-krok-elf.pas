{ G6.81 — canonical фізичні свідки D12 для машинного D6-кроку.
  Не інтерпретатор D6: лише незалежні входи/очікування для SENS-оракула.
  Весь exact numeric codec — існуючий wsm.numericplane. }
program test_d6_krok_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String;Total:SizeInt;

procedure Save(const Name:String;const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data));
  finally S.Free end;
end;

procedure CaseOne(const LabelId,Input,Answer:RawByteString);
var F:TExplicitNumeric;
begin
  { Створення лише числових D12 із явним доменом; жодних D7-цифр. }
  Save(String(LabelId)+'.sens',EncodeNumericDecimal(Input,12));
  Save(String(LabelId)+'.expected.sens',EncodeNumericDecimal(Answer,12));
  F:=ReadNumericPhysical(EncodeNumericDecimal(Input,12),12);
  if F.DomainWidth<>12 then raise Exception.Create('D12 admission failure');
  Inc(Total);
end;

var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Total:=0;
  CaseOne('01','-2048','-2047');
  CaseOne('02','-1024','-1023');
  CaseOne('03','-2','-1');
  CaseOne('04','-1','0');
  CaseOne('05','0','1');
  CaseOne('06','1','2');
  CaseOne('07','1023','1024');
  CaseOne('08','2046','2047');
  if Total<>8 then raise Exception.Create('неповні D12 свідки');
  Save('overflow.sens',EncodeNumericDecimal('2047',12));
  Save('bad-d24.sens',EncodeNumericDecimal('1',24));
  SetLength(Words,1);
  Words[0]:='1'; Save('bad-d1.sens',EncodeT5M(Words));
  Words[0]:='0010110'; Save('bad-d7.sens',EncodeT5M(Words));
  Save('bad-t5m.sens',#$F3);
  Save('empty.sens','');
  WriteLn('D6-001110-FIXTURES=8');
end.

{ Кожен тестовий числовий атом є окремим exact packed T5M D12.
  Значення F — керований FPC numeric record, звільнення автоматичне.
  1) Чому 2047+1 не допускається в цьому D12-only backend?
  2) Чому D1 і D7 файли формуються окремими ширинами?
  3) Чому Answer не є семантичним oracle?
  4) Чому signed -2048 допустимий D12? }