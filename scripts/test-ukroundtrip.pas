{ G1.8 — реальні позитивні та негативні докази механічного
  оборотного піднабору звичайної української .lisp проєкції.
  Жодного тесту семантики SENS поза pinned таблицями. }
program test_ukroundtrip;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.bind, wsm.domain,
  wsm.ukroundtrip;

var Tables:TDomainSet; Checks,Rejected:SizeInt; Current:RawByteString;

function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

procedure Check(Condition:Boolean; const Why:UnicodeString);
begin
  Inc(Checks);
  if not Condition then begin
    WriteLn(StdErr,UkrBytes('УК-РАУНДТРИП-ТЕСТ-ПОМИЛКА: '),UkrBytes(Why));
    Halt(1);
  end;
end;

function WordsOf(const A:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;

procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free; end;
end;

procedure Positive(const W:array of RawByteString;
  const Expected:RawByteString; const Why:UnicodeString);
var Physical,Projection,RoundTrip:RawByteString;
begin
  Physical:=EncodeT5M(WordsOf(W));
  Projection:=PhysicalToUkrainian(Physical,Tables);
  Check(Projection=Expected,Why);
  RoundTrip:=UkrainianToPhysical(Projection,Tables);
  Check(RoundTrip=Physical,'Побайтовий фізичний round-trip');
  Check(PhysicalToUkrainian(RoundTrip,Tables)=Projection,
    'Детермінований повторний український текст');
end;

procedure RejectPhysical(const W:array of RawByteString;
  const Why:UnicodeString);
var Projection:RawByteString; RejectedHere:Boolean;
begin
  Projection:='';
  RejectedHere:=False;
  try Projection:=PhysicalToUkrainian(EncodeT5M(WordsOf(W)),Tables);
  except on E:EUkRoundtripError do RejectedHere:=True; end;
  Check(RejectedHere,Why);
  Check(Projection='','Не опубліковано часткову текстову проєкцію');
  Inc(Rejected);
end;

procedure RejectText(const S:RawByteString; const Why:UnicodeString);
var Physical:RawByteString; RejectedHere:Boolean;
begin
  Physical:='';
  RejectedHere:=False;
  try Physical:=UkrainianToPhysical(S,Tables);
  except on E:EUkRoundtripError do RejectedHere:=True; end;
  Check(RejectedHere,Why);
  Check(Physical='','Не опубліковано частковий фізичний результат');
  Inc(Rejected);
end;

begin
  Checks:=0;Rejected:=0;
  ForceDirectories('build/m0.2/ukroundtrip');
  LoadPinnedDomains('external/sens',Tables);
  { У текстовій проєкції НЕМАЄ двійкових слів у функційній позиції. }
  Positive(['0'],UkrBytes('ні')+#10,'D1:0 — звичайне ні');
  Positive(['1'],UkrBytes('так')+#10,'D1:1 — звичайне так');
  Positive(['0','1'],UkrBytes('ні')+#10+UkrBytes('так')+#10,
    'Дві форми без додаткових D2 пропусків');
  Positive(['10','111','0','1','01'],
    UkrBytes('(сполучити ні так)')+#10,'Український виклик D3:111');
  Positive(['10','010','10','111','1','0','01','01'],
    UkrBytes('(атом? (сполучити так ні))')+#10,
    'Вкладені D2 форми й українська назва-предикат');
  Positive(['10','01'],'()'+#10,'Порожній D2 список, не D3:000');
  Positive(['10','10','01','1','01'],'(() '+UkrBytes('так')+')'+#10,
    'Вкладений порожній D2 список');
  Positive(['0000'],UkrBytes('застосувати')+#10,
    'Українська проєкція D4 без заяви про викличність');

  Current:=EncodeT5M(WordsOf(['10','111','0','1','01']));
  Save('build/m0.2/ukroundtrip/valid.sens',Current);
  Save('build/m0.2/ukroundtrip/valid.expected.lisp',
    UkrBytes('(сполучити ні так)')+#10);
  Save('build/m0.2/ukroundtrip/valid.input.lisp',
    UkrBytes('; людський коментар')+#10+
    UkrBytes('  (сполучити   ні')+#13+#10+
    UkrBytes('   так)')+#10);
  Save('build/m0.2/ukroundtrip/ambiguous.sens',
    EncodeT5M(WordsOf(['000'])));
  Save('build/m0.2/ukroundtrip/separator.sens',
    EncodeT5M(WordsOf(['0','00','1'])));
  Save('build/m0.2/ukroundtrip/dotted.sens',
    EncodeT5M(WordsOf(['10','0','11','1','01'])));
  Save('build/m0.2/ukroundtrip/invalid.sens',#$F3);
  Save('build/m0.2/ukroundtrip/invalid.lisp',
    UkrBytes('(сполучити ні )')+#0);
  Check(UkrainianToPhysical(
      UkrBytes('  ; коментар')+#10+
      UkrBytes(' (сполучити ні')+#10+
      UkrBytes(' так)')+#10,Tables)=Current,
    'Пробіли й українські коментарі не стають двійковими словами');

  RejectPhysical(['000'],'D3:000 неоднозначне з порожнім D2');
  RejectPhysical(['0','000'],'Пізній D3:000 не видає частковий текст');
  RejectPhysical(['0','00','1'],'Явний D2:00 не губиться');
  RejectPhysical(['10','0','11','1','01'],'D2 крапкова пара');
  RejectPhysical(['0','10','0','11','1','01'],
    'Пізня крапкова пара — атомарна відмова');
  RejectPhysical(['1111111111'],'Непідтверджений D10');
  RejectText('','Порожній текст');
  RejectText(UkrBytes('; лише коментар')+#10,'Жодної текстової форми');
  RejectText('0','ASCII біт не є українським атомом');
  RejectText('CONS','Англійський dispatch заборонено');
  RejectText(UkrBytes('неіснуюча-назва'),'Неіснуюча українська координата');
  RejectText(UkrBytes('крапка'),'D2 структурний символ не є атомом');
  RejectText(UkrBytes('"ні"'),'Рядок не є атомом SENS');
  RejectText(UkrBytes('(сполучити ні'),'Незакрита текстова форма');
  RejectText(#$C0#$AF,'Невалідний UTF-8');
  RejectText(UkrBytes('ні')+#0,'NUL у тексті');
  { Підміна pinned координат у ТІЛЬКИ локальній копії таблиць.
    Жоден текст не може видати чужий фізичний домен. }
  Tables[3][1].Ukrainian:=UkrBytes('ні');
  RejectPhysical(['0'],'Однакові surface між доменами');
  RejectText(UkrBytes('ні'),'Неоднозначна поверхня');
  Tables[3][1].Ukrainian:=UkrBytes('як-є');
  Tables[3][7].Ukrainian:='';
  RejectPhysical(['111'],'Відсутня українська проєкція');
  Tables[3][7].Ukrainian:=UkrBytes('сполучити');
  { Реальний зіпсований T5M byte має бути відхилений фізичним reader. }
  try
    Current:=PhysicalToUkrainian(#$F3,Tables);
    Check(False,'Заборонений байт T5M прийнято');
  except
    on E:EUkRoundtripError do Check(True,'Заборонений байт відхилено');
  end;

  Check(UkrainianToPhysical(UkrBytes('так'),Tables)=
    EncodeT5M(WordsOf(['1'])),'Відновлення після негативних перевірок');
  WriteLn(UkrBytes('УК-РАУНДТРИП-ГАРАЗД мова=українська .lisp=звичайна'),
    UkrBytes(' .sens=побайтово-незмінний негативних='),Rejected,
    UkrBytes(' перевірок='),Checks);
end.
