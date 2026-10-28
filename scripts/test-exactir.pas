program test_exactir;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarybind, wsm.exactir;

var
  T: TDomainSet;
  W: TExactWords;
  IR: TExactIR;
  I, J, Trials: SizeInt;
  Bad: Boolean;

procedure Check(Condition: Boolean; const MessageText: String);
begin
  if not Condition then begin
    WriteLn(StdErr, 'ТОЧНЕ-IR-ПОМИЛКА: ', MessageText);
    Halt(1);
  end;
end;

function ExactWords(const Data: array of RawByteString): TExactWords;
var K: SizeInt;
begin
  SetLength(Result, Length(Data));
  for K := 0 to High(Data) do Result[K] := Data[K];
end;

procedure FailAtomic(const Physical: RawByteString; const LabelText: String);
begin
  SetLength(IR.Nodes, 1);
  SetLength(IR.Roots, 1);
  IR.BoundLeaves := 7;
  Bad := False;
  try
    BuildExactIR(Physical, T, IR);
  except
    on E: Exception do begin
      Bad := (E is ET5MError) or (E is ED2PhysicalError) or
             (E is EBinaryBindError) or (E is EExactIRError);
    end;
  end;
  Check(Bad, LabelText + ': не відхилено');
  Check((Length(IR.Nodes)=0) and (Length(IR.Roots)=0) and
    (IR.BoundLeaves=0), LabelText + ': частковий IR після відмови');
end;

begin
  LoadPinnedDomains('external/sens', T);
  W := ExactWords(['10','111','00','0','000','01']);
  BuildExactIR(EncodeT5M(W), T, IR);
  Check((Length(IR.Roots)=1) and (IR.Roots[0]=0) and
        (Length(IR.Nodes)=4) and (IR.BoundLeaves=3),
        'коренева структура і три зв’язані координати');
  Check((IR.Nodes[0].Kind=ikList) and (not IR.Nodes[0].HasKey) and
        (IR.Nodes[0].WordIndex=1) and (IR.Nodes[0].ParentIndex=-1),
        'структурний D2 маркер не є доменною функцією');
  Check((IR.Nodes[1].Kind=ikIdentity) and IR.Nodes[1].HasKey and
        SameKey(IR.Nodes[1].Key, ExactKey('111')) and
        (IR.Nodes[1].WordIndex=2) and (IR.Nodes[1].ParentIndex=0) and
        (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1),
        'D3:111 із pinned домену');
  Check((IR.Nodes[2].Kind=ikIdentity) and
        SameKey(IR.Nodes[2].Key, ExactKey('0')) and
        (IR.Nodes[2].ChildIndex=1), 'D1:0 первинний двійковий ключ');
  Check((IR.Nodes[3].Kind=ikEmpty) and IR.Nodes[3].HasKey and
        SameKey(IR.Nodes[3].Key, ExactKey('000')) and
        (IR.Nodes[3].WordIndex=5) and
        (IR.Nodes[3].Physical.TritStart=12) and
        (IR.Nodes[3].Physical.TritEnd=15),
        'D3:000 відмінне від D1:0 і не втратило адресу');
  Check(not SameKey(IR.Nodes[3].Key, IR.Nodes[2].Key),
        'змішано різні домени з однаковими значеннями');

  W := ExactWords(['0','1']);
  Check(Length(EncodeT5M(W))=1, 'обидва домени в одному фізичному байті');
  BuildExactIR(EncodeT5M(W), T, IR);
  Check((Length(IR.Roots)=2) and (IR.Roots[0]=0) and (IR.Roots[1]=1) and
        (IR.Nodes[0].ParentIndex=-1) and
        (IR.Nodes[1].ParentIndex=-1) and
        (IR.Nodes[0].RootIndex=0) and
        (IR.Nodes[1].RootIndex=1) and
        (IR.Nodes[0].Physical.ByteStart=0) and
        (IR.Nodes[1].Physical.ByteStart=0) and
        (IR.Nodes[0].Physical.TritStart=0) and
        (IR.Nodes[1].Physical.TritStart=2),
        'два фізичні корені в одному байті');

  W := ExactWords(['10','1','0','11','000','01']);
  BuildExactIR(EncodeT5M(W), T, IR);
  Check((Length(IR.Nodes)=5) and (IR.BoundLeaves=3) and
        (IR.Nodes[0].Kind=ikPair) and
        (IR.Nodes[2].Kind=ikPair) and
        (IR.Nodes[2].ParentIndex=0) and
        (IR.Nodes[4].Kind=ikEmpty) and
        (IR.Nodes[4].ParentIndex=2) and
        (IR.Nodes[4].Depth=2),
        'крапкова пара зберігає зв’язки у IR');

  W := ExactWords(['000000001']);
  BuildExactIR(EncodeT5M(W), T, IR);
  Check((Length(IR.Nodes)=1) and IR.Nodes[0].HasKey and
        (IR.Nodes[0].Key.Width=9) and
        (KeyBits(IR.Nodes[0].Key)='000000001') and
        (IR.Nodes[0].Physical.TritEnd=9),
        'провідні нулі та ширина D9');

  FailAtomic(#243, 'заборонений T5M байт');
  FailAtomic(#242, 'зайве фізичне заповнення');
  FailAtomic(EncodeT5M(ExactWords(['10','1'])),
    'незакрита двійкова структура');
  FailAtomic(EncodeT5M(ExactWords(['01'])),
    'закривальний D2 без відкриття');
  FailAtomic(EncodeT5M(ExactWords(['1111111111'])),
    'W10 за межами pinned D2 reader');
  SetLength(T[1], 0);
  FailAtomic(EncodeT5M(ExactWords(['1'])),
    'неповний ратифікований покажчик');
  LoadPinnedDomains('external/sens', T);

  { D2 допускає довгі списки, але проміжне IR має власний бюджет
    розгортання вкладених крапкових пар. }
  SetLength(W, 262);
  W[0] := '10';
  for I := 1 to 258 do W[I] := '1';
  W[259] := '11'; W[260] := '0'; W[261] := '01';
  FailAtomic(EncodeT5M(W), 'перевищено глибину дерева пар');

  Trials := 0;
  for I := 1 to 80 do begin
    SetLength(W, I+2);
    W[0] := '10';
    for J := 1 to I do
      if J mod 2 = 0 then W[J] := '0' else W[J] := '1';
    W[I+1] := '01';
    BuildExactIR(EncodeT5M(W), T, IR);
    Check((Length(IR.Nodes)=I+1) and (IR.BoundLeaves=I) and
          (Length(IR.Roots)=1), 'стрес: вузли IR');
    for J := 1 to I do
      Check((IR.Nodes[J].ParentIndex=0) and
            (IR.Nodes[J].ChildIndex=J-1) and
            (IR.Nodes[J].Depth=1) and IR.Nodes[J].HasKey and
            (IR.Nodes[J].WordIndex=J+1),
            'стрес: порядок, ідентичність та походження');
    Inc(Trials);
  end;
  WriteLn('ТОЧНЕ-IR-ГАРАЗД: двійкові-домени=первинні ',
    'дерево=точне адреси=точні ',
    'відмови=атомарні перевірки=',Trials);
  WriteLn('ТОЧНЕ-IR-МЕЖІ: викличність=не-доведено ',
    'машинний-код=відсутній Core4=не-виконується');
end.
