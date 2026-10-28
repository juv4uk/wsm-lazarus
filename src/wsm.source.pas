{ G1.1: UTF-8 structural reader for Ukrainian .lisp projection.
  NOT a canonical binary .sens decoder, domain binder, evaluator or SIR1 compiler.
  Every atom/string is opaque data. SENS alone supplies semantic authority. }
unit wsm.source;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;

type
  ESourceError = class(Exception)
  public
    ByteOffset, Line, ByteColumn: SizeInt;
    constructor CreateAt(const Problem: String; AOffset, ALine, AColumn: SizeInt);
  end;

  TSourceKind = (skList, skAtom, skString);
  TSourceNode = class
  private
    FChildCount: SizeInt; { фактично створені діти, не місткість }
    procedure AddBuffered(Child: TSourceNode);
    procedure Seal;
  public
    Kind: TSourceKind;
    Text: RawByteString;     { exact UTF-8 source bytes, including string quotes }
    ByteOffset, Line, ByteColumn: SizeInt; { source, 1-based bytes }
    Children: array of TSourceNode;
    destructor Destroy; override;
    procedure Add(Child: TSourceNode);
  end;

  TSourceDocument = class
  private
    FFormCount: SizeInt; { фактичні корені, не місткість }
    procedure AddBuffered(Item: TSourceNode);
    procedure Seal;
  public
    Forms: array of TSourceNode;
    destructor Destroy; override;
    procedure Add(Item: TSourceNode);
  end;

function ReadUkrainianSource(const Source: RawByteString): TSourceDocument;

implementation

const
  MaxSourceBytes = 16 * 1024 * 1024;
  MaxSyntaxDepth = 256;
  MaxSourceNodes = 65536; { ресурсний ліміт читача, не закон SENS }

constructor ESourceError.CreateAt(const Problem: String;
  AOffset, ALine, AColumn: SizeInt);
begin
  inherited Create(Problem);
  ByteOffset := AOffset;
  Line := ALine;
  ByteColumn := AColumn;
end;

destructor TSourceNode.Destroy;
var I: SizeInt;
begin
  for I := 0 to High(Children) do Children[I].Free;
  inherited Destroy;
end;

procedure TSourceNode.Add(Child: TSourceNode);
var N: SizeInt;
begin
  N := Length(Children);
  SetLength(Children, N+1);
  Children[N] := Child;
  FChildCount := N + 1;
end;

procedure TSourceNode.AddBuffered(Child: TSourceNode);
var Capacity: SizeInt;
begin
  if FChildCount = Length(Children) then begin
    Capacity := Length(Children);
    if Capacity = 0 then Capacity := 8
    else Capacity := Capacity * 2;
    SetLength(Children, Capacity);
  end;
  Children[FChildCount] := Child;
  Inc(FChildCount);
end;

procedure TSourceNode.Seal;
begin
  SetLength(Children, FChildCount);
end;

destructor TSourceDocument.Destroy;
var I: SizeInt;
begin
  for I := 0 to High(Forms) do Forms[I].Free;
  inherited Destroy;
end;

procedure TSourceDocument.Add(Item: TSourceNode);
var N: SizeInt;
begin
  N := Length(Forms);
  SetLength(Forms, N+1);
  Forms[N] := Item;
  FFormCount := N + 1;
end;

procedure TSourceDocument.AddBuffered(Item: TSourceNode);
var Capacity: SizeInt;
begin
  if FFormCount = Length(Forms) then begin
    Capacity := Length(Forms);
    if Capacity = 0 then Capacity := 8
    else Capacity := Capacity * 2;
    SetLength(Forms, Capacity);
  end;
  Forms[FFormCount] := Item;
  Inc(FFormCount);
end;

procedure TSourceDocument.Seal;
begin
  SetLength(Forms, FFormCount);
end;

procedure ErrorAt(const Source: RawByteString; Offset: SizeInt;
  const Problem: String);
