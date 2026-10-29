program test_d2source;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source;

var
  W: TExactWords;
  Doc: TD2Document;
  I: SizeInt;
  Rejected: Boolean;

procedure Require(Ok: Boolean; const Why: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'D2SOURCE-FAIL ', Why);
    Halt(1);
  end;
end;

function WordsOf(const Source: array of RawByteString): TExactWords;
var N: SizeInt;
begin
  SetLength(Result, Length(Source));
  for N := 0 to High(Source) do Result[N] := Source[N];
end;

procedure RejectWords(const Source: array of RawByteString;
                      ExpectedIndex: SizeInt; const CaseName: String);
var Failure: Boolean; Parsed: TD2Document;
begin
  Parsed := nil;
  Failure := False;
  try
    Parsed := ParseD2Words(WordsOf(Source));
  except
    on E: ED2SourceError do begin
      Failure := True;
      Require(E.WordIndex = ExpectedIndex,
        CaseName + ' wrong source word index: ' + IntToStr(E.WordIndex));
    end;
  end;
  Parsed.Free;
  Require(Failure, CaseName + ' was accepted');
end;

{ G1.17: кожен вузол має фізичний напіввідкритий інтервал точних слів.
  Сепаратори не належать атомам, але внутрішні сепаратори містяться
  всередині інтервалу списку; EOF є межею count+1. }
procedure CheckWordSpans;
var Parsed: TD2Document; Node: TD2Node;
begin
  Parsed := ParseD2Words(WordsOf(
    ['00','10','1','00','10','000','01','01','00','0']));
  try
    Require((Parsed.Roots[0].WordIndex=2) and
      (Parsed.Roots[0].EndWordIndexExclusive=9),
      'outer list span includes open, separators, nested form, close');
    Require((Parsed.Roots[0].Children[0].WordIndex=3) and
      (Parsed.Roots[0].Children[0].EndWordIndexExclusive=4),
      'atom span includes exactly its own word');
    Node := Parsed.Roots[0].Children[1];
    Require((Node.WordIndex=5) and (Node.EndWordIndexExclusive=8),
      'nested list span includes both framing words');
    Require((Node.Children[0].WordIndex=6) and
      (Node.Children[0].EndWordIndexExclusive=7),
      'D3 empty span includes only its own exact word');
    Require((Parsed.Roots[1].WordIndex=10) and
      (Parsed.Roots[1].EndWordIndexExclusive=11),
      'final atom span ends at one-past-EOF');
  finally Parsed.Free; end;

  Parsed := ParseD2Words(WordsOf(['10','01']));
  try
    Require((Parsed.Roots[0].WordIndex=1) and
      (Parsed.Roots[0].EndWordIndexExclusive=3),
      'empty D2 list span includes open and close');
  finally Parsed.Free; end;

  Parsed := ParseD2Words(WordsOf(
    ['10','1','00','0','11','10','1','01','01']));
  try
    Node := Parsed.Roots[0];
    Require((Node.Kind=dkPair) and (Node.WordIndex=1) and
      (Node.EndWordIndexExclusive=10),
      'dotted root pair retains original form span');
    Require((Node.Children[1].Kind=dkPair) and
      (Node.Children[1].WordIndex=1) and
      (Node.Children[1].EndWordIndexExclusive=10),
      'each synthetic dotted pair retains original form span');
    Require((Node.Children[1].Children[1].WordIndex=6) and
      (Node.Children[1].Children[1].EndWordIndexExclusive=9),
      'dotted tail list retains its own source span');
  finally Parsed.Free; end;
end;


{ G1.14: реальні канонічні T5M слова, межі D2 AST і похідні пари.
  Без SENS callability: D1 атом лишається opaque exact бітовим словом. }
procedure CheckWideD2Growth;
var
  Words: TExactWords;
  Physical: RawByteString;
  Parsed: TD2Document;
  Node: TD2Node;
  J, PairCount: SizeInt;
  Failed: Boolean;
