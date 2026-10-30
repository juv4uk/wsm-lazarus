{ G6.185 — явні D48/D96/D192 поза діапазонами попередніх доменів.
  G6.180 — окрема фізична порожнеча D3:000 дає D1:0.
  G6.174 — D1:0/D1:1 негативні за numberp, 8 числових позитивів.
  G6.158 — тестові ДВІЙКОВІ свідки: D2 рамка та точний D5:01001.
  Десяткові числа існують лише в host-маніфесті, не в .sens;
  D12/D24 — explicit signed numeric admission.
  Жодної функції Core1 не копіюємо в тестовий генератор. }
program test_irwidenumberp;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;M:TStringList;Count:SizeInt;Zero12,Zero24,Zero48,Zero96,Zero192:RawByteString;

{ Name: host filename, Physical: borrowed canonical bytes.
  F: owned stream; all bytes persisted exactly once.
  1) Чому текстова проєкція не є джерелом фізичних .sens?
  2) Де звільняється F у разі помилки?
  3) Що зберігає провідні нулі? }
procedure Save(const Name:String;const Physical:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Physical)>0 then F.WriteBuffer(Physical[1],Length(Physical));
  finally F.Free end;
end;

{ Items: borrowed exact bitwords, з D2 10/01, не text syntax.
  Words: managed owned FPC array; Result: packed T5M bytes.
  1) Яке слово є OPEN, а яке CLOSE?
  2) Чому W24 не зводимо до W12?
  3) Чому T5M «2» не є мовним числом? }
function Pack(const Items:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Items));
  for I:=0 to High(Items) do Words[I]:=Items[I];
  Result:=EncodeT5M(Words);
end;

procedure Positive(const LabelText,Decimal:RawByteString;Width:SizeInt);
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,Width),Width);
  Save(String(LabelText)+'.sens',Pack(['10','01001',N.ExactBits,'01']));
  Save(String(LabelText)+'.expected.sens',Pack(['1']));
  M.Add(String(LabelText)+#9+String(Decimal)+#9+IntToStr(Width));
  Inc(Count);
end;

{ D1:0 і D1:1 не є числами за pinned Contract 12.0.
  Вхідний D1 exact key; після запуску машинний D1:0 T5M.
  OracleArg є тільки українською текстовою ПРОЄКЦІЄЮ для SENS REPL,
  не фізичним SENS source або локальним законом.
  1) Чому Width=1 не є знаковим числом D12?
  2) Чому oracle має обчислити саме предикат D1?
  3) Чому очікуваний T5M біт 0, а не ASCII символ?
  4) Чому це не загальна підтримка D3 списків? }
{ Decimal: borrowed host decimal, Width: explicit ratified numeric domain.
  Ніколи не визначаємо домен із десяткового тексту: це лише тестове
  підтвердження, що вибраний фізичний W реально потрібний.
  1) Чому попередній домен мусить відмовити?
  2) Чому signed -minimum також перевіряємо?
  3) Хто створює канонічний фізичний T5M?
  4) Чому це не runtime-операція або новий мовний закон? }
procedure PositiveBeyond(const LabelText,Decimal:RawByteString;Width:SizeInt);
begin
  if not (Width in [48,96,192]) then Halt(68);
  try
    EncodeNumericDecimal(Decimal,Width div 2);
    Halt(69);
  except
    on E:ENumericPlaneError do begin end;
  end;
  Positive(LabelText,Decimal,Width);
end;

procedure NegativeD1(const LabelText,Bits,OracleArg:RawByteString);
begin
  if not ((Bits='0') or (Bits='1')) then Halt(65);
  Save(String(LabelText)+'.sens',Pack(['10','01001',Bits,'01']));
  Save(String(LabelText)+'.expected.sens',Pack(['0']));
  M.Add(String(LabelText)+#9+String(OracleArg)+#9+'1');
  Inc(Count);
end;

{ Один pinned D3:000 wkEmpty; не host false і не число.
  Тільки власні байти canonical Pack. Вивід — T5M D1:0.
  1) Чому D3:000 відмінний від D1:0?
  2) Чому wkEmpty є обов'язковим?
  3) Чому oracle перевіряє українську проєкцію, а не цей код?
  4) Коли звільняється managed рядок M? }
procedure NegativeD3Empty;
begin
  Save('11.sens',Pack(['10','01001','000','01']));
  Save('11.expected.sens',Pack(['0']));
  M.Add('11'+#9+'()'+#9+'3');
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  M:=TStringList.Create;
  try
    Count:=0;
    Positive('01','0',12);
    Positive('02','1',12);
    Positive('03','-1',12);
    Positive('04','2047',12);
    Positive('05','-2048',12);
    Positive('06','2048',24);
    Positive('07','-8388608',24);
    Positive('08','8388607',24);
    NegativeD1('09','0','(нуль? 1)');
    NegativeD1('10','1','(нуль? 0)');
    NegativeD3Empty;
    PositiveBeyond('12','8388608',48);
    PositiveBeyond('13','-8388609',48);
    PositiveBeyond('14','140737488355328',96);
    PositiveBeyond('15','-140737488355329',96);
    PositiveBeyond('16','39614081257132168796771975168',192);
    PositiveBeyond('17','-39614081257132168796771975169',192);
    Zero12:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
    Zero24:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24).ExactBits;
    Zero48:=ReadNumericPhysical(EncodeNumericDecimal('0',48),48).ExactBits;
    Zero96:=ReadNumericPhysical(EncodeNumericDecimal('0',96),96).ExactBits;
    Zero192:=ReadNumericPhysical(EncodeNumericDecimal('0',192),192).ExactBits;
    Save('wrong-head.sens',Pack(['10','01000',Zero12,'01']));
    Save('wrong-domain.sens',Pack(['10','010010',Zero12,'01']));
    Save('d1-extra.sens',Pack(['10','01001','1','0','01']));
    Save('d1-nested.sens',Pack(['10','01001','10','1','01','01']));
    Save('d3-extra.sens',Pack(['10','01001','000','1','01']));
    Save('d3-nested.sens',Pack(['10','01001','10','000','01','01']));
    Save('d7.sens',Pack(['10','01001','0010110','01']));
    Save('d48-extra.sens',Pack(['10','01001',Zero48,'1','01']));
    Save('d96-extra.sens',Pack(['10','01001',Zero96,'1','01']));
    Save('d192-extra.sens',Pack(['10','01001',Zero192,'1','01']));
    Save('missing.sens',Pack(['10','01001','01']));
    Save('extra.sens',Pack(['10','01001',Zero12,Zero24,'01']));
    Save('nested.sens',Pack(['10','01001','10',Zero12,'01','01']));
    Save('two-roots.sens',Pack(['10','01001',Zero12,'01','0']));
    Save('dotted.sens',Pack(['10','01001','11',Zero12,'01']));
    Save('unclosed.sens',Pack(['10','01001',Zero12]));
    Save('root-atom.sens',Pack([Zero12]));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','01001',Zero12,'01']));
    M.SaveToFile(Dir+'/cases.tsv');
    if Count<>17 then Halt(1);
    WriteLn(RawByteString(UTF8Encode(UnicodeString(
      'G6.185-ЧИСЛО-СВІДКИ-ГОТОВО physical=17'))));
  finally M.Free end;
end.
