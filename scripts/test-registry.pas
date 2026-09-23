(* test-registry.pas — M0.5 tests for the semantic registry bridge (#7),
 * plus SID8-ONLY parsing tests (#24).
 *
 * Loads the REAL pinned lib/surface/semantic-registry.lisp (not a
 * hand-copied excerpt -- #7's own "не робити" forbids a second,
 * hand-maintained authority) and proves:
 *   1. several surface aliases resolve to one identity;
 *   2. an unknown symbol acquires no invented semantics;
 *   3. the resolved value is the canonical semantic ID (TSid8), not the
 *      spelling;
 *   4. TSid8.FromExact requires exactly eight '0'/'1' characters -- a
 *      would-be four-character short form like "0001" is REJECTED
 *      (fail-closed), never silently accepted as if it were
 *      "00000001" (SID8-ONLY's width/leading-zero invariant, #24);
 *   5. the symbolic apostrophe row is read as an ordinary opaque token,
 *      not reinterpreted as this file's own quote-sugar;
 *   6. TSid8's domain is the COMPLETE closed set 00000000..11111111
 *      (all 256 eight-bit spellings) in Pascal itself, not narrowed to
 *      whichever SIDs the pinned registry happens to admit today --
 *      owner, 2026-09-23: "виділи 00000000-11111111 під функції мови,
 *      і зроби так щоб паскаль сприймав як 8-бітне двійкове, все
 *      зарезервовано під мову". *)
program test_registry;

{$mode objfpc}{$H+}

uses
  sysutils, classes,
  wsm.values, wsm.registry;

const
  { Relative to repo root -- test.sh's own cd "$(dirname "$0")/.." makes
    this the CWD whenever this binary actually runs under the M0 gate. }
  REGISTRY_PATH = 'external/my-lisp/lib/surface/semantic-registry.lisp';

var
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

var
  reg: TRegistry;
  source: RawByteString;
  quoteID, altQuoteID, carID, unknownID: TSid8;
  found, raised: Boolean;
  spaceIndex, cmpIndex: Integer;
  spelling: RawByteString;
  spaceIDs: array[0..255] of TSid8;
  spaceRoundTrips, spaceDistinct: Boolean;
begin
  npass := 0;
  nfail := 0;

  source := LoadFileVerbatim(REGISTRY_PATH);
  RegistryLoad(reg, source);

  Check(Length(reg.Entries) > 0, 'registry loads at least one row');

  { (1) multiple surface aliases -> one identity. "quote" (en) and
    "як-є" (ук/укр) are the same row, same ID, in the pinned registry. }
  found := RegistryLookup(reg, 'quote', quoteID);
  Check(found, 'en spelling "quote" resolves');
  found := RegistryLookup(reg, 'як-є', altQuoteID);
  Check(found, 'ук/укр spelling "як-є" resolves');
  Check(quoteID = altQuoteID,
    'aliases "quote" and "як-є" resolve to the same identity');

  { (2) unknown symbol acquires no invented semantics. }
  found := RegistryLookup(reg, 'this-spelling-does-not-exist-anywhere',
    unknownID);
  Check(not found,
    'unknown spelling is reported unresolved, not guessed');

  { (3) downstream gets the canonical semantic ID (TSid8), never the
    spelling itself, as the dispatch key -- there is no string form to
    compare against a spelling at all any more (SID8-ONLY, #24). }
  Check(quoteID = TSid8.FromExact('00000001'),
    'quote resolves to the exact SID8 00000001');
  Check(quoteID.ToBinaryString = '00000001',
    'SID8 renders back to its full fixed-width binary spelling for display');

  { (4) SID8-ONLY width/leading-zero invariant: a four-character
    short form must be REJECTED, never silently accepted as if it were
    the real eight-character spelling (#24). }
  raised := False;
  try
    TSid8.FromExact('0001');
  except
    on E: EValueError do raised := True;
  end;
  Check(raised, 'TSid8.FromExact rejects a wrong-width ("0001") lexeme, fail-closed');

  raised := False;
  try
    TSid8.FromExact('0000000X');
  except
    on E: EValueError do raised := True;
  end;
  Check(raised, 'TSid8.FromExact rejects a non-0/1 character, fail-closed');

  { (5) symbolic apostrophe: (sym "'") in the pinned row for quote must
    read as the literal one-character spelling ', not as this file's
    own quote-sugar or any other reinterpretation. }
  found := RegistryLookup(reg, '''', altQuoteID);
  Check(found and (altQuoteID = quoteID),
    'symbolic apostrophe spelling resolves to the same quote identity');

  { A second, unrelated identity as a sanity cross-check: car is id
    00000101 in the pinned registry, distinct from quote. }
  found := RegistryLookup(reg, 'car', carID);
  Check(found and (carID = TSid8.FromExact('00000101')) and (carID <> quoteID),
    'car resolves to a distinct, correct identity');

  { (6) SID8's full closed domain (2026-09-23, owner: "виділи
    00000000-11111111 під функції мови, і зроби так щоб паскаль
    сприймав як 8-бітне двійкове, все зарезервовано під мову"): the
    WHOLE eight-bit space is reserved my-lisp function-identity
    namespace, not narrowed to whichever SIDs the pinned registry
    happens to admit today. Prove this exhaustively: every one of the
    256 possible eight-character '0'/'1' spellings constructs without
    error, round-trips back to itself exactly, and is distinct from
    every other value -- TSid8 is total and faithful across the full
    closed 00000000..11111111 domain in Pascal itself, not merely in
    the registry text. }
  spaceRoundTrips := True;
  for spaceIndex := 0 to 255 do
  begin
    spelling := ByteToBinarySpelling(spaceIndex);
    spaceIDs[spaceIndex] := TSid8.FromExact(spelling);
    if spaceIDs[spaceIndex].ToBinaryString <> spelling then
      spaceRoundTrips := False;
  end;
  Check(spaceRoundTrips,
    'all 256 eight-character spellings 00000000..11111111 construct and round-trip exactly');

  spaceDistinct := True;
  for spaceIndex := 0 to 255 do
    for cmpIndex := spaceIndex + 1 to 255 do
      if spaceIDs[spaceIndex] = spaceIDs[cmpIndex] then
        spaceDistinct := False;
  Check(spaceDistinct,
    'all 256 constructed SID8 values are pairwise distinct -- the closed domain is faithfully total, no collisions');

  WriteLn('REGISTRY: pass=', npass, ' fail=', nfail);
  if nfail > 0 then
    Halt(1);
end.
