{ G1: Ukrainian .lisp structural reader. No SENS laws, binder, or .sens encoder. }
unit wsm.source;
{$mode objfpc}{$H+}{$B-}
interface
uses SysUtils;

type
  ESourceError = class(Exception);
  TSourceKind = (skOpen, skClose, skAtom, skString, skDot);
  TSourceToken = record
    Kind: TSourceKind;
    Raw: RawByteString; // exact original UTF-8 bytes; no normalization
    ByteOffset: SizeInt; // 0-based
    Line, Column: SizeInt; // 1-based, UTF-8 scalar columns
    Depth: SizeInt; // nesting before this token; closing uses resulting depth
  end;
  TSourceDocument = record
    Tokens: array of TSourceToken;
    FormCount: SizeInt;
    ByteCount: SizeInt;
  end;

function ReadUkrainianProjection(const Source: RawByteString): TSourceDocument;

implementation

type
  TFrame = record
    HasHead, HasDot, HasTail: Boolean;
  end;

procedure BadUtf8(const Position: SizeInt);
begin
  raise ESourceError.CreateFmt('invalid UTF-8 at byte=%d', [Position-1]);
end;

procedure ValidateUtf8(const S: RawByteString);
var
  I, J, N, L: SizeInt;
  B, B1, B2: Byte;
  Value: LongWord;
begin
  L := Length(S);
  if L > 64 * 1024 * 1024 then
    raise ESourceError.Create('source exceeds 64 MiB');
  I := 1;
  while I <= L do begin
    B := Ord(S[I]);
    if (B < 32) and (B <> 9) and (B <> 10) and (B <> 13) then
      BadUtf8(I);
    if B = 127 then BadUtf8(I);
    if B < 128 then N := 1
    else if (B >= 194) and (B <= 223) then N := 2
    else if (B >= 224) and (B <= 239) then N := 3
    else if (B >= 240) and (B <= 244) then N := 4
    else begin BadUtf8(I); Exit; end;
    if I + N - 1 > L then BadUtf8(I);
    Value := B and ((1 shl (7-N))-1);
    for J := 1 to N-1 do begin
      B1 := Ord(S[I+J]);
      if (B1 and $C0) <> $80 then BadUtf8(I+J);
      Value := (Value shl 6) or (B1 and $3F);
    end;
    if (N = 2) and (Value < $80) then BadUtf8(I);
    if (N = 3) and (Value < $800) then BadUtf8(I);
    if (N = 4) and (Value < $10000) then BadUtf8(I);
    if (Value >= $D800) and (Value <= $DFFF) then BadUtf8(I);
    if Value > $10FFFF then BadUtf8(I);
    if Value = $FEFF then BadUtf8(I); // no hidden BOM in exact source
    if N > 1 then begin
      B2 := Ord(S[I+1]);
      if (B = $E0) and (B2 < $A0) then BadUtf8(I);
      if (B = $ED) and (B2 >= $A0) then BadUtf8(I);
      if (B = $F0) and (B2 < $90) then BadUtf8(I);
      if (B = $F4) and (B2 >= $90) then BadUtf8(I);
    end;
    Inc(I,N);
  end;
end;

