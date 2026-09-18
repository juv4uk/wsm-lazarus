(* wsm.values.pas — FPC substrate value representation (M0.3).
 *
 * No Lisp evaluation semantics live here. This unit owns only the physical
 * representation and storage mechanics needed by later layers:
 *   kVNil     — the empty-list value, distinct from every host nil pointer;
 *   kUnbound  — the unbound marker, distinct from the empty list;
 *   kPair     — arena-owned pair handle;
 *   kNumber   — normalized exact rational inside the M0 Int64 boundary;
 *   kSymbol   — interned arena-owned byte string;
 *   kString   — arena-owned bytes plus explicit length.
 *
 * Surface operator names are intentionally absent from the API. Later semantic
 * dispatch must arrive through the pinned registry/ID bridge, not this unit. *)
unit wsm.values;

{$mode objfpc}{$H-}

interface

uses
  sysutils;

type
  TValueKind = (kVNil, kUnbound, kPair, kNumber, kSymbol, kString);

  PPair = ^TPair;

  TValue = record
    case kind: TValueKind of
      kVNil, kUnbound: ();
      kPair:   (pair: PPair);
      kNumber: (qnum, qden: Int64);
      kSymbol: (sym: Pointer);
      kString: (str: PAnsiChar; strLen: Int32);
  end;

  TPair = record
    head, tail: TValue;
  end;

  TSymEntry = record
    p: PAnsiChar;
    len: Int32;
  end;

  TSymbolTable = record
    entries: array[0..1023] of TSymEntry;
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

function PairHead(v: TValue): TValue;
function PairTail(v: TValue): TValue;
function ValueEqual(a, b: TValue): Boolean;
function ValueToDebugString(v: TValue): RawByteString;

function IsNil(v: TValue): Boolean;
function IsUnbound(v: TValue): Boolean;
function IsPair(v: TValue): Boolean;
function IsNumber(v: TValue): Boolean;
function IsSymbol(v: TValue): Boolean;
function IsString(v: TValue): Boolean;

implementation

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
  FillChar(st.entries, SizeOf(st.entries), 0);
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
  Result.pair := p;
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

  if st.count >= Length(st.entries) then
    raise EValueError.CreateFmt(
      'InternSymbol: intern table full (%d)',
      [Length(st.entries)]
    );

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
  Result := v.pair^.head;
end;

function PairTail(v: TValue): TValue;
begin
  RequirePair(v, 'PairTail');
  Result := v.pair^.tail;
end;

function ValueEqual(a, b: TValue): Boolean;
begin
  Result := False;
  if a.kind <> b.kind then
    Exit;

  case a.kind of
    kVNil, kUnbound:
      Result := True;

    kPair:
      begin
        if (a.pair = nil) or (b.pair = nil) then
          raise EValueError.Create('ValueEqual: nil pair handle');
        Result := a.pair = b.pair;
      end;

    kNumber:
      Result := (a.qnum = b.qnum) and (a.qden = b.qden);

    kSymbol:
      begin
        if (a.sym = nil) or (b.sym = nil) then
          raise EValueError.Create('ValueEqual: nil symbol handle');
        Result := a.sym = b.sym;
      end;

    kString:
      begin
        if a.strLen <> b.strLen then
          Exit;
        if a.strLen = 0 then
        begin
          Result := True;
          Exit;
        end;
        if (a.str = nil) or (b.str = nil) then
          raise EValueError.Create('ValueEqual: nil string handle');
        Result := CompareByte(a.str^, b.str^, a.strLen) = 0;
      end;
  end;
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

initialization
  DNil.kind := kVNil;
  DUnbound.kind := kUnbound;

end.
