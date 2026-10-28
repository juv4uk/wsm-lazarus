{ Syntactic source-AST head projections through the pinned SENS domain index.
  This unit does NOT decide callability, evaluation, quotation, macro expansion,
  variable binding or semantic admission. Heads may be literal data. }
unit wsm.bindtree;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.domain, wsm.bind, wsm.bindindex, wsm.source;
type
  THeadState = (hsBound, hsUnknown, hsNonAtom);
  THeadOccurrence = record
    State: THeadState;
    Key: TDomainKey; { meaningful ONLY when State = hsBound }
    Name: RawByteString;
    ByteOffset, Line, ByteColumn: SizeInt;
  end;
  THeadOccurrences = array of THeadOccurrence;
  EBindTreeError = class(Exception)
  public
    ByteOffset, Line, ByteColumn: SizeInt;
    constructor CreateAt(const Problem: String;
      AOffset, ALine, AColumn: SizeInt);
  end;
procedure CollectHeadOccurrences(const Source: TSourceDocument;
  const Index: TBindIndex; out Heads: THeadOccurrences);
procedure RequireBoundHeads(const Heads: THeadOccurrences);
implementation
const MaxHeadOccurrences = 200000;
constructor EBindTreeError.CreateAt(const Problem: String;
  AOffset, ALine, AColumn: SizeInt);
begin
  inherited Create(Problem);
  ByteOffset := AOffset;
  Line := ALine;
  ByteColumn := AColumn;
end;
procedure AppendHead(var Heads: THeadOccurrences;
  const Node: TSourceNode; const Index: TBindIndex);
var N: SizeInt; H: THeadOccurrence; Head: TSourceNode;
begin
  if Length(Node.Children) = 0 then Exit; { () has no syntactic head }
  if Length(Heads) >= MaxHeadOccurrences then
    raise EBindTreeError.CreateAt('head occurrence limit',
      Node.ByteOffset, Node.Line, Node.ByteColumn);
  Head := Node.Children[0];
  if Head = nil then raise EBindTreeError.CreateAt('nil AST child',
    Node.ByteOffset, Node.Line, Node.ByteColumn);
  H.Name := '';
  H.Key.Width := 0;
  H.Key.Bits := 0;
  H.ByteOffset := Head.ByteOffset;
  H.Line := Head.Line;
  H.ByteColumn := Head.ByteColumn;
  H.State := hsNonAtom;
  if Head.Kind = skAtom then begin
    H.Name := Head.Text;
    try
      H.Key := IndexedUkrainian(Index, H.Name);
      H.State := hsBound;
    except
      on E: EBindError do begin
        if E.Message <> 'unknown Ukrainian surface' then raise;
        H.State := hsUnknown;
      end;
    end;
  end;
  N := Length(Heads);
  SetLength(Heads, N+1);
  Heads[N] := H;
end;
procedure Visit(const Node: TSourceNode; const Index: TBindIndex;
  var Heads: THeadOccurrences);
var I: SizeInt;
begin
  if Node = nil then raise EBindTreeError.Create('nil AST node');
  if Node.Kind <> skList then Exit;
  AppendHead(Heads, Node, Index);
  for I := 0 to High(Node.Children) do Visit(Node.Children[I], Index, Heads);
end;
procedure CollectHeadOccurrences(const Source: TSourceDocument;
  const Index: TBindIndex; out Heads: THeadOccurrences);
var I: SizeInt;
begin
  SetLength(Heads, 0);
  if Source = nil then raise EBindTreeError.Create('nil AST document');
  if (Index.Count <= 0) or (Length(Index.Slots) = 0) then
    raise EBindTreeError.Create('uninitialized domain index');
  for I := 0 to High(Source.Forms) do Visit(Source.Forms[I], Index, Heads);
end;
procedure RequireBoundHeads(const Heads: THeadOccurrences);
var I: SizeInt; H: THeadOccurrence;
begin
  for I := 0 to High(Heads) do begin
    H := Heads[I];
    if H.State = hsBound then Continue;
    if H.State = hsUnknown then
      raise EBindTreeError.CreateAt(
        'unknown Ukrainian head: ' + String(H.Name),
        H.ByteOffset, H.Line, H.ByteColumn);
    raise EBindTreeError.CreateAt('non-atomic structural head',
      H.ByteOffset, H.Line, H.ByteColumn);
  end;
end;
end.
