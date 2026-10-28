{ G1: lossless UTF-8 token reader for Ukrainian .lisp surface.
  Mechanism only. Not canonical binary .sens, not eval, not SENS law authority.
  D2 exact coordinates come from wsm.domain, never from token spelling. }
unit wsm.sourcelex;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.domain;

type
  ESourceLexError = class(Exception);
  TSourceKind = (skTrivia, skComment, skOpen, skClose, skDot, skWord, skString);
  TSourceToken = record
    Kind: TSourceKind;
    Raw: RawByteString;
    StartByte, ByteLength, Line, Column: SizeInt;
    HasD2: Boolean;
    D2: TDomainKey;
  end;
  TSourceTokens = array of TSourceToken;

procedure ScanUkrainianSurface(const Source: RawByteString;
  out Tokens: TSourceTokens);
function RestoreUkrainianSurface(const Tokens: TSourceTokens): RawByteString;

implementation

const MAX_NESTING = 768;

type
  TCursor = record
    Offset, Line, Column: SizeInt;
  end;

function ByteNumber(const Source: RawByteString; Index: SizeInt): Integer;
begin
  Result := Ord(Source[Index]);
end;

procedure Advance(const Source: RawByteString; var P: TCursor);
begin
  if P.Offset > Length(Source) then Exit;
  if Source[P.Offset] = #10 then begin
    Inc(P.Line);
    P.Column := 1;
  end else Inc(P.Column);
  Inc(P.Offset);
end;

procedure Bad(const P: TCursor; const Why: String);
begin
  raise ESourceLexError.CreateFmt('source:%d:%d byte=%d: %s',
    [P.Line, P.Column, P.Offset, Why]);
end;

function Continuation(B: Integer): Boolean;
begin
  Result := (B >= $80) and (B <= $BF);
end;

procedure ValidateUtf8(const Source: RawByteString);
var P: TCursor; B, B2, B3, B4, Count: Integer; N: SizeInt;
begin
  N := Length(Source);
  P.Offset := 1; P.Line := 1; P.Column := 1;
  while P.Offset <= N do begin
    B := ByteNumber(Source, P.Offset);
    if B < $80 then begin
      if ((B < $20) and not (B in [9,10,13])) or (B = $7F) then
        Bad(P, 'control byte forbidden in .lisp source');
      Count := 1;
    end else begin
      if (B >= $C2) and (B <= $DF) then Count := 2
      else if (B >= $E0) and (B <= $EF) then Count := 3
      else if (B >= $F0) and (B <= $F4) then Count := 4
      else Bad(P, 'invalid UTF-8 leading byte');
      if P.Offset + Count - 1 > N then Bad(P, 'truncated UTF-8 sequence');
      B2 := ByteNumber(Source, P.Offset + 1);
      if not Continuation(B2) then Bad(P, 'invalid UTF-8 continuation');
      if ((B = $E0) and (B2 < $A0)) or
         ((B = $ED) and (B2 > $9F)) or
         ((B = $F0) and (B2 < $90)) or
         ((B = $F4) and (B2 > $8F)) then
        Bad(P, 'noncanonical UTF-8 scalar');
      if Count >= 3 then begin
        B3 := ByteNumber(Source, P.Offset + 2);
        if not Continuation(B3) then Bad(P, 'invalid UTF-8 continuation');
      end;
      if Count = 4 then begin
        B4 := ByteNumber(Source, P.Offset + 3);
        if not Continuation(B4) then Bad(P, 'invalid UTF-8 continuation');
      end;
    end;
    while Count > 0 do begin
      Advance(Source, P);
      Dec(Count);
    end;
  end;
end;