begin
  { Одне фізичне D2 відкриття + 99998 точних D1 + D2 закриття.
    Публічні Children мають не містити резервних nil-слотів. }
  SetLength(Words, MaxD2Words);
  Words[0] := '10';
  for J := 1 to MaxD2Words-2 do Words[J] := '1';
  Words[MaxD2Words-1] := '01';
  Physical := EncodeT5M(Words);
  Parsed := ReadD2T5M(Physical);
  try
    Require(Length(Parsed.Roots)=1, 'великий фізичний список: root');
    Require(Length(Parsed.Roots[0].Children)=MaxD2Words-2,
      'великий фізичний список: точна кількість дітей');
    Require(Parsed.Roots[0].Children[MaxD2Words-3].WordIndex =
      MaxD2Words-1, 'останній фізичний WordIndex');
    Require(Parsed.Roots[0].Children[MaxD2Words-3].Bits = '1',
      'останнє D1 бітове слово змінено');
  finally Parsed.Free; end;

  { 100000 незалежних фізичних коренів без додаткового D2 framing. }
  for J := 0 to High(Words) do Words[J] := '0';
  Physical := EncodeT5M(Words);
  Parsed := ReadD2T5M(Physical);
  try
    Require(Length(Parsed.Roots)=MaxD2Words,
      'точна кількість незалежних фізичних коренів');
    Require(Parsed.Roots[MaxD2Words-1].WordIndex=MaxD2Words,
      'остання фізична адреса кореня втрачена');
    Require(Parsed.Roots[MaxD2Words-1].Bits='0',
      'останній фізичний біт змінився');
  finally Parsed.Free; end;

  { Крапкова пара з багатьма головами: не обійти порожній резерв. }
  SetLength(Words,304);
  Words[0]:='10';
  for J:=1 to 300 do Words[J]:='1';
  Words[301]:='11';
  Words[302]:='0';
  Words[303]:='01';
  Parsed:=ReadD2T5M(EncodeT5M(Words));
  try
    Require(Length(Parsed.Roots)=1,'фізична крапкова пара root');
    Node:=Parsed.Roots[0];
    PairCount:=0;
    while Node.Kind=dkPair do begin
      Require(Length(Node.Children)=2,'виведена пара має двох дітей');
      Require(Node.Children[0].Bits='1','голова фізичної пари втрачена');
      Inc(PairCount);
      Node:=Node.Children[1];
    end;
    Require((PairCount=300) and (Node.Bits='0') and
      (Node.WordIndex=303),'послідовність 300 голів/хвіст втрачена');
  finally Parsed.Free; end;

  { Межа 100000 є лише ресурсним guard reader, не мовним законом. }
  SetLength(Words,MaxD2Words+1);
  for J:=0 to High(Words) do Words[J]:='1';
  Failed:=False;
  try
    Parsed:=ParseD2Words(Words);
    Parsed.Free;
  except on E:ED2SourceError do
    Failed:=(E.WordIndex=1) and (Pos('word limit',E.Message)>0);
  end;
  Require(Failed,'100001-ше слово має бути відхилене до AST');

  { Пізній EOF має звільнити десятки тисяч уже створених вузлів. }
  SetLength(Words,MaxD2Words);
  Words[0]:='10';
  for J:=1 to High(Words) do Words[J]:='1';
  Failed:=False;
  try
    Parsed:=ParseD2Words(Words);
    Parsed.Free;
  except on E:ED2SourceError do
    Failed:=(E.WordIndex=MaxD2Words+1) and
      (Pos('unterminated',E.Message)>0);
  end;
  Require(Failed,'пізній D2 EOF мав відхилити неповний список');

  Parsed:=ParseD2Words(WordsOf(['10','000','01']));
  try
    Require((Length(Parsed.Roots)=1) and
      (Length(Parsed.Roots[0].Children)=1) and
      (Parsed.Roots[0].Children[0].Kind=dkEmpty),
      'відновлення після пізнього EOF втратило D3:000');
  finally Parsed.Free; end;
end;


{ G1.27: один коректний фізичний список D2 з крапкою породжує
  глибокий ЛАНЦЮГ похідних пар, навіть якщо вхідні дужки не вкладені.
  Звільнення має бути ітеративним, як і сам обхід, без stack overflow. }
