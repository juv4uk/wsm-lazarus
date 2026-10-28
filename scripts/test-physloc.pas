program test_physloc;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc;

var
  W, OutWords: TExactWords;
  S, Physical: RawByteString;
  Spans, Again: TPhysicalWordSpans;
  P: TPhysicalWordSpan;
  NodeSpan: TPhysicalNodeSpan;
  Node: TD2Node;
  Doc: TD2Document;
  I, J, Cases: Integer;
  Failed: Boolean;

procedure Check(Ok: Boolean; const Context: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'PHYSLOC-FAIL ', Context);
    Halt(1);
  end;
end;

function MakeWords(const Values: array of RawByteString): TExactWords;
var N: SizeInt;
begin
  SetLength(Result, Length(Values));
  for N := 0 to High(Values) do Result[N] := Values[N];
end;

procedure CheckOffset(const PhysicalBytes: RawByteString;
  const Source: array of RawByteString; N, TStart, TEnd, BStart, BEnd: SizeInt);
var A: TExactWords; V: TPhysicalWordSpans; T: TPhysicalWordSpan; K: SizeInt;
begin
  DecodeT5MWithLocations(PhysicalBytes, A, V);
  Check(Length(A) = Length(Source), 'word cardinality mismatch');
  for K := 0 to High(Source) do
    Check(A[K] = Source[K], 'word bytes/leading zeros mismatch');
  T := LocatePhysicalWord(PhysicalBytes, V, N);
  Check((T.TritStart = TStart) and (T.TritEnd = TEnd) and
        (T.ByteStart = BStart) and (T.ByteEnd = BEnd) and
        (not T.IsEOF), 'wrong physical half-open location at index ' + IntToStr(N));
end;

function FailedNodeSpan(const PhysicalBytes: RawByteString;
  const WordSpans: TPhysicalWordSpans; ANode: TD2Node): Boolean;
var Span: TPhysicalNodeSpan;
begin
  Result := False;
  try
    Span := LocatePhysicalNodeSpan(PhysicalBytes, WordSpans, ANode);
    Result := Span.WordStart = 0;
  except
    on E: EPhysicalLocationError do Result := True;
  end;
end;

procedure ExpectSyntaxError(const Words: array of RawByteString;
  ExpectedIndex, ExpectedTrit, ExpectedByte: SizeInt;
  const CaseName: String);
var A, OldWords: TExactWords; D: TD2Document; V: TPhysicalWordSpans;
begin
  A := MakeWords(Words);
  { Перед помилкою зовнішній out мав успішний результат. Навіть після
    пізньої D2-помилки він має бути АТОМАРНО очищений. }
  DecodeT5MWithLocations(EncodeT5M(MakeWords(['0'])), OldWords, V);
  Check((Length(OldWords)=1) and (Length(V)=1),
    CaseName+' не створено попередній валідний результат');
  D := nil;
  Failed := False;
  try D := ReadD2WithPhysicalLocations(EncodeT5M(A), V);
  except
    on E: ED2PhysicalError do begin
      Failed := True;
      Check(E.Span.WordIndex = ExpectedIndex, CaseName + ' bad word index');
      Check(E.Span.TritStart = ExpectedTrit, CaseName + ' bad trit index');
      Check(E.Span.ByteStart = ExpectedByte, CaseName + ' bad byte index');
      Check((E.Span.ByteEnd >= E.Span.ByteStart), CaseName + ' invalid span');
      Check(E.Span.IsEOF = (ExpectedIndex = Length(A)+1), CaseName + ' wrong EOF flag');
    end;
  end;
  Check((D=nil) and (Length(V)=0),
    CaseName+' неатомарно опубліковано адреси недопущеного D2');
  D.Free;
  Check(Failed, CaseName + ' malformed D2 was accepted');
end;

