(* test-registry.pas — M0.5 tests for the semantic registry bridge (#7).
 *
 * Loads the REAL pinned lib/surface/semantic-registry.lisp (not a
 * hand-copied excerpt -- #7's own "не робити" forbids a second,
 * hand-maintained authority) and proves:
 *   1. several surface aliases resolve to one identity;
 *   2. an unknown symbol acquires no invented semantics;
 *   3. the resolved value is the canonical semantic ID, not the spelling;
 *   4. "0001"-shaped IDs are not silently collapsed into "1" (leading
 *      zeros survive the round trip);
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
  quoteID, altQuoteID, carID, unknownID: RawByteString;
  found: Boolean;
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
  Check((quoteID <> '') and (quoteID = altQuoteID),
    'aliases "quote" and "як-є" resolve to the same identity');

  { (2) unknown symbol acquires no invented semantics. }
  found := RegistryLookup(reg, 'this-spelling-does-not-exist-anywhere',
    unknownID);
  Check((not found) and (unknownID = ''),
    'unknown spelling is reported unresolved, not guessed');

  { (3) downstream gets the canonical semantic ID, never the spelling
    itself, as the dispatch key. }
  Check(quoteID <> 'quote',
    'resolved value is the semantic ID, not the surface spelling back');

  { (4) "0001"-shaped opacity: the pinned registry's own first real row
    is id 00000001 for quote -- leading zeros must survive verbatim. }
  Check(quoteID = '00000001',
    'quote resolves to the exact opaque lexeme 00000001, zeros intact');
  Check(Length(quoteID) = 8,
    'semantic ID keeps its full fixed-width lexeme, not a shortened number');

  { (5) symbolic apostrophe: (sym "'") in the pinned row for quote must
    read as the literal one-character spelling ', not as this file's
    own quote-sugar or any other reinterpretation. }
  found := RegistryLookup(reg, '''', altQuoteID);
  Check(found and (altQuoteID = quoteID),
    'symbolic apostrophe spelling resolves to the same quote identity');

  { A second, unrelated identity as a sanity cross-check: car is id
    00000101 in the pinned registry, distinct from quote. }
  found := RegistryLookup(reg, 'car', carID);
  Check(found and (carID = '00000101') and (carID <> quoteID),
    'car resolves to a distinct, correct identity');

  WriteLn('REGISTRY: pass=', npass, ' fail=', nfail);
  if nfail > 0 then
    Halt(1);
end.
