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
 *   4. ParseSid8 requires exactly eight '0'/'1' characters -- a
 *      would-be four-character short form like "0001" is REJECTED
 *      (fail-closed), never silently accepted as if it were
 *      "00000001" (SID8-ONLY's width/leading-zero invariant, #24);
 *   5. the symbolic apostrophe row is read as an ordinary opaque token,
 *      not reinterpreted as this file's own quote-sugar. *)
program test_registry;

{$mode objfpc}{$H+}

uses
  sysutils, classes,
  wsm.registry;

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
  Check(quoteID = %00000001,
    'quote resolves to the exact packed SID8 %00000001');
  Check(Sid8ToBinaryString(quoteID) = '00000001',
    'SID8 renders back to its full fixed-width binary spelling for display');

  { (4) SID8-ONLY width/leading-zero invariant: a four-character
    short form must be REJECTED, never silently accepted as if it were
    the real eight-character spelling (#24). }
  raised := False;
  try
    ParseSid8('0001');
  except
    on E: ERegistryError do raised := True;
  end;
  Check(raised, 'ParseSid8 rejects a wrong-width ("0001") lexeme, fail-closed');

  raised := False;
  try
    ParseSid8('0000000X');
  except
    on E: ERegistryError do raised := True;
  end;
  Check(raised, 'ParseSid8 rejects a non-0/1 character, fail-closed');

  { (5) symbolic apostrophe: (sym "'") in the pinned row for quote must
    read as the literal one-character spelling ', not as this file's
    own quote-sugar or any other reinterpretation. }
  found := RegistryLookup(reg, '''', altQuoteID);
  Check(found and (altQuoteID = quoteID),
    'symbolic apostrophe spelling resolves to the same quote identity');

  { A second, unrelated identity as a sanity cross-check: car is id
    00000101 in the pinned registry, distinct from quote. }
  found := RegistryLookup(reg, 'car', carID);
  Check(found and (carID = %00000101) and (carID <> quoteID),
    'car resolves to a distinct, correct identity');

  WriteLn('REGISTRY: pass=', npass, ' fail=', nfail);
  if nfail > 0 then
    Halt(1);
end.
