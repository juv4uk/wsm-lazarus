program test_bindtree;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain, wsm.bind, wsm.bindindex,
  wsm.source, wsm.bindtree;
var Tables: TDomainSet; Index: TBindIndex; D: TSourceDocument;
    Heads: THeadOccurrences; S: RawByteString; F: TFileStream;
    I, BoundCount, UnknownCount, NonAtomCount: Integer;
    Caught: Boolean;
procedure Check(Ok: Boolean; const Why: String);
begin
  if not Ok then begin WriteLn(StdErr,'BINDTREE-FAIL ',Why); Halt(1); end;
end;
begin
  LoadPinnedDomains('external/sens', Tables);
  BuildBindIndex(Tables, Index);
  D := ReadUkrainianSource('(сполучити (як-є ()))' + #10 +
    '(за-умовою так) ()');
  try
    CollectHeadOccurrences(D, Index, Heads);
    Check(Length(Heads)=3, 'strict source heads count');
    Check(Heads[0].State=hsBound, 'D3 cons head is not bound');
    Check(SameKey(Heads[0].Key, ExactKey('111')), 'D3 cons coordinate');
    Check(SameKey(Heads[1].Key, ExactKey('001')), 'D3 quote coordinate');
    Check(SameKey(Heads[2].Key, ExactKey('110')), 'D3 cond coordinate');
    Check((Heads[2].Line=2) and (Heads[2].ByteColumn=2),
      'UTF-8 byte-position provenance of second form');
    Check((Heads[0].TopFormIndex=0) and (Heads[0].ParentIndex=-1)
      and (Heads[0].ChildIndex=-1) and (Heads[0].Depth=0)
      and (Heads[0].ListByteOffset=1), 'first root ancestry');
    Check((Heads[1].TopFormIndex=0) and (Heads[1].ParentIndex=0)
      and (Heads[1].ChildIndex=1) and (Heads[1].Depth=1)
      and (Heads[1].ListByteOffset>Heads[0].ListByteOffset),
      'nested child ancestry');
    Check((Heads[2].TopFormIndex=1) and (Heads[2].ParentIndex=-1)
      and (Heads[2].ChildIndex=-1) and (Heads[2].Depth=0),
      'second form ancestry');
    RequireBoundHeads(Heads);
  finally D.Free; end;

  S := '(сполучити (невідоме так))' + #10 + '(("рядок"))';
  D := ReadUkrainianSource(S);
  try
    CollectHeadOccurrences(D, Index, Heads);
    BoundCount:=0; UnknownCount:=0; NonAtomCount:=0;
    for I:=0 to High(Heads) do
      case Heads[I].State of
        hsBound: Inc(BoundCount);
        hsUnknown: begin
          Inc(UnknownCount);
          Check(Heads[I].ByteOffset=Pos('невідоме',S),
            'unknown head byte position lost');
          Check(Heads[I].Line=1, 'unknown head line wrong');
          Check(Heads[I].Name='невідоме', 'unknown head spelling changed');
          Check(Heads[I].Key.Width=0, 'unknown head got fake coordinate');
        end;
        hsNonAtom: Inc(NonAtomCount);
      end;
    Check(BoundCount=1, 'bound head count');
    Check(UnknownCount=1, 'unknown head count');
    Check(NonAtomCount=2, 'non-atomic head count');
    Check((Heads[2].TopFormIndex=1) and (Heads[2].ParentIndex=-1)
      and (Heads[2].Depth=0), 'non-atomic root ancestry');
    Check((Heads[3].ParentIndex=2) and (Heads[3].ChildIndex=0)
      and (Heads[3].Depth=1), 'non-atomic nested ancestry');
    Caught:=False;
    try RequireBoundHeads(Heads);
    except on E:EBindTreeError do begin
      Caught:=True;
      Check(E.ByteOffset=Pos('невідоме',S),
        'strict error missing exact byte position');
    end; end;
    Check(Caught, 'strict binder accepted unknown head');
  finally D.Free; end;

  Caught:=False;
  try CollectHeadOccurrences(nil, Index, Heads);
  except on E:EBindTreeError do Caught:=True; end;
  Check(Caught, 'nil source accepted');
  D := ReadUkrainianSource('(так)');
  try
    Index.Count:=0;
    Caught:=False;
    try CollectHeadOccurrences(D, Index, Heads);
    except on E:EBindTreeError do Caught:=True; end;
    Check(Caught,'uninitialized index accepted');
  finally D.Free; end;

  LoadPinnedDomains('external/sens',Tables);
  BuildBindIndex(Tables,Index);
  F := TFileStream.Create('external/sens/lib/core4.lisp', fmOpenRead);
  try
    Check(F.Size>0, 'missing pinned Core4');
    Check(F.Size<=16*1024*1024, 'Core4 source too large');
    SetLength(S,F.Size); F.ReadBuffer(S[1],Length(S));
  finally F.Free; end;
  D := ReadUkrainianSource(S);
  try
    CollectHeadOccurrences(D,Index,Heads);
    Check(Length(Heads)>10,'Core4 AST did not expose structural heads');
    for I:=0 to High(Heads) do begin
      Check((Heads[I].ListByteOffset>0) and
        (Heads[I].ListByteOffset<=Heads[I].ByteOffset),
        'Core4 list/head position invariant');
      if Heads[I].ParentIndex=-1 then begin
        Check((Heads[I].Depth=0) and (Heads[I].ChildIndex=-1),
          'Core4 top-level ancestry invariant');
      end else begin
        Check((Heads[I].ParentIndex>=0) and (Heads[I].ParentIndex<I),
          'Core4 parent must precede child');
        Check(Heads[I].Depth=Heads[Heads[I].ParentIndex].Depth+1,
          'Core4 relative depth invariant');
        Check(Heads[I].TopFormIndex=Heads[Heads[I].ParentIndex].TopFormIndex,
          'Core4 root form invariant');
        Check(Heads[I].ChildIndex>=0, 'Core4 child slot invariant');
      end;
    end;
  finally D.Free; end;
  WriteLn('BINDTREE-OK source=AST heads=positioned ancestry=checked ',
    'known=exact-domain unknown=explicit strict=reject core4=parse-only');
end.
