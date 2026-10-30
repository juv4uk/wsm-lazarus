{ G6.170 — 12 реальних вкладених фізичних форм і 15 негативів.
  Генератор НЕ є SENS oracle: тільки чинні T5M та числові механізми.
  Єдиний семантичний доказ — запуск кожного того ж .sens у pinned SENS.
  Питання: як зберігаються leading zero W12? Чому це одна D2 форма?
  Чому overflow проміжного SUB треба відхилити, а не modulo?
  Чому W24 добуток є іншим числовим доменом? }
program test_irsubmul;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericsub,
     wsm.numericmul,wsm.irsubmul;
var Root,Dir:String;Positives,Negatives,Widened:SizeInt;

{ FPC 3.2.2 перекодовує константний StdErr до '?' без явного UTF-8.
  Це ЛИШЕ host діагностика; canonical T5M байти незмінні.
  Питання: чому повідомлення ≠ мовне D7? Де числова ширина?
  Чому міграція логів не змінює SENS семантику? }
function UA(const Value:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Value)) end;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

{ Owned bytes збережені TFileStream із гарантованим finally.
  Файли .sens завжди raw packed T5M, не Unicode проєкція.
  Питання: хто закриває файловий дескриптор? Коли виділяється файл?
  Чому один T5M пакет не можна підмінити plain decimal текстом? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

function Bits12(const Decimal:RawByteString):RawByteString;
var Numeric:TExplicitNumeric;
begin
  Numeric:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  if (Numeric.DomainWidth<>12) or (Length(Numeric.ExactBits)<>12) then
    raise Exception.Create('пошкоджена точна ширина D12');
  Result:=Numeric.ExactBits;
end;

{ Фізичне джерело — одна правильна вкладена D2 форма, загорнена T5M.
  D5-ключі п'ятибітні з pinned lib/domains/d5.lisp.
  Ця генерація є тестовою формою, не авторитетом callable законів.
  Питання: чому SUB=01010, IMUL/множення=10110?
  Чому 01 закриває лише поточний D2 список?
  Чому зовнішній аргумент після закриття внутрішнього списку? }
function Nested(const A,B,C:RawByteString):RawByteString;
begin
  Result:=EncodeT5M(Words(['10','10110','10','01011',A,B,'01',C,'01']));
end;

procedure CaseOf(const LabelText:String;const AText,BText,CText:RawByteString);
var A,B,C,Difference,Expected,Physical,Image:RawByteString;
    Numeric:TExplicitNumeric;Width:SizeInt;
begin
  A:=EncodeNumericDecimal(AText,12);
  B:=EncodeNumericDecimal(BText,12);
  C:=EncodeNumericDecimal(CText,12);
  Difference:=SubtractNumericPhysical(A,B,12);
  Numeric:=ReadNumericPhysical(Difference,12); { fail closed: no wide intermediate }
  if Numeric.DomainWidth<>12 then Halt(3);
  Expected:=MultiplyNumericPhysical(Difference,C,12);
  try
    Numeric:=ReadNumericPhysical(Expected,12); Width:=12;
  except on ENumericPlaneError do begin
    Numeric:=ReadNumericPhysical(Expected,24); Width:=24;
    Inc(Widened);
  end end;
  Physical:=Nested(Bits12(AText),Bits12(BText),Bits12(CText));
  Image:=BuildPhysicalNestedSubMulELF(Physical,RawByteString(Root));
  if (Length(Image)<150) or (Copy(Image,1,4)<>#$7F'ELF') then
    Halt(4);
  if BuildPhysicalNestedSubMulELF(Physical,RawByteString(Root))<>Image then
    Halt(5);
  Save(LabelText+'.sens',Physical);
  Save(LabelText+'-expected.sens',Expected);
  Save(LabelText+'.elf',Image);
  WriteLn(LabelText,#9,AText,#9,BText,#9,CText,#9,Width);
  Inc(Positives);
end;

procedure Reject(const LabelText:String;const Physical:RawByteString);
var Image:RawByteString;Rejected:Boolean;
begin
  Save('bad-'+LabelText+'.sens',Physical);
  Image:='';Rejected:=False;
  try Image:=BuildPhysicalNestedSubMulELF(Physical,RawByteString(Root));
  except on E:Exception do Rejected:=True end;
  if not Rejected or (Image<>'') then
    raise Exception.Create('прийнято відхилену форму '+LabelText);
  Inc(Negatives);
end;

var A,B,C:RawByteString;
begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);Dir:=ParamStr(2);
  if not ForceDirectories(Dir) then Halt(2);
  SetTextCodePage(Output,CP_UTF8);SetTextCodePage(StdErr,CP_UTF8);
  Positives:=0;Negatives:=0;Widened:=0;
  CaseOf('01','2','3','4');
  CaseOf('02','-2','1','3');
  CaseOf('03','2047','1','2');
  CaseOf('04','-2048','-1','1');
  CaseOf('05','100','200','-3');
  CaseOf('06','-1024','-1024','-1');
  CaseOf('07','0','0','2047');
  CaseOf('08','2047','2047','2047');
  CaseOf('09','-2048','-2048','-2048');
  CaseOf('10','2000','-1','-2');
  CaseOf('11','2047','0','-1');
  CaseOf('12','-2048','0','-1');
  A:=Bits12('2');B:=Bits12('3');C:=Bits12('4');
  Reject('голий-атом',EncodeT5M(Words(['1'])));
  Reject('чужа-зовнішня-голова',
    EncodeT5M(Words(['10','01010','10','01011',A,B,'01',C,'01'])));
  Reject('чужа-вкладена-голова',
    EncodeT5M(Words(['10','10110','10','10110',A,B,'01',C,'01'])));
  Reject('плоска-форма',EncodeT5M(Words(['10','10110',A,B,C,'01'])));
  Reject('переставлені-аргументи',
    EncodeT5M(Words(['10','10110',C,'10','01011',A,B,'01','01'])));
  Reject('мало-аргументів',
    EncodeT5M(Words(['10','10110','10','01011',A,B,'01','01'])));
  Reject('зайвий-аргумент',
    EncodeT5M(Words(['10','10110','10','01011',A,B,'01',C,C,'01'])));
  Reject('заміна-на-D1',
    EncodeT5M(Words(['10','10110','10','01010','1',B,'01',C,'01'])));
  Reject('заміна-на-D7',
    EncodeT5M(Words(['10','10110','10','01010',A,'0010110','01',C,'01'])));
  Reject('заміна-на-D24',
    EncodeT5M(Words(['10','10110','10','01011',A,B,'01',
                     Bits12('4')+'000000000000','01'])));
  Reject('порожній-D3',
    EncodeT5M(Words(['10','10110','10','01010','000',B,'01',C,'01'])));
  Reject('другий-корінь',EncodeT5M(Words(['10','10110','10','01011',A,B,'01',C,'01','1'])));
  Reject('пара-замість-списку',
    EncodeT5M(Words(['11','10110','10','01011',A,B,'01',C,'01'])));
  Reject('переповнення-різниці',
    Nested(Bits12('2047'),Bits12('-1'),Bits12('2')));
  Reject('пошкоджений-T5M',#$F3);
  Save('empty.sens','');
  Save('fake.lisp','(помножити (відняти 2 3) 4)'+#10);
  if (Positives<>12) or (Negatives<>15) or (Widened<2) then
    Halt(6);
  WriteLn(StdErr,UA('D5-SUB-IMUL-СВІДКИ-ГАРАЗД ELF='),Positives,
    UA(' негативів='),Negatives,UA(' широкий-D24='),Widened);
end.
