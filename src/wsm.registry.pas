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
 * SID8-ONLY (issue #24, ecosystem#16, 2026-09-23 · owner correction
 * 2026-09-23: "%00000001 - це не наш сід, це підміна"): TSid8 is an
 * OPAQUE record with a `strict private` field, not a bare Byte alias.
 * A plain `TSid8 = Byte` was tried first and rejected -- FPC treats
 * %00000001, %1, %01 and plain 1 as one indistinguishable value with
 * no memory of ever being an exact eight-character spelling, so any
 * Byte could silently pass itself off as a SID with no way to tell a
 * validated identity from an arbitrary number. That is exactly what
 * my-lisp's own Sid8(u8) (crates/my-lisp/src/sid.rs) already guards
 * against on the Rust side: "the packed byte is a private
 * runtime/transport mechanism and is never the public semantic name
 * of the SID" -- its field is private, constructible only through the
 * width-validating sid! macro.
 *
 * TSid8 ITSELF NOW LIVES IN wsm.values.pas (issue #32, 2026-09-23 --
 * owner: "спочатку нам тре визнати що сід це функції мови ... парсер
 * вже має знати повне таблицю"): the general reader (wsm.reader.pas)
 * needed to recognize the SID token SHAPE natively, for every pinned
 * file, not just this unit's own narrow registry lexer -- see
 * wsm.values.pas's header comment for the full rationale. This unit
 * now reuses that shared type instead of declaring its own; nothing
 * about registry parsing itself changed.
 *)
unit wsm.registry;

{$mode objfpc}{$H-}

interface

uses
  sysutils, wsm.values;

type
  ERegistryError = class(EValueError);

  TRegistryEntry = record
    ID: TSid8;
    Spellings: array of RawByteString;
  end;

  TRegistry = record
    Entries: array of TRegistryEntry;
  end;

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
  entry.ID := TSid8.FromExact(tok);

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
