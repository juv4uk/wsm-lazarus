{ G3.43. Checked FPC selftest, не семантичний oracle.
  Модель Int64 тут ТІЛЬКИ незалежні маломасштабні тестові значення,
  жодного Int64 немає у реалізації двійкового множення. }
program test_numericmul;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.t5m, wsm.numericplane, wsm.numericmul;
var Checks, I,J:SizeInt; Words:TExactWords; Failed:Boolean;
procedure Need(OK:Boolean;const Why:String);
begin
  Inc(Checks);
  if not OK then raise Exception.Create('МНОЖЕННЯ-ТЕСТ: '+Why);
end;
function ExpectProduct(const A,B:RawByteString; WIn,WOut:SizeInt;
  const Expected:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  Result:=MultiplyNumericPhysical(EncodeNumericDecimal(A,WIn),
    EncodeNumericDecimal(B,WIn),WIn);
  Need(Result=EncodeNumericDecimal(Expected,WOut),
    'фізичні T5M байти не збіглися: '+String(A)+' * '+String(B));
  N:=ReadNumericPhysical(Result,WOut);
  Need((N.DomainWidth=WOut) and (Length(N.ExactBits)=WOut),
    'порушено точний вихідний домен');
  Need(RenderNumericDecimal(N)=Expected,'пошкоджено знак або число');
end;
procedure Reject(const L,R:RawByteString;W:SizeInt;const Why:String);
var Data:RawByteString;
begin
  Failed:=False;
  try Data:=MultiplyNumericPhysical(L,R,W)
  except on E:Exception do Failed:=True end;
  Need(Failed,'невідхилений '+Why);
end;
begin
  try
    Checks:=0;
    ExpectProduct('0','-2048',12,12,'0');
    ExpectProduct('1','-2048',12,12,'-2048');
    ExpectProduct('-1','-2048',12,24,'2048');
    ExpectProduct('2047','2',12,24,'4094');
    ExpectProduct('2047','2047',12,24,'4190209');
    ExpectProduct('-2048','-2048',12,24,'4194304');
    ExpectProduct('-2048','2047',12,24,'-4192256');
    ExpectProduct('8388607','2',24,48,'16777214');
    ExpectProduct('140737488355327','2',48,96,'281474976710654');
    ExpectProduct('39614081257132168796771975167','2',96,192,
      '79228162514264337593543950334');
    ExpectProduct('-1','-1',192,192,'1');
    ExpectProduct('0','0',192,192,'0');
    { Для всіх тестових D12 і D24 малих цілих: FPC двійкова
      реалізація порівнюється з незалежною Int64 моделлю. }
    for I:=-16 to 16 do for J:=-16 to 16 do begin
      ExpectProduct(RawByteString(IntToStr(I)),RawByteString(IntToStr(J)),
        12,12,RawByteString(IntToStr(I*J)));
      ExpectProduct(RawByteString(IntToStr(I)),RawByteString(IntToStr(J)),
        24,24,RawByteString(IntToStr(I*J)));
    end;
    Reject(EncodeNumericDecimal('1',12),EncodeNumericDecimal('1',24),
      12,'неявна зміна D12/D24');
    Reject(EncodeNumericDecimal('1',12),EncodeNumericDecimal('1',12),
      24,'недійсний явний домен');
    Reject(#243,EncodeNumericDecimal('1',12),12,'зіпсований T5M');
    Reject('',EncodeNumericDecimal('1',12),12,'порожній T5M');
    SetLength(Words,1);Words[0]:='1';
    Reject(EncodeT5M(Words),EncodeNumericDecimal('1',12),12,'D1 замість D12');
    SetLength(Words,2);Words[0]:=StringOfChar('0',12);
    Words[1]:=StringOfChar('0',12);
    Reject(EncodeT5M(Words),EncodeNumericDecimal('1',12),12,
      'два фізичні атоми');
    Reject(EncodeNumericDecimal(
      '3138550867693340381917894711603833208051177722232017256447',192),
      EncodeNumericDecimal('2',192),192,'переповнення D192');
    Reject(EncodeNumericDecimal(
      '-3138550867693340381917894711603833208051177722232017256448',192),
      EncodeNumericDecimal('2',192),192,'від’ємне переповнення D192');
    ExpectProduct('-7','7',12,12,'-49');
    Need(Checks>6500,'неповна матриця позитивних/негативних свідків');
    WriteLn('NUMERIC-MUL-OK width=D12-D192 model-pairs=2178 checks=',Checks,
      ' overflow=promote D192=fail-closed');
    WriteLn('NUMERIC-MUL-LIMIT SENS-laws=pinned Core1=NOT-EXECUTED');
  except on E:Exception do begin
    WriteLn(StdErr,'NUMERIC-MUL-FAIL: ',E.Message);Halt(1);
  end end;
end.
