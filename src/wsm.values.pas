(* wsm.values.pas — FPC substrate value representation (M0.3).
 *
 * No Lisp evaluation semantics live here. This unit owns only the physical
 * representation and storage mechanics needed by later layers:
 *   kVNil     — the empty-list value, distinct from every host nil pointer;
 *   kUnbound  — the unbound marker, distinct from the empty list;
 *   kPair     — arena-owned pair handle;
 *   kNumber   — normalized exact rational inside the M0 Int64 boundary;
 *   kSymbol   — interned arena-owned byte string;
 *   kString   — arena-owned bytes plus explicit length;
 *   kSid      — an exact eight-bit function/semantic identity (TSid8).
 *
 * Surface operator names are intentionally absent from the API. Later semantic
 * dispatch must arrive through the pinned registry/ID bridge, not this unit.
 *
 * SID8 NATIVE RECOGNITION (issue #32, 2026-09-23 -- owner: "спочатку нам
 * тре визнати що сід це функції мови ... парсер вже має знати повне
 * таблицю, потім використовувати сід як функції"): TSid8 used to live one
 * layer up, in the registry bridge unit, built only by that unit's own
 * narrow lexer for the pinned semantic registry file. That left every
 * OTHER pinned file containing SID-shaped tokens
 * (contracts/core1-historical-sid-map.lisp, and any future one) unsafe
 * to read with the general syntax-only reader unit: a token like
 * "00000010" would parse as the ordinary DECIMAL number 10, not the
 * bit-pattern 2 -- the exact confusion issue #24 already fixed once for
 * the registry file specifically. TSid8 moves down to this unit so the
 * general reader can recognize the SID token SHAPE (exactly eight
 * '0'/'1' characters) natively and directly, during ordinary
 * tokenization, for every pinned file -- purely SYNTACTIC recognition
 * (a token's shape), never semantic (this unit still knows nothing
 * about what any particular SID means; that stays exclusively the
 * registry bridge and evaluator units' job), which reuse this same
 * TSid8 instead of declaring their own. *)
unit wsm.values;

{$mode objfpc}{$H-}
{$modeswitch AdvancedRecords}

interface

uses
  sysutils;

type
  { The one function/semantic-identity representation, shared by every
    unit in this codebase. FValue is `strict private`: no code can read
    or set it directly, or construct a TSid8 by any route other than
    FromExact below -- there is no bare-Byte back door and no separate
    "trusted/already validated" shortcut. See wsm.registry.pas's
    original design-history header comment for the four earlier,
    rejected representations (bare Byte alias, text-macro wrapper,
    bit-tuple decomposition, unchecked passthrough) before this one.

    CLOSED DOMAIN: this value space is the COMPLETE closed set of all
    spellings from 00000000 through 11111111 -- all 256 eight-bit
    spellings, not narrowed to whichever SIDs any particular pinned
    registry happens to admit today. FromExact accepts any well-formed
    eight-character '0'/'1' spelling regardless of registry membership,
    so the domain is total in Pascal itself. This whole space is
    reserved exclusively for my-lisp function/semantic identity: no
    code in this codebase may use a bare eight-character '0'/'1'-shaped
    literal for any other purpose. }
  TSid8 = record
  strict private
    FValue: Byte;
  public
    { The ONLY constructor. Parses an exact eight-character '0'/'1'
      source spelling, most-significant-bit first, and packs it into
      FValue. Raises EValueError on any width or character violation --
      a malformed SID fails closed, it is never coerced, truncated, or
      silently accepted at the wrong width. }
    class function FromExact(const text: RawByteString): TSid8; static;

    class operator = (const a, b: TSid8): Boolean;
    class operator <> (const a, b: TSid8): Boolean;

    { Renders back to the eight-character binary spelling. Display
      only -- never use this to reconstruct a dispatch key or to
      compare identities. }
    function ToBinaryString: RawByteString;
  end;

  TValueKind = (kVNil, kUnbound, kPair, kNumber, kSymbol, kString, kSid);

  TValue = record
    case kind: TValueKind of
      kVNil, kUnbound: ();
      kPair:   (pair: Pointer);
      kNumber: (qnum, qden: Int64);
      kSymbol: (sym: Pointer);
      kString: (str: PAnsiChar; strLen: Int32);
      kSid:    (sid: TSid8);
  end;

  TSymEntry = record
    p: PAnsiChar;
    len: Int32;
  end;

  TSymbolTable = record
    entries: array of TSymEntry;
    count: Int32;
  end;

  TArena = record
    blocks: array of PByte;
    cur, lim: PByte;
  end;

  EValueError = class(Exception);

procedure ArenaInit(out a: TArena);
procedure ArenaReset(var a: TArena);
procedure SymbolTableReset(var st: TSymbolTable);
function ArenaAlloc(var a: TArena; size: SizeInt): PByte;
function ArenaAllocZ(var a: TArena; size: SizeInt): PByte;

function MakeNil: TValue;
function MakeUnbound: TValue;
function MakePair(var a: TArena; head, tail: TValue): TValue;
function MakeNumber(num, den: Int64): TValue;
function InternSymbol(
  var a: TArena;
  var st: TSymbolTable;
  bytes: PAnsiChar;
  len: Int32
): TValue;
function MakeString(var a: TArena; bytes: PAnsiChar; len: Int32): TValue;
function MakeSid(id: TSid8): TValue;

function PairHead(v: TValue): TValue;
function PairTail(v: TValue): TValue;
function ValueToDebugString(v: TValue): RawByteString;

{ The TSid8 payload of a kSid value. Raises EValueError if v is not a
  SID -- mirrors SymbolName's own "one fact this kind IS" shape. }
function SidValue(v: TValue): TSid8;

{ The interned name of a symbol, for callers (e.g. a registry bridge)
  that must resolve a surface spelling to something else -- this is not
  a surface-named structural accessor like Car/Cdr, it exposes the one
  fact a symbol IS: its own interned bytes. Raises EValueError if v is
  not a symbol. }
function SymbolName(v: TValue): RawByteString;

function IsNil(v: TValue): Boolean;
function IsUnbound(v: TValue): Boolean;
function IsPair(v: TValue): Boolean;
function IsNumber(v: TValue): Boolean;
function IsSymbol(v: TValue): Boolean;
function IsString(v: TValue): Boolean;
function IsSid(v: TValue): Boolean;

{ True iff text is exactly eight characters, all '0'/'1' -- the SID
  token SHAPE, purely syntactic, checked before any numeric/symbol
  classification decides what a bare atom token means (issue #32). }
function IsSid8Spelling(const text: RawByteString): Boolean;

implementation

class function TSid8.FromExact(const text: RawByteString): TSid8;
var
  i: Integer;
  bits: Byte;
  ch: AnsiChar;
begin
  if Length(text) <> 8 then
    raise EValueError.CreateFmt(
      'TSid8.FromExact: expected exactly 8 characters, got %d ("%s")',
      [Length(text), text]);
  bits := 0;
  for i := 1 to 8 do
  begin
    ch := text[i];
    if (ch <> '0') and (ch <> '1') then
      raise EValueError.CreateFmt(
        'TSid8.FromExact: expected only ''0''/''1'' characters, got "%s"',
        [text]);
    bits := (bits shl 1) or (Ord(ch) - Ord('0'));
  end;
  Result.FValue := bits;
end;

class operator TSid8.= (const a, b: TSid8): Boolean;
begin
  Result := a.FValue = b.FValue;
end;

class operator TSid8.<> (const a, b: TSid8): Boolean;
begin
  Result := a.FValue <> b.FValue;
end;

function TSid8.ToBinaryString: RawByteString;
var
  i: Integer;
  v: Byte;
begin
  v := FValue;
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

function IsSid8Spelling(const text: RawByteString): Boolean;
var
  i: Integer;
  ch: AnsiChar;
begin
  if Length(text) <> 8 then
  begin
    Result := False;
    Exit;
  end;
  for i := 1 to 8 do
  begin
    ch := text[i];
    if (ch <> '0') and (ch <> '1') then
    begin
      Result := False;
      Exit;
    end;
  end;
  Result := True;
end;

type
  PPair = ^TPair;
  TPair = record
    head, tail: TValue;
  end;

const
  ARENA_BLOCK: SizeInt = 1 shl 16;

var
  DNil, DUnbound: TValue;

procedure ArenaInit(out a: TArena);
begin
  SetLength(a.blocks, 0);
  a.cur := nil;
  a.lim := nil;
end;

procedure ArenaReset(var a: TArena);
var
  i: SizeInt;
begin
  for i := 0 to High(a.blocks) do
    if a.blocks[i] <> nil then
      FreeMem(a.blocks[i]);
  SetLength(a.blocks, 0);
  a.cur := nil;
  a.lim := nil;
end;

procedure SymbolTableReset(var st: TSymbolTable);
begin
  SetLength(st.entries, 0);
  st.count := 0;
end;

function ArenaAlloc(var a: TArena; size: SizeInt): PByte;
var
  alignedSize, blockSize: SizeInt;
  block: PByte;
begin
  if size <= 0 then
    raise EValueError.CreateFmt('ArenaAlloc: invalid size %d', [size]);
  if size > High(SizeInt) - 15 then
    raise EValueError.CreateFmt('ArenaAlloc: size overflow %d', [size]);

  alignedSize := (size + 15) and not SizeInt(15);

  if (a.cur = nil) or (SizeInt(a.lim - a.cur) < alignedSize) then
  begin
    blockSize := ARENA_BLOCK;
    if alignedSize > blockSize then
      blockSize := alignedSize;

    GetMem(block, blockSize);
    SetLength(a.blocks, Length(a.blocks) + 1);
    a.blocks[High(a.blocks)] := block;
    a.cur := block;
    a.lim := block + blockSize;
  end;

  Result := a.cur;
  a.cur := a.cur + alignedSize;
end;

function ArenaAllocZ(var a: TArena; size: SizeInt): PByte;
begin
  Result := ArenaAlloc(a, size);
  FillChar(Result^, size, 0);
end;

function MakeNil: TValue;
begin
  Result := DNil;
end;

function MakeUnbound: TValue;
begin
  Result := DUnbound;
end;

function MakePair(var a: TArena; head, tail: TValue): TValue;
var
  p: PPair;
begin
  p := PPair(ArenaAllocZ(a, SizeOf(TPair)));
  p^.head := head;
  p^.tail := tail;
  Result.kind := kPair;
  Result.pair := Pointer(p);
end;

function AbsMagnitude(v: Int64): QWord;
begin
  if v < 0 then
    Result := QWord(-(v + 1)) + 1
  else
    Result := QWord(v);
end;

function GcdMagnitude(a, b: QWord): QWord;
var
  r: QWord;
begin
  while b <> 0 do
  begin
    r := a mod b;
    a := b;
    b := r;
  end;

  if a = 0 then
    Result := 1
  else
    Result := a;
end;

function MakeNumber(num, den: Int64): TValue;
var
  nmag, dmag, g, negativeLimit: QWord;
  negative: Boolean;
begin
  if den = 0 then
    raise EValueError.Create('MakeNumber: denominator=0');

  negative := (num < 0) xor (den < 0);
  nmag := AbsMagnitude(num);
  dmag := AbsMagnitude(den);
  g := GcdMagnitude(nmag, dmag);

  nmag := nmag div g;
  dmag := dmag div g;

  if dmag > QWord(High(Int64)) then
    raise EValueError.Create('MakeNumber: normalized denominator exceeds Int64');

  Result.kind := kNumber;
  Result.qden := Int64(dmag);

  negativeLimit := QWord(High(Int64)) + 1;
  if negative then
  begin
    if nmag > negativeLimit then
      raise EValueError.Create('MakeNumber: normalized numerator exceeds Int64');
    if nmag = negativeLimit then
      Result.qnum := Low(Int64)
    else
      Result.qnum := -Int64(nmag);
  end
  else
  begin
    if nmag > QWord(High(Int64)) then
      raise EValueError.Create('MakeNumber: normalized numerator exceeds Int64');
    Result.qnum := Int64(nmag);
  end;
end;

function InternSymbol(
  var a: TArena;
  var st: TSymbolTable;
  bytes: PAnsiChar;
  len: Int32
): TValue;
var
  i: Int32;
  dst: PAnsiChar;
  newCapacity: SizeInt;
begin
  if len < 0 then
    raise EValueError.CreateFmt('InternSymbol: invalid length %d', [len]);
  if (len > 0) and (bytes = nil) then
    raise EValueError.Create('InternSymbol: nil bytes with non-zero length');

  for i := 0 to st.count - 1 do
    if st.entries[i].len = len then
      if (len = 0) or (CompareByte(st.entries[i].p^, bytes^, len) = 0) then
      begin
        Result.kind := kSymbol;
        Result.sym := st.entries[i].p;
        Exit;
      end;

  if st.count = High(Int32) then
    raise EValueError.Create('InternSymbol: symbol count exceeds Int32 host budget');

  if st.count = Length(st.entries) then
  begin
    if Length(st.entries) = 0 then
      newCapacity := 64
    else
      newCapacity := SizeInt(Length(st.entries)) * 2;

    if newCapacity > High(Int32) then
      newCapacity := High(Int32);
    if newCapacity <= st.count then
      raise EValueError.Create('InternSymbol: cannot grow host symbol table');
    SetLength(st.entries, newCapacity);
  end;

  dst := PAnsiChar(ArenaAlloc(a, SizeInt(len) + 1));
  if len > 0 then
    Move(bytes^, dst^, len);
  dst[len] := #0;

  st.entries[st.count].p := dst;
  st.entries[st.count].len := len;
  Inc(st.count);

  Result.kind := kSymbol;
  Result.sym := dst;
end;

function MakeString(var a: TArena; bytes: PAnsiChar; len: Int32): TValue;
var
  dst: PAnsiChar;
begin
  if len < 0 then
    raise EValueError.CreateFmt('MakeString: invalid length %d', [len]);
  if (len > 0) and (bytes = nil) then
    raise EValueError.Create('MakeString: nil bytes with non-zero length');

  dst := PAnsiChar(ArenaAlloc(a, SizeInt(len) + 1));
  if len > 0 then
    Move(bytes^, dst^, len);
  dst[len] := #0;

  Result.kind := kString;
  Result.str := dst;
  Result.strLen := len;
end;

function MakeSid(id: TSid8): TValue;
begin
  Result.kind := kSid;
  Result.sid := id;
end;

procedure RequirePair(v: TValue; const OperationName: RawByteString);
begin
  if v.kind <> kPair then
    raise EValueError.CreateFmt(
      '%s: kind %d is not a pair',
      [OperationName, Ord(v.kind)]
    );
  if v.pair = nil then
    raise EValueError.CreateFmt('%s: nil pair handle', [OperationName]);
end;

function PairHead(v: TValue): TValue;
begin
  RequirePair(v, 'PairHead');
  Result := PPair(v.pair)^.head;
end;

function PairTail(v: TValue): TValue;
begin
  RequirePair(v, 'PairTail');
  Result := PPair(v.pair)^.tail;
end;

function SymbolName(v: TValue): RawByteString;
begin
  if v.kind <> kSymbol then
    raise EValueError.CreateFmt(
      'SymbolName: kind %d is not a symbol', [Ord(v.kind)]);
  if v.sym = nil then
    raise EValueError.Create('SymbolName: nil symbol handle');
  { InternSymbol always NUL-terminates the arena-allocated bytes it
    stores, so this is a safe, ordinary PAnsiChar->AnsiString copy. }
  Result := PAnsiChar(v.sym);
end;

function SidValue(v: TValue): TSid8;
begin
  if v.kind <> kSid then
    raise EValueError.CreateFmt(
      'SidValue: kind %d is not a SID', [Ord(v.kind)]);
  Result := v.sid;
end;

function ValueToDebugString(v: TValue): RawByteString;
begin
  case v.kind of
    kVNil:
      Result := '()';

    kUnbound:
      Result := '#<unbound>';

    kSymbol:
      begin
        if v.sym = nil then
          raise EValueError.Create('ValueToDebugString: nil symbol handle');
        Result := PAnsiChar(v.sym);
      end;

    kString:
      begin
        if v.strLen < 0 then
          raise EValueError.Create('ValueToDebugString: invalid string length');
        if (v.strLen > 0) and (v.str = nil) then
          raise EValueError.Create('ValueToDebugString: nil string handle');
        SetString(Result, v.str, v.strLen);
      end;

    kNumber:
      Result := RawByteString(Format('%d/%d', [v.qnum, v.qden]));

    kPair:
      begin
        if v.pair = nil then
          raise EValueError.Create('ValueToDebugString: nil pair handle');
        Result := '#<pair>';
      end;

    kSid:
      Result := v.sid.ToBinaryString;
  end;
end;

function IsNil(v: TValue): Boolean;
begin
  Result := v.kind = kVNil;
end;

function IsUnbound(v: TValue): Boolean;
begin
  Result := v.kind = kUnbound;
end;

function IsPair(v: TValue): Boolean;
begin
  Result := v.kind = kPair;
end;

function IsNumber(v: TValue): Boolean;
begin
  Result := v.kind = kNumber;
end;

function IsSymbol(v: TValue): Boolean;
begin
  Result := v.kind = kSymbol;
end;

function IsString(v: TValue): Boolean;
begin
  Result := v.kind = kString;
end;

function IsSid(v: TValue): Boolean;
begin
  Result := v.kind = kSid;
end;

initialization
  DNil.kind := kVNil;
  DUnbound.kind := kUnbound;

end.
