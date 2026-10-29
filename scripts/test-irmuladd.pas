{ G6.92 — канонічні фізичні свідки вкладеного D5 множення → додавання.
  Це генератор тестів, НЕ незалежний мовний оракул. Exact D5 ключі —
  pinned lib/domains/d5.lisp, числова механіка — існуючі D12 gates.
  Питання: чому W12 не є числовим законом без D5 контексту?
  Чому добуток D24 відхиляємо, але суму D24 зберігаємо?
  Чому файли .sens не є текстовою українською проєкцією?
  Хто перевіряє програму незалежно від FPC? }
program test_irmuladd;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericmul,
     wsm.numericadd,wsm.irmuladd;
var Root,Dir:String;Positives,Negatives,Widened:SizeInt;

function UA(const V:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(V)) end;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

{ Owned file stream завершується finally; Result передано позичено.
  Зберігаємо справжні packed T5M байти без Unicode конвертування. }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

function Bits12(const Decimal:RawByteString):RawByteString;
var Value:TExplicitNumeric;
begin
  Value:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  if (Value.DomainWidth<>12) or (Length(Value.ExactBits)<>12) then
    raise Exception.Create('точна ширина D12 втрачена');
  Result:=Value.ExactBits;
end;

{ D5:01010 зовнішнє додавання, D5:10110 внутрішнє множення.
  Власний результат — єдина канонічна packed D2 програма .sens;
  01 закриває рівно один список. Немає .lisp за канонічний вхід.
  Питання: як синтаксис D2 відокремлює два списки?
  Чому бітовий ключ не може бути замінений словом MUL?
  Чому D7 символ тут не дорівнює точній голові D5? }
function Nested(const A,B,C:RawByteString):RawByteString;
begin
  Result:=EncodeT5M(Words(['10','01010','10','10110',A,B,'01',C,'01']));
end;

procedure CaseOf(const LabelText:String;const AText,BText,CText:RawByteString);
var A,B,C,Product,Expected,Physical,Image:RawByteString;
    Numeric:TExplicitNumeric;Width:SizeInt;
begin
  A:=EncodeNumericDecimal(AText,12);
  B:=EncodeNumericDecimal(BText,12);
  C:=EncodeNumericDecimal(CText,12);
  Product:=MultiplyNumericPhysical(A,B,12);
  Numeric:=ReadNumericPhysical(Product,12); { strict D12 intermediate }
  if Numeric.DomainWidth<>12 then Halt(3);
  Expected:=AddNumericPhysical(Product,C,12);
  try Numeric:=ReadNumericPhysical(Expected,12);Width:=12
  except on ENumericPlaneError do begin
    Numeric:=ReadNumericPhysical(Expected,24);Width:=24;
    Inc(Widened);
  end end;
  Physical:=Nested(Bits12(AText),Bits12(BText),Bits12(CText));
  Image:=BuildPhysicalNestedMulAddELF(Physical,RawByteString(Root));
  if (Length(Image)<150) or (Copy(Image,1,4)<>#$7F'ELF') then Halt(4);
  if BuildPhysicalNestedMulAddELF(Physical,RawByteString(Root))<>Image then Halt(5);
  Save(LabelText+'.sens',Physical);
  Save(LabelText+'-expected.sens',Expected);
  Save(LabelText+'.elf',Image);
  WriteLn(LabelText,#9,AText,#9,BText,#9,CText,#9,Width);
  Inc(Positives);
end;

{ Reject не має права публікувати ELF чи змінювати фізичний input.
  Локальні RawByteString auto-managed, повторні відмови ізолюються. }
procedure Reject(const LabelText:String;const Physical:RawByteString);
var Image:RawByteString;Rejected:Boolean;
begin
  Save('bad-'+LabelText+'.sens',Physical);
  Image:='';Rejected:=False;
  try Image:=BuildPhysicalNestedMulAddELF(Physical,RawByteString(Root))
  except on E:Exception do Rejected:=True end;
  if not Rejected or (Image<>'') then
    raise Exception.Create('прийнято хибну фізичну форму: '+LabelText);
  Inc(Negatives);
end;

var A,B,C:RawByteString;
begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);Dir:=ParamStr(2);
  if not ForceDirectories(Dir) then Halt(2);
  SetTextCodePage(Output,CP_UTF8);
  Positives:=0;Negatives:=0;Widened:=0;
  CaseOf('01','2','3','4');
  CaseOf('02','-2','1','3');
  CaseOf('03','2047','-1','2');
  CaseOf('04','-2048','1','1');
  CaseOf('05','100','20','-300');
  CaseOf('06','-1024','2','100');
  CaseOf('07','0','0','2047');
  CaseOf('08','2047','1','1');
  CaseOf('09','-2048','1','-1');
  CaseOf('10','1000','2','100');
  CaseOf('11','-1024','2','-2048');
  CaseOf('12','2047','1','2047');
  A:=Bits12('2');B:=Bits12('3');C:=Bits12('4');
  Reject('голий-атом',EncodeT5M(Words(['1'])));
  Reject('чужа-зовнішня-голова',
    EncodeT5M(Words(['10','10110','10','10110',A,B,'01',C,'01'])));
  Reject('чужа-вкладена-голова',
    EncodeT5M(Words(['10','01010','10','01010',A,B,'01',C,'01'])));
  Reject('плоска-форма',EncodeT5M(Words(['10','01010',A,B,C,'01'])));
  Reject('переставлені-аргументи',
    EncodeT5M(Words(['10','01010',C,'10','10110',A,B,'01','01'])));
  Reject('мало-аргументів',
    EncodeT5M(Words(['10','01010','10','10110',A,B,'01','01'])));
  Reject('зайвий-аргумент',
    EncodeT5M(Words(['10','01010','10','10110',A,B,'01',C,C,'01'])));
  Reject('заміна-на-D1',
    EncodeT5M(Words(['10','01010','10','10110','1',B,'01',C,'01'])));
  Reject('заміна-на-D7',
    EncodeT5M(Words(['10','01010','10','10110',A,'0010110','01',C,'01'])));
  Reject('заміна-на-D24',
    EncodeT5M(Words(['10','01010','10','10110',A,B,'01',
                    Bits12('4')+'000000000000','01'])));
  Reject('порожній-D3',
    EncodeT5M(Words(['10','01010','10','10110','000',B,'01',C,'01'])));
  Reject('другий-корінь',
    EncodeT5M(Words(['10','01010','10','10110',A,B,'01',C,'01','1'])));
  Reject('пара-замість-списку',
    EncodeT5M(Words(['11','01010','10','10110',A,B,'01',C,'01'])));
  Reject('переповнення-добутку',
    Nested(Bits12('2047'),Bits12('2'),Bits12('1')));
  Reject('пошкоджений-T5M',#$F3);
  Save('empty.sens','');
  Save('fake.lisp',UA('(додати (помножити 2 3) 4)')+#10);
  if (Positives<>12) or (Negatives<>15) or (Widened<>5) then Halt(6);
  WriteLn(StdErr,UA('D5-ВКЛАДЕНЕ-СВІДКИ-ГАРАЗД ELF='),Positives,
    UA(' негативів='),Negatives,UA(' широкий-D24='),Widened);
end.
