(* test-sid8-integrity.pas — proves TSid8 is genuinely 8-bit binary
 * everywhere it flows through this codebase, and is never lost/degraded
 * along the way (owner, 2026-09-23: "чи всюди сід це 8-бітне двійкове і
 * чи десь це не втрачається").
 *
 * Three independent proofs, all against REAL pinned data, none
 * hand-copied:
 *   1. exhaustive storage round-trip: every one of the 256 possible SID8
 *      values survives being wrapped in a TValue (kSid) and stored/
 *      retrieved through an ordinary structural pair -- the same kind of
 *      container every interpreted expression's operands pass through
 *      -- with its exact eight-character spelling unchanged;
 *   2. whole-registry cross-validation: EVERY row's SID in the real
 *      pinned lib/surface/semantic-registry.lisp, as read by TWO
 *      independently-written parsers (wsm.registry.pas's own narrow
 *      lexer, and the general reader's SID8 native recognition from
 *      #32), agrees exactly -- not spot-checked on a few hand-picked
 *      rows, every single one;
 *   3. whole-historical-map cross-validation: for EVERY row in the real
 *      pinned contracts/core1-historical-sid-map.lisp whose my-lisp name
 *      resolves in the current registry, that row's own declared SID
 *      matches RegistryLookup's answer exactly -- proving the historical
 *      bridge itself has not drifted from the live registry anywhere in
 *      the file, not only at the one NIL row #26 already exercises.
 *)
program test_sid8_integrity;

{$mode objfpc}{$H+}

uses
  sysutils, classes,
  wsm.values, wsm.reader, wsm.registry, wsm.historical;

const
  REGISTRY_PATH = 'external/my-lisp/lib/surface/semantic-registry.lisp';
  HISTORICAL_MAP_PATH = 'external/my-lisp/contracts/core1-historical-sid-map.lisp';

var
  npass, nfail: Int32;
  arena: TArena;
  symbols: TSymbolTable;

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

function LoadFileVerbatim(const path: RawByteString): RawByteString;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(path, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, fs.Size);
    if fs.Size > 0 then
      fs.ReadBuffer(Result[1], fs.Size);
  finally
    fs.Free;
  end;
end;

function ByteToBinarySpelling(b: Byte): RawByteString;
var
  k: Integer;
begin
  SetLength(Result, 8);
  for k := 8 downto 1 do
  begin
    if (b and 1) = 1 then
      Result[k] := '1'
    else
      Result[k] := '0';
    b := b shr 1;
  end;
end;

function Nth(v: TValue; n: Integer): TValue;
begin
  while n > 0 do
  begin
    v := PairTail(v);
    Dec(n);
  end;
  Result := PairHead(v);
end;

var
  i: Integer;
  spelling: RawByteString;
  sid, sidFromEntry: TSid8;
  v, pairVal, retrieved: TValue;
  reg: TRegistry;
  histMap: THistoricalMap;
  registrySource, historicalSource: RawByteString;
  r: TReader;
  registryRows, row: TValue;
  rowSid: TValue;
  rowCount: Integer;
  histRoot, histRowsSection, histRows, histRow: TValue;
  myLispName: RawByteString;
  foundInRegistry: Boolean;

begin
  npass := 0;
  nfail := 0;
  ArenaInit(arena);
  SymbolTableReset(symbols);

  { (1) exhaustive storage round-trip: all 256 SID8 values, wrapped as a
    TValue and passed through an ordinary structural pair, come back
    with their exact eight-character spelling intact. }
  for i := 0 to 255 do
  begin
    spelling := ByteToBinarySpelling(i);
    sid := TSid8.FromExact(spelling);
    v := MakeSid(sid);
    pairVal := MakePair(arena, v, MakeNil);
    retrieved := PairHead(pairVal);
    Check(IsSid(retrieved) and (SidValue(retrieved).ToBinaryString = spelling),
      'SID ' + spelling + ' survives MakeSid -> MakePair -> PairHead unchanged');
  end;

  { (2) whole-registry cross-validation: every row's SID in the real
    pinned semantic-registry.lisp, read by two independent parsers,
    agrees exactly. }
  registrySource := LoadFileVerbatim(REGISTRY_PATH);
  RegistryLoad(reg, registrySource);

  ReaderInit(r, registrySource, arena, symbols);
  registryRows := ReadOne(r);
  Check(IsPair(registryRows), 'general reader parses the real registry file as one list of rows');

  rowCount := 0;
  while IsPair(registryRows) do
  begin
    row := PairHead(registryRows);
    rowSid := PairHead(row);
    Check(IsSid(rowSid),
      'registry row ' + IntToStr(rowCount) + ' SID column is recognized as kSid by the general reader, not a decimal number');
    if IsSid(rowSid) and (rowCount <= High(reg.Entries)) then
      Check(SidValue(rowSid) = reg.Entries[rowCount].ID,
        'registry row ' + IntToStr(rowCount) +
        ' SID agrees between wsm.registry.pas''s narrow lexer and the general reader');
    Inc(rowCount);
    registryRows := PairTail(registryRows);
  end;
  Check(rowCount = Length(reg.Entries),
    'total row count agrees between the narrow lexer (' + IntToStr(Length(reg.Entries)) +
    ') and the general reader (' + IntToStr(rowCount) + ')');

  { (3) whole-historical-map cross-validation: every row in the real
    pinned historical-sid-map whose my-lisp name resolves in the current
    registry has a SID matching RegistryLookup exactly -- the historical
    bridge has not drifted from the live registry anywhere in the file. }
  historicalSource := LoadFileVerbatim(HISTORICAL_MAP_PATH);
  HistoricalMapLoad(histMap, historicalSource);

  ReaderInit(r, historicalSource, arena, symbols);
  histRoot := ReadOne(r);
  histRowsSection := MakeNil;
  begin
    histRows := PairTail(histRoot);
    while IsPair(histRows) do
    begin
      if IsSymbol(PairHead(PairHead(histRows))) and
         (SymbolName(PairHead(PairHead(histRows))) = 'rows') then
      begin
        histRowsSection := PairHead(histRows);
        Break;
      end;
      histRows := PairTail(histRows);
    end;
  end;
  Check(IsPair(histRowsSection), 'rows section found in the real historical-sid-map file');

  rowCount := 0;
  histRows := PairTail(histRowsSection);
  while IsPair(histRows) do
  begin
    histRow := PairHead(histRows);
    if IsSid(Nth(histRow, 1)) and IsSymbol(Nth(histRow, 2)) then
    begin
      myLispName := SymbolName(Nth(histRow, 2));
      foundInRegistry := RegistryLookup(reg, myLispName, sidFromEntry);
      if foundInRegistry then
      begin
        Check(SidValue(Nth(histRow, 1)) = sidFromEntry,
          'historical-sid-map row for "' + myLispName +
          '" has a SID matching the live registry''s own SID for that name exactly');
        Inc(rowCount);
      end;
    end;
    histRows := PairTail(histRows);
  end;
  Check(rowCount > 5,
    'a meaningful number of historical-sid-map rows were cross-checked against the live registry, got ' +
    IntToStr(rowCount));

  WriteLn('SID8-INTEGRITY: pass=', npass, ' fail=', nfail);
  if nfail > 0 then
    Halt(1);
end.
