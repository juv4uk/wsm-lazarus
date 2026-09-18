(* wsm.values.pas — FPC substrate value representation (FPCLZ-M0-VALUE).
 *
 * НИЯКОЇ Lisp-семантики тут. Це лише фізичне представлення значень:
 *   kNil    — порожній список ()   (НЕ nil-вказівник, НЕ #<unbound>)
 *   kUnbound— маркер незв'язаного  (злиття () і #<unbound> у точності,
 *              див. absorption-vector №1)
 *   kPair   — cons-клітинка в арені (deterministic memory, без GC)
 *   kNumber — exact rational inline: Int64 num/den, канонічно
 *             скорочений (gcd=1, den>0). Всі копії лишаються канонічними
 *             (absorption-vector №3: exactness в межах tier-1).
 *   kSymbol — інтернований: equality за вказівником.
 *   kString — сирі байти в арені + довжина; 0-based індексація власним
 *             кодом, без AnsiString (absorption-vector №2: 1-based).
 *
 * Оборона:
 *   - variant record — компілятор фізично забороняє змішати kind-и.
 *   - НЕ використовувати тип Variant / TObject-ковбасу (заборона в core,
 *     див. AGENTS.md / scripts/check-no-lcl.sh).
 *   - Одиниця, де FPC-виключення стають невинними: лише EValueError,
 *     конвертується в ErrorKind на одному кордоні (wsm.conform). *)
unit wsm.values;

{$mode objfpc}{$H-}

interface

uses sysutils;

type
  TValueKind = (kVNil, kUnbound, kPair, kNumber, kSymbol, kString);

  PPair = ^TPair;

  (* TValue — tagged union. Розмір: tag + найбільший варіант.
   * kNumber тримає num/den ІНЛАЙН (24B), щоб by-value копії не руйнували
   * канонічність (absorption-vector №4). *)
  TValue = record
    case kind: TValueKind of
      kVNil, kUnbound: ();
      kPair:  (pair: PPair);
      kNumber:(qnum, qden: Int64);
      kSymbol:(sym: Pointer);
      kString:(str: PAnsiChar; strLen: Int32);
  end;

  TPair = record
    car, cdr: TValue;
  end;

  TSymEntry = record
    p: PAnsiChar;
    len: Int32;
  end;

  (* Мінімальний детермінований інтернер для M0 (без RTL-хіпа):
   * фіксована таблиця, лінійний пошук — на tier-1 символів < 1024. *)
  TSymbolTable = record
    entries: array[0..1023] of TSymEntry;
    count: Int32;
  end;

  (* Арена: bump-алокатор на життя одного witness-запуску. *)
  TArena = record
    blocks: array of PByte;
    cur, lim: PByte;
  end;

  EValueError = class(Exception);

function  ArenaNew  (out a: TArena): TArena;
procedure ArenaReset(var a: TArena);
function  ArenaAlloc(var a: TArena; size: SizeInt): PByte;
function  ArenaAllocZ(var a: TArena; size: SizeInt): PByte;

function MakeNil: TValue;
function MakeUnbound: TValue;
function MakePair(var a: TArena; car, cdr: TValue): TValue;
function MakeNumber(num, den: Int64): TValue;
function InternSymbol(var a: TArena; var st: TSymbolTable; bytes: PAnsiChar; len: Int32): TValue;
function MakeString(var a: TArena; bytes: PAnsiChar; len: Int32): TValue;

function Car(v: TValue): TValue;
function Cdr(v: TValue): TValue;

function ValueEqual(a, b: TValue): Boolean;  (* substrate-level, не Lisp eq? *)
function ValueToDebugString(v: TValue): PAnsiChar;

function   IsNil(v: TValue): Boolean;
function   IsUnbound(v: TValue): Boolean;
function   IsPair(v: TValue): Boolean;
function   IsNumber(v: TValue): Boolean;
function   IsSymbol(v: TValue): Boolean;
function   IsString(v: TValue): Boolean;

implementation

const
  ARENA_BLOCK = 1 shl 16;   (* 64 KiB per block *)

var
  DNil, DUnbound: TValue;

function ArenaNew(out a: TArena): TArena;
begin
  SetLength(a.blocks, 0);
  a.cur := nil;
  a.lim := nil;
  ArenaNew := a;
end;

procedure ArenaReset(var a: TArena);
begin
  a.cur := nil;
  a.lim := nil;
end;