procedure CheckDeepDottedDestruction;
const Heads = MaxD2Words - 4;
var
  Source: TExactWords;
  Physical: RawByteString;
  Parsed: TD2Document;
  Cursor: TD2Node;
  J, Pass, Seen: SizeInt;
  Rejected: Boolean;
begin
  SetLength(Source, MaxD2Words);
  Source[0] := '10'; { D2 відкриття }
  for J := 1 to Heads do Source[J] := '1'; { точні D1 біти }
  Source[Heads+1] := '11'; { D2 крапка }
  Source[Heads+2] := '000'; { структурне D3:000, не D1:0 }
  Source[Heads+3] := '01'; { D2 закриття }
  Physical := EncodeT5M(Source);
  for Pass := 1 to 2 do begin
    Parsed := ReadD2T5M(Physical);
    try
      Require(Length(Parsed.Roots)=1,
        'втрачений фізичний корінь довгого крапкового списку');
      Cursor := Parsed.Roots[0];
      Seen := 0;
      while Cursor.Kind=dkPair do begin
        Require((Length(Cursor.Children)=2) and
          (Cursor.Children[0].Bits='1') and
          (Cursor.WordIndex=1) and
          (Cursor.EndWordIndexExclusive=MaxD2Words+1),
          'пошкоджено точні біти або інтервал похідної пари');
        Inc(Seen);
        Cursor := Cursor.Children[1];
      end;
      Require((Seen=Heads) and (Cursor.Kind=dkEmpty) and
        (Cursor.Bits='000') and (Cursor.Width=3) and
        (Cursor.WordIndex=MaxD2Words-1),
        'неповний ланцюг або загублений точний D3-хвіст');
    finally
      { До G1.27 рекурсивний деструктор створював ~100k вкладених
        Pascal викликів та міг завершити процес через стек. }
      Parsed.Free;
    end;
  end;

  { Пізня D2-синтаксична помилка після всіх головних атомів має
    звільнити приватне AST без публікації часткового документа. }
  Source[MaxD2Words-1] := '1'; { замість закриття }
  Rejected := False;
  Parsed := nil;
  try
    Parsed := ReadD2T5M(EncodeT5M(Source));
  except on E:ED2SourceError do
    Rejected := (E.WordIndex=MaxD2Words) and
      (Pos('dotted tail',E.Message)>0);
  end;
  Parsed.Free;
  Require(Rejected,'пізній D2 збій крапкового списку не відхилено');
  Parsed := ParseD2Words(WordsOf(['10','000','01']));
  try
    Require((Length(Parsed.Roots)=1) and
      (Parsed.Roots[0].Children[0].Kind=dkEmpty),
      'відновлення D2 після великої відмови');
  finally Parsed.Free; end;
  WriteLn('D2-DESTRUCTION-OK фізичних-слів=',MaxD2Words,
    ' пар=',Heads,' повні-звільнення=2 негативний-EOF=відхилено');
end;

