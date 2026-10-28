program test_binarytree;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarybind, wsm.binarytree;
var Tables: TDomainSet; W: TExactWords; Tree: TBinaryTreeEntries;
    I, N, Count: SizeInt; Failed: Boolean; Data: RawByteString;
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

  N:=900;
  SetLength(W,N+2);
  W[0]:='10';
  for I:=1 to N do W[I]:='1';
  W[N+1]:='01';
  ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  Check((Length(Tree)=N+1) and (Tree[N].ParentIndex=0) and
    (Tree[N].ChildIndex=N-1),'широкий список без втрати ancestry');

  { Коректний T5M/D2 з глибоким ланцюгом похідних крапкових пар:
    синтаксичний reader приймає його, але фізичний інспектор має
    відхилити перевищення глибини БЕЗ частково зібраного дерева. }
  N := MaxD2SyntaxDepth + 3;
  SetLength(W, N + 4);
  W[0] := '10';
  for I := 1 to N do W[I] := '1';
  W[N+1] := '11';
  W[N+2] := '0';
  W[N+3] := '01';
  Failed := False;
  try
    ReadBinaryTree(EncodeT5M(W), Tables, Tree);
  except
    on E: EBinaryTreeError do
      Failed := Pos('глибину', E.Message) > 0;
  end;
  Check(Failed, 'перевищену глибину похідних пар прийнято');
  Check(Length(Tree) = 0,
    'після пізньої помилки залишилося частково зібране дерево');

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
  SetLength(Tables[1],0);
  Failed:=False;
  W:=WordsOf(['1']);
  try ReadBinaryTree(EncodeT5M(W),Tables,Tree);
  except on E:EBinaryBindError do Failed:=True; end;
  Check(Failed,'неповна pinned таблиця пройшла');
  Check(Length(Tree)=0,'неповна pinned таблиця залишила старе дерево');
  WriteLn('ДВІЙКОВЕ-ДЕРЕВО-ГАРАЗД: атомарність=так ');
  WriteLn('T5M=фізичний D2=структурний домени=точні ');
  WriteLn('батьки=перевірені пари=похідні LCL=окремий викличність=не-доведено');
end.
