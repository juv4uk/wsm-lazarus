{ G3.38 — FPC механічні позитиви/негативи точного D12+ додавання.
  Очікування pinned numeric-d12-start-extension-1, не новий закон. }
program test_numericadd;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd;
var Checks:SizeInt; Dir:String; Words:TExactWords;
procedure Ensure(Ok:Boolean;const Why:RawByteString);
begin
  Inc(Checks);
  if not Ok then begin
    WriteLn(StdErr,RawByteString('ДОДАВАННЯ-ТЕСТ-ПОМИЛКА: '),Why);Halt(1);
  end;
end;
{ Decimal тут тільки очікуваний тестовий свідок, у механізмі
  математичний результат рахується без host decimal/Int64.
  Питання: чому порівнюємо фізичні байти? Хто задає обидва домени?
  Коли звільняються проміжні RawByteString? }
function ExpectSum(const A,B:RawByteString; WIn,WOut:SizeInt;
  const Expected:RawByteString):RawByteString;
var Got:RawByteString; N:TExplicitNumeric;
begin
  Got:=AddNumericPhysical(EncodeNumericDecimal(A,WIn),
    EncodeNumericDecimal(B,WIn),WIn);
  Ensure(Got=EncodeNumericDecimal(Expected,WOut),
    'фізичні байти суми не збіглися');
  N:=ReadNumericPhysical(Got,WOut);
  Ensure((N.DomainWidth=WOut) and (Length(N.ExactBits)=WOut),
    'пошкоджено точну ширину');
  Ensure(RenderNumericDecimal(N)=Expected,'пошкоджено знак відповіді');
  Result:=Got;
end;
{ Негативні входи не мають права повертати фізичну відповідь.
  Питання: чи дозволений змішаний D12/D24? Чому malformed T5M
  не можна замінити D3:000? Що перевіряє відновлення після помилок? }
procedure Reject(const L,R:RawByteString; W:SizeInt;
  const Why:RawByteString);
var Got:RawByteString; Failed:Boolean;
begin
  Failed:=False;
  try Got:=AddNumericPhysical(L,R,W)
  except on E:Exception do Failed:=True end;
  Ensure(Failed,Why);
end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(IncludeTrailingPathDelimiter(Dir)+Name,fmCreate);
  try if Bytes<>'' then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);Checks:=0;
  Ensure(SelectedNumericDomain('D12')=12,'перша сходинка не D12');
  ExpectSum('0','0',12,12,'0');
  ExpectSum('7','-7',12,12,'0');
  ExpectSum('-1','1',12,12,'0');
  ExpectSum('-2048','2047',12,12,'-1');
  ExpectSum('2047','-2048',12,12,'-1');
  ExpectSum('2047','1',12,24,'2048');
  ExpectSum('-2048','-1',12,24,'-2049');
  ExpectSum('8388607','1',24,48,'8388608');
  ExpectSum('-8388608','-1',24,48,'-8388609');
  ExpectSum('140737488355327','1',48,96,'140737488355328');
  ExpectSum('39614081257132168796771975167','1',96,192,
    '39614081257132168796771975168');
  ExpectSum('-1','1',192,192,'0');
  ExpectSum('0','0',192,192,'0');
  Reject(EncodeNumericDecimal('2047',12),
    EncodeNumericDecimal('1',24),12,'змішаний D12/D24');
  Reject(EncodeNumericDecimal('1',12),
    EncodeNumericDecimal('1',12),24,'неявне звуження/розширення');
  Reject(#243,EncodeNumericDecimal('1',12),12,'зіпсований T5M');
  Reject('',EncodeNumericDecimal('1',12),12,'порожній атом');
  SetLength(Words,2);
  Words[0]:=StringOfChar('0',12);
  Words[1]:=StringOfChar('1',12);
  Reject(EncodeT5M(Words),EncodeNumericDecimal('1',12),12,'два слова');
  SetLength(Words,1);Words[0]:='1';
  Reject(EncodeT5M(Words),EncodeNumericDecimal('1',12),12,'D1 як D12');
  Reject(EncodeNumericDecimal(
    '3138550867693340381917894711603833208051177722232017256447',192),
    EncodeNumericDecimal('1',192),192,'переповнення D192');
  Reject(EncodeNumericDecimal(
    '-3138550867693340381917894711603833208051177722232017256448',192),
    EncodeNumericDecimal('-1',192),192,'відємне переповнення D192');
  Save('left.sens',EncodeNumericDecimal('2047',12));
  Save('right.sens',EncodeNumericDecimal('1',12));
  Save('expected.sens',EncodeNumericDecimal('2048',24));
  Save('bad.sens',#243);
  Save('wrong.sens',EncodeNumericDecimal('1',24));
  Save('human.lisp',RawByteString('1'));
  Ensure(ExpectSum('-1','1',12,12,'0')=
    EncodeNumericDecimal('0',12),'немає відновлення після відмов');
  WriteLn(RawByteString('ДОДАВАННЯ-FPC-ГАРАЗД перевірок='),Checks,
    ' D12-D192=точні переповнення=розширені',
    ' змішані-домени=відхилено T5M=відхилено');
  WriteLn(RawByteString('ДОДАВАННЯ-МЕЖА лише=same-domain-двійкові-атоми'),
    ' D5/REPL/Core4=не-заявлено');
end.