function Space(C: AnsiChar): Boolean;
begin
  Result := C in [' ',#9,#10,#13];
end;

function Boundary(C: AnsiChar): Boolean;
begin
  Result := Space(C) or (C in ['(',')','"',';']);
end;

procedure ScanUkrainianSurface(const Source: RawByteString;
  out Tokens: TSourceTokens);
var
  P, Start: TCursor;
  N, Capacity, Depth: SizeInt;
  C: AnsiChar;
  Kind: TSourceKind;

  procedure Emit(K: TSourceKind; const S: TCursor);
  begin
    if N = Capacity then begin
      if Capacity = 0 then Capacity := 32 else Capacity := Capacity * 2;
      SetLength(Tokens, Capacity);
    end;
    Tokens[N].Kind := K;
    Tokens[N].StartByte := S.Offset;
    Tokens[N].ByteLength := P.Offset - S.Offset;
    Tokens[N].Raw := Copy(Source, S.Offset, P.Offset - S.Offset);
    Tokens[N].Line := S.Line;
    Tokens[N].Column := S.Column;
    Tokens[N].HasD2 := False;
    Tokens[N].D2.Width := 0;
    Tokens[N].D2.Bits := 0;
    case K of
      skOpen: begin Tokens[N].HasD2 := True;
                    Tokens[N].D2 := ExactKey('10'); end;
      skClose: begin Tokens[N].HasD2 := True;
                     Tokens[N].D2 := ExactKey('01'); end;
      skDot: begin Tokens[N].HasD2 := True;
                   Tokens[N].D2 := ExactKey('11'); end;
    end;
    Inc(N);
  end;

begin
  ValidateUtf8(Source); { reject malformed data even in comments/strings }
  SetLength(Tokens, 0);
  N := 0; Capacity := 0; Depth := 0;
  P.Offset := 1; P.Line := 1; P.Column := 1;
  while P.Offset <= Length(Source) do begin
    Start := P;
    C := Source[P.Offset];
    if Space(C) then begin
      repeat
        Advance(Source, P);
      until (P.Offset > Length(Source)) or
        (not Space(Source[P.Offset]));
      Kind := skTrivia;
    end else if C = ';' then begin
      repeat
        Advance(Source, P);
      until (P.Offset > Length(Source)) or (Source[P.Offset] = #10);
      Kind := skComment;
    end else if C = '(' then begin
      if Depth >= MAX_NESTING then Bad(P, 'nesting exceeds reader bound');
      Inc(Depth); Advance(Source, P); Kind := skOpen;
    end else if C = ')' then begin
      if Depth = 0 then Bad(P, 'unmatched closing parenthesis');
      Dec(Depth); Advance(Source, P); Kind := skClose;
    end else if C = '"' then begin
      Advance(Source, P);
      while True do begin
        if P.Offset > Length(Source) then Bad(Start, 'unterminated string');
        if Source[P.Offset] = '"' then begin
          Advance(Source, P); Break;
        end;
        if Source[P.Offset] = #92 then begin
          Advance(Source, P);
          if P.Offset > Length(Source) then
            Bad(Start, 'unterminated string escape');
        end;
        Advance(Source, P);
      end;
      Kind := skString;
    end else if (C = '.') and
      ((P.Offset = Length(Source)) or Boundary(Source[P.Offset+1])) then begin
      if Depth = 0 then Bad(P, 'dot outside list');
      Advance(Source, P);
      Kind := skDot;
    end else begin
      repeat
        Advance(Source, P);
      until (P.Offset > Length(Source)) or Boundary(Source[P.Offset]);
      Kind := skWord;
    end;
    Emit(Kind, Start);
  end;
  if Depth <> 0 then Bad(P, 'unclosed list at EOF');
  SetLength(Tokens, N);
end;

function RestoreUkrainianSurface(const Tokens: TSourceTokens): RawByteString;
var I, Total, Offset: SizeInt;
begin
  Total := 0;
  for I := 0 to High(Tokens) do begin
    if (Tokens[I].ByteLength <> Length(Tokens[I].Raw)) or
       (Tokens[I].StartByte <> Total + 1) then
      raise ESourceLexError.Create('noncontiguous or modified token span');
    if Total > High(SizeInt) - Tokens[I].ByteLength then
      raise ESourceLexError.Create('source length overflow');
    Inc(Total, Tokens[I].ByteLength);
  end;
  SetLength(Result, Total);
  Offset := 1;
  for I := 0 to High(Tokens) do
    if Tokens[I].ByteLength > 0 then begin
      Move(Tokens[I].Raw[1], Result[Offset], Tokens[I].ByteLength);
      Inc(Offset, Tokens[I].ByteLength);
    end;
end;
end.