function ReadUkrainianProjection(const Source: RawByteString): TSourceDocument;
var
  P, Line, Col, Depth, Count, Start, AtLine, AtCol, AtDepth: SizeInt;
  LastCR, Closed, Escaped: Boolean;
  C: AnsiChar;
  Frames: array of TFrame;

  procedure Fail(const Why: String);
  begin
    raise ESourceError.CreateFmt('line=%d column=%d byte=%d %s',
                                  [Line,Col,P-1,Why]);
  end;

  procedure Step;
  var B: Byte;
  begin
    C := Source[P];
    B := Ord(C);
    if C = #13 then begin Inc(Line); Col := 1; LastCR := True; end
    else if C = #10 then begin
      if not LastCR then Inc(Line);
      Col := 1; LastCR := False;
    end
    else begin
      if (B and $C0) <> $80 then Inc(Col);
      LastCR := False;
    end;
    Inc(P);
  end;

  procedure EmitToken(const Kind: TSourceKind; const Text: RawByteString;
                      const BPos, LPos, CPos, Nesting: SizeInt);
  begin
    if Count = Length(Result.Tokens) then begin
      if Count = 0 then SetLength(Result.Tokens,16)
      else SetLength(Result.Tokens,Count*2);
    end;
    Result.Tokens[Count].Kind := Kind;
    Result.Tokens[Count].Raw := Text;
    Result.Tokens[Count].ByteOffset := BPos-1;
    Result.Tokens[Count].Line := LPos;
    Result.Tokens[Count].Column := CPos;
    Result.Tokens[Count].Depth := Nesting;
    Inc(Count);
  end;

  procedure BeginValue;
  begin
    if Depth = 0 then begin Inc(Result.FormCount); Exit; end;
    if Frames[Depth-1].HasDot then begin
      if Frames[Depth-1].HasTail then Fail('more than one dotted tail');
      Frames[Depth-1].HasTail := True;
    end
    else Frames[Depth-1].HasHead := True;
  end;

begin
  ValidateUtf8(Source);
  Result.FormCount := 0; Result.ByteCount := Length(Source);
  SetLength(Result.Tokens,0); SetLength(Frames,0);
  Count := 0; P := 1; Line := 1; Col := 1; Depth := 0; LastCR := False;
  while P <= Length(Source) do begin
    C := Source[P];
    if C in [' ',#9,#10,#13] then begin Step; Continue; end;
    if C = ';' then begin
      while P <= Length(Source) do begin
        if Source[P] in [#10,#13] then Break;
        Step;
      end;
      Continue;
    end;
    Start := P; AtLine := Line; AtCol := Col; AtDepth := Depth;
    case C of
      '(':
        begin
          BeginValue;
          if Depth >= 1024 then Fail('maximum nesting depth exceeded');
          EmitToken(skOpen,'(',Start,AtLine,AtCol,AtDepth);
          SetLength(Frames,Depth+1);
          Frames[Depth].HasHead := False;
          Frames[Depth].HasDot := False;
          Frames[Depth].HasTail := False;
          Inc(Depth); Step;
        end;
      ')':
        begin
          if Depth = 0 then Fail('unexpected close parenthesis');
          if Frames[Depth-1].HasDot and not Frames[Depth-1].HasTail then
            Fail('missing dotted tail');
          Dec(Depth);
          SetLength(Frames,Depth);
          EmitToken(skClose,')',Start,AtLine,AtCol,Depth);
          Step;
        end;
      '"':
        begin
          Step; Closed := False; Escaped := False;
          while P <= Length(Source) do begin
            C := Source[P];
            Step;
            if Escaped then Escaped := False
            else if C = #92 then Escaped := True
            else if C = '"' then begin Closed := True; Break; end;
          end;
          if not Closed then Fail('unterminated string');
          BeginValue;
          EmitToken(skString,Copy(Source,Start,P-Start),Start,AtLine,AtCol,AtDepth);
        end;
    else
      begin
        while P <= Length(Source) do begin
          C := Source[P];
          if C in [' ',#9,#10,#13,'(',')',';','"'] then Break;
          Step;
        end;
        if P = Start then Fail('invalid lexical byte');
        if (P-Start = 1) and (Source[Start] = '.') then begin
          if Depth = 0 then Fail('dotted marker outside list');
          if not Frames[Depth-1].HasHead then Fail('dotted marker lacks head');
          if Frames[Depth-1].HasDot then Fail('duplicate dotted marker');
          Frames[Depth-1].HasDot := True;
          EmitToken(skDot,'.',Start,AtLine,AtCol,AtDepth);
        end
        else begin
          BeginValue;
          EmitToken(skAtom,Copy(Source,Start,P-Start),Start,AtLine,AtCol,AtDepth);
        end;
      end;
    end;
  end;
  if Depth <> 0 then Fail('unclosed list');
  SetLength(Result.Tokens,Count);
end;

end.
