{ G1.8 — реальні позитивні та негативні докази механічного
  оборотного піднабору звичайної української .lisp проєкції.
  Жодного тесту семантики SENS поза pinned таблицями. }
program test_ukroundtrip;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.bind, wsm.domain,
  wsm.ukroundtrip;

var Tables:TDomainSet; Longs:TLongProjection;
    Checks,Rejected,D,P:SizeInt; Current,DomainBytes:RawByteString;
    DomainStream:TFileStream;
    CorruptRoot,DomainSource,DomainTarget:String;
    Many,Token,LargePhysical:RawByteString;
    ManyWords:TExactWords;
    I:SizeInt;
    Refused:Boolean;

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
  Projection:=PhysicalToUkrainian(Physical,Tables,Longs);
  Check(Projection=Expected,Why);
  RoundTrip:=UkrainianToPhysical(Projection,Tables,Longs);
  Check(RoundTrip=Physical,'Побайтовий фізичний round-trip');
  Check(PhysicalToUkrainian(RoundTrip,Tables,Longs)=Projection,
    'Детермінований повторний український текст');
end;

procedure RejectPhysical(const W:array of RawByteString;
  const Why:UnicodeString);
var Projection:RawByteString; RejectedHere:Boolean;
begin
  Projection:='';
  RejectedHere:=False;
  try Projection:=PhysicalToUkrainian(EncodeT5M(WordsOf(W)),Tables,Longs);
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
  try Physical:=UkrainianToPhysical(S,Tables,Longs);
  except on E:EUkRoundtripError do RejectedHere:=True; end;
  Check(RejectedHere,Why);
  Check(Physical='','Не опубліковано частковий фізичний результат');
  Inc(Rejected);
end;

begin
  Checks:=0;Rejected:=0;
  ForceDirectories('build/m0.2/ukroundtrip');
  LoadPinnedDomains('external/sens',Tables);
  LoadPinnedLongProjection('external/sens',Tables,Longs);
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
    'Повна українська укр проєкція D4 без викличності');
  Positive(['0101'],UkrBytes('порожній?')+#10,
    'D4 укр відрізняється від скороченого ук');
  RejectText(UkrBytes('порожнє?'),
    'Скорочене ук не підміняє повне укр');

  { G2.19: фізичне випробування верхньої межі геометричного буфера.
    Тільки справжня pinned українська проєкція D1:1 -> "так", жоден
    окремий тестовий закон SENS. Видиме Count=32768, не резерв. }
  Token:=UkrBytes('так ');
  SetLength(Many,Length(Token)*32768);
  for I:=0 to 32767 do
    Move(Token[1],Many[I*Length(Token)+1],Length(Token));
  LargePhysical:=UkrainianToPhysical(Many,Tables,Longs);
  DecodeT5M(LargePhysical,ManyWords);
  Check(Length(ManyWords)=32768,
    '32768 українських атомів дають рівно 32768 exact слів');
  Check((ManyWords[0]='1') and (ManyWords[32767]='1'),
    'Перше та останнє слово лишаються фізичним D1:1');
  Check(PhysicalToUkrainian(LargePhysical,Tables,Longs)=
    StringReplace(Many,' ',#10,[rfReplaceAll]),
    'Довга pinned проєкція відновлюється побайтово');
  WriteLn(UkrBytes('УК-ГЕОМЕТРИЧНИЙ-БУФЕР-ГАРАЗД слів=32768 T5M=точний'));
  Many:=Many+UkrBytes('так');
  RejectText(Many,
    '32769-те точне слово відхилено до EncodeT5M без partial result');
  RejectText(StringOfChar(' ',1024*1024)+UkrBytes('так'),
    'Перевищено 1 МіБ входу української проєкції');
  Many:='';LargePhysical:='';ManyWords:=nil;

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
      UkrBytes(' так)')+#10,Tables,Longs)=Current,
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
  Longs[3][1]:=UkrBytes('ні');
  RejectPhysical(['0'],'Однакові surface між доменами');
  RejectText(UkrBytes('ні'),'Неоднозначна поверхня');
  Longs[3][1]:=UkrBytes('як-є');
  Longs[3][7]:='';
  RejectPhysical(['111'],'Відсутня українська проєкція');
  Longs[3][7]:=UkrBytes('сполучити');
  { Реальний зіпсований T5M byte має бути відхилений фізичним reader. }
  try
    Current:=PhysicalToUkrainian(#$F3,Tables,Longs);
    Check(False,'Заборонений байт T5M прийнято');
  except
    on E:EUkRoundtripError do Check(True,'Заборонений байт відхилено');
  end;

  { G2.16: підміна ЛИШЕ локальної копії останньої D9 таблиці.
    Чинний pinned SENS незмінний. Навіть на пізній відмові жодна
    успішно прочитана D1–D8 проєкція не стає доступною викликачеві. }
  CorruptRoot:='build/m0.2/ukroundtrip/tampered';
  Check(ForceDirectories(CorruptRoot+'/lib/domains'),
    'Створено приватну теку для негативного pinned-свідка');
  for D:=1 to 9 do begin
    DomainSource:='external/sens/lib/domains/d'+IntToStr(D)+'.lisp';
    DomainTarget:=CorruptRoot+'/lib/domains/d'+IntToStr(D)+'.lisp';
    DomainStream:=TFileStream.Create(DomainSource,fmOpenRead or fmShareDenyWrite);
    try
      SetLength(DomainBytes,SizeInt(DomainStream.Size));
      Check(Length(DomainBytes)>0,'Непорожня pinned доменна таблиця');
      DomainStream.ReadBuffer(DomainBytes[1],Length(DomainBytes));
    finally DomainStream.Free; end;
    if D=9 then begin
      P:=Pos(#$28#$D1#$83#$D0#$BA#$D1#$80#$20,DomainBytes);
      Check(P>0,'Справжнє поле укр у pinned таблиці D9');
      DomainBytes[P]:='x'; { руйнує обов'язкове поле без зміни доменних бітів }
    end;
    Save(DomainTarget,DomainBytes);
  end;
  Refused:=False;
  try
    LoadPinnedLongProjection(RawByteString(CorruptRoot),Tables,Longs);
  except
    on E:EUkRoundtripError do Refused:=True;
  end;
  Check(Refused,'Пізня пошкоджена D9 укр таблиця відхилена');
  for D:=1 to 9 do
    Check(Length(Longs[D])=0,
      'Не оприлюднено часткові координати D1–D9 після відмови');
  LoadPinnedLongProjection('external/sens',Tables,Longs);
  Check(UkrainianToPhysical(UkrBytes('так'),Tables,Longs)=
    EncodeT5M(WordsOf(['1'])),'Повторне завантаження здорового pin після відмови');
  WriteLn(UkrBytes('УК-ПРОЄКЦІЯ-АТОМАРНА D1–D9=так відмова-D9=повністю-порожньо'));
  Check(UkrainianToPhysical(UkrBytes('так'),Tables,Longs)=
    EncodeT5M(WordsOf(['1'])),'Відновлення після негативних перевірок');
  WriteLn(UkrBytes('УК-РАУНДТРИП-ГАРАЗД мова=українська-укр .lisp=звичайна'),
    UkrBytes(' .sens=побайтово-незмінний негативних='),Rejected,
    UkrBytes(' перевірок='),Checks);
end.
