{ Чисті механічні докази D12+; не виконання D5 arithmetic. }
program test_numericplane;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.numericplane;
var Checks, I:SizeInt; N:TExplicitNumeric; Words:TExactWords;
procedure Ensure(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then begin
    WriteLn(StdErr,'ЧИСЛО-ТЕСТ-ПОМИЛКА: ',Why); Halt(1);
  end;
end;
procedure RoundTrip(const Decimal:RawByteString; W:SizeInt);
var B,B2:RawByteString; S:TExplicitNumeric;
begin
  B:=EncodeNumericDecimal(Decimal,W);
  S:=ReadNumericPhysical(B,W);
  Ensure(S.DomainWidth=W,'втрачено явно обраний домен');
  Ensure(Length(S.ExactBits)=W,'втрачено точну ширину');
  Ensure(RenderNumericDecimal(S)=Decimal,'втрачено знакову десяткову проєкцію');
  B2:=EncodeNumericDecimal(RenderNumericDecimal(S),W);
  Ensure(B=B2,'змінилися канонічні фізичні байти');
end;
procedure RejectDecimal(const Decimal:RawByteString; W:SizeInt);
var Failed:Boolean; B:RawByteString;
begin
  Failed:=False;
  try B:=EncodeNumericDecimal(Decimal,W);
  except on E:ENumericPlaneError do Failed:=True;end;
  Ensure(Failed,'прийнято неканонічне або переповнене десяткове число '+String(Decimal));
end;
procedure RejectPhysical(const Physical:RawByteString; W:SizeInt);
var Failed:Boolean; S:TExplicitNumeric;
begin
  Failed:=False;
  try S:=ReadNumericPhysical(Physical,W);
  except
    on E:ENumericPlaneError do Failed:=True;
    on E:ET5MError do Failed:=True;
  end;
  Ensure(Failed,'прийнято фізично або доменно недійсне число');
end;
function ExactWord(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W);end;
begin
  Checks:=0;
  Ensure(SelectedNumericDomain('D12')=12,'D12 має бути першою числовою сходинкою');
  Ensure(SelectedNumericDomain('D192')=192,'обмежена D192 сходинка');
  { Всі 4096 точних D12 integer patterns, не вибірка. }
  for I:=-2048 to 2047 do RoundTrip(IntToStr(I),12);
  RoundTrip('0',24);
  RoundTrip('-1',24);
  RoundTrip('8388607',24);
  RoundTrip('-8388608',24);
  RoundTrip('140737488355327',48);
  RoundTrip('-140737488355328',48);
  RoundTrip('39614081257132168796771975167',96);
  RoundTrip('-39614081257132168796771975168',96);
  RoundTrip('3138550867693340381917894711603833208051177722232017256447',192);
  RoundTrip('-3138550867693340381917894711603833208051177722232017256448',192);
  { Explicit two's complement: мінус один фізично усі 12 одиниць. }
  N:=ReadNumericPhysical(EncodeNumericDecimal('-1',12),12);
  Ensure(N.ExactBits=StringOfChar('1',12),'D12: -1 exact-width physical');
  N:=ReadNumericPhysical(EncodeNumericDecimal('-2048',12),12);
  Ensure(N.ExactBits='100000000000','D12 мінімум має окремий знаковий біт');
  N:=ReadNumericPhysical(EncodeNumericDecimal('2047',12),12);
  Ensure(N.ExactBits='011111111111','D12 максимум має провідний нуль');
  N:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12);
  Ensure(N.ExactBits='000000000000','числовий D12:0 не є D1:0');

  RejectDecimal('',12);
  RejectDecimal('-0',12);
  RejectDecimal('00',12);
  RejectDecimal('01',12);
  RejectDecimal('-00',12);
  RejectDecimal('+1',12);
  RejectDecimal('2048',12);
  RejectDecimal('-2049',12);
  RejectDecimal('1.5',12);
  RejectDecimal('1e1',12);
  RejectDecimal('1 0',12);
  RejectDecimal('8388608',24);
  RejectDecimal('-8388609',24);
  RejectDecimal('1',10); { D10 координата не є числовою }
  RejectPhysical(ExactWord('0'),12); { D1 not D12 }
  RejectPhysical(ExactWord('000'),12); { D3 empty not D12 }
  RejectPhysical(EncodeNumericDecimal('1',12),24); { явний D24 не D12 }
  RejectPhysical(#243,12);
  RejectPhysical(#242,12);
  RejectPhysical('',12);
  RejectPhysical(ExactWord('1'),1);
  { Два фізично коректні окремі D12 слова — НЕ один numeric atom. }
  SetLength(Words,2);
  Words[0]:=StringOfChar('0',12);Words[1]:=StringOfChar('1',12);
  RejectPhysical(EncodeT5M(Words),12);
  Ensure(RenderNumericDecimal(
    ReadNumericPhysical(EncodeNumericDecimal('-2048',12),12))='-2048',
    'recover after invalid physical input');
  WriteLn('ЧИСЛОВА-ПЛОЩИНА-ГАРАЗД D12=4096/4096 D24-D192=межі ',
    'two-complement=точний T5M=байт-в-байт домен=явний перевірок=',Checks);
  WriteLn('ЧИСЛОВА-ПЛОЩИНА-МЕЖА арифметика=НЕ_ВИКОНУЄТЬСЯ ',
    'Core4=НЕ_ВИКОНУЄТЬСЯ REPL=НЕ_ГОТОВИЙ');
end.
