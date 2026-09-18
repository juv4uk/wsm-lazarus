(* wsm.reader.pas — syntax-only reader for the pinned my-lisp surface (M0.4).
 *
 * This unit turns bytes into structural TValue data. It does NOT resolve
 * semantic IDs, dispatch operators, inspect the Canon registry, or evaluate.
 * Contract-owned syntax handled here:
 *   - lists and dotted pairs
 *   - strings
 *   - exact M0 integers / finite base-10 decimals
 *   - symbols
 *   - Contract 4.0 apostrophe: leading 'form => (quote form), while an
 *     apostrophe inside a token remains an ordinary symbol byte.
 *)
unit wsm.reader;

{$mode objfpc}{$H-}

interface

uses
  sysutils, wsm.values;

type
  EReaderError = class(Exception);

  TReader = record
    input: RawByteString;
    pos: SizeInt;   { 1-based byte offset }
    line: SizeInt;
    column: SizeInt;
    arena: ^TArena;
    symbols: ^TSymbolTable;
  end;

procedure ReaderInit(
  out r: TReader;
  const input: RawByteString;
  var arena: TArena;
  var symbols: TSymbolTable
);
function ReadOne(var r: TReader): TValue;
function ReaderAtEnd(var r: TReader): Boolean;

implementation

function Peek(const r: TReader): AnsiChar;
begin
  if r.pos > Length(r.input) then
    Result := #0
  else
    Result := r.input[r.pos];
end;

procedure Advance(var r: TReader);
var
  ch: AnsiChar;
begin
  if r.pos > Length(r.input) then Exit;
  ch := r.input[r.pos];
  Inc(r.pos);
  if ch = #10 then
  begin
    Inc(r.line);
    r.column := 1;
  end
  else
    Inc(r.column);
end;

procedure Fail(const r: TReader; const msg: RawByteString);
begin
  raise EReaderError.CreateFmt(
    'reader:%d:%d: %s',
    [r.line, r.column, string(msg)]
  );
end;