begin
  { Fixed exact words and independently derived base-3 physical bytes.
    This is transport + structure, NOT evidence of SENS callability. }
  W := WordsOf(['10', '1', '01']);
  Require(EncodeT5M(W) = #104#53, 'physical D2 golden mismatch');
  Doc := ReadD2T5M(EncodeT5M(W));
  try
    Require(Length(Doc.Roots) = 1, 'single top-level D2 structure');
    Require(Doc.Roots[0].Kind = dkList, 'D2 OPEN/CLOSE list');
    Require(Doc.Roots[0].WordIndex = 1, 'list starts at exact word 1');
    Require(Length(Doc.Roots[0].Children) = 1, 'list item count');
    Require(Doc.Roots[0].Children[0].Kind = dkIdentity, 'D1 is opaque identity');
    Require(Doc.Roots[0].Children[0].Width = 1, 'identity width lost');
    Require(Doc.Roots[0].Children[0].Bits = '1', 'identity bit changed');
    Require(Doc.Roots[0].Children[0].WordIndex = 2, 'identity word position');
  finally Doc.Free; end;

  W := WordsOf(['00', '10', '1', '00', '000', '01', '00', '1']);
  Doc := ReadD2T5M(EncodeT5M(W));
  try
    Require(Length(Doc.Roots) = 2, 'multiple physical root expressions');
    Require(Doc.Roots[0].WordIndex = 2, 'skip initial D2 separator');
    Require(Length(Doc.Roots[0].Children) = 2, 'skip inner separator');
    Require(Doc.Roots[0].Children[1].Kind = dkEmpty, 'D3:000 structural empty');
    Require(Doc.Roots[0].Children[1].Width = 3, 'D3 empty provenance width');
    Require(Doc.Roots[0].Children[1].Bits = '000', 'D3 empty exact payload');
    Require(Doc.Roots[1].WordIndex = 8, 'second top-level word offset');
  finally Doc.Free; end;

  W := WordsOf(['10','1','00','0','11','10','1','01','01']);
  Doc := ReadD2T5M(EncodeT5M(W));
  try
    Require(Length(Doc.Roots) = 1, 'single dotted expression');
    Require(Doc.Roots[0].Kind = dkPair, 'D2 dot builds pair');
    Require(Length(Doc.Roots[0].Children) = 2, 'outer pair cardinality');
    Require(Doc.Roots[0].Children[0].Bits = '1', 'first dotted head');
    Require(Doc.Roots[0].Children[1].Kind = dkPair, 'dotted nested pair');
    Require(Doc.Roots[0].Children[1].Children[0].Bits = '0',
      'second dotted head');
    Require(Doc.Roots[0].Children[1].Children[1].Kind = dkList,
      'D2 dotted tail retained as list');
  finally Doc.Free; end;

  W := WordsOf(['10','01','10','000','01']);
  Doc := ReadD2T5M(EncodeT5M(W));
  try
    Require(Length(Doc.Roots) = 2, 'two empty and nonempty D2 lists');
    Require((Doc.Roots[0].Kind = dkList) and
      (Length(Doc.Roots[0].Children) = 0), 'D2 empty list');
    Require((Doc.Roots[1].Kind = dkList) and
      (Doc.Roots[1].Children[0].Kind = dkEmpty),
      'D3 empty identity distinct from D2 brackets in syntax provenance');
  finally Doc.Free; end;

  RejectWords(['01'], 1, 'stray D2 CLOSE');
  RejectWords(['11'], 1, 'stray D2 DOT');
  RejectWords(['10','1'], 3, 'open list without close');
  RejectWords(['10','11','1','01'], 2, 'dot without head');
  RejectWords(['10','1','11','01'], 4, 'dot without tail');
  RejectWords(['10','1','11','1','1','01'], 5, 'dot with two tails');
  RejectWords(['10','1','01','01'], 4, 'close after completed root');
  RejectWords(['1111111111'], 1, 'W10 not admitted in current D2 reader');
  RejectWords([''], 1, 'zero width');
  RejectWords(['2'], 1, 'nonbinary payload');
  RejectWords([], 1, 'empty exact word stream');

  CheckWordSpans;

  W := WordsOf(['10','1','01']);
  W[0] := '10';
  Rejected := False;
  try Doc := ReadD2T5M(#243);
  except on E: ET5MError do Rejected := True; end;
  Require(Rejected, 'forbidden byte must fail inside transport boundary');
  Rejected := False;
  try Doc := ReadD2T5M(#242);
  except on E: ET5MError do Rejected := True; end;
  Require(Rejected, 'invalid padding must fail inside transport boundary');

  SetLength(W, 2*258+1);
  for I := 0 to 257 do W[I] := '10';
  W[258] := '1';
  for I := 259 to High(W) do W[I] := '01';
  Rejected := False;
  try Doc := ParseD2Words(W);
  except on E: ED2SourceError do begin
    Rejected := True;
    Require(Pos('depth', E.Message) > 0, 'overdepth error must name depth');
    Require(E.WordIndex >= 257, 'overdepth source location');
  end; end;
  Require(Rejected, 'unbounded D2 nesting accepted');

  CheckWideD2Growth;
  CheckDeepDottedDestruction;

  WriteLn('D2SOURCE-OK FPC pinned-D2=structure D3:000=empty T5M=physical-golden');
  WriteLn('D2SOURCE-SCOPE mechanical-ast-only semantic-callability=NOT_PROVED core4-execution=NOT_PROVED');
end.
