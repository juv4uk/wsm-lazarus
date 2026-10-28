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
        (Stats.StructuralNodes=2) and (Stats.MaxDepth=2),
        'коректні вкладені крапкові пари');
  IR.Nodes[2].ParentIndex := 9;
  ExpectBad('похідна пара має неіснуючого батька');

  Physical := EncodeT5M(WordsOf(['0','1']));
  Check(Length(Physical)=1, 'обидва точні слова у спільному байті');
  Rebuild;
  VerifyExactIRStructure(IR, Stats);
  Check((Stats.Roots=2) and (Stats.Nodes=2) and
        (Stats.BoundLeaves=2) and (IR.Nodes[0].Physical.ByteStart=0) and
        (IR.Nodes[1].Physical.ByteStart=0) and
        (IR.Nodes[0].Physical.TritStart<>IR.Nodes[1].Physical.TritStart),
        'два корені з окремими тритами одного байта');

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
        (IR.Nodes[1].ParentIndex=0) and
        (IR.Nodes[2].ParentIndex=1) and
        (IR.Nodes[3].ParentIndex=1) and
        (IR.Nodes[4].ParentIndex=0),
        'фізичний вкладений список із незалежним сусідом');
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

  WriteLn('ТОЧНЕ-IR-СТОРОЖ-ГАРАЗД негативні=',Count,
    ' структура=перевірена домени=точні часткова-статистика=відсутня');
  WriteLn('ТОЧНЕ-IR-СТОРОЖ-МЕЖІ: EIR1=не-читається кодогенерація=відсутня');
end.