function IsWhitespace(ch: AnsiChar): Boolean;
begin
  Result := ch in [' ', #9, #10, #13];
end;

procedure SkipSpaceAndComments(var r: TReader);
begin
  while True do
  begin
    while IsWhitespace(Peek(r)) do
      Advance(r);

    if Peek(r) <> ';' then Exit;
    while (Peek(r) <> #0) and (Peek(r) <> #10) do
      Advance(r);
  end;
end;

function IsDelimiter(ch: AnsiChar): Boolean;
begin
  Result := (ch = #0) or IsWhitespace(ch) or
            (ch = '(') or (ch = ')') or (ch = '"') or (ch = ';');
end;

function RawSlice(const s: RawByteString; startPos, count: SizeInt): RawByteString;
begin
  if count <= 0 then
    Result := ''
  else
    Result := Copy(s, startPos, count);
end;

function MakeSymbolBytes(var r: TReader; const s: RawByteString): TValue;
var
  p: PAnsiChar;
begin
  if Length(s) = 0 then
    p := nil
  else
    p := PAnsiChar(s);
  Result := InternSymbol(r.arena^, r.symbols^, p, Length(s));
end;

function CheckedMul10(v: Int64; const r: TReader): Int64;
begin
  if (v > High(Int64) div 10) or (v < Low(Int64) div 10) then
    Fail(r, 'numeric literal exceeds M0 Int64 boundary');
  Result := v * 10;
end;

function CheckedAddDigit(v: Int64; digit: Integer; negative: Boolean;
  const r: TReader): Int64;
begin
  if negative then
  begin
    if v < (Low(Int64) + digit) div 10 then
      Fail(r, 'numeric literal exceeds M0 Int64 boundary');
    Result := v * 10 - digit;
  end
  else
  begin
    if v > (High(Int64) - digit) div 10 then
      Fail(r, 'numeric literal exceeds M0 Int64 boundary');
    Result := v * 10 + digit;
  end;
end;

function Pow10Checked(n: Integer; const r: TReader): Int64;
var
  i: Integer;
begin
  Result := 1;
  for i := 1 to n do
    Result := CheckedMul10(Result, r);
end;

function TryExactNumber(const token: RawByteString; const r: TReader;
  out value: TValue): Boolean;
var
  i, digitsAfter, expValue, expSign, exponent, scale: Integer;
  negative, sawDigit, sawSep, sawExp, expDigits: Boolean;
  ch: AnsiChar;
  mantissa, factor, den: Int64;
begin
  Result := False;
  if Length(token) = 0 then Exit;

  i := 1;
  negative := False;
  if token[i] in ['+', '-'] then
  begin
    negative := token[i] = '-';
    Inc(i);
    if i > Length(token) then Exit;
  end;

  mantissa := 0;
  digitsAfter := 0;
  sawDigit := False;
  sawSep := False;
  sawExp := False;

  while i <= Length(token) do
  begin
    ch := token[i];
    if ch in ['0'..'9'] then
    begin
      sawDigit := True;
      mantissa := CheckedAddDigit(mantissa, Ord(ch)-Ord('0'), negative, r);
      if sawSep and not sawExp then Inc(digitsAfter);
      Inc(i);
      Continue;
    end;

    if (ch in ['.', ',']) and not sawSep and not sawExp then
    begin
      sawSep := True;
      Inc(i);
      Continue;
    end;

    if (ch in ['e', 'E']) and sawDigit and not sawExp then
    begin
      sawExp := True;
      Inc(i);
      Break;
    end;

    Exit;
  end;

  if not sawDigit then Exit;
  if sawSep and (digitsAfter = 0) then Exit;

  exponent := 0;
  if sawExp then
  begin
    if i > Length(token) then Exit;
    expSign := 1;
    if token[i] in ['+', '-'] then
    begin
      if token[i] = '-' then expSign := -1;
      Inc(i);
    end;
    if i > Length(token) then Exit;

    expValue := 0;
    expDigits := False;
    while i <= Length(token) do
    begin
      ch := token[i];
      if not (ch in ['0'..'9']) then Exit;
      expDigits := True;
      if expValue > 100000 then
        Fail(r, 'numeric exponent exceeds reader boundary');
      expValue := expValue * 10 + (Ord(ch)-Ord('0'));
      Inc(i);
    end;
    if not expDigits then Exit;
    exponent := expSign * expValue;
  end;

  if i <= Length(token) then Exit;

  scale := digitsAfter - exponent;
  if scale >= 0 then
  begin
    if scale > 18 then
      Fail(r, 'exact decimal denominator exceeds M0 Int64 boundary');
    den := Pow10Checked(scale, r);
    value := MakeNumber(mantissa, den);
  end
  else
  begin
    if -scale > 18 then
      Fail(r, 'exact decimal numerator exceeds M0 Int64 boundary');
    factor := Pow10Checked(-scale, r);
    if mantissa <> 0 then
    begin
      if (mantissa > 0) and (mantissa > High(Int64) div factor) then
        Fail(r, 'exact decimal numerator exceeds M0 Int64 boundary');
      if (mantissa < 0) and (mantissa < Low(Int64) div factor) then
        Fail(r, 'exact decimal numerator exceeds M0 Int64 boundary');
    end;
    value := MakeNumber(mantissa * factor, 1);
  end;

  Result := True;
end;

function ReadExpr(var r: TReader): TValue; forward;

function ReadString(var r: TReader): TValue;
var
  buf: RawByteString;
  ch: AnsiChar;
  p: PAnsiChar;
begin
  Advance(r); { opening quote }
  buf := '';
  while True do
  begin
    ch := Peek(r);
    if ch = #0 then Fail(r, 'unterminated string');
    if ch = '"' then
    begin
      Advance(r);
      Break;
    end;

    if ch = '\\' then
    begin
      Advance(r);
      ch := Peek(r);
      if ch = #0 then Fail(r, 'unterminated string escape');
      case ch of
        'n': buf := buf + #10;
        'r': buf := buf + #13;
        't': buf := buf + #9;
        '"': buf := buf + '"';
        '\\': buf := buf + '\\';
      else
        Fail(r, 'unsupported string escape');
      end;
      Advance(r);
    end
    else
    begin
      buf := buf + ch;
      Advance(r);
    end;
  end;

  if Length(buf) = 0 then p := nil else p := PAnsiChar(buf);
  Result := MakeString(r.arena^, p, Length(buf));
end;

function ReadToken(var r: TReader): TValue;
var
  startPos: SizeInt;
  token: RawByteString;
  numberValue: TValue;
begin
  startPos := r.pos;
  while not IsDelimiter(Peek(r)) do
  begin
    { A leading apostrophe is handled by ReadExpr. Inside a token it is data. }
    if Peek(r) = ')' then Break;
    Advance(r);
  end;

  token := RawSlice(r.input, startPos, r.pos - startPos);
  if Length(token) = 0 then Fail(r, 'expected token');

  if TryExactNumber(token, r, numberValue) then
    Result := numberValue
  else
    Result := MakeSymbolBytes(r, token);
end;

function ReadList(var r: TReader): TValue;
var
  head, tail, node, item, dottedTail: TValue;
  first, dotted: Boolean;
begin
  Advance(r); { '(' }
  SkipSpaceAndComments(r);
  if Peek(r) = ')' then
  begin
    Advance(r);
    Exit(MakeNil);
  end;

  first := True;
  dotted := False;
  head := MakeNil;
  tail := MakeNil;

  while True do
  begin
    SkipSpaceAndComments(r);
    if Peek(r) = #0 then Fail(r, 'unterminated list');

    if Peek(r) = ')' then
    begin
      Advance(r);
      Break;
    end;

    { Dot is special only as a complete list token. }
    if Peek(r) = '.' then
    begin
      Advance(r);
      if not IsDelimiter(Peek(r)) then
      begin
        { Symbol beginning with dot: rewind and read normally. }
        Dec(r.pos);
        Dec(r.column);
      end
      else
      begin
        if first or dotted then Fail(r, 'misplaced dotted-pair marker');
        dotted := True;
        SkipSpaceAndComments(r);
        dottedTail := ReadExpr(r);
        SkipSpaceAndComments(r);
        if Peek(r) <> ')' then Fail(r, 'dotted pair must end after one tail');
        Advance(r);
        tail.pair^.tail := dottedTail;
        Break;
      end;
    end;

    if dotted then Fail(r, 'expression after dotted tail');

    item := ReadExpr(r);
    node := MakePair(r.arena^, item, MakeNil);
    if first then
    begin
      head := node;
      tail := node;
      first := False;
    end
    else
    begin
      tail.pair^.tail := node;
      tail := node;
    end;
  end;

  Result := head;
end;

function ReadQuote(var r: TReader): TValue;
var
  quoteSym, quoted, inner: TValue;
begin
  Advance(r); { apostrophe; ReadExpr itself owns following whitespace/comments }
  quoteSym := MakeSymbolBytes(r, 'quote');
  quoted := ReadExpr(r);
  inner := MakePair(r.arena^, quoted, MakeNil);
  Result := MakePair(r.arena^, quoteSym, inner);
end;

function ReadExpr(var r: TReader): TValue;
begin
  SkipSpaceAndComments(r);
  case Peek(r) of
    #0: Fail(r, 'unexpected EOF');
    '(' : Result := ReadList(r);
    ')' : Fail(r, 'unexpected closing parenthesis');
    '"' : Result := ReadString(r);
    '''': Result := ReadQuote(r);
  else
    Result := ReadToken(r);
  end;
end;

procedure ReaderInit(
  out r: TReader;
  const input: RawByteString;
  var arena: TArena;
  var symbols: TSymbolTable
);
begin
  r.input := input;
  r.pos := 1;
  r.line := 1;
  r.column := 1;
  r.arena := @arena;
  r.symbols := @symbols;
end;

function ReadOne(var r: TReader): TValue;
begin
  Result := ReadExpr(r);
end;

function ReaderAtEnd(var r: TReader): Boolean;
begin
  SkipSpaceAndComments(r);
  Result := Peek(r) = #0;
end;

end.
