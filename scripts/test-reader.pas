program test_reader;

{$mode objfpc}{$H+}

uses
  sysutils, wsm.values, wsm.reader;

var
  A: TArena;
  ST: TSymbolTable;
  Passes, Fails: LongInt;

procedure Check(C: Boolean; const Name: string);
begin
  if C then Inc(Passes)
  else begin Inc(Fails); WriteLn('FAIL: ', Name); end;
end;

function SymText(V: TValue): RawByteString;
begin
  Check(IsSymbol(V), 'expected symbol');
  if IsSymbol(V) then Result := PAnsiChar(V.sym) else Result := '';
end;

procedure Parse(const S: RawByteString; out R: TReader; out V: TValue);
begin
  ReaderInit(R, S, A, ST);
  V := ReadOne(R);
end;

procedure TestEmptyAndLists;
var R: TReader; V, T: TValue;
begin
  Parse('()', R, V);
  Check(IsNil(V), 'empty list is kVNil');
  Check(ReaderAtEnd(R), 'empty list consumes input');

  Parse('(a b c)', R, V);
  Check(IsPair(V), 'proper list pair');
  Check(SymText(PairHead(V)) = 'a', 'proper list head a');
  T := PairTail(V);
  Check(SymText(PairHead(T)) = 'b', 'proper list second b');
  T := PairTail(T);
  Check(SymText(PairHead(T)) = 'c', 'proper list third c');
  Check(IsNil(PairTail(T)), 'proper list nil tail');

  Parse('(a b . c)', R, V);
  T := PairTail(V);
  Check(SymText(PairHead(T)) = 'b', 'dotted list second b');
  Check(SymText(PairTail(T)) = 'c', 'dotted tail c');
end;

procedure TestQuoteAndApostrophe;
var R: TReader; V, Args: TValue;
begin
  Parse('''x', R, V);
  Check(IsPair(V), 'quote expands to list');
  Check(SymText(PairHead(V)) = 'quote', 'quote structural head');
  Args := PairTail(V);
  Check(SymText(PairHead(Args)) = 'x', 'quote structural operand');
  Check(IsNil(PairTail(Args)), 'quote exactly one operand');

  Parse('''   x', R, V);
  Check(SymText(PairHead(PairTail(V))) = 'x', 'quote allows ignored space');

  Parse('об''єкт', R, V);
  Check(SymText(V) = RawByteString('об''єкт'), 'internal apostrophe stays in symbol');
end;

procedure TestUnknownIsJustSymbol;
var R: TReader; A1, A2: TValue;
begin
  Parse('car', R, A1);
  Parse('never-defined-canon-symbol', R, A2);
  Check(IsSymbol(A1) and IsSymbol(A2), 'known-looking and unknown both symbols');
  Check(SymText(A1) = 'car', 'reader preserves known-looking spelling');
  Check(SymText(A2) = 'never-defined-canon-symbol', 'reader preserves unknown spelling');
end;

procedure TestStrings;
var R: TReader; V: TValue;
begin
  Parse('"a\\n\\t\\\"b"', R, V);
  Check(IsString(V), 'string kind');
  Check(V.strLen = 5, 'string decoded length');
  Check(ValueToDebugString(V) = RawByteString('a' + #10 + #9 + '"b'), 'string escapes');

end;

procedure TestNumbers;
var R: TReader; V: TValue;
begin
  Parse('42', R, V);
  Check(IsNumber(V) and (V.qnum=42) and (V.qden=1), 'integer exact');

  Parse('-0,25', R, V);
  Check(IsNumber(V) and (V.qnum=-1) and (V.qden=4), 'comma decimal exact');

  Parse('12.455', R, V);
  Check(IsNumber(V) and (V.qnum=2491) and (V.qden=200), 'dot decimal exact');

  Parse('1,5e3', R, V);
  Check(IsNumber(V) and (V.qnum=1500) and (V.qden=1), 'scientific exact');

  Parse('5/336', R, V);
  Check(IsNumber(V) and (V.qnum=5) and (V.qden=336), 'slash rational exact');

  Parse('10/20', R, V);
  Check(IsNumber(V) and (V.qnum=1) and (V.qden=2), 'slash rational reduced');

  Parse('1/0', R, V);
  Check(IsSymbol(V), 'zero denominator falls back to symbol');

  Parse('.5', R, V);
  Check(IsNumber(V) and (V.qnum=1) and (V.qden=2), 'leading-dot decimal exact');

  Parse('5.', R, V);
  Check(IsNumber(V) and (V.qnum=5) and (V.qden=1), 'trailing-dot decimal exact');

  Parse('0e100', R, V);
  Check(IsNumber(V) and (V.qnum=0) and (V.qden=1), 'zero with large exponent stays exact zero');

  Parse('а,б', R, V);
  Check(IsSymbol(V), 'comma non-number remains symbol');

  Parse('1.2.3', R, V);
  Check(IsSymbol(V), 'malformed numeric-looking token remains symbol');

  Parse('999999999999999999999x', R, V);
  Check(IsSymbol(V), 'overflowing prefix does not reclassify malformed token');

  Parse('.?', R, V);
  Check(IsSymbol(V) and (SymText(V) = '.?'), 'symbolic Canon spelling .? stays symbol');
end;

procedure ExpectReaderError(const S, Name: RawByteString);
var R: TReader; V: TValue; Raised: Boolean;
begin
  Raised := False;
  try
    Parse(S, R, V);
  except
    on E: EReaderError do Raised := True;
  end;
  Check(Raised, string(Name));
end;

procedure ExpectNumericOverflow(const S, Name: RawByteString);
var R: TReader; V: TValue; Raised: Boolean;
begin
  Raised := False;
  try
    Parse(S, R, V);
  except
    on E: EReaderNumericOverflow do Raised := True;
  end;
  Check(Raised, string(Name));
end;

procedure TestErrors;
var Deep: RawByteString;
begin
  ExpectReaderError('(', 'unterminated list errors');
  ExpectReaderError('"abc', 'unterminated string errors');
  ExpectReaderError('"a\\qb"', 'unsupported escape fails closed');
  ExpectReaderError('(a . b c)', 'invalid dotted pair errors');
  ExpectReaderError(')', 'unexpected close errors');
  ExpectNumericOverflow('9223372036854775808', 'large exact integer is NumericOverflow');
  ExpectNumericOverflow('1e19', 'out-of-M0 exact exponent is NumericOverflow');

  Deep := RawByteString(StringOfChar('(', 800) + '42' + StringOfChar(')', 800));
  ExpectReaderError(Deep, 'deep nesting fails named before stack overflow');
end;

begin
  ArenaInit(A);
  SymbolTableReset(ST);
  try
    TestEmptyAndLists;
    TestQuoteAndApostrophe;
    TestUnknownIsJustSymbol;
    TestStrings;
    TestNumbers;
    TestErrors;
  finally
    ArenaReset(A);
  end;

  WriteLn('READER: pass=', Passes, ' fail=', Fails);
  if Fails <> 0 then Halt(1);
end.
