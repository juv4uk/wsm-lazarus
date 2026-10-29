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
    Many,Token,LargePhysical,OriginalD7,MutantD7:RawByteString;
    ManyWords:TExactWords;
    I:SizeInt;
    Refused:Boolean;
    OldName:RawByteString;
    CorruptTables:TDomainSet;

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
  { G1.32: справжні pinned D7 quoted текстові координати тепер
    ЧИТАЮТЬСЯ ПОВНІСТЮ, разом із ')' та екранованою лапкою.
    Вони залишаються даними: жодного D7 dispatch як SENS функції. }
  Check(Longs[7][41]='")"','D7:0101001 укр цитована ) не обрізана');
  Check(Longs[7][40]='"("','D7:0101000 укр цитована ( не обрізана');
  Check(Longs[7][34]='"\""','D7:0100010 укр цитована лапка не обрізана');
  Check(Longs[7][32]='" "','D7:0100000 укр quoted пробіл');
  Check(Longs[7][22]='','D7:0010110 SYN не має текстового значення');
  RejectText('")"','D7 текст не є викличним українським атомом');
  RejectPhysical(['0101001'],
    'D7 цитовані символи не виконуються як непрозорий Lisp-атом');
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

  { G2.20 — перевірки exact-name індексу незалежно від буфера G2.19. }
  { Локальна пізня неоднозначність D9 має відхиляти НАВІТЬ D1:1:
    стара лінійна перевірка шукала дубль лише запитаного слова. }
  OldName:=Longs[9][High(Longs[9])];
  Longs[9][High(Longs[9])]:=UkrBytes('ні');
  RejectPhysical(['1'],
    'Незалежна пізня дубльована назва D9 відхилена до проєкції D1:1');
  RejectText(UkrBytes('так'),
    'Укромована таблиця з дублем у D9 відхилена до пакування D1:1');
  Longs[9][High(Longs[9])]:=OldName;
  Check(UkrainianToPhysical(UkrBytes('так'),Tables,Longs)=
    EncodeT5M(WordsOf(['1'])),'Укр індекс відновлюється після дубля D9');

  { Повний pinned набір має exact ширину/порядок для всіх D1–D9.
    Тест псує лише глибоку копію таблиці — оригінал не змінюється. }
  CorruptTables:=Tables;
  CorruptTables[9]:=Copy(Tables[9],0,Length(Tables[9]));
  CorruptTables[9][High(CorruptTables[9])].Key.Bits:=0;
  Refused:=False;
  try
    Current:=UkrainianToPhysical(UkrBytes('так'),CorruptTables,Longs);
  except on E:EUkRoundtripError do Refused:=True; end;
  Check(Refused,'Пошкоджена пізня exact D9 координата відхилена');
  Check(UkrainianToPhysical(UkrBytes('так'),Tables,Longs)=
    EncodeT5M(WordsOf(['1'])),'Початковий pinned D9 не пошкоджено');


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
  { G1.32: після негативу D9 повертаємо незмінний d9.lisp,
    після чого перевіряємо ТРИ незалежні пошкодження справжнього
    pinned D7. Вони повинні відхиляти навіть повну здорову D1–D6
    таблицю, не оприлюднюючи часткових Longs. }
  DomainSource:='external/sens/lib/domains/d9.lisp';
  DomainTarget:=CorruptRoot+'/lib/domains/d9.lisp';
  DomainStream:=TFileStream.Create(DomainSource,fmOpenRead or fmShareDenyWrite);
  try
    SetLength(DomainBytes,SizeInt(DomainStream.Size));
    DomainStream.ReadBuffer(DomainBytes[1],Length(DomainBytes));
  finally DomainStream.Free end;
  Save(DomainTarget,DomainBytes);

  DomainSource:='external/sens/lib/domains/d7.lisp';
  DomainTarget:=CorruptRoot+'/lib/domains/d7.lisp';
  DomainStream:=TFileStream.Create(DomainSource,fmOpenRead or fmShareDenyWrite);
  try
    SetLength(OriginalD7,SizeInt(DomainStream.Size));
    DomainStream.ReadBuffer(OriginalD7[1],Length(OriginalD7));
  finally DomainStream.Free end;
  for P:=1 to 3 do begin
    case P of
      1: MutantD7:=StringReplace(OriginalD7,
        '(укр ")")','(укр "\q")',[]);
      2: MutantD7:=OriginalD7+#10+'(зайва-форма)';
      3: MutantD7:=StringReplace(OriginalD7,
        '(0101001 ','(0101000 ',[]);
    end;
    Check(MutantD7<>OriginalD7,
      'Мутант D7 має реально змінювати pinned байти');
    Save(DomainTarget,MutantD7);
    Refused:=False;
    try LoadPinnedLongProjection(RawByteString(CorruptRoot),Tables,Longs);
    except on E:EUkRoundtripError do Refused:=True end;
    Check(Refused,'Структурну D7 мутацію відхилено у спільному читачі');
    for D:=1 to 9 do
      Check(Length(Longs[D])=0,
        'Після пізньої D7 відмови відсутня часткова укр таблиця');
    Inc(Rejected);
  end;
  Save(DomainTarget,OriginalD7);
  LoadPinnedLongProjection(RawByteString(CorruptRoot),Tables,Longs);
  Check((Longs[7][41]='")"') and (Longs[7][34]='"\""'),
    'Після трьох D7 відмов повернено точні pinned quotation');

  LoadPinnedLongProjection('external/sens',Tables,Longs);
  Check(UkrainianToPhysical(UkrBytes('так'),Tables,Longs)=
    EncodeT5M(WordsOf(['1'])),'Повторне завантаження здорового pin після відмови');
  WriteLn(UkrBytes('УКР-Д7-ЦИТОВАНІ-ДАНІ-ГАРАЗД'),
    UkrBytes(' координат=128 укр=повна 0101001=) 0100010=лапка'),
    UkrBytes(' чужі-форми/escape/дубль=відхилено out=порожньо'));
  WriteLn(UkrBytes('УК-ПРОЄКЦІЯ-АТОМАРНА D1–D9=так відмова-D9=повністю-порожньо'));
  Check(UkrainianToPhysical(UkrBytes('так'),Tables,Longs)=
    EncodeT5M(WordsOf(['1'])),'Відновлення після негативних перевірок');
  WriteLn(UkrBytes('УК-РАУНДТРИП-ГАРАЗД мова=українська-укр .lisp=звичайна'),
    UkrBytes(' .sens=побайтово-незмінний негативних='),Rejected,
    UkrBytes(' перевірок='),Checks);
end.
