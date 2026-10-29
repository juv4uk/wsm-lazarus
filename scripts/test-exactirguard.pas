{ G6.7: фактичні позитивні й негативні FPC свідки цілісності ExactIR. }
program test_exactirguard;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.domain, wsm.bind, wsm.exactir,
  wsm.exactirguard;
var
  Tables: TDomainSet;
  IR: TExactIR;
  Stats: TExactIRGuardStats;
  Physical, Prefix: RawByteString;
  Count: SizeInt;
  Failed: Boolean;
  Swapped: TExactIRNode;

procedure Check(OK: Boolean; const Explanation: String);
begin
  if not OK then begin
    WriteLn(StdErr, 'ПЕРЕВІРКА-IR-ПОМИЛКА: ', Explanation);
    Halt(1);
  end;
end;

function WordsOf(const Words: array of RawByteString): TExactWords;
var I: SizeInt;
begin
  SetLength(Result, Length(Words));
  for I := 0 to High(Words) do Result[I] := Words[I];
end;

procedure Rebuild;
begin
  BuildExactIR(Physical, Tables, IR);
end;

procedure ExpectBad(const Explanation: String);
begin
  Stats.Nodes := 99;
  Stats.Roots := 99;
  Stats.BoundLeaves := 99;
  Stats.StructuralNodes := 99;
  Stats.MaxDepth := 99;
  Failed := False;
  try
    VerifyExactIRStructure(IR, Stats);
  except
    on E: EExactIRGuardError do Failed := True;
  end;
  Check(Failed, Explanation+' не відхилено');
  Check((Stats.Nodes = 0) and (Stats.Roots = 0) and
        (Stats.BoundLeaves = 0) and (Stats.StructuralNodes = 0) and
        (Stats.MaxDepth = 0),
        Explanation+' опублікувало часткову статистику');
  Inc(Count);
end;

