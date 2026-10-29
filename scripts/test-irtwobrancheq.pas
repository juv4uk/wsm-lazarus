{ G6.104 — фізичні свідки двох незалежних вкладених D5 піддерев.
  Генератор — ЛИШЕ host fixture. Незалежний semantic oracle — pinned SENS.
  16 контрольних відповідей — лише host-свідки, pinned SENS CLI — обов'язковий незалежний оракул. }
program test_irtwobrancheq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
     wsm.numericsub;
var Folder:String;Count,Negatives:SizeInt;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

{ Borrowed HostFileName, Data — canonical owned packed physical bytes.
  Stream — локальний, завжди закривається. Файл .sens не UTF-8 text.
  Питання: чому encoded T5M не є decimal projection?
  Хто звільняє Stream після винятку?
  Як у fixture не зіпсувати leading zero бітів?
  Де справжній SENS oracle? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

function Bits12(const Decimal:RawByteString):RawByteString;
var Numeric:TExplicitNumeric;
begin
  Numeric:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Result:=Numeric.ExactBits;
  if Length(Result)<>12 then raise Exception.Create('втрачено exact W12');
end;

{ Чотири numeric D12 і три точні callable D5:
  eq( add(A,B), sub(C,D) ) з двома вкладеними D2 списками.
  Result — packed .sens (owned managed RawByteString).
  Питання: чому два окремих D2 close необхідні?
  Чому порядок sibling-списків важливий?
  Чому D24 тут не можна мовчки прийняти?
  Чому імена не визначають binary function? }
function Nested(const A,B,C,D:RawByteString):RawByteString;
begin
  Result:=EncodeT5M(Words([
    '10','101','10','01010',A,B,'01',
    '10','01011',C,D,'01','01']));
end;

{ Inputs borrowed decimal fixture labels, NOT SENS source.
  Sum/Difference — numeric laws delegated to existing pinned mechanics.
  Canonical source .sens and independently compiled ELF are distinct artifacts;
  no Pascal boolean and no English semantic dispatch.
  Питання: чому host fixtures не замінюють upstream pinned oracle?
  Чому дві гілки мають пройти явний D12 admission?
  Чому знак D12 зберігається при пакуванні?
  Як negative fixture виявляє підміну правого аргументу? }
procedure CaseOf(const LabelText,A,B,C,D,Expected:RawByteString);
var PA,PB,PC,PD,Sum,Difference:RawByteString;N:TExplicitNumeric;
begin
  if (Expected<>'0') and (Expected<>'1') then Halt(23);
  PA:=EncodeNumericDecimal(A,12);PB:=EncodeNumericDecimal(B,12);
  PC:=EncodeNumericDecimal(C,12);PD:=EncodeNumericDecimal(D,12);
  Sum:=AddNumericPhysical(PA,PB,12);
  Difference:=SubtractNumericPhysical(PC,PD,12);
  N:=ReadNumericPhysical(Sum,12);
  if N.DomainWidth<>12 then Halt(24);
  N:=ReadNumericPhysical(Difference,12);
  if N.DomainWidth<>12 then Halt(25);
  Save(String(LabelText)+'-program.sens',
       Nested(Bits12(A),Bits12(B),Bits12(C),Bits12(D)));
  Save(String(LabelText)+'-expected.sens',EncodeT5M(Words([Expected])));
  WriteLn(LabelText,#9,A,#9,B,#9,C,#9,D,#9,Expected);
  Inc(Count);
end;

procedure Negative(const LabelText,Value:RawByteString);
begin
  Save('bad-'+String(LabelText)+'.sens',Value);
  Inc(Negatives);
end;

var A,B,C,D,W24:RawByteString;D24Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not ForceDirectories(Folder) then Halt(2);
  Count:=0;Negatives:=0;
  CaseOf('01','2','3','8','4','0');
  CaseOf('02','2','3','8','3','1');
  CaseOf('03','-2','-3','-4','3','0');
  CaseOf('04','-2','-3','3','4','0');
  CaseOf('05','0','0','0','0','1');
  CaseOf('06','2047','0','2046','0','0');
  CaseOf('07','-2048','0','-2047','0','0');
  CaseOf('08','-2048','1','-2048','0','0');
  CaseOf('09','1023','1024','2047','1','0');
  CaseOf('10','1023','1024','2047','0','1');
  CaseOf('11','-1000','-1000','-1999','0','0');
  CaseOf('12','-1000','-1000','-2048','0','0');
  CaseOf('13','120','-200','-70','20','0');
  CaseOf('14','100','200','100','-200','1');
  CaseOf('15','2047','-2048','-2048','-2047','1');
  CaseOf('16','-2048','2047','2047','2047','0');
  if Count<>16 then Halt(26);
  A:=Bits12('2');B:=Bits12('3');C:=Bits12('8');D:=Bits12('4');
  Negative('root',EncodeT5M(Words([
    '10','11010','10','01010',A,B,'01','10','01011',C,D,'01','01'])));
  Negative('add-head',EncodeT5M(Words([
    '10','101','10','01011',A,B,'01','10','01011',C,D,'01','01'])));
  Negative('sub-head',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01010',C,D,'01','01'])));
  Negative('swap-siblings',EncodeT5M(Words([
    '10','101','10','01011',C,D,'01','10','01010',A,B,'01','01'])));
  Negative('flat',EncodeT5M(Words(['10','101',A,B,C,D,'01'])));
  Negative('missing-left',EncodeT5M(Words([
    '10','101','10','01010',A,'01','10','01011',C,D,'01','01'])));
  Negative('missing-right',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01011',C,'01','01'])));
  Negative('extra-left',EncodeT5M(Words([
    '10','101','10','01010',A,B,A,'01','10','01011',C,D,'01','01'])));
  Negative('extra-right',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01011',C,D,C,'01','01'])));
  Negative('d1-left',EncodeT5M(Words([
    '10','101','10','01010','1',B,'01','10','01011',C,D,'01','01'])));
  Negative('d7-right',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01011','0010110',D,'01','01'])));
  DecodeT5M(EncodeNumericDecimal('1',24),D24Words);W24:=D24Words[0];
  Negative('d24',Nested(A,B,W24,D));
  Negative('w13',Nested(A,B,'0000000000001',D));
  Negative('two-roots',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01011',C,D,'01','01','0'])));
  Negative('dotted',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','11','10','01011',C,D,'01','01'])));
  Negative('corrupt',#$FF);
  Negative('padding',#$F2);
  Negative('empty','');
  Negative('overflow-add',Nested(Bits12('2047'),Bits12('1'),C,D));
  Negative('overflow-sub',Nested(A,B,Bits12('2047'),Bits12('-1')));
  if Negatives<>20 then Halt(27);
  Save('fake.lisp','(тотожне? (додати 2 3) (відняти 8 4))'+#10);
  WriteLn(StdErr,'ДВОГІЛКОВИЙ-Д3-СВІДКИ: ',Count,' позитивів, ',Negatives,' негативів');
end.
