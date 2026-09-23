(* wsm.registry.pas — M0.5 semantic registry bridge (issue #7).
 *
 * Reads the pinned lib/surface/semantic-registry.lisp as a NARROW,
 * purpose-built registry schema -- deliberately not through wsm.reader's
 * general Lisp reader (#7's own instruction). The registry format is
 * regular enough (one flat row per semantic identity, five fixed tagged
 * fields) that a dedicated parser is more mechanical and cannot silently
 * pick up unrelated future reader syntax changes.
 *
 * This unit resolves a surface spelling (any of the en/ук/укр/sa/sym
 * columns) to its canonical semantic ID. It does NOT interpret what any
 * ID means, does NOT implement car/cdr/eq/... semantics, and does NOT
 * dispatch anything -- that is explicitly M0.6/wsm.eval's job (#8), not
 * this unit's.
 *
 * SID8-ONLY (issue #24, ecosystem#16, 2026-09-23): the semantic ID is
 * parsed from its bare eight-bit binary source spelling (e.g. the atom
 * 00000001, never a quoted string) into TSid8 = Byte -- the identity
 * downstream code carries and compares is the packed byte, never text.
 * A string/quoted rendering of the same value is itself a forbidden
 * second identity under SID8-ONLY, not a harmless intermediate step.
 * ParseSid8 validates exactly eight '0'/'1' characters before packing,
 * so a malformed or wrong-width source lexeme fails closed at parse
 * time rather than silently keeping leading zeros as string data (the
 * concern #7's original acceptance gate (4) raised, now satisfied by
 * width-checked packing instead of by staying textual). Sid8ToBinaryString
 * exists solely to render a TSid8 back to its eight-character spelling
 * for human-facing error messages -- display only, never a dispatch key.
 *)
unit wsm.registry;

{$mode objfpc}{$H-}

interface

uses
  sysutils, wsm.values;

type
  ERegistryError = class(EValueError);

  { The one function-identity representation: an exact packed eight-bit
    token, matching my-lisp's own Sid8(u8) (crates/my-lisp/src/sid.rs)
    bit-for-bit. Never a string, decimal, or hex alias (SID8-ONLY,
    issue #24). }
  TSid8 = Byte;

  TRegistryEntry = record
    ID: TSid8;
    Spellings: array of RawByteString;
  end;

  TRegistry = record
    Entries: array of TRegistryEntry;
  end;

{ Parses an exact eight-character '0'/'1' source lexeme into its packed
  TSid8, most-significant-bit first (matching my-lisp's own
  Sid8::__from_macro_spelling bit order exactly, so a value round-trips
  identically across substrates). Raises ERegistryError on any width or
  character violation -- a malformed SID fails closed, it is never
  coerced or truncated. }
function ParseSid8(const text: RawByteString): TSid8;

{ Tags a raw byte as a TSid8, unchanged -- for hardcoding a known
  dispatch identity directly in Pascal source (e.g. wsm.eval's
  ID_QUOTE), authored with FPC's own native binary-literal syntax:
  SID8(%00000001). The value passes through exactly as written: no
  parsing, no decomposition into bits, no recombination, no text
  anywhere. This is not validation -- there is nothing to validate,
  since a `Byte` parameter is already, structurally, eight bits and
  no more or fewer. It exists purely so a call site reads as "this
  literal is a semantic identity," the same role RegistryLookup's own
  `spelling` parameter plays for surface text. }
function SID8(const raw: Byte): TSid8; inline;

{ Renders a TSid8 back to its eight-character binary spelling. Display
  only, for human-facing error messages -- never use this to reconstruct
  a dispatch key or to compare identities. }
function Sid8ToBinaryString(v: TSid8): RawByteString;

{ Parses the full registry source text (as read verbatim from the pinned
  lib/surface/semantic-registry.lisp file) into an in-memory lookup
  table. Raises ERegistryError on any malformed row. }
procedure RegistryLoad(out reg: TRegistry; const source: RawByteString);

{ Resolves a surface spelling (matched byte-for-byte against any column
  of any row -- en/ук/укр/sa/sym alike, "one identity for aliases/
  surfaces" per #7) to its canonical semantic ID. Returns False, leaving
  id undefined, for any spelling not present in the pinned registry --
  an unknown symbol must never acquire invented semantics by guessing. }
function RegistryLookup(const reg: TRegistry; const spelling: RawByteString;
  out id: TSid8): Boolean;

implementation

function ParseSid8(const text: RawByteString): TSid8;
var
  i: Integer;
  bits: Byte;
  ch: AnsiChar;
begin
  if Length(text) <> 8 then
    raise ERegistryError.CreateFmt(
      'ParseSid8: expected exactly 8 characters, got %d ("%s")',
      [Length(text), text]);
  bits := 0;
  for i := 1 to 8 do
  begin
    ch := text[i];
    if (ch <> '0') and (ch <> '1') then
      raise ERegistryError.CreateFmt(
        'ParseSid8: expected only ''0''/''1'' characters, got "%s"', [text]);
    bits := (bits shl 1) or (Ord(ch) - Ord('0'));
  end;
  Result := bits;
end;

function SID8(const raw: Byte): TSid8; inline;
begin
  Result := raw;
end;

function Sid8ToBinaryString(v: TSid8): RawByteString;
var
  i: Integer;
begin
  SetLength(Result, 8);
  for i := 8 downto 1 do
  begin
    if (v and 1) = 1 then
      Result[i] := '1'
    else
      Result[i] := '0';
    v := v shr 1;
  end;
end;

type
  TTokenKind = (tkOpen, tkClose, tkAtom, tkString, tkEOF);

  TLexer = record
    input: RawByteString;
    pos: SizeInt;   { 1-based byte offset }
    line: SizeInt;
  end;

procedure LexInit(out lx: TLexer; const input: RawByteString);
begin
  lx.input := input;
  lx.pos := 1;
  lx.line := 1;
end;

function LexPeekChar(const lx: TLexer): AnsiChar;
begin
  if lx.pos > Length(lx.input) then
    Result := #0
  else
    Result := lx.input[lx.pos];
end;

procedure LexAdvanceChar(var lx: TLexer);
begin
  if lx.pos > Length(lx.input) then Exit;
  if lx.input[lx.pos] = #10 then Inc(lx.line);
  Inc(lx.pos);
end;

function IsRegistryDelimiter(ch: AnsiChar): Boolean;
begin
  Result := (ch = '(') or (ch = ')') or (ch = '"') or
            (ch = ' ') or (ch = #9) or (ch = #10) or (ch = #13) or (ch = #0);
end;

procedure LexSkipTrivia(var lx: TLexer);
begin
  while True do
  begin
    case LexPeekChar(lx) of
      ' ', #9, #10, #13: LexAdvanceChar(lx);
      ';':
        while (LexPeekChar(lx) <> #10) and (LexPeekChar(lx) <> #0) do
          LexAdvanceChar(lx);
    else
      Exit;
    end;
  end;
end;

{ One token of the narrow registry syntax: (  )  bare-atom  "string".
  A quoted string is taken VERBATIM between the two quote characters --
  in particular (sym "'") yields the one-character string "'" itself,
  never re-interpreted as this file's own quote-sugar. That is exactly
  #7's own apostrophe edge case: a surface token of the registry schema,
  not quote sugar. }
function LexNext(var lx: TLexer; out kind: TTokenKind): RawByteString;
var
  start: SizeInt;
  ch: AnsiChar;
begin
  LexSkipTrivia(lx);
  ch := LexPeekChar(lx);
  if ch = #0 then
  begin
    kind := tkEOF;
    Result := '';
    Exit;
  end;
  if ch = '(' then
  begin
    LexAdvanceChar(lx);
    kind := tkOpen;
    Result := '(';
    Exit;
  end;
  if ch = ')' then
  begin
    LexAdvanceChar(lx);
    kind := tkClose;
    Result := ')';
    Exit;
  end;
  if ch = '"' then
  begin
    LexAdvanceChar(lx);
    start := lx.pos;
    while LexPeekChar(lx) <> '"' do
    begin
      if LexPeekChar(lx) = #0 then
        raise ERegistryError.CreateFmt(
          'registry:%d: unterminated string literal', [lx.line]);
      LexAdvanceChar(lx);
    end;
    kind := tkString;
    Result := Copy(lx.input, start, lx.pos - start);
    LexAdvanceChar(lx); { consume closing quote }
    Exit;
  end;
  start := lx.pos;
  while not IsRegistryDelimiter(LexPeekChar(lx)) do
    LexAdvanceChar(lx);
  kind := tkAtom;
  Result := Copy(lx.input, start, lx.pos - start);
end;

procedure ExpectKind(var lx: TLexer; expected: TTokenKind;
  const context: RawByteString);
var
  kind: TTokenKind;
begin
  LexNext(lx, kind);
  if kind <> expected then
    raise ERegistryError.CreateFmt('registry:%d: expected %s',
      [lx.line, context]);
end;

{ Parses one (tag value) pair, assuming the opening ( has already been
  consumed by the caller. The tag itself (en/ук/укр/sa/sym) is read and
  discarded -- callers key spellings purely by value, never by which
  language column produced them, matching "one identity for aliases/
  surfaces" (#7). Returns '' for an explicit empty-list value (), meaning
  "no spelling recorded for this tag in this row". }
function ParseTaggedValue(var lx: TLexer): RawByteString;
var
  kind: TTokenKind;
  valueTok: RawByteString;
begin
  LexNext(lx, kind); { the tag: consumed, intentionally unused }
  if kind <> tkAtom then
    raise ERegistryError.CreateFmt('registry:%d: expected field tag',
      [lx.line]);

  valueTok := LexNext(lx, kind);
  if kind = tkOpen then
  begin
    ExpectKind(lx, tkClose, 'empty-list close ) after (');
    Result := '';
  end
  else if (kind = tkAtom) or (kind = tkString) then
    Result := valueTok
  else
    raise ERegistryError.CreateFmt(
      'registry:%d: unexpected token in field value', [lx.line]);

  ExpectKind(lx, tkClose, ') closing (tag value)');
end;

{ Parses one row's body, assuming the row's opening ( has already been
  consumed by the caller. }
procedure ParseRowBody(var lx: TLexer; out entry: TRegistryEntry);
var
  kind: TTokenKind;
  tok, value: RawByteString;
  spellings: array of RawByteString;
  n: SizeInt;
begin
  tok := LexNext(lx, kind);
  if kind <> tkAtom then
    raise ERegistryError.CreateFmt('registry:%d: expected ID lexeme',
      [lx.line]);
  entry.ID := ParseSid8(tok);

  SetLength(spellings, 0);
  while True do
  begin
    tok := LexNext(lx, kind);
    if kind = tkClose then Break;
    if kind <> tkOpen then
      raise ERegistryError.CreateFmt(
        'registry:%d: expected (tag value) or row-closing )', [lx.line]);
    value := ParseTaggedValue(lx);
    if value <> '' then
    begin
      n := Length(spellings);
      SetLength(spellings, n + 1);
      spellings[n] := value;
    end;
  end;
  entry.Spellings := spellings;
end;

procedure RegistryLoad(out reg: TRegistry; const source: RawByteString);
var
  lx: TLexer;
  kind: TTokenKind;
  tok: RawByteString;
  n: SizeInt;
  entry: TRegistryEntry;
begin
  LexInit(lx, source);
  ExpectKind(lx, tkOpen, 'registry-opening (');
  SetLength(reg.Entries, 0);
  while True do
  begin
    tok := LexNext(lx, kind);
    if kind = tkClose then Break;
    if kind <> tkOpen then
      raise ERegistryError.CreateFmt(
        'registry:%d: expected row or registry-closing ), got "%s"',
        [lx.line, tok]);
    ParseRowBody(lx, entry);
    n := Length(reg.Entries);
    SetLength(reg.Entries, n + 1);
    reg.Entries[n] := entry;
  end;
  ExpectKind(lx, tkEOF, 'end of input after registry');
end;

function RegistryLookup(const reg: TRegistry; const spelling: RawByteString;
  out id: TSid8): Boolean;
var
  i, j: SizeInt;
begin
  for i := 0 to High(reg.Entries) do
    for j := 0 to High(reg.Entries[i].Spellings) do
      if reg.Entries[i].Spellings[j] = spelling then
      begin
        id := reg.Entries[i].ID;
        Result := True;
        Exit;
      end;
  Result := False;
end;

end.
