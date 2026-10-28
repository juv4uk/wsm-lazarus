program test_bindatoms;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.source, wsm.domain, wsm.bind,
  wsm.bindindex, wsm.bindatoms;
var Tables: TDomainSet; Index: TBindIndex; Doc: TSourceDocument;
    Atoms: TAtomRecords; S: RawByteString; F: TFileStream;
    I, Known, Unknown: SizeInt; Failed: Boolean;
procedure Check(Value: Boolean; const Reason: String);
begin
  if not Value then begin WriteLn(StdErr, 'BINDATOMS-FAIL ', Reason); Halt(1); end;
end;
begin
  LoadPinnedDomains('external/sens', Tables);
  BuildBindIndex(Tables, Index);
  S := 'так' + #10 + '(сполучити моя-змінна (як-є "так") ())';
  Doc := ReadUkrainianSource(S);
  try
    CollectSourceAtoms(Doc, Index, Atoms);
    Check(Length(Atoms)=4,'four atoms, string and () excluded');
    Check((Atoms[0].Position=apTopLevel) and (Atoms[0].Depth=0)
      and (Atoms[0].ChildIndex=-1) and (Atoms[0].ParentListByteOffset=0)
      and (Atoms[0].TopFormIndex=0),'top-level atom provenance');
    Check((Atoms[0].Resolution=arDomainProjection) and
      SameKey(Atoms[0].Key,ExactKey('1')),'D1 atom identity');
    Check((Atoms[1].Position=apFirstChild) and
      (Atoms[1].TopFormIndex=1) and (Atoms[1].Depth=1) and
      (Atoms[1].ByteOffset=Pos('сполучити', S)) and
      SameKey(Atoms[1].Key, ExactKey('111')),'list head provenance');
    Check((Atoms[2].Name='моя-змінна') and
      (Atoms[2].Position=apOtherChild) and (Atoms[2].Depth=1)
      and (Atoms[2].Resolution=arUnresolved) and
      (Atoms[2].Key.Width=0) and (Atoms[2].Key.Bits=0) and
      (Atoms[2].ByteOffset=Pos('моя-змінна', S)),
      'unresolved argument cannot acquire fake coordinate');
    Check((Atoms[3].Position=apFirstChild) and (Atoms[3].Depth=2)
      and (Atoms[3].ByteOffset=Pos('як-є', S)) and
      (Atoms[3].ParentListByteOffset=Pos('(як-є',S)) and
      SameKey(Atoms[3].Key,ExactKey('001')),'nested projection');
  finally Doc.Free; end;

  Doc:=ReadUkrainianSource('() "так" ; comment' + #10);
  try
    CollectSourceAtoms(Doc,Index,Atoms);
    Check(Length(Atoms)=0,'empty list / string / comment should have no atoms');
  finally Doc.Free; end;

  Failed:=False;
  try CollectSourceAtoms(nil,Index,Atoms);
  except on E:EAtomCensusError do Failed:=True; end;
  Check(Failed,'nil AST accepted');
  Index.Count:=0;
  Doc:=ReadUkrainianSource('(так)');
  try
    Failed:=False;
    try CollectSourceAtoms(Doc,Index,Atoms);
    except on E:EAtomCensusError do Failed:=True; end;
    Check(Failed,'uninitialized binder accepted');
  finally Doc.Free; end;

  LoadPinnedDomains('external/sens',Tables);
  BuildBindIndex(Tables,Index);
  F:=TFileStream.Create('external/sens/lib/core4.lisp',fmOpenRead);
  try
    Check((F.Size>0) and (F.Size<=16*1024*1024),'invalid pinned Core4');
    SetLength(S,F.Size);
    F.ReadBuffer(S[1],Length(S));
  finally F.Free; end;
  Doc:=ReadUkrainianSource(S);
  try
    CollectSourceAtoms(Doc,Index,Atoms);
    Check(Length(Atoms)>10000,'Core4 atom census unexpectedly small');
    Known:=0; Unknown:=0;
    for I:=0 to High(Atoms) do begin
      Check((Atoms[I].TopFormIndex>=0) and
        (Atoms[I].TopFormIndex<Length(Doc.Forms)),
        'Core4 atom top-form index');
      Check((Atoms[I].ByteOffset>=1) and
        (Atoms[I].ByteOffset<=Length(S)) and
        (Copy(S,Atoms[I].ByteOffset,Length(Atoms[I].Name))=Atoms[I].Name),
        'Core4 exact UTF-8 byte provenance');
      if Atoms[I].Resolution=arDomainProjection then begin
        Inc(Known);
        Check((Atoms[I].Key.Width>=FirstDomain) and
          (Atoms[I].Key.Width<=LastDomain), 'Core4 exact domain width');
        Check(SameKey(Atoms[I].Key,
          IndexedUkrainian(Index,Atoms[I].Name)), 'Core4 binder identity parity');
      end else begin
        Inc(Unknown);
        Check(Atoms[I].Key.Width=0,'unresolved Core4 name gained fake identity');
      end;
    end;
    Check(Known+Unknown=Length(Atoms),'atom ledger count mismatch');
  finally Doc.Free; end;
  WriteLn('BINDATOMS-OK core4-atoms=',Length(Atoms),
    ' domain-projections=',Known,' unresolved=',Unknown,
    ' strings=excluded positions=byte-exact callable=unverified');
end.
