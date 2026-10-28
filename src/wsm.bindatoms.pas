{ G2.6: byte-exact syntactic atom census over the Ukrainian source AST.
  Domain matches are projections only, not variable/callability/eval authority. }
unit wsm.bindatoms;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.source, wsm.domain, wsm.bind, wsm.bindindex;
type
  EAtomCensusError = class(Exception);
  TAtomPosition = (apTopLevel, apFirstChild, apOtherChild);
  TAtomResolution = (arDomainProjection, arUnresolved);
  TAtomRecord = record
    Name: RawByteString;
    Resolution: TAtomResolution;
    Key: TDomainKey; { only valid for arDomainProjection }
    Position: TAtomPosition; { purely syntactic: first child is not necessarily callable }
    TopFormIndex: SizeInt;
    ParentListByteOffset: SizeInt; { 0 for top-level }
    ChildIndex: SizeInt; { -1 for top-level }
    Depth: SizeInt;
    ByteOffset, Line, ByteColumn: SizeInt;
  end;
  TAtomRecords = array of TAtomRecord;
procedure CollectSourceAtoms(const Document: TSourceDocument;
  const Index: TBindIndex; out Atoms: TAtomRecords);
implementation
const
  MaxAtoms = 200000;
  MaxDepth = 256;

procedure AppendAtom(const Node: TSourceNode; const Index: TBindIndex;
  TopFormIndex, ParentOffset, ChildIndex, Depth: SizeInt;
  var Atoms: TAtomRecords; var Used: SizeInt);
var A: TAtomRecord; NewCapacity: SizeInt;
begin
  if Used >= MaxAtoms then raise EAtomCensusError.Create('atom census limit exceeded');
  if Length(Atoms) = Used then begin
    if Used = 0 then NewCapacity := 64 else NewCapacity := Used * 2;
    if NewCapacity > MaxAtoms then NewCapacity := MaxAtoms;
    SetLength(Atoms, NewCapacity);
  end;
  if (Node.ByteOffset < 1) or (Node.Line < 1) or (Node.ByteColumn < 1) or
     ((ParentOffset > 0) and (Node.ByteOffset <= ParentOffset)) then
    raise EAtomCensusError.Create('invalid atom source position');
  if Node.Text = '' then raise EAtomCensusError.Create('empty source atom');
  A.Name := Node.Text;
  A.TopFormIndex := TopFormIndex;
  A.ParentListByteOffset := ParentOffset;
  A.ChildIndex := ChildIndex;
  A.Depth := Depth;
  A.ByteOffset := Node.ByteOffset;
  A.Line := Node.Line;
  A.ByteColumn := Node.ByteColumn;
  A.Key.Width := 0;
  A.Key.Bits := 0;
  if ChildIndex < 0 then A.Position := apTopLevel
  else if ChildIndex = 0 then A.Position := apFirstChild
  else A.Position := apOtherChild;
  try
    A.Key := IndexedUkrainian(Index, Node.Text);
    A.Resolution := arDomainProjection;
  except
    on E: EBindError do begin
      if E.Message <> 'unknown Ukrainian surface' then raise;
      A.Resolution := arUnresolved;
    end;
  end;
  Atoms[Used] := A;
  Inc(Used);
end;

procedure Visit(const Node: TSourceNode; const Index: TBindIndex;
  TopFormIndex, ParentOffset, ChildIndex, Depth: SizeInt;
  var Atoms: TAtomRecords; var Used: SizeInt);
var I: SizeInt;
begin
  if Node = nil then raise EAtomCensusError.Create('nil source node');
  if Depth > MaxDepth then raise EAtomCensusError.Create('atom nesting limit');
  case Node.Kind of
    skList: begin
      for I := 0 to High(Node.Children) do
        Visit(Node.Children[I], Index, TopFormIndex, Node.ByteOffset,
          I, Depth+1, Atoms, Used);
    end;
    skAtom: begin
      if Length(Node.Children) <> 0 then
        raise EAtomCensusError.Create('atom with children');
      AppendAtom(Node, Index, TopFormIndex, ParentOffset,
        ChildIndex, Depth, Atoms, Used);
    end;
    skString: begin
      if Length(Node.Children) <> 0 then
        raise EAtomCensusError.Create('string with children');
      { String bytes are DATA, never domain surface names. }
    end;
    else raise EAtomCensusError.Create('unsupported AST kind');
  end;
end;

procedure CollectSourceAtoms(const Document: TSourceDocument;
  const Index: TBindIndex; out Atoms: TAtomRecords);
var I, Used: SizeInt;
begin
  SetLength(Atoms, 0);
  if Document = nil then raise EAtomCensusError.Create('nil source document');
  if (Index.Count <= 0) or (Length(Index.Slots) = 0) then
    raise EAtomCensusError.Create('uninitialized domain index');
  Used := 0;
  for I := 0 to High(Document.Forms) do
    Visit(Document.Forms[I], Index, I, 0, -1, 0, Atoms, Used);
  SetLength(Atoms, Used);
end;
end.
