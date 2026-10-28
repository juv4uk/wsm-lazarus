program test_bindindex;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.bind, wsm.bindindex;
var Tables: TDomainSet; Index: TBindIndex; K, K2: TDomainKey;
    D, I, Count: Integer; Raised: Boolean;
procedure Check(Ok: Boolean; const MessageText: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'BINDINDEX-FAIL ', MessageText);
    Halt(1);
  end;
end;
begin
  LoadPinnedDomains('external/sens', Tables);
  BuildBindIndex(Tables, Index);
  Count := 0;
  for D := FirstDomain to LastDomain do
    for I := 0 to High(Tables[D]) do begin
      if Tables[D][I].Ukrainian = '' then Continue;
      K := IndexedUkrainian(Index, Tables[D][I].Ukrainian);
      K2 := BindUkrainian(Tables, Tables[D][I].Ukrainian);
      Check(SameKey(K, K2), 'indexed and linear binders disagree');
      Check(SameKey(K, Tables[D][I].Key), 'indexed coordinate mismatch');
      K2 := IndexedUkrainianInDomain(Index, Tables[D][I].Ukrainian, D);
      Check(SameKey(K, K2), 'scoped index coordinate mismatch');
      Inc(Count);
    end;
  Check(Index.Count = Count, 'index lost or duplicated a surface');
  Check(Count > 1000, 'pinned source unexpectedly empty');
  Raised := False;
  try K := IndexedUkrainian(Index, 'quote');
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'unrecognized English spelling accepted');
  Raised := False;
  try K := IndexedUkrainian(Index, '');
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'empty name accepted');
  Raised := False;
  try K := IndexedUkrainian(Index, 'ТаК');
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'byte-exact case check missing');
  Raised := False;
  try K := IndexedUkrainianInDomain(Index, 'так', 3);
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'wrong-domain lookup accepted');
  Raised := False;
  try K := IndexedUkrainianInDomain(Index, 'так', 0);
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'invalid domain accepted');
  { A built index must remain stable if a caller later edits the source tables. }
  Tables[1][0].Ukrainian := 'за-умовою';
  K := IndexedUkrainian(Index, 'за-умовою');
  Check(SameKey(K, ExactKey('110')), 'snapshot changed after input mutation');
  Raised := False;
  try BuildBindIndex(Tables, Index);
  except on E: EBindError do Raised := True; end;
  Check(Raised, 'duplicate Ukrainian surface did not fail closed');
  WriteLn('BINDINDEX-OK domains=10 checked=', Count,
    ' byte-exact=1 snapshots=1 ambiguity=reject');
end.
