{ G1.2: physical T5M .sens transport, strictly from juv4uk/sens
  scripts/sens_t5_t5m_codec.py::encode_t5m_projection/decode_t5m_bytes.
  It returns exact words as bytes "0"/"1" and does NOT infer domain,
  SENS semantics, callable status or D2 syntax from their widths. }
unit wsm.t5m;
{$mode objfpc}{$H+}
interface
uses SysUtils;
const MAX_T5M_FILE_BYTES = 4 * 1024 * 1024;
type
  ET5MError = class(Exception);
  TExactWords = array of RawByteString;

function EncodeT5M(const Words: TExactWords): RawByteString;
procedure DecodeT5M(const Physical: RawByteString; out Words: TExactWords);

implementation

function EncodeT5M(const Words: TExactWords): RawByteString;
var
  I, J, K, P, N, TritCount, Padded, V, Total: SizeInt;
  Trits: RawByteString;
begin
  if Length(Words) = 0 then raise ET5MError.Create('empty T5M word list');
  Total := 0;
  for I := 0 to High(Words) do begin
    N := Length(Words[I]);
    if (N = 0) or (N > MAX_T5M_FILE_BYTES * 5) then
      raise ET5MError.Create('empty/oversized exact word');
    for J := 1 to N do
      if not (Words[I][J] in ['0','1']) then
        raise ET5MError.Create('nonbinary exact word');
    if Total > MAX_T5M_FILE_BYTES * 5 - N then
      raise ET5MError.Create('T5M exceeds file boundary');
    Inc(Total, N);
    if I <> High(Words) then begin
      if Total >= MAX_T5M_FILE_BYTES * 5 then
        raise ET5MError.Create('T5M exceeds file boundary');
      Inc(Total);
    end;
  end;
  Padded := ((Total + 4) div 5) * 5;
  if Padded div 5 > MAX_T5M_FILE_BYTES then
    raise ET5MError.Create('T5M exceeds file boundary');
  SetLength(Trits, Padded);
  P := 1;
  for I := 0 to High(Words) do begin
    for J := 1 to Length(Words[I]) do begin
      Trits[P] := Words[I][J];
      Inc(P);
    end;
    if I <> High(Words) then begin Trits[P] := '2'; Inc(P); end;
  end;
  while P <= Padded do begin Trits[P] := '2'; Inc(P); end;
  SetLength(Result, Padded div 5);
  for I := 0 to Length(Result)-1 do begin
    V := 0;
    for K := 1 to 5 do V := V * 3 +
      (Ord(Trits[I*5+K]) - Ord('0'));
    Result[I+1] := AnsiChar(V); { valid 0..242 byte }
  end;
end;

procedure DecodeT5M(const Physical: RawByteString; out Words: TExactWords);
const Divisors: array[0..4] of Integer = (81,27,9,3,1);
var
  I, K, B, Digit, N, Capacity, Padding: SizeInt;
  Current: RawByteString;

  procedure AddWord;
  begin
    if Current = '' then raise ET5MError.Create('empty exact word');
    if N = Capacity then begin
      if Capacity = 0 then Capacity := 16 else Capacity := Capacity * 2;
      SetLength(Words, Capacity);
    end;
    Words[N] := Current;
    Inc(N);
    Current := '';
  end;

begin
  SetLength(Words, 0);
  if (Length(Physical) = 0) or
     (Length(Physical) > MAX_T5M_FILE_BYTES) then
    raise ET5MError.Create('empty/oversized physical T5M file');
  N := 0; Capacity := 0; Current := ''; Padding := 0;
  for I := 1 to Length(Physical) do begin
    B := Ord(Physical[I]);
    if B >= 243 then raise ET5MError.Create('invalid T5M byte 243..255');
    for K := 0 to 4 do begin
      Digit := (B div Divisors[K]) mod 3;
      if Digit = 2 then begin
        if Current <> '' then begin
          AddWord;
          Padding := 1;
        end else Inc(Padding);
        if Padding >= 5 then
          raise ET5MError.Create('too many terminal padding trits');
      end else begin
        if Padding > 1 then
          raise ET5MError.Create('noncanonical repeated separator');
        if (Padding > 0) and (N = 0) then
          raise ET5MError.Create('noncanonical leading separator');
        Padding := 0;
        if Length(Current) >= MAX_T5M_FILE_BYTES * 5 then
          raise ET5MError.Create('word too large');
        if Digit = 1 then Current := Current + '1'
        else Current := Current + '0';
      end;
    end;
  end;
  if Current <> '' then AddWord;
  if N = 0 then raise ET5MError.Create('empty T5M word stream');
  SetLength(Words, N);
end;

end.