begin
  LoadPinnedDomains('external/sens', Tables);
  Physical := EncodeT5M(WordsOf(['10','111','00','0','000','01']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Nodes = 4) and (Stats.Roots = 1) and
        (Stats.BoundLeaves = 3) and (Stats.StructuralNodes = 1) and
        (Stats.MaxDepth = 1), 'правильний список і три доменні листки');

  Count := 0;
  { G6.46: межі є 0-based [I,End) у вже зв'язаному ExactIR;
    перевірка ніколи не робить з host-індексу фізичний біт чи закон.
    Питання: чому край виключний, листок має I+1, а негативи
    не мають публікувати навіть часткову Stats? }
  Check((IR.Nodes[0].SubtreeEndExclusive=4) and
        (IR.Nodes[1].SubtreeEndExclusive=2) and
        (IR.Nodes[2].SubtreeEndExclusive=3) and
        (IR.Nodes[3].SubtreeEndExclusive=4),
        'початкові pinned межі списку й кожного атома');

  IR.Nodes[0].SubtreeEndExclusive := 0;
  ExpectBad('нульова межа кореневого IR');
  Rebuild;
  IR.Nodes[0].SubtreeEndExclusive := Length(IR.Nodes)+1;
  ExpectBad('межа IR виходить за кінець масиву');
  Rebuild;
  IR.Nodes[0].SubtreeEndExclusive := 3;
  ExpectBad('передчасне завершення кореневого D2');
  Rebuild;
  IR.Nodes[1].SubtreeEndExclusive := 3;
  ExpectBad('листок охопив чужий вузол');
  Rebuild;
  IR.Nodes[1].SubtreeEndExclusive := 1;
  ExpectBad('листок із кінцем перед власним індексом');
  Rebuild;
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Nodes=4) and (Stats.BoundLeaves=3),
        'після підроблених меж відновлено здоровий ExactIR');

  { G6.24: узгоджено підмінюємо також Physical.WordIndex,
    аби старий guard приймав слово з чужим фізичним індексом.
    Всі індивідуальні поля залишаються в допустимих межах,
    але два різні реальні IR-листки отримують ОДИН індекс. }
  IR.Nodes[2].WordIndex := IR.Nodes[1].WordIndex;
  IR.Nodes[2].Physical.WordIndex := IR.Nodes[1].WordIndex;
  ExpectBad('два фізичні листки з повторним WordIndex');
  Rebuild;
  IR.Nodes[1].Physical.TritStart := IR.Nodes[2].Physical.TritStart;
  IR.Nodes[1].Physical.TritEnd := IR.Nodes[2].Physical.TritEnd+2;
  { Ключ D3:111 має ширину 3: зміщуємо в інтервалі наявних
    тритів, формула байтів лишається валідною. }
  IR.Nodes[1].Physical.TritEnd := IR.Nodes[1].Physical.TritStart+3;
  IR.Nodes[1].Physical.ByteStart := IR.Nodes[1].Physical.TritStart div 5;
  IR.Nodes[1].Physical.ByteEnd := (IR.Nodes[1].Physical.TritEnd-1) div 5+1;
  { Перше слово тепер фізично ПІЗНІШЕ другого. }
  ExpectBad('слова IR із оберненим фізичним порядком тритів');
  Rebuild;
  IR.Nodes[1].ParentIndex := 2;
  ExpectBad('посилання на ще не створеного батька');
  Rebuild;
  IR.Nodes[1].RootIndex := 3;
  ExpectBad('підміна кореневої форми');
  Rebuild;
  IR.Nodes[1].Depth := 2;
  ExpectBad('підміна глибини');
  Rebuild;
  IR.Nodes[2].ChildIndex := 9;
  ExpectBad('підміна порядку дитини');
  Rebuild;
  IR.Roots[0] := 1;
  ExpectBad('підміна покажчика кореня');
  Rebuild;
  IR.BoundLeaves := 4;
  ExpectBad('підміна числа зв’язаних листків');
  Rebuild;
  IR.Nodes[1].HasKey := False;
  ExpectBad('втрата точного доменного ключа');
  Rebuild;
  IR.Nodes[1].Key := ExactKey('000');
  ExpectBad('підміна D3:111 на D3:000 без зміни типу');
  Rebuild;
  IR.Nodes[3].Key := ExactKey('0');
  ExpectBad('підміна D3:000 на D1:0');
  Rebuild;
  IR.Nodes[0].HasKey := True;
  ExpectBad('D2 структура отримала доменний ключ');
  Rebuild;
  IR.Nodes[0].Physical.WordIndex := 99;
  ExpectBad('підміна фізичного слова');
  Rebuild;
  { Структурний сторож не має права вірити байтовим адресам
    стороннього producer, якщо тритова адреса суперечить T5M/5.
    Обидва forged інтервали нижче досі НЕ порожні. }
  IR.Nodes[0].Physical.ByteStart := 1;
  IR.Nodes[0].Physical.ByteEnd := 2;
  ExpectBad('підроблений байт початку кореневої D2-форми');
  Rebuild;
  IR.Nodes[0].Physical.ByteEnd := 2;
  ExpectBad('підроблений байт завершення кореневої D2-форми');
  Rebuild;
  IR.Nodes[1].Physical.ByteStart := 1;
  ExpectBad('підроблений початковий байт вкладеного D3 листка');
  Rebuild;
  IR.Nodes[1].Physical.ByteEnd := IR.Nodes[1].Physical.ByteEnd+1;
  ExpectBad('підроблений кінцевий байт вкладеного D3 листка');
  Rebuild;
  IR.Nodes[0].Physical.TritEnd := IR.Nodes[0].Physical.TritEnd + 1;
  ExpectBad('підміна ширини фізичного D2');
  Rebuild;
  IR.Nodes[2].Physical.ByteEnd := IR.Nodes[2].Physical.ByteStart;
  ExpectBad('порожній фізичний інтервал байтів');
  Rebuild;
  IR.Nodes[0].Kind := ikPair;
  ExpectBad('крапкова пара з трьома нащадками');
  Rebuild;
  SetLength(IR.Roots, 0);
  ExpectBad('відсутні кореневі покажчики');

  Physical := EncodeT5M(WordsOf(['10','1','0','11','000','01']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Nodes=5) and (Stats.BoundLeaves=3) and
        (Stats.StructuralNodes=2) and (Stats.MaxDepth=2) and
        (IR.Nodes[0].SubtreeEndExclusive=5) and
        (IR.Nodes[2].SubtreeEndExclusive=5),
        'коректні вкладені крапкові пари та їхні межі');
  Check((IR.Nodes[0].Kind=ikPair) and
        (IR.Nodes[2].Kind=ikPair) and
        (IR.Nodes[2].WordIndex=IR.Nodes[0].WordIndex) and
        (IR.Nodes[2].Physical.TritStart=IR.Nodes[0].Physical.TritStart),
        'похідна пара не створює нового фізичного слова');
  IR.Nodes[2].ParentIndex := 9;
  ExpectBad('похідна пара має неіснуючого батька');

  Physical := EncodeT5M(WordsOf(['0','1']));
  Check(Length(Physical)=1, 'обидва точні слова у спільному байті');
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Roots=2) and (Stats.Nodes=2) and
        (Stats.BoundLeaves=2) and
        (IR.Nodes[0].SubtreeEndExclusive=1) and
        (IR.Nodes[1].SubtreeEndExclusive=2) and
        (IR.Nodes[0].Physical.ByteStart=0) and
        (IR.Nodes[1].Physical.ByteStart=0) and
        (IR.Nodes[0].Physical.TritStart<>IR.Nodes[1].Physical.TritStart),
        'два корені з окремими тритами одного байта');
  IR.Nodes[0].SubtreeEndExclusive := 2;
  ExpectBad('перший D1 листок захопив другий корінь T5M');
  Rebuild;
  VerifyExactIRStructure(IR,Stats);
  { Незалежна регресія: кожен індивідуальний half-open span
    все ще коректний і має ширину D1, але ДВА корені займають
    ті самі трити. Стара перевірка пропускала це. }
  IR.Nodes[1].Physical.TritStart := IR.Nodes[0].Physical.TritStart;
  IR.Nodes[1].Physical.TritEnd := IR.Nodes[0].Physical.TritEnd;
  ExpectBad('два різні фізичні слова перекрили один трит');
  Rebuild;
  { Індекси зростають, трити ДІЙСНО різні: валідна пара
    коренів має лишатися дозволеною після пізньої відмови. }
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Roots=2) and (Stats.BoundLeaves=2),
    'два окремі D1 корені в одному байті після відмови');

  Physical := EncodeT5M(WordsOf(['000000001']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((IR.Nodes[0].Key.Width=9) and
        (KeyBits(IR.Nodes[0].Key)='000000001') and
        (Stats.Nodes=1) and (Stats.BoundLeaves=1),
        'провідні нулі D9 збережені');

  { Реальний pinned exact IR: вкладений D2-список із двома D1 листками,
    після нього — ще один листок зовнішнього списку. Модифікуємо
    ЛИШЕ порядок записів, не змінюючи жодного локального
    ParentIndex/Depth/ChildIndex або доменної ідентичності.
    Старий guard помилково приймав такий зламаний DFS preorder. }
  Physical := EncodeT5M(WordsOf(['10','10','1','0','01','1','01']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Length(IR.Nodes)=5) and (Stats.Roots=1) and
        (Stats.StructuralNodes=2) and (Stats.BoundLeaves=3) and
        (IR.Nodes[0].SubtreeEndExclusive=5) and
        (IR.Nodes[1].SubtreeEndExclusive=4) and
        (IR.Nodes[4].SubtreeEndExclusive=5) and
        (IR.Nodes[1].ParentIndex=0) and
        (IR.Nodes[2].ParentIndex=1) and
        (IR.Nodes[3].ParentIndex=1) and
        (IR.Nodes[4].ParentIndex=0),
        'фізичний вкладений список із незалежним сусідом');
  { Зламаний кінець вкладеного списку при правильних
    ParentIndex/Depth/ChildIndex та незмінному фізичному T5M. }
  IR.Nodes[1].SubtreeEndExclusive := 5;
  ExpectBad('вкладений список перейшов у сусідній вузол');
  Rebuild;
  IR.Nodes[1].SubtreeEndExclusive := 3;
  ExpectBad('вкладений список закрився до останньої дитини');
  Rebuild;
  IR.Nodes[0].SubtreeEndExclusive := 4;
  ExpectBad('верхній список закрився до останнього листка');
  Rebuild;
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Nodes=5) and (Stats.MaxDepth=2),
        'межі вкладеного списку відновлено після негативів');
  Swapped := IR.Nodes[3];
  IR.Nodes[3] := IR.Nodes[4];
  IR.Nodes[4] := Swapped;
  Check((IR.Nodes[3].ParentIndex=0) and
        (IR.Nodes[3].ChildIndex=1) and
        (IR.Nodes[4].ParentIndex=1) and
        (IR.Nodes[4].ChildIndex=1) and
        (IR.Nodes[4].Depth=2),
        'перестановка зберегла локальні поля, але порушила preorder');
  ExpectBad('повернення в уже закритий вкладений D2 список');
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Nodes=5) and (Stats.BoundLeaves=3),
        'чинне правильне вкладене дерево лишилося допущеним');

  { Перша ikPair кожного фізичного списку має власний D2 OPEN.
    Лише наступні праві похідні пари можуть повторювати цю опору. }
  Physical := EncodeT5M(WordsOf(['10','1','11','0','01']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Nodes=3) and (IR.Nodes[0].Kind=ikPair),
    'початкова фізична крапкова пара');
  IR.Nodes[0].WordIndex := 99;
  IR.Nodes[0].Physical.WordIndex := 99;
  IR.Nodes[0].Physical.TritStart := 100;
  IR.Nodes[0].Physical.TritEnd := 102;
  IR.Nodes[0].Physical.ByteStart := 20;
  IR.Nodes[0].Physical.ByteEnd := 21;
  ExpectBad('опора кореневої пари фізично пізніша за її листки');

  Physical := EncodeT5M(WordsOf([
    '10','1','11','0','01', '00', '10','0','11','1','01']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Roots=2) and (Stats.Nodes=6) and (IR.Roots[1]=3),
    'дві незалежні крапкові форми з фізичним пропуском');
  IR.Nodes[3].WordIndex := IR.Nodes[0].WordIndex;
  IR.Nodes[3].Physical := IR.Nodes[0].Physical;
  ExpectBad('два фізичні корені повторили одну опору D2 OPEN');

  Physical := EncodeT5M(WordsOf([
    '10','10','1','11','0','01','11',
    '10','0','1','11','000','01','01']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Nodes=9) and (Stats.StructuralNodes=4) and
    (Stats.BoundLeaves=5) and (IR.Nodes[1].Kind=ikPair) and
    (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[4].Kind=ikPair) and
    (IR.Nodes[4].ChildIndex=1) and (IR.Nodes[6].Kind=ikPair) and
    (IR.Nodes[6].ParentIndex=4) and
    (IR.Nodes[4].WordIndex<>IR.Nodes[0].WordIndex) and
    (IR.Nodes[6].WordIndex=IR.Nodes[4].WordIndex),
    'ліві й праві фізичні пари та права похідна опора');
  IR.Nodes[1].WordIndex := IR.Nodes[0].WordIndex;
  IR.Nodes[1].Physical := IR.Nodes[0].Physical;
  ExpectBad('ліва фізична пара видала себе за праву похідну');
  Rebuild;
  IR.Nodes[6].Physical.TritStart := IR.Nodes[6].Physical.TritStart+1;
  IR.Nodes[6].Physical.TritEnd := IR.Nodes[6].Physical.TritEnd+1;
  IR.Nodes[6].Physical.ByteStart := IR.Nodes[6].Physical.TritStart div 5;
  IR.Nodes[6].Physical.ByteEnd := (IR.Nodes[6].Physical.TritEnd-1) div 5+1;
  ExpectBad('похідна опора з тим самим словом і чужими тритами');
  Rebuild;
  IR.Nodes[6].WordIndex := IR.Nodes[5].WordIndex;
  IR.Nodes[6].Physical.WordIndex := IR.Nodes[5].WordIndex;
  ExpectBad('похідна пара підмінила індекс опори адресою листка');
  Rebuild;
  IR.Nodes[4].Physical.TritStart := IR.Nodes[3].Physical.TritStart;
  IR.Nodes[4].Physical.TritEnd := IR.Nodes[4].Physical.TritStart+2;
  IR.Nodes[4].Physical.ByteStart := IR.Nodes[4].Physical.TritStart div 5;
  IR.Nodes[4].Physical.ByteEnd := (IR.Nodes[4].Physical.TritEnd-1) div 5+1;
  ExpectBad('нова права фізична опора перекрила попередній листок');
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Nodes=9) and (Stats.BoundLeaves=5),
    'коректні вкладені й похідні пари після пізніх відмов');

  Physical := EncodeT5M(WordsOf(['10','10','1','11','0','01','01']));
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((IR.Nodes[0].Kind=ikList) and (IR.Nodes[1].Kind=ikPair),
    'фізична пара всередині звичайного списку');
  IR.Nodes[1].WordIndex := IR.Nodes[0].WordIndex;
  IR.Nodes[1].Physical := IR.Nodes[0].Physical;
  ExpectBad('пара повторила опору звичайного списку');
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  { Окремі D2 корені, перший — список. Точна межа не може
    перекривати наступну форму навіть за повністю справних бітів. }
  Physical := EncodeT5M(WordsOf(['10','1','01','0']));
  Rebuild;
  VerifyExactIRStructure(IR,Stats);
  Check((Length(IR.Nodes)=3) and (Stats.Roots=2) and
        (IR.Roots[0]=0) and (IR.Roots[1]=2) and
        (IR.Nodes[0].SubtreeEndExclusive=2) and
        (IR.Nodes[2].SubtreeEndExclusive=3),
        'два незалежні корені та межа D2 списку');
  IR.Nodes[0].SubtreeEndExclusive := 3;
  ExpectBad('структурний корінь перетнув наступну форму');
  Rebuild;
  VerifyExactIRStructure(IR,Stats);
  Check((Stats.Roots=2) and (Stats.Nodes=3),
        'завершальний позитив після підміни межі кореня');
  WriteLn('ТОЧНЕ-IR-МЕЖІ-ПІДДЕРЕВ-ГАРАЗД',
    ' 0-based=точно вкладені=так пара=так',
    ' спільний-байт=без-колізії відмови=атомарні');
  WriteLn('ТОЧНЕ-IR-ОПОРИ-ГАРАЗД негативні=7 вкладені=так похідні=так відновлення=так');

  WriteLn('ТОЧНЕ-IR-СТОРОЖ-ГАРАЗД негативні=',Count,
    ' структура=перевірена байтові-адреси=перевірені домени=точні часткова-статистика=відсутня');
  WriteLn('ТОЧНЕ-IR-СТОРОЖ-МЕЖІ: EIR1=не-читається кодогенерація=відсутня');
end.