var I, L, C: SizeInt;
begin
  L := 1; C := 1;
  for I := 1 to Offset-1 do
    if Source[I] = #13 then begin Inc(L); C := 1; end
    else if Source[I] = #10 then begin
      if (I = 1) or (Source[I-1] <> #13) then Inc(L);
      C := 1;
    end else Inc(C);
  raise ESourceError.CreateAt(Problem, Offset, L, C);
end;

procedure ValidateUTF8(const S: RawByteString);
var I, J, N, B, B1: SizeInt;
begin
  if Length(S) > MaxSourceBytes then ErrorAt(S, 1, 'source size limit');
  I := 1;
  while I <= Length(S) do begin
    B := Ord(S[I]);
    if B = 0 then ErrorAt(S, I, 'NUL byte is not valid source');
    if B < $80 then begin
      if (B < $20) and not (B in [9, 10, 13]) then
        ErrorAt(S, I, 'unsupported control byte');
      Inc(I);
      Continue;
    end;
    if (B >= $C2) and (B <= $DF) then N := 2
    else if (B >= $E0) and (B <= $EF) then N := 3
    else if (B >= $F0) and (B <= $F4) then N := 4
    else ErrorAt(S, I, 'invalid UTF-8 leading byte');
    if I+N-1 > Length(S) then ErrorAt(S, I, 'truncated UTF-8');
    for J := 1 to N-1 do
      if (Ord(S[I+J]) < $80) or (Ord(S[I+J]) > $BF) then
        ErrorAt(S, I+J, 'invalid UTF-8 continuation');
    B1 := Ord(S[I+1]);
    if ((B = $E0) and (B1 < $A0)) or
       ((B = $ED) and (B1 >= $A0)) or
       ((B = $F0) and (B1 < $90)) or
       ((B = $F4) and (B1 > $8F)) then
      ErrorAt(S, I, 'overlong/surrogate/out-of-range UTF-8');
    Inc(I, N);
  end;
end;

type
  TScanner = class
  private
    FSource: RawByteString;
    FPos, FLine, FColumn: SizeInt;
    FNodes: SizeInt;
    function Current: AnsiChar;
    procedure Advance;
    procedure SkipTrivia;
    procedure Fail(const Problem: String);
    function ParseForm(Depth: SizeInt): TSourceNode;
  public
    constructor Create(const S: RawByteString);
    function Parse: TSourceDocument;
  end;

constructor TScanner.Create(const S: RawByteString);
begin
  inherited Create;
  FSource := S;
  FPos := 1; FLine := 1; FColumn := 1;
  FNodes := 0;
end;

function TScanner.Current: AnsiChar;
begin
  if FPos > Length(FSource) then Result := #0
  else Result := FSource[FPos];
end;

procedure TScanner.Advance;
var Previous, C: AnsiChar;
begin
  if FPos > Length(FSource) then Exit;
  C := FSource[FPos];
  Previous := #0;
  if FPos > 1 then Previous := FSource[FPos-1];
  Inc(FPos);
  if C = #13 then begin Inc(FLine); FColumn := 1; end
  else if C = #10 then begin
    if Previous <> #13 then Inc(FLine);
    FColumn := 1;
  end else Inc(FColumn);
end;

procedure TScanner.Fail(const Problem: String);
begin
  raise ESourceError.CreateAt(Problem, FPos, FLine, FColumn);
end;

procedure TScanner.SkipTrivia;
begin
  while FPos <= Length(FSource) do begin
    if Current in [' ', #9, #10, #13] then Advance
    else if Current = ';' then begin
      while (FPos <= Length(FSource)) and
            not (Current in [#10, #13]) do Advance;
    end else Break;
  end;
end;

function TScanner.ParseForm(Depth: SizeInt): TSourceNode;
var Start: SizeInt; C: AnsiChar; Finished: Boolean;
begin
  if Depth > MaxSyntaxDepth then Fail('source nesting limit');
  if FPos > Length(FSource) then Fail('unexpected end of source');
  { Перевірка до алокації: під час відмови батьківські AST звільняються. }
  if FNodes >= MaxSourceNodes then Fail('перевищено ліміт вузлів джерела');
  Inc(FNodes);
  Result := TSourceNode.Create;
  Result.ByteOffset := FPos;
  Result.Line := FLine;
  Result.ByteColumn := FColumn;
  try
    if Current = '(' then begin
      Result.Kind := skList;
      Advance;
      while True do begin
        SkipTrivia;
        if FPos > Length(FSource) then Fail('unclosed list');
        if Current = ')' then begin Advance; Break; end;
        Result.AddBuffered(ParseForm(Depth+1));
      end;
    end
    else if Current = ')' then Fail('unexpected closing parenthesis')
    else if Current = '"' then begin
      Result.Kind := skString;
      Start := FPos;
      Advance;
      Finished := False;
      while FPos <= Length(FSource) do begin
        C := Current;
        if C = '"' then begin Advance; Finished := True; Break; end;
        if C = '\' then begin
          Advance;
          if FPos > Length(FSource) then Fail('unterminated string escape');
        end;
        Advance;
      end;
      if not Finished then Fail('unterminated string');
      Result.Text := Copy(FSource, Start, FPos-Start);
    end
    else begin
      Result.Kind := skAtom;
      Start := FPos;
      while FPos <= Length(FSource) do begin
        C := Current;
        if C in [' ', #9, #10, #13, '(', ')', ';', '"'] then Break;
        Advance;
      end;
      if FPos = Start then Fail('unexpected source character');
      Result.Text := Copy(FSource, Start, FPos-Start);
    end;
    { Ні один споживач не побачить зарезервовані nil-слоти. }
    Result.Seal;
  except
    Result.Free;
    raise;
  end;
end;

function TScanner.Parse: TSourceDocument;
begin
  Result := TSourceDocument.Create;
  try
    SkipTrivia;
    while FPos <= Length(FSource) do begin
      Result.AddBuffered(ParseForm(0));
      SkipTrivia;
    end;
    Result.Seal;
  except
    Result.Free;
    raise;
  end;
end;

function ReadUkrainianSource(const Source: RawByteString): TSourceDocument;
var S: TScanner;
begin
  ValidateUTF8(Source);
  S := TScanner.Create(Source);
  try
    Result := S.Parse;
  finally
    S.Free;
  end;
end;
end.