begin
  { Pinned T5M five-trit MSB-first golden, byte indexes are zero-based.
    Two exact words can legitimately point into the SAME physical byte. }
  W := MakeWords(['10','1','01']);
  Physical := EncodeT5M(W);
  Check(Physical = #104#53, 'pinned mixed D2 carrier byte golden');
  CheckOffset(Physical, ['10','1','01'], 1, 0, 2, 0, 1);
  CheckOffset(Physical, ['10','1','01'], 2, 3, 4, 0, 1);
  CheckOffset(Physical, ['10','1','01'], 3, 5, 7, 1, 2);

  Physical := EncodeT5M(MakeWords(['0','1']));
  Check(Length(Physical) = 1, 'two small words fit in one byte');
  CheckOffset(Physical, ['0','1'], 1, 0, 1, 0, 1);
  CheckOffset(Physical, ['0','1'], 2, 2, 3, 0, 1);

  Physical := EncodeT5M(MakeWords(['00000','1']));
  CheckOffset(Physical, ['00000','1'], 1, 0, 5, 0, 1);
  CheckOffset(Physical, ['00000','1'], 2, 6, 7, 1, 2);

  { Explicit zero-length EOF sentinel is at physical file byte length;
    logical trit cursor is at last meaningful bit, before tail padding. }
  DecodeT5MWithLocations(Physical, OutWords, Spans);
  P := LocatePhysicalWord(Physical, Spans, Length(OutWords)+1);
  Check(P.IsEOF and (P.WordIndex=3) and
        (P.TritStart=7) and (P.TritEnd=7) and
        (P.ByteStart=2) and (P.ByteEnd=2), 'EOF source location');

  Doc := ReadD2WithPhysicalLocations(EncodeT5M(
    MakeWords(['10','000','01'])), Spans);
  try
    Check((Length(Doc.Roots) = 1) and
          (Doc.Roots[0].Kind = dkList), 'D2 normal path parse');
    Check(Doc.Roots[0].Children[0].Kind = dkEmpty,
          'D3:000 remains structural empty with exact source span');
    Check(Spans[1].WordIndex = 2, 'AST to physical location mapping');
  finally Doc.Free; end;

  { G1.18: AST word intervals map to exact contiguous physical envelopes. }
  Physical := EncodeT5M(MakeWords(
    ['00','10','1','00','10','000','01','01','00','0']));
  Doc := ReadD2WithPhysicalLocations(Physical, Spans);
  try
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans, Doc.Roots[0]);
    Check((NodeSpan.WordStart=2) and (NodeSpan.WordEndExclusive=9) and
      (NodeSpan.TritStart=3) and (NodeSpan.TritEnd=23) and
      (NodeSpan.ByteStart=0) and (NodeSpan.ByteEnd=5),
      'nested list envelope includes its exact OPEN/CLOSE and interior');
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans,
      Doc.Roots[0].Children[0]);
    Check((NodeSpan.WordStart=3) and (NodeSpan.WordEndExclusive=4) and
      (NodeSpan.TritStart=6) and (NodeSpan.TritEnd=7) and
      (NodeSpan.ByteStart=1) and (NodeSpan.ByteEnd=2),
      'atom maps to exact source word even when byte is shared');
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans,
      Doc.Roots[0].Children[1]);
    Check((NodeSpan.WordStart=5) and (NodeSpan.WordEndExclusive=8) and
      (NodeSpan.TritStart=11) and (NodeSpan.TritEnd=20) and
      (NodeSpan.ByteStart=2) and (NodeSpan.ByteEnd=4),
      'nested empty-list form maps across physical word separators');
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans, Doc.Roots[1]);
    Check((NodeSpan.WordStart=10) and (NodeSpan.WordEndExclusive=11) and
      (NodeSpan.TritStart=27) and (NodeSpan.TritEnd=28) and
      (NodeSpan.ByteStart=5) and (NodeSpan.ByteEnd=6),
      'last top-level atom maps to final physical byte');
  finally Doc.Free; end;

  Physical := EncodeT5M(MakeWords(['10','01']));
  Doc := ReadD2WithPhysicalLocations(Physical, Spans);
  try
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans, Doc.Roots[0]);
    Check((NodeSpan.WordStart=1) and (NodeSpan.WordEndExclusive=3) and
      (NodeSpan.TritStart=0) and (NodeSpan.TritEnd=5) and
      (NodeSpan.ByteStart=0) and (NodeSpan.ByteEnd=1),
      'empty D2 list physical envelope includes both framing words');
  finally Doc.Free; end;

  Physical := EncodeT5M(MakeWords(
    ['10','1','00','0','11','10','1','01','01']));
  Doc := ReadD2WithPhysicalLocations(Physical, Spans);
  try
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans, Doc.Roots[0]);
    Check((NodeSpan.WordStart=1) and (NodeSpan.WordEndExclusive=10) and
      (NodeSpan.TritStart=0) and (NodeSpan.TritEnd=23) and
      (NodeSpan.ByteStart=0) and (NodeSpan.ByteEnd=5),
      'synthetic dotted pair retains whole physical source envelope');
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans,
      Doc.Roots[0].Children[1].Children[1]);
    Check((NodeSpan.WordStart=6) and (NodeSpan.WordEndExclusive=9) and
      (NodeSpan.TritStart=13) and (NodeSpan.TritEnd=20) and
      (NodeSpan.ByteStart=2) and (NodeSpan.ByteEnd=4),
      'dotted tail list retains its own physical source envelope');
  finally Doc.Free; end;

  Physical := EncodeT5M(MakeWords(['0','1']));
  Doc := ReadD2WithPhysicalLocations(Physical, Spans);
  try
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans, Doc.Roots[0]);
    Check((NodeSpan.TritStart=0) and (NodeSpan.TritEnd=1) and
      (NodeSpan.ByteStart=0) and (NodeSpan.ByteEnd=1),
      'first exact word maps inside shared byte');
    NodeSpan := LocatePhysicalNodeSpan(Physical, Spans, Doc.Roots[1]);
    Check((NodeSpan.TritStart=2) and (NodeSpan.TritEnd=3) and
      (NodeSpan.ByteStart=0) and (NodeSpan.ByteEnd=1),
      'second exact word shares byte without losing trit precision');
  finally Doc.Free; end;

  Check(FailedNodeSpan(Physical, Spans, nil), 'nil AST node span');
  Node := TD2Node.Create;
  try
    Node.WordIndex := 1;
    Node.EndWordIndexExclusive := 1;
    Check(FailedNodeSpan(Physical, Spans, Node), 'empty AST node interval');
    Node.WordIndex := 2;
    Node.EndWordIndexExclusive := 1;
    Check(FailedNodeSpan(Physical, Spans, Node), 'reversed AST node interval');
    Node.WordIndex := 1;
    Node.EndWordIndexExclusive := Length(Spans)+2;
    Check(FailedNodeSpan(Physical, Spans, Node), 'AST node interval past EOF');
  finally Node.Free; end;

  ExpectSyntaxError(['01'], 1, 0, 0, 'stray D2 close');
  ExpectSyntaxError(['11'], 1, 0, 0, 'stray D2 dot');
  ExpectSyntaxError(['10','1'], 3, 4, 1, 'unterminated D2 list EOF');
  ExpectSyntaxError(['10','1','11','01'], 4, 8, 1, 'dot missing tail');
  ExpectSyntaxError(['10','11','1','01'], 2, 3, 0, 'dot missing head');
  ExpectSyntaxError(['1111111111'], 1, 0, 0, 'unsupported source width');

  DecodeT5MWithLocations(EncodeT5M(MakeWords(['0'])), OutWords, Spans);
  Failed := False;
  try P := LocatePhysicalWord(#80, Spans, 0);
  except on E: EPhysicalLocationError do Failed := True; end;
  Check(Failed, 'zero word index accepted');
  Failed := False;
  try P := LocatePhysicalWord(#80, Spans, 3);
  except on E: EPhysicalLocationError do Failed := True; end;
  Check(Failed, 'past EOF word index accepted');
  Spans[0].WordIndex := 888;
  Failed := False;
  try P := LocatePhysicalWord(#80, Spans, 1);
  except on E: EPhysicalLocationError do Failed := True; end;
  Check(Failed, 'corrupt word span accepted');

  { Зіпсований останній байт і попередній валідний результат:
    не залишити часткових T5M-слів/physical spans. }
  DecodeT5MWithLocations(
    EncodeT5M(MakeWords(['10','0','01'])), OutWords, Spans);
  Check((Length(OutWords)=3) and (Length(Spans)=3),
    'немає позитивного T5M свідка перед пізньою відмовою');
  Failed := False;
  try DecodeT5MWithLocations(
    EncodeT5M(MakeWords(['10','0','01'])) + #243, OutWords, Spans);
  except on E:ET5MError do Failed:=True; end;
  Check(Failed and (Length(OutWords)=0) and (Length(Spans)=0),
    'пізній недопустимий байт T5M залишив часткові слова/адреси');
  DecodeT5MWithLocations(
    EncodeT5M(MakeWords(['1'])), OutWords, Spans);
  Check((Length(OutWords)=1) and (Length(Spans)=1),
    'T5M не відновився після пізнього помилкового байта');

  Failed := False;
  try Doc := ReadD2WithPhysicalLocations(#243, Spans);
  except on E: ET5MError do Failed := True; end;
  Check(Failed and (Length(Spans)=0),
    'заборонений T5M байт залишив недопущені physical spans');
  Failed := False;
  try Doc := ReadD2WithPhysicalLocations(#242, Spans);
  except on E: ET5MError do Failed := True; end;
  Check(Failed and (Length(Spans)=0),
    'неканонічне T5M заповнення залишило фізичні адреси');

  { Non-semantic deterministic location stress, exact widths 1..9. }
  Cases := 0;
  for I := 1 to 96 do begin
    SetLength(W, (I mod 12) + 1);
    for J := 0 to High(W) do begin
      SetLength(S, ((I + 3*J) mod 9)+1);
      FillChar(S[1], Length(S), Ord('0'));
      if ((I+J) mod 2) = 1 then S[Length(S)] := '1';
      W[J] := S;
    end;
    Physical := EncodeT5M(W);
    DecodeT5MWithLocations(Physical, OutWords, Spans);
    DecodeT5MWithLocations(Physical, OutWords, Again);
    Check(Length(Spans) = Length(W), 'stress wrong count');
    for J := 0 to High(W) do begin
      Check((OutWords[J] = W[J]) and
            (Spans[J].TritStart=Again[J].TritStart) and
            (Spans[J].ByteStart=Again[J].ByteStart),
            'non-deterministic physical source span');
      if J > 0 then
        Check(Spans[J].TritStart = Spans[J-1].TritEnd+1,
              'exact separator not counted');
    end;
    Inc(Cases);
  end;
  WriteLn('PHYSLOC-OK fpc-t5m-word-byte-trit-spans=exact source-errors=located stress=',Cases);
  WriteLn('ФІЗИЧНІ-АДРЕСИ-АТОМАРНО late-D2=6 late-T5M=1 ',
    'out-spans=empty out-words=empty відновлення=так');
  WriteLn('PHYSLOC-SCOPE mechanical-only semantic-oracle=NOT_RUN core4-execution=NOT_PROVEN');
end.
