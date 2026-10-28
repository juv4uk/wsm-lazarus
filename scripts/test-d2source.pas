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

  WriteLn('D2SOURCE-OK FPC pinned-D2=structure D3:000=empty T5M=physical-golden');
  WriteLn('D2SOURCE-SCOPE mechanical-ast-only semantic-callability=NOT_PROVED core4-execution=NOT_PROVED');
end.
