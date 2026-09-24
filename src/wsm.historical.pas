(* wsm.historical.pas — Core1 historical (McCarthy 1960 / Lisp 1.5) SID
 * bridge (issue #26, #32).
 *
 * Reads the pinned contracts/core1-historical-sid-map.lisp through the
 * GENERAL reader (wsm.reader.pas) -- safe to do since #32 taught that
 * reader to recognize the SID token shape natively, the same way
 * wsm.registry.pas's own narrow lexer always has. This unit does NOT
 * duplicate that file's authority: it only extracts, for a given
 * historical surface spelling (e.g. "NIL"), the my-lisp SID that file's
 * own `rows` section already declares -- exactly the "resolve by SID,
 * not by spelling" principle #8/#24 already established for every other
 * admitted operator, applied here to a historical CONTROL VALUE instead
 * of an operator. The parse tree itself is a throwaway, local-arena
 * structure: HistoricalMapLoad extracts plain (name, SID) pairs during
 * loading and frees the arena immediately after, so nothing here keeps
 * a dangling reference into reader-owned storage.
 *
 * Scope (issue #26's own "не робити"): this unit resolves ONLY the one
 * historical name Core1's real, pinned forms actually need right now --
 * NIL, which the historical map's own row bridges to my-lisp's
 * empty-list ground identity (SID 00000000). It does NOT attempt to
 * resolve every historical name in that file to a my-lisp VALUE; most
 * rows describe admitted OPERATORS already reached through
 * wsm.registry.pas's ordinary surface-name path, not ground values.
 * T is deliberately NOT handled here: the pinned
 * contracts/core1-bootstrap-contract.lisp lists T as a "seed-only"
 * mechanism with NO my-lisp SID at all (by design, not by omission), so
 * "resolve it via SID" cannot apply to it -- see #26/#32 discussion,
 * 2026-09-23.
 *)
unit wsm.historical;

{$mode objfpc}{$H-}

interface

uses
  sysutils, wsm.values, wsm.reader;

type
  EHistoricalMapError = class(EValueError);

  THistoricalRow = record
    HistoricalName: RawByteString;
    ID: TSid8;
  end;

  THistoricalMap = record
    Rows: array of THistoricalRow;
  end;

{ Parses the full historical-sid-map source text (as read verbatim from
  the pinned contracts/core1-historical-sid-map.lisp file) via the
  general reader, into plain (historical name, SID) pairs. The reader's
  own arena is local to this call and freed before returning -- map
  holds independent RawByteString/TSid8 copies only. Raises
  EHistoricalMapError if the file's top-level shape is not what this
  unit expects. }
procedure HistoricalMapLoad(out map: THistoricalMap; const source: RawByteString);

{ Resolves a historical surface spelling (matched against the fourth
  element of each `(row SID name HISTORICAL-NAME source fit status)`
  entry in the map's `rows` section) to its bridged my-lisp SID. Returns
  False, leaving id undefined, for any spelling not present as a row in
  the pinned historical map -- an unknown historical name never
  acquires invented semantics by guessing, matching RegistryLookup's own
  contract. }
function HistoricalLookup(const map: THistoricalMap;
  const historicalName: RawByteString; out id: TSid8): Boolean;

implementation

function FindSection(const name: RawByteString; sections: TValue): TValue;
begin
  Result := MakeNil;
  while IsPair(sections) do
  begin
    if IsSymbol(PairHead(PairHead(sections))) and
       (SymbolName(PairHead(PairHead(sections))) = name) then
    begin
      Result := PairHead(sections);
      Exit;
    end;
    sections := PairTail(sections);
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

procedure HistoricalMapLoad(out map: THistoricalMap; const source: RawByteString);
var
  r: TReader;
  arena: TArena;
  symbols: TSymbolTable;
  root, rowsSection, rows, row: TValue;
  n: SizeInt;
begin
  SetLength(map.Rows, 0);
  ArenaInit(arena);
  SymbolTableReset(symbols);
  try
    ReaderInit(r, source, arena, symbols);
    root := ReadOne(r);
    if (not IsPair(root)) or (not IsSymbol(PairHead(root))) then
      raise EHistoricalMapError.Create(
        'HistoricalMapLoad: expected one top-level tagged form');

    rowsSection := FindSection('rows', PairTail(root));
    if not IsPair(rowsSection) then
      raise EHistoricalMapError.Create(
        'HistoricalMapLoad: no "rows" section found');

    rows := PairTail(rowsSection);
    while IsPair(rows) do
    begin
      row := PairHead(rows);
      { The NIL row's own historical-name column now reads as kVNil
        directly (issue #28's reader-level NIL fix), not as a kSymbol
        named "NIL" -- stored here under the literal text "NIL" so
        HistoricalLookup's by-name contract is unaffected; every other
        row's historical name is an ordinary symbol, unchanged. }
      if IsSid(Nth(row, 1)) then
      begin
        if IsSymbol(Nth(row, 3)) then
        begin
          n := Length(map.Rows);
          SetLength(map.Rows, n + 1);
          map.Rows[n].HistoricalName := SymbolName(Nth(row, 3));
          map.Rows[n].ID := SidValue(Nth(row, 1));
        end
        else if IsNil(Nth(row, 3)) then
        begin
          n := Length(map.Rows);
          SetLength(map.Rows, n + 1);
          map.Rows[n].HistoricalName := 'NIL';
          map.Rows[n].ID := SidValue(Nth(row, 1));
        end;
      end;
      rows := PairTail(rows);
    end;
  finally
    ArenaReset(arena);
  end;
end;

function HistoricalLookup(const map: THistoricalMap;
  const historicalName: RawByteString; out id: TSid8): Boolean;
var
  i: SizeInt;
begin
  for i := 0 to High(map.Rows) do
    if map.Rows[i].HistoricalName = historicalName then
    begin
      id := map.Rows[i].ID;
      Result := True;
      Exit;
    end;
  Result := False;
end;

end.
