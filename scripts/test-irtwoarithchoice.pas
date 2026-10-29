{ G6.116 — лише генератор host fixtures; НЕ закон SENS, не evaluator.
  32 canonical packed D3:101 nested D5 (+/-) програми;
  реальний oracle — незалежний pinned SENS CLI на цих САМИХ байтах. }
program test_irtwoarithchoice;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.numericadd,wsm.numericsub;
var Folder:String;Count,Negatives:SizeInt;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

{ Borrowed Name/Data; managed packed T5M bytes; local TFileStream
  owned and released by finally. .sens is never Unicode/ASCII source.
  Питання: як зберігаються leading zeros? Чому T5M, не UTF-8?
  Хто звільняє Stream? Де незалежний oracle? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

function Bits12(const Decimal:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Result:=N.ExactBits;
  if Length(Result)<>12 then raise Exception.Create('втрачено W12');
end;

{ LOp/ROp: borrowed exact 5-bit pinned D5 coordinates; A..D:
  borrowed exact 12-bit numeric operands. Result: owned binary T5M
  D2 list, без текстового dispatch чи D7-значень.
  Питання: чому D3:101 має три біти? Чому D5 рівно п'ять?
  Чому порядок гілок важливий? Хто звільняє Result? }
function Nested(const LOp,ROp,A,B,C,D:RawByteString):RawByteString;
begin
  Result:=EncodeT5M(Words([
    '10','101','10',LOp,A,B,'01',
    '10',ROp,C,D,'01','01']));
end;

{ Очікувана D1 відповідь задана незалежними записаними golden-свідками,
  ніколи не використовується компілятором. Arithmetic checks у fixture
  лише підтверджують числовий D12 діапазон; pinned SENS REPL є oracle.
  Питання: чому fixture expected не є джерелом мовного закону?
  Чому D24 неможливо усікти? Чому LOp/ROp це physical bits?
  Навіщо перевіряти той самий .sens через upstream SENS? }
procedure CaseOf(const LabelText,A,B,C,D,LOp,ROp,Expected:RawByteString);
var PA,PB,PC,PD,LValue,RValue:RawByteString;N:TExplicitNumeric;
begin
  if (Expected<>'0') and (Expected<>'1') then Halt(21);
  PA:=EncodeNumericDecimal(A,12);PB:=EncodeNumericDecimal(B,12);
  PC:=EncodeNumericDecimal(C,12);PD:=EncodeNumericDecimal(D,12);
  if LOp='01010' then LValue:=AddNumericPhysical(PA,PB,12)
  else if LOp='01011' then LValue:=SubtractNumericPhysical(PA,PB,12)
  else Halt(22);
  if ROp='01010' then RValue:=AddNumericPhysical(PC,PD,12)
  else if ROp='01011' then RValue:=SubtractNumericPhysical(PC,PD,12)
  else Halt(23);
  N:=ReadNumericPhysical(LValue,12);
  if N.DomainWidth<>12 then Halt(24);
  N:=ReadNumericPhysical(RValue,12);
  if N.DomainWidth<>12 then Halt(25);
  Save(String(LabelText)+'-program.sens',
       Nested(LOp,ROp,Bits12(A),Bits12(B),Bits12(C),Bits12(D)));
  Save(String(LabelText)+'-expected.sens',EncodeT5M(Words([Expected])));
  WriteLn(LabelText,#9,A,#9,B,#9,C,#9,D,#9,LOp,#9,ROp,#9,Expected);
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
  CaseOf('01','2','3','8','3','01010','01010','0');
  CaseOf('02','2','3','5','0','01010','01010','1');
  CaseOf('03','5','2','3','4','01010','01010','1');
  CaseOf('04','0','0','0','0','01010','01010','1');
  CaseOf('05','-1','0','-1','0','01010','01010','1');
  CaseOf('06','2047','0','2046','0','01010','01010','0');
  CaseOf('07','-2048','0','-2048','0','01010','01010','1');
  CaseOf('08','10','3','8','5','01010','01010','1');
  CaseOf('09','2','3','8','3','01010','01011','1');
  CaseOf('10','2','3','5','0','01010','01011','1');
  CaseOf('11','5','2','3','4','01010','01011','0');
  CaseOf('12','0','0','0','0','01010','01011','1');
  CaseOf('13','-1','0','-1','0','01010','01011','1');
  CaseOf('14','2047','0','2046','0','01010','01011','0');
  CaseOf('15','-2048','0','-2048','0','01010','01011','1');
  CaseOf('16','10','3','8','5','01010','01011','0');
  CaseOf('17','2','3','8','3','01011','01010','0');
  CaseOf('18','2','3','5','0','01011','01010','0');
  CaseOf('19','5','2','3','4','01011','01010','0');
  CaseOf('20','0','0','0','0','01011','01010','1');
  CaseOf('21','-1','0','-1','0','01011','01010','1');
  CaseOf('22','2047','0','2046','0','01011','01010','0');
  CaseOf('23','-2048','0','-2048','0','01011','01010','1');
  CaseOf('24','10','3','8','5','01011','01010','0');
  CaseOf('25','2','3','8','3','01011','01011','0');
  CaseOf('26','2','3','5','0','01011','01011','0');
  CaseOf('27','5','2','3','4','01011','01011','0');
  CaseOf('28','0','0','0','0','01011','01011','1');
  CaseOf('29','-1','0','-1','0','01011','01011','1');
  CaseOf('30','2047','0','2046','0','01011','01011','0');
  CaseOf('31','-2048','0','-2048','0','01011','01011','1');
  CaseOf('32','10','3','8','5','01011','01011','0');
  if Count<>32 then Halt(26);
  A:=Bits12('2');B:=Bits12('3');C:=Bits12('8');D:=Bits12('3');
  Negative('root',EncodeT5M(Words([
    '10','11010','10','01010',A,B,'01','10','01011',C,D,'01','01'])));
  Negative('left-head',Nested('11010','01011',A,B,C,D));
  Negative('right-head',Nested('01010','11011',A,B,C,D));
  Negative('flat',EncodeT5M(Words(['10','101',A,B,C,D,'01'])));
  Negative('missing-left',EncodeT5M(Words([
    '10','101','10','01010',A,'01','10','01011',C,D,'01','01'])));
  Negative('missing-right',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01011',C,'01','01'])));
  Negative('extra-left',EncodeT5M(Words([
    '10','101','10','01010',A,B,A,'01','10','01011',C,D,'01','01'])));
  Negative('extra-right',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01011',C,D,C,'01','01'])));
  Negative('d1-left',Nested('01010','01011','1',B,C,D));
  Negative('d7-right',Nested('01010','01011',A,B,'0010110',D));
  DecodeT5M(EncodeNumericDecimal('1',24),D24Words);W24:=D24Words[0];
  Negative('d24',Nested('01010','01011',A,B,W24,D));
  Negative('w13',Nested('01010','01011',A,B,'0000000000001',D));
  Negative('two-roots',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','10','01011',C,D,'01','01','0'])));
  Negative('dotted',EncodeT5M(Words([
    '10','101','10','01010',A,B,'01','11','10','01011',C,D,'01','01'])));
  Negative('corrupt',#$FF);
  Negative('padding',#$F2);
  Negative('empty','');
  Negative('overflow-plus-left',Nested('01010','01011',Bits12('2047'),Bits12('1'),C,D));
  Negative('overflow-minus-left',Nested('01011','01010',Bits12('-2048'),Bits12('1'),C,D));
  Negative('overflow-plus-right',Nested('01011','01010',A,B,Bits12('2047'),Bits12('1')));
  Negative('overflow-minus-right',Nested('01010','01011',A,B,Bits12('-2048'),Bits12('1')));
  if Negatives<>21 then Halt(27);
  Save('fake.lisp','(тотожне? (додати 2 3) (відняти 8 3))'+#10);
  WriteLn(StdErr,'ВИБІР-ДВОХ-АРИФМЕТИЧНИХ-ГІЛОК-СВІДКИ: ',Count,' позитивів, ',
          Negatives,' негативів');
end.
