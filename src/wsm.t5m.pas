{ Physical T5M transport for pinned SENS. Mechanical codec ONLY.
  Authority: external/sens@1f1bf676.../research/zig-codecs/t5m.zig.
  Each byte encodes five base-3 trits; 2 is separator/final padding.
  Exact widths come from word boundaries, not a semantic name or domain law. }
unit wsm.t5m;
{$mode objfpc}{$H+}
interface
uses SysUtils;

const
  T5MMaxBytes = 4 * 1024 * 1024;
  T5MMaxWords = 1000000; { explicit memory-admission limit, not a SENS law }

type
  ET5MError = class(Exception);
  TExactWord = record
    Width: SizeInt;
    Bits: RawByteString;
  end;
  TExactWords = array of TExactWord;

function DecodeT5M(const Physical: RawByteString): TExactWords;
function EncodeT5M(const Words: TExactWords): RawByteString;

implementation

procedure Invalid(const Why: String);
begin
  raise ET5MError.Create('T5M-FAIL ' + Why);
end;

function DecodeT5M(const Physical: RawByteString): TExactWords;
var
  T: array of Byte;
  I, J, V, N, Tail, Body, Width, Count, W, Offset: SizeInt;
begin
  N := Length(Physical);
  if N = 0 then Invalid('empty physical program');
  if N > T5MMaxBytes then Invalid('physical byte limit');
  SetLength(T,N*5);
  for I := 0 to N-1 do begin
    V := Ord(Physical[I+1]);
    if V >= 243 then Invalid('physical byte outside 0..242 at offset=' + IntToStr(I));
    for J := 4 downto 0 do begin
      T[I*5+J] := V mod 3;
      V := V div 3;
    end;
  end;

  Tail := 0;
  while (Tail < Length(T)) and (T[High(T)-Tail] = 2) do Inc(Tail);
  if Tail >= 5 then Invalid('invalid physical padding (>= five terminal separators)');
  Body := Length(T)-Tail;
  if Body = 0 then Invalid('empty domain word');

  Count := 1; Width := 0;
  for I := 0 to Body-1 do
    if T[I] = 2 then begin
      if Width = 0 then Invalid('empty domain word or consecutive separators');
      if Count >= T5MMaxWords then Invalid('word count limit');
      Inc(Count); Width := 0;
    end else
      Inc(Width);
  if Width = 0 then Invalid('empty last word');

  SetLength(Result,Count);
  W := 0; Width := 0;
  for I := 0 to Body-1 do begin
    if T[I] = 2 then begin
      Result[W].Width := Width;
      SetLength(Result[W].Bits,Width);
      Inc(W); Width := 0;
    end else Inc(Width);
  end;
  Result[W].Width := Width;
  SetLength(Result[W].Bits,Width);

  W := 0; Offset := 0;
  for I := 0 to Body-1 do begin
    if T[I] = 2 then begin Inc(W); Offset := 0; end
    else begin
      Inc(Offset);
      if T[I] = 0 then Result[W].Bits[Offset] := '0'
      else Result[W].Bits[Offset] := '1';
    end;
  end;
end;

function EncodeT5M(const Words: TExactWords): RawByteString;
var
  I, J, Width, Needed, TCount, ByteIndex: SizeInt;
  Current, Used: Integer;

  procedure PutTrit(Digit: Integer);
  begin
    Current := Current * 3 + Digit;
    Inc(Used);
    if Used = 5 then begin
      Inc(ByteIndex);
      Result[ByteIndex] := AnsiChar(Current);
      Current := 0;
      Used := 0;
    end;
  end;

begin
  if Length(Words) = 0 then Invalid('empty physical program');
  if Length(Words) > T5MMaxWords then Invalid('word count limit');
  TCount := Length(Words)-1;
  for I := 0 to High(Words) do begin
    Width := Words[I].Width;
    if (Width = 0) or (Width <> Length(Words[I].Bits)) then
      Invalid('missing word or inexact width');
    if Width > T5MMaxBytes*5-TCount then Invalid('physical byte limit');
    Inc(TCount, Width);
    for J := 1 to Width do
      if not (Words[I].Bits[J] in ['0','1']) then
        Invalid('nonbinary word');
  end;
  Needed := (TCount+4) div 5;
  if Needed > T5MMaxBytes then Invalid('physical byte limit');
  SetLength(Result,Needed);
  ByteIndex := 0; Current := 0; Used := 0;
  for I := 0 to High(Words) do begin
    if I <> 0 then PutTrit(2);
    for J := 1 to Words[I].Width do
      PutTrit(Ord(Words[I].Bits[J])-Ord('0'));
  end;
  while Used <> 0 do PutTrit(2);
  if ByteIndex <> Needed then Invalid('internal physical size mismatch');
end;
end.