function ArenaAlloc(var a: TArena; size: SizeInt): PByte;
begin
  size := (size + 15) and not 15;
  if (a.cur = nil) or (SizeInt(a.lim - a.cur) < size) then begin
    SetLength(a.blocks, Length(a.blocks) + 1);
    GetMem(a.blocks[High(a.blocks)], ARENA_BLOCK);
    a.cur := a.blocks[High(a.blocks)];
    a.lim := a.cur + ARENA_BLOCK;
  end;
  Result := a.cur;
  a.cur := a.cur + size;
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

function MakePair(var a: TArena; car, cdr: TValue): TValue;
var p: PPair;
begin
  p := PPair(ArenaAllocZ(a, SizeOf(TPair)));
  p^.car := car;
  p^.cdr := cdr;
  Result.kind := kPair;
  Result.pair := p;
end;

function GCD(a, b: Int64): Int64;
begin
  if a < 0 then a := -a;
  if b < 0 then b := -b;
  while b <> 0 do begin
    Result := b;
    b := a mod b;
    a := Result;
  end;
  if a = 0 then Result := 1 else Result := a;
end;

function MakeNumber(num, den: Int64): TValue;
var g: Int64;
begin
  if den = 0 then
    raise EValueError.Create('MakeNumber: denominator=0');
  if den < 0 then begin
    num := -num;
    den := -den;
  end;
  g := GCD(num, den);
  Result.kind := kNumber;
  Result.qnum := num div g;
  Result.qden := den div g;
end;

function InternSymbol(var a: TArena; var st: TSymbolTable; bytes: PAnsiChar; len: Int32): TValue;
var i: Int32; dst: PAnsiChar;
begin
  for i := 0 to st.count - 1 do
    if (st.entries[i].len = len) and
       (CompareByte(st.entries[i].p^, bytes^, len) = 0) then begin
      Result.kind := kSymbol;
      Result.sym := st.entries[i].p;
      Exit;
    end;
  if st.count >= 1024 then
    raise EValueError.Create('InternSymbol: intern table full (1024)');
  dst := PAnsiChar(ArenaAlloc(a, len + 1));
  Move(bytes^, dst^, len);
  dst[len] := #0;
  st.entries[st.count].p := dst;
  st.entries[st.count].len := len;
  Inc(st.count);
  Result.kind := kSymbol;
  Result.sym := dst;
end;

function MakeString(var a: TArena; bytes: PAnsiChar; len: Int32): TValue;
var dst: PAnsiChar;
begin
  dst := PAnsiChar(ArenaAlloc(a, len + 1));
  Move(bytes^, dst^, len);
  dst[len] := #0;
  Result.kind := kString;
  Result.str := dst;
  Result.strLen := len;
end;

function Car(v: TValue): TValue;
begin
  if v.kind <> kPair then
    raise EValueError.CreateFmt('Car: kind %d is not a pair', [Ord(v.kind)]);
  Result := v.pair^.car;
end;

function Cdr(v: TValue): TValue;
begin
  if v.kind <> kPair then
    raise EValueError.CreateFmt('Cdr: kind %d is not a pair', [Ord(v.kind)]);
  Result := v.pair^.cdr;
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
      Result := (a.pair = b.pair);   (* фізична ідентичність cons-клітинки *)
    kNumber:
      Result := (a.qnum = b.qnum) and (a.qden = b.qden);
    kSymbol:
      Result := (a.sym = b.sym);     (* інтернованість: ідентичність вказівника *)
    kString:
      Result := (a.strLen = b.strLen) and
                (CompareByte(a.str^, b.str^, a.strLen) = 0);
    else
      Result := False;
  end;
end;

function ValueToDebugString(v: TValue): PAnsiChar;
begin
  case v.kind of
    kVNil:    ValueToDebugString := '()';
    kUnbound: ValueToDebugString := '#<unbound>';
    kSymbol:  ValueToDebugString := v.sym;
    kString:  ValueToDebugString := v.str;
    kNumber:  ValueToDebugString := PAnsiChar(Format('%d/%d', [v.qnum, v.qden]));
    kPair:    ValueToDebugString := '#<pair>';
  end;
end;

function IsNil(v: TValue): Boolean;      begin IsNil := v.kind = kVNil; end;
function IsUnbound(v: TValue): Boolean;  begin IsUnbound := v.kind = kUnbound; end;
function IsPair(v: TValue): Boolean;     begin IsPair := v.kind = kPair; end;
function IsNumber(v: TValue): Boolean;   begin IsNumber := v.kind = kNumber; end;
function IsSymbol(v: TValue): Boolean;   begin IsSymbol := v.kind = kSymbol; end;
function IsString(v: TValue): Boolean;   begin IsString := v.kind = kString; end;

initialization
  DNil.kind := kVNil;
  DUnbound.kind := kUnbound;

end.