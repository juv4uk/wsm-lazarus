program test_binarytree;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarybind, wsm.binarytree,
  wsm.binaryheads;
var Tables: TDomainSet; W: TExactWords; Tree: TBinaryTreeEntries;
    Heads: TBinaryHeads;
    I, N, Count: SizeInt; Failed: Boolean; Data: RawByteString;
    Saved: TBinaryTreeEntry;
procedure Check(Ok: Boolean; const Why: String);
begin
  if not Ok then begin WriteLn(StdErr,'ДЕРЕВО-ДВІЙКОВОЇ-МОВИ-ПОМИЛКА: ',Why);
    Halt(1); end;
end;
function WordsOf(const A: array of RawByteString): TExactWords;
var J:SizeInt;
begin
  SetLength(Result, Length(A));
  for J:=0 to High(A) do Result[J]:=A[J];
end;
begin
  LoadPinnedDomains('external/sens',Tables);
  W:=WordsOf(['10','111','00','1','000','01','00','0']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  Check(Length(Tree)=5,'список і корінь мають п''ять вузлів');
  Check((Tree[0].Kind=dkList) and (Tree[0].ParentIndex=-1) and
    (Tree[0].RootIndex=0) and (Tree[0].Depth=0) and
    (Tree[0].AnchorWordIndex=1) and Tree[0].HasPhysicalWord and
    (Tree[0].Physical.TritStart=0) and
    (Tree[0].Physical.TritEnd=2) and (Tree[0].Key.Width=0),
    'кореневий список є D2 структурою, не функцією');
  Check((Tree[1].Kind=dkIdentity) and (Tree[1].ParentIndex=0) and
    (Tree[1].ChildIndex=0) and (Tree[1].Depth=1) and
    SameKey(Tree[1].Key, ExactKey('111')) and
    (Tree[1].Physical.TritStart=3) and
    (Tree[1].Physical.TritEnd=6),'перше доменне слово');
  Check((Tree[2].Kind=dkIdentity) and (Tree[2].ParentIndex=0) and
    (Tree[2].ChildIndex=1) and (Tree[2].Physical.TritStart=10) and
    SameKey(Tree[2].Key,ExactKey('1')),'друге слово');
  Check((Tree[3].Kind=dkEmpty) and (Tree[3].ParentIndex=0) and
    (Tree[3].ChildIndex=2) and (Tree[3].Physical.TritStart=12) and
    SameKey(Tree[3].Key,ExactKey('000')) and
    not SameKey(Tree[3].Key,ExactKey('0')),'D3 порожня структура');
  Check((Tree[4].RootIndex=1) and (Tree[4].ParentIndex=-1) and
    (Tree[4].Depth=0) and (Tree[4].AnchorWordIndex=8) and
    SameKey(Tree[4].Key,ExactKey('0')),'інша верхня форма');
  Check(Pos('домен 3',String(BinaryTreeCaption(Tree[1])))>0,
    'український підпис окремий від двійкової тотожності');

  W:=WordsOf(['0','1']);
  Data:=EncodeT5M(W);
  Check(Length(Data)=1,'два слова містяться в одному байті');
  ReadBinaryTree(Data,Tables,Tree);
  Check((Length(Tree)=2) and
    (Tree[0].Physical.ByteStart=Tree[1].Physical.ByteStart) and
    (Tree[0].Physical.TritStart=0) and
    (Tree[1].Physical.TritStart=2),'один байт, різні трити та корені');

  W:=WordsOf(['10','1','00','0','11','10','1','01','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  Check(Length(Tree)=6,'два похідні вузли пар із фізичним хвостом');
  Check((Tree[0].Kind=dkPair) and not Tree[0].HasPhysicalWord and
    (Tree[0].AnchorWordIndex=1) and (Tree[0].Key.Width=0),
    'пара не має вигаданого слова');
  Check((Tree[1].ParentIndex=0) and (Tree[1].ChildIndex=0) and
    SameKey(Tree[1].Key,ExactKey('1')),'перший елемент пари');
  Check((Tree[2].Kind=dkPair) and not Tree[2].HasPhysicalWord and
    (Tree[2].ParentIndex=0) and (Tree[2].ChildIndex=1) and
    (Tree[2].Depth=1),'похідна вкладена пара');
  Check((Tree[4].Kind=dkList) and Tree[4].HasPhysicalWord and
    (Tree[4].AnchorWordIndex=6),'справжня рамка хвоста');
  Check(Pos('похідна',String(BinaryTreeCaption(Tree[0])))>0,
    'підпис не маскує похідну пару під токен');

  W:=WordsOf(['10','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  Check((Length(Tree)=1) and (Tree[0].Kind=dkList) and
    (Tree[0].Key.Width=0),'порожній список D2 без хибного D3');
  W:=WordsOf(['000']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  Check((Length(Tree)=1) and (Tree[0].Kind=dkEmpty) and
    SameKey(Tree[0].Key,ExactKey('000')),'самостійне D3:000');


  { Фізичні голови є першими безпосередніми дітьми D2-списків.
    Це механічний індекс, а не дозвіл на виклик. }
  W:=WordsOf(['10','111','00','1','000','01','00','0']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check((Length(Heads)=1) and (Heads[0].ListIndex=0) and
    (Heads[0].HeadIndex=1) and (Heads[0].RootIndex=0) and
    (Heads[0].Kind=hkExactHead) and
    SameKey(Heads[0].Key,ExactKey('111')) and
    (Heads[0].WordIndex=2) and
    (Heads[0].Physical.TritStart=3) and
    (Heads[0].Physical.TritEnd=6),
    'точна фізична голова першої D2-форми');

  { Вкладений список на першій позиції НЕ є звичайним
    доменним викликом. D3:000 у хвості — структурні дані. }
  W:=WordsOf(['10','10','1','01','000','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check((Length(Heads)=2) and
    (Heads[0].Kind=hkStructuralHead) and
    (Heads[0].HeadIndex=1) and (Heads[0].Key.Width=0) and
    (Heads[0].WordIndex=0) and
    (Heads[1].Kind=hkExactHead) and
    SameKey(Heads[1].Key,ExactKey('1')) and
    (Heads[1].ListIndex=1) and (Heads[1].HeadIndex=2),
    'відокремлено структурну та точну голову');

  W:=WordsOf(['10','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check((Length(Heads)=1) and (Heads[0].Kind=hkNoHead) and
    (Heads[0].HeadIndex=-1) and (Heads[0].WordIndex=0),
    'порожній D2-список не має голови');

  W:=WordsOf(['10','000','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check((Length(Heads)=1) and (Heads[0].Kind=hkStructuralHead) and
    (Heads[0].Key.Width=0) and (Heads[0].HeadIndex=1),
    'порожня структура D3:000 не приймається як звичайна голова');

  W:=WordsOf(['10','0','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check((Length(Heads)=1) and (Heads[0].Kind=hkExactHead) and
    SameKey(Heads[0].Key,ExactKey('0')) and
    (Heads[0].Key.Width=1), 'D1:0 зберіг свою точну ширину');

  W:=WordsOf(['10','1','11','0','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check(Length(Heads)=0,'похідна пара не є D2-списком');

  { Відоме D3:001 на першій позиції теж лише синтаксична
    координата: hkExactHead не надає callability. }
  W:=WordsOf(['10','001','1','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check((Length(Heads)=1) and (Heads[0].Kind=hkExactHead) and
    SameKey(Heads[0].Key,ExactKey('001')),
    'синтаксичний індекс не тлумачить D3');

  { Пошкоджений preorder має відхилятися без часткового
    результату. Після відмови нове дерево обробляється. }
  Tree[1].ChildIndex:=2;
  Failed:=False;
  try CollectBinaryHeads(Tree,Heads);
  except on E:EBinaryHeadsError do Failed:=True; end;
  Check(Failed,'пропущений нульовий номер дитини пройшов');
  Check(Length(Heads)=0,'індекс залишив часткові голови');
  W:=WordsOf(['10','111','01']);
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  CollectBinaryHeads(Tree,Heads);
  Check((Length(Heads)=1) and (Heads[0].Kind=hkExactHead) and
    SameKey(Heads[0].Key,ExactKey('111')),
    'повторне індексування після відмови');

  { Реальне T5M дерево: кореневий список із двома вкладеними
    списками; синтаксична голова першого — exact D1:1. }
  W := WordsOf(['10','10','1','0','01','10','1','01','01']);
  ReadBinaryTree(EncodeT5M(W), Tables, Tree);
  CollectBinaryHeads(Tree, Heads);
  Check((Length(Tree) = 6) and (Length(Heads) = 3) and
    (Heads[0].Kind = hkStructuralHead) and
    (Heads[1].Kind = hkExactHead) and
    SameKey(Heads[1].Key, ExactKey('1')) and
    (Heads[2].Kind = hkExactHead),
    'коректний preorder двох вкладених списків');

  { Навмисне розриваємо піддерево A після початку B, але
    ЗБЕРІГАЄМО локальні parent/child/depth/first-child інваріанти:
    0=root;1=A;2=A[0];3=B;4=B[0];5=A[1] (незаконне повернення).
    Попередня перевірка локальних індексів цю помилку пропускала. }
  Saved := Tree[3];
  Tree[3] := Tree[4];
  Tree[4] := Tree[5];
  Tree[4].ParentIndex := 3;
  Tree[5] := Saved;
  Failed := False;
  try
    CollectBinaryHeads(Tree, Heads);
  except
    on E: EBinaryHeadsError do
      Failed := Pos('preorder', E.Message) > 0;
  end;
  Check(Failed, 'повторний вхід до закритого піддерева прийнято');
  Check(Length(Heads) = 0,
    'після розриву preorder залишено часткові голови');

  { Після структурної помилки допустимо новий коректний T5M. }
  W := WordsOf(['10','111','01']);
  ReadBinaryTree(EncodeT5M(W), Tables, Tree);
  CollectBinaryHeads(Tree, Heads);
  Check((Length(Heads)=1) and (Heads[0].Kind=hkExactHead) and
    SameKey(Heads[0].Key,ExactKey('111')),
    'після відмови індекс не відновлюється');

  N:=900;
  SetLength(W,N+2);
  W[0]:='10';
  for I:=1 to N do W[I]:='1';
  W[N+1]:='01';
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  Check((Length(Tree)=N+1) and (Tree[N].ParentIndex=0) and
    (Tree[N].ChildIndex=N-1),'широкий список без втрати ancestry');

  { Рівень дужок D2 = 1, але 259 ПОХІДНИХ dkPair.
    Це НЕ синтаксична глибина: суворий ParseD2Words уже допустив.
    Старий рекурсивний inspector відхиляв такий коректний вхід. }
  N := MaxD2SyntaxDepth + 3;
  SetLength(W, N + 4);
  W[0] := '10';
  for I := 1 to N do W[I] := '1';
  W[N+1] := '11';
  W[N+2] := '000';
  W[N+3] := '01';
  ReadBinaryTree(EncodeT5M(W), Tables, Tree);
  Check((Length(Tree)=2*N+1) and
    (Tree[0].Kind=dkPair) and (Tree[0].Depth=0) and
    (Tree[2*N].Kind=dkEmpty) and
    SameKey(Tree[2*N].Key,ExactKey('000')) and
    (Tree[2*N].Depth=N),
    'глибоку похідну пару помилково прирівняно до вкладених D2 дужок');
  CollectBinaryHeads(Tree,Heads);
  Check(Length(Heads)=0,'похідна пара стала фіктивним D2-списком');

  { Реальний фізичний T5M з 40000 голів, 80001 вузлом дерева,
    точні родинні індекси і zero-copy семантика pinned D1/D3.
    Кожний вузол дерева перевіряємо в одному лінійному проході. }
  N := 40000;
  SetLength(W,N+4);
  W[0]:='10';
  for I:=1 to N do W[I]:='1';
  W[N+1]:='11';
  W[N+2]:='000';
  W[N+3]:='01';
  Data:=EncodeT5M(W);
  ReadBinaryTree(Data,Tables,Tree);
  Check(Length(Tree)=2*N+1,'великий фізичний preorder утратив вузли');
  for I:=0 to N-1 do begin
    Check((Tree[2*I].Kind=dkPair) and
      (not Tree[2*I].HasPhysicalWord) and
      (Tree[2*I].Key.Width=0) and
      (Tree[2*I].AnchorWordIndex=1) and
      (Tree[2*I].Depth=I) and
      (((I=0) and (Tree[2*I].ParentIndex=-1) and
        (Tree[2*I].ChildIndex=-1)) or
       ((I>0) and (Tree[2*I].ParentIndex=2*I-2) and
        (Tree[2*I].ChildIndex=1))),
      'пара загубила точний synthetic ancestry');
    Check((Tree[2*I+1].Kind=dkIdentity) and
      Tree[2*I+1].HasPhysicalWord and
      (Tree[2*I+1].ParentIndex=2*I) and
      (Tree[2*I+1].ChildIndex=0) and
      (Tree[2*I+1].Depth=I+1) and
      (Tree[2*I+1].Physical.WordIndex=I+2) and
      (Tree[2*I+1].Key.Width=1) and
      SameKey(Tree[2*I+1].Key,ExactKey('1')),
      'крапковий листок утратив D1 або фізичну позицію');
  end;
  Check((Tree[2*N].Kind=dkEmpty) and
    SameKey(Tree[2*N].Key,ExactKey('000')) and
    (Tree[2*N].ParentIndex=2*N-2) and
    (Tree[2*N].ChildIndex=1) and
    (Tree[2*N].Depth=N) and
    (Tree[2*N].Physical.WordIndex=N+3),
    'кінцевий D3:000 або його фізична адреса загублені');
  CollectBinaryHeads(Tree,Heads);
  Check(Length(Heads)=0,'довгий похідний ланцюг отримав фіктивну голову');

  { Більше ніж MaxTreeNodes фізичних+похідних вузлів: зупинити
    публікацію цілого дерева, не знизивши квоту чи gate. }
  N:=50000;
  SetLength(W,N+4);
  W[0]:='10';
  for I:=1 to N do W[I]:='1';
  W[N+1]:='11';
  W[N+2]:='000';
  W[N+3]:='01';
  Failed:=False;
  try ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  except on E:EBinaryTreeError do
    Failed:=Pos('межу вузлів',E.Message)>0; end;
  Check(Failed,'100001-й вузол плоского дерева пройшов квоту');
  Check(Length(Tree)=0,'після перевищення квоти залишилося старе дерево');
  WriteLn('ДВІЙКОВЕ-ДЕРЕВО-ГЛИБИНА-ГАРАЗД: ',
    'пари=40000 вузлів=80001 квота=100000 ',
    'синтаксис=D2-рівень-1 100001=відхилено preorder=точний');


  { Після відмови API має допускати наступний коректний фізичний файл. }
  W := WordsOf(['1']);
  ReadBinaryTree(EncodeT5M(W), Tables, Tree);
  Check((Length(Tree) = 1) and
    SameKey(Tree[0].Key, ExactKey('1')),
    'повторне читання після відмови втратило тотожність');

  Failed:=False;
  try ReadBinaryTree(#243,Tables,Tree);
  except on E:ET5MError do Failed:=True; end;
  Check(Failed,'пошкоджений T5M пройшов');
  Check(Length(Tree)=0,'пошкоджений T5M залишив старе дерево');
  Failed:=False;
  try ReadBinaryTree('',Tables,Tree);
  except on E:ET5MError do Failed:=True; end;
  Check(Failed,'порожній фізичний потік пройшов');
  Failed:=False;
  W:=WordsOf(['10','1']);
  try ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  except on E:ED2PhysicalError do Failed:=E.Span.IsEOF and
    (E.Span.WordIndex=3); end;
  Check(Failed,'незакритий D2 не вказав адресу EOF');
  Failed:=False;
  W:=WordsOf(['0000000000']);
  try ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  except on E:ED2PhysicalError do Failed:=E.Span.WordIndex=1; end;
  Check(Failed,'ширина W10 поза чинним D2 допуском пройшла');
  { G2.46: opt-in D10 — те саме фізичне D2-дерево з exact W10.
    D7 SYN — лише текстові дані; D12+ не виводиться з W12. }
  W:=WordsOf(['10','0000000000','0010110','000','01','1111111111']);
  Data:=EncodeT5M(W);
  ReadBinaryTreeD10(Data,Tables,Tree);
  Check(Length(Tree)=5,'D10: чотири листки і фізична рамка D2');
  Check((Tree[0].Kind=dkList) and (Tree[0].Key.Width=0) and
        (Tree[0].ParentIndex=-1) and
        (Tree[0].Physical.WordIndex=1),
    'D10: коренева рамка не є викличною функцією');
  Check((Tree[1].ParentIndex=0) and (Tree[1].ChildIndex=0) and
        (Tree[1].RootIndex=0) and
        SameKey(Tree[1].Key,ExactKey('0000000000')) and
        (Tree[1].Physical.WordIndex=2) and
        (Tree[1].Physical.TritEnd-Tree[1].Physical.TritStart=10),
    'D10: десять точних бітів із провідними нулями');
  Check((Tree[2].ParentIndex=0) and
        SameKey(Tree[2].Key,ExactKey('0010110')) and
        (Tree[2].Physical.WordIndex=3),
    'D7 SYN: недруковані дані, не opcode');
  Check((Tree[3].Kind=dkEmpty) and (Tree[3].ParentIndex=0) and
        SameKey(Tree[3].Key,ExactKey('000')) and
        not SameKey(Tree[3].Key,ExactKey('0')),
    'D3:000 зберігає власну тотожність');
  Check((Tree[4].ParentIndex=-1) and (Tree[4].RootIndex=1) and
        SameKey(Tree[4].Key,ExactKey('1111111111')) and
        (Tree[4].Physical.WordIndex=6),
    'D10: крайній правий ключ незалежного кореня');

  Failed:=False;
  try ReadBinaryTree(Data,Tables,Tree);
  except on E:ED2PhysicalError do Failed:=True; end;
  Check(Failed,'вузький W1..W9 API не повинен допускати W10');
  Check(Length(Tree)=0,'вузький W10-нет допуск залишив старе дерево');

  Failed:=False;
  try ReadBinaryTreeD10(EncodeT5M(WordsOf(['00000000000'])),Tables,Tree);
  except on E:EBinaryBindError do Failed:=True; end;
  Check(Failed,'W11 пройшов opt-in D10 binder');
  Check(Length(Tree)=0,'W11 залишив старий результат');
  Failed:=False;
  try ReadBinaryTreeD10(EncodeT5M(WordsOf(['000000000000'])),Tables,Tree);
  except on E:EBinaryBindError do Failed:=True; end;
  Check(Failed,'W12 механічно оголошений допустимим D12');
  Check(Length(Tree)=0,'W12 залишив часткове дерево');

  Failed:=False;
  try ReadBinaryTreeD10(#243,Tables,Tree);
  except on E:ET5MError do Failed:=True; end;
  Check(Failed,'пошкоджені T5M байти пройшли wide-reader');
  Check(Length(Tree)=0,'T5M-відмова не очистила дерево');
  Failed:=False;
  try ReadBinaryTreeD10(EncodeT5M(
    WordsOf(['10','0000000000'])),Tables,Tree);
  except on E:ED2PhysicalError do
    Failed:=E.Span.IsEOF and (E.Span.WordIndex=3); end;
  Check(Failed,'D10: незакритий D2 не дав точної EOF-адреси');
  Check(Length(Tree)=0,'D10: пізній EOF оприлюднив часткове дерево');

  ReadBinaryTreeD10(EncodeT5M(WordsOf(['0000000000'])),Tables,Tree);
  Check((Length(Tree)=1) and
        SameKey(Tree[0].Key,ExactKey('0000000000')),
    'відновлення wide-reader після всіх відмов');
  WriteLn('D10-ДВІЙКОВЕ-ДЕРЕВО-ГАРАЗД: ', 
    'точні-W10=так D7=дані D12+=відмова D2=фізичний атомарність=так');
  
  SetLength(Tables[1],0);
  Failed:=False;
  W:=WordsOf(['1']);
  try ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  except on E:EBinaryBindError do Failed:=True; end;
  Check(Failed,'неповна pinned таблиця пройшла');
  Check(Length(Tree)=0,'неповна pinned таблиця залишила старе дерево');
  WriteLn('ДВІЙКОВЕ-ДЕРЕВО-ГАРАЗД: атомарність=так ');
  WriteLn('ДВІЙКОВІ-ГОЛОВИ-ГАРАЗД: D2=перші-діти координати=точні preorder=суцільний викличність=не-доведено');
  WriteLn('T5M=фізичний D2=структурний домени=точні ');
  WriteLn('батьки=перевірені пари=похідні LCL=окремий викличність=не-доведено');
end.
