(* test-values.pas — M0.3 tests for physical value/storage mechanics.
 * No evaluator or semantic registry is involved. *)
program test_values;

{$mode objfpc}{$H+}

uses
  sysutils,
  wsm.values;

var
  a: TArena;
  st: TSymbolTable;
  npass, nfail: Int32;

procedure Check(cond: Boolean; const what: RawByteString);
begin
  if cond then
    Inc(npass)
  else
  begin
    Inc(nfail);
    WriteLn('FAIL: ', what);
  end;
end;

function SameNumber(a, b: TValue): Boolean;
begin
  Result := IsNumber(a) and IsNumber(b) and
            (a.qnum = b.qnum) and (a.qden = b.qden);
end;

var
  nilv, unbound, p, nested, one, half, minusHalf: TValue;
  s1, s2, s1b, emptySym: TValue;
  str1, str2, empty1, empty2, badPair, afterReset: TValue;
  alphaName, betaName, helloText, worldText: RawByteString;
  dbg1, dbg2, generatedName: RawByteString;
  raised: Boolean;
  largeBlock: PByte;
  i: Integer;
begin
  npass := 0;
  nfail := 0;
  ArenaInit(a);
  SymbolTableReset(st);

  alphaName := 'alpha';
  betaName := 'beta';
  helloText := 'hello';
  worldText := 'world';

  nilv := MakeNil;
  unbound := MakeUnbound;
  Check(IsNil(nilv), 'empty-list value has kVNil kind');
  Check(not IsNil(unbound), 'unbound marker is not empty-list value');
  Check(IsUnbound(unbound), 'unbound marker has kUnbound kind');
  Check(not IsPair(nilv), 'empty-list value is not a pair');
  Check(nilv.kind <> unbound.kind, 'empty-list and unbound kinds are distinct');
  Check(IsNil(nilv) and not IsUnbound(nilv), 'empty-list storage tag is unambiguous');
  Check(IsUnbound(unbound) and not IsNil(unbound), 'unbound storage tag is unambiguous');

  p := MakePair(a, MakeNumber(1, 2), MakeNil);
  Check(IsPair(p), 'pair constructor yields pair kind');
  Check(SameNumber(PairHead(p), MakeNumber(1, 2)), 'pair head roundtrip');
  Check(IsNil(PairTail(p)), 'pair tail roundtrip');

  nested := MakePair(a, p, p);
  Check(
    IsPair(PairHead(nested)) and IsPair(PairTail(nested)) and
    (PairHead(nested).pair = p.pair) and (PairTail(nested).pair = p.pair),
    'nested pair preserves opaque pair handle identity'
  );

  one := MakeNumber(1, 1);
  half := MakeNumber(1, 2);
  minusHalf := MakeNumber(-1, 2);
  Check(SameNumber(one, MakeNumber(2, 2)), '2/2 normalizes to 1/1');
  Check(SameNumber(half, MakeNumber(2, 4)), '2/4 normalizes to 1/2');
  Check(
    SameNumber(minusHalf, MakeNumber(2, -4)),
    'negative denominator normalizes into numerator sign'
  );
  Check(IsNumber(one) and (one.qden > 0), 'normalized denominator is positive');
  Check(
    SameNumber(MakeNumber(0, 5), MakeNumber(0, 1)),
    'zero numerator normalizes denominator to one'
  );
  Check(
    MakeNumber(Low(Int64), 1).qnum = Low(Int64),
    'minimum Int64 numerator remains representable'
  );
  Check(
    MakeNumber(Low(Int64), -2).qnum = Int64(4611686018427387904),
    'minimum Int64 reduces before sign normalization'
  );

  raised := False;
  try
    MakeNumber(Low(Int64), -1);
  except
    on E: EValueError do
      raised := True;
  end;
  Check(raised, 'unrepresentable positive 2^63 is rejected');

  raised := False;
  try
    MakeNumber(1, 0);
  except
    on E: EValueError do
      raised := True;
  end;
  Check(raised, 'zero denominator is rejected');

  s1 := InternSymbol(a, st, PAnsiChar(alphaName), Length(alphaName));
  s2 := InternSymbol(a, st, PAnsiChar(betaName), Length(betaName));
  s1b := InternSymbol(a, st, PAnsiChar(alphaName), Length(alphaName));
  emptySym := InternSymbol(a, st, nil, 0);
  Check(IsSymbol(s1) and IsSymbol(s2), 'interned values have symbol kind');
  Check(s1.sym = s1b.sym, 'same symbol bytes reuse one handle');
  Check(s1.sym <> s2.sym, 'different symbol bytes use different handles');
  Check(emptySym.sym <> nil, 'empty symbol still owns a stable arena handle');

  for i := 1 to 1500 do
  begin
    generatedName := RawByteString(Format('generated-symbol-%d', [i]));
    s2 := InternSymbol(a, st, PAnsiChar(generatedName), Length(generatedName));
  end;
  Check(st.count > 1024, 'symbol table grows beyond former silent 1024 ceiling');
  Check(
    Length(st.entries) >= st.count,
    'dynamic symbol-table capacity covers every interned handle'
  );
  s1b := InternSymbol(a, st, PAnsiChar(alphaName), Length(alphaName));
  Check(
    s1b.sym = s1.sym,
    'symbol interning identity survives host table growth'
  );

  str1 := MakeString(a, PAnsiChar(helloText), Length(helloText));
  str2 := MakeString(a, PAnsiChar(worldText), Length(worldText));
  Check(
    (str1.strLen = Length(helloText)) and (str2.strLen = Length(worldText)),
    'string lengths are explicit'
  );
  Check(str1.str <> str2.str, 'different strings occupy distinct arena regions');
  Check(
    ValueToDebugString(str1) =
      ValueToDebugString(MakeString(a, PAnsiChar(helloText), Length(helloText))),
    'string storage preserves equal byte content without production equality API'
  );
  Check(
    ValueToDebugString(str1) <> ValueToDebugString(str2),
    'different string storage preserves different byte content'
  );

  empty1 := MakeString(a, nil, 0);
  empty2 := MakeString(a, nil, 0);
  Check(
    (empty1.strLen = 0) and (empty2.strLen = 0),
    'zero-length strings are represented without dereference'
  );

  Check(ValueToDebugString(str1) = helloText, 'debug string preserves full string bytes');
  dbg1 := ValueToDebugString(MakeNumber(1, 2));
  dbg2 := ValueToDebugString(MakeNumber(3, 4));
  Check(dbg1 = '1/2', 'debug number result survives later debug conversion');
  Check(dbg2 = '3/4', 'second debug number conversion is correct');

  badPair.kind := kPair;
  badPair.pair := nil;
  raised := False;
  try
    PairHead(badPair);
  except
    on E: EValueError do
      raised := True;
  end;
  Check(raised, 'nil pair handle is rejected');

  raised := False;
  try
    MakeString(a, nil, -1);
  except
    on E: EValueError do
      raised := True;
  end;
  Check(raised, 'negative string length is rejected');

  largeBlock := ArenaAlloc(a, (1 shl 16) + 32);
  Check(largeBlock <> nil, 'arena supports allocation larger than default block');

  Check(Length(a.blocks) > 0, 'arena owns allocated blocks before reset');
  ArenaReset(a);
  SymbolTableReset(st);
  Check(
    (Length(a.blocks) = 0) and (a.cur = nil) and (a.lim = nil),
    'arena reset releases all blocks and clears cursor state'
  );
  Check(
    (st.count = 0) and (Length(st.entries) = 0),
    'symbol table reset clears stale arena handles and host capacity'
  );

  afterReset := MakePair(a, MakeNil, MakeNil);
  Check(
    IsNil(PairHead(afterReset)) and IsNil(PairTail(afterReset)),
    'arena remains usable after reset'
  );

  ArenaReset(a);
  SymbolTableReset(st);

  WriteLn('VALUES: pass=', npass, ' fail=', nfail);
  if nfail > 0 then
    Halt(1);
end.
