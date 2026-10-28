{ G1.3: mechanical D2 AST over already-decoded exact T5M words.
  Structural protocol mirrors pinned SENS canonical_reader.rs.
  This neither decides callability nor executes any SENS law or Core4. }
unit wsm.d2source;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m;

const
  MaxD2SyntaxDepth = 256;
  MaxD2Words = 100000; { mechanical resource admission, NOT a language law }

type
  ED2SourceError = class(Exception)
  public
    WordIndex: SizeInt;  { 1-based; EOF is count+1 }
    constructor CreateAt(const Problem: String; AtWord: SizeInt);
  end;

  TD2Kind = (dkIdentity, dkEmpty, dkList, dkPair);
  TD2Node = class
  public
    Kind: TD2Kind;
    WordIndex: SizeInt;
    Width: SizeInt;
    Bits: RawByteString;
    Children: array of TD2Node; { lists: items; dotted pairs: head, tail }
    destructor Destroy; override;
    procedure Add(ChildNode: TD2Node);
  end;

  TD2Document = class
  public
    Roots: array of TD2Node;
    destructor Destroy; override;
    procedure Add(RootNode: TD2Node);
  end;

function ParseD2Words(const Words: TExactWords): TD2Document;
function ReadD2T5M(const Physical: RawByteString): TD2Document;

implementation

constructor ED2SourceError.CreateAt(const Problem: String; AtWord: SizeInt);
begin
  inherited Create(Problem);
  WordIndex := AtWord;
end;

destructor TD2Node.Destroy;
var I: SizeInt;
begin
  for I := 0 to High(Children) do Children[I].Free;
  inherited Destroy;
end;

procedure TD2Node.Add(ChildNode: TD2Node);
var N: SizeInt;
begin
  N := Length(Children);
  SetLength(Children, N + 1);
  Children[N] := ChildNode;
end;

destructor TD2Document.Destroy;
var I: SizeInt;
begin
  for I := 0 to High(Roots) do Roots[I].Free;
  inherited Destroy;
end;

procedure TD2Document.Add(RootNode: TD2Node);
var N: SizeInt;
begin
  N := Length(Roots);
  SetLength(Roots, N + 1);
  Roots[N] := RootNode;
end;

procedure ValidateWords(const Words: TExactWords);
var I, J, Width: SizeInt;
begin
  if Length(Words) = 0 then
    raise ED2SourceError.CreateAt('empty exact-word sequence', 1);
  if Length(Words) > MaxD2Words then
    raise ED2SourceError.CreateAt('D2 structural reader word limit', 1);
  for I := 0 to High(Words) do begin
    Width := Length(Words[I]);
    { The current pinned canonical reader has W1 and W3..W9 payloads
      plus the structural W2. D10/D12+ execution is NOT admitted here. }
    if (Width < 1) or (Width > 9) then
      raise ED2SourceError.CreateAt('unsupported exact source width', I + 1);
    for J := 1 to Width do
      if not (Words[I][J] in ['0', '1']) then
        raise ED2SourceError.CreateAt('nonbinary exact source word', I + 1);
  end;
end;

type
  TD2Parser = class
  private
    FWords: TExactWords;
    FPosition: SizeInt;
    procedure Fail(const Problem: String);
    procedure SkipSeparators;
    function IsD2(const Code: RawByteString): Boolean;
    function ParseExpr(Depth: SizeInt): TD2Node;
    function ParseList(Depth: SizeInt): TD2Node;
  public
    constructor Create(const Words: TExactWords);
    function Parse: TD2Document;
  end;

constructor TD2Parser.Create(const Words: TExactWords);
begin
  inherited Create;
  FWords := Words;
  FPosition := 0;
end;

procedure TD2Parser.Fail(const Problem: String);
begin
  raise ED2SourceError.CreateAt(Problem, FPosition + 1);
end;

function TD2Parser.IsD2(const Code: RawByteString): Boolean;
begin
  Result := (FPosition < Length(FWords)) and (FWords[FPosition] = Code);
end;

procedure TD2Parser.SkipSeparators;
begin
  while IsD2('00') do Inc(FPosition);
end;

function TD2Parser.ParseExpr(Depth: SizeInt): TD2Node;
var Bits: RawByteString;
begin
  if Depth > MaxD2SyntaxDepth then Fail('D2 nesting exceeds AST depth limit');
  if FPosition >= Length(FWords) then Fail('expected exact D2 expression');
  Bits := FWords[FPosition];
  if Length(Bits) = 2 then begin
    if Bits = '10' then Exit(ParseList(Depth));
    if Bits = '01' then Fail('unexpected D2 close 01');
    if Bits = '11' then Fail('misplaced D2 dot 11');
    if Bits = '00' then Fail('D2 separator 00 in expression position');
  end;
  Result := TD2Node.Create;
  Result.WordIndex := FPosition + 1;
  Result.Width := Length(Bits);
  Result.Bits := Bits;
  if Bits = '000' then Result.Kind := dkEmpty
  else Result.Kind := dkIdentity;
  Inc(FPosition);
end;

function TD2Parser.ParseList(Depth: SizeInt): TD2Node;
var ListNode, Tail, NewPair: TD2Node; I: SizeInt;
begin
  ListNode := TD2Node.Create;
  ListNode.Kind := dkList;
  ListNode.WordIndex := FPosition + 1;
  Inc(FPosition); { consume D2 10 OPEN }
  try
    while True do begin
      SkipSeparators;
      if FPosition >= Length(FWords) then
        Fail('unterminated D2 10 structure');
      if IsD2('01') then begin
        Inc(FPosition);
        Result := ListNode;
        Exit;
      end;
      if IsD2('11') then begin
        if Length(ListNode.Children) = 0 then
          Fail('D2 dot needs a head expression');
        Inc(FPosition);
        SkipSeparators;
        if (FPosition >= Length(FWords)) or IsD2('01') or IsD2('11') then
          Fail('D2 dot needs exactly one tail expression');
        Tail := nil;
        try
          Tail := ParseExpr(Depth + 1);
          SkipSeparators;
          if not IsD2('01') then
            Fail('D2 dotted tail must end with 01');
          Inc(FPosition);
          Result := Tail;
          Tail := nil;
          for I := High(ListNode.Children) downto 0 do begin
            NewPair := TD2Node.Create;
            NewPair.Kind := dkPair;
            NewPair.WordIndex := ListNode.WordIndex;
            NewPair.Add(ListNode.Children[I]);
            ListNode.Children[I] := nil;
            NewPair.Add(Result);
            Result := NewPair;
          end;
          ListNode.Free;
          Exit;
        finally
          Tail.Free;
        end;
      end;
      ListNode.Add(ParseExpr(Depth + 1));
    end;
  except
    ListNode.Free;
    raise;
  end;
end;

function TD2Parser.Parse: TD2Document;
begin
  Result := TD2Document.Create;
  try
    SkipSeparators;
    while FPosition < Length(FWords) do begin
      Result.Add(ParseExpr(0));
      SkipSeparators;
    end;
  except
    Result.Free;
    raise;
  end;
end;

function ParseD2Words(const Words: TExactWords): TD2Document;
var P: TD2Parser;
begin
  ValidateWords(Words);
  P := TD2Parser.Create(Words);
  try
    Result := P.Parse;
  finally
    P.Free;
  end;
end;

function ReadD2T5M(const Physical: RawByteString): TD2Document;
var Words: TExactWords;
begin
  { Physical byte validation belongs to the already-merged upstream-derived
    T5M codec. D2 parsing does not duplicate the transport grammar. }
  DecodeT5M(Physical, Words);
  Result := ParseD2Words(Words);
end;

end.
