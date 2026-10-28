{ G1.5: exact physical offsets for decoded T5M word boundaries and D2 errors.
  Transport and D2 syntax are delegated to pinned-derived wsm.t5m /
  wsm.d2source. A byte may contain fragments of several exact words.
  This is NOT source semantics, a second decoder, or a SENS oracle. }
unit wsm.physloc;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.t5m, wsm.d2source;

type
  EPhysicalLocationError = class(Exception);

  TPhysicalWordSpan = record
    WordIndex: SizeInt;       { 1-based; count + 1 denotes EOF }
    TritStart: SizeInt;       { 0-based half-open meaningful trits }
    TritEnd: SizeInt;
    ByteStart: SizeInt;       { 0-based half-open physical bytes }
    ByteEnd: SizeInt;
    IsEOF: Boolean;
  end;
  TPhysicalWordSpans = array of TPhysicalWordSpan;

  ED2PhysicalError = class(Exception)
  public
    Span: TPhysicalWordSpan;
    constructor CreateAt(const Problem: String; const AtSpan: TPhysicalWordSpan);
  end;

procedure DecodeT5MWithLocations(const Physical: RawByteString;
  out Words: TExactWords; out Spans: TPhysicalWordSpans);
function LocatePhysicalWord(const Physical: RawByteString;
  const Spans: TPhysicalWordSpans; WordIndex: SizeInt): TPhysicalWordSpan;
function ReadD2WithPhysicalLocations(const Physical: RawByteString;
  out Spans: TPhysicalWordSpans): TD2Document;

implementation

constructor ED2PhysicalError.CreateAt(const Problem: String;
  const AtSpan: TPhysicalWordSpan);
begin
  inherited Create(Problem);
  Span := AtSpan;
end;

procedure DecodeT5MWithLocations(const Physical: RawByteString;
  out Words: TExactWords; out Spans: TPhysicalWordSpans);
var I, Cursor, W, Limit: SizeInt;
    CandidateWords: TExactWords;
    CandidateSpans: TPhysicalWordSpans;
begin
  { Атомарний out-контракт: ніяких довірених слів/адрес до повного
    допуску фізичного T5M, канонічності і ВСІХ координат.
    Ці записи — приватні, навіть коли пізня перевірка відмовить. }
  SetLength(Words, 0);
  SetLength(Spans, 0);
  DecodeT5M(Physical, CandidateWords);
  if EncodeT5M(CandidateWords) <> Physical then
    raise EPhysicalLocationError.Create('noncanonical physical T5M bytes');
  SetLength(CandidateSpans, Length(CandidateWords));
  Cursor := 0;
  Limit := Length(Physical) * 5;
  for I := 0 to High(CandidateWords) do begin
    W := Length(CandidateWords[I]);
    if (W = 0) or (W > Limit - Cursor) then
      raise EPhysicalLocationError.Create('invalid exact-word boundary');
    CandidateSpans[I].WordIndex := I + 1;
    CandidateSpans[I].TritStart := Cursor;
    CandidateSpans[I].TritEnd := Cursor + W;
    CandidateSpans[I].ByteStart := Cursor div 5;
    CandidateSpans[I].ByteEnd := (Cursor + W + 4) div 5;
    CandidateSpans[I].IsEOF := False;
    Inc(Cursor, W);
    if I <> High(CandidateWords) then begin
      if Cursor >= Limit then
        raise EPhysicalLocationError.Create('missing T5M word separator');
      Inc(Cursor); { precisely one trit 2 separator between exact words }
    end;
  end;
  if Cursor > Limit then
    raise EPhysicalLocationError.Create('invalid physical T5M length');
  { Одночасна публікація тільки після останньої перевірки. }
  Words := CandidateWords;
  Spans := CandidateSpans;
end;

function LocatePhysicalWord(const Physical: RawByteString;
  const Spans: TPhysicalWordSpans; WordIndex: SizeInt): TPhysicalWordSpan;
var LastEnd: SizeInt;
begin
  if (WordIndex < 1) or (WordIndex > Length(Spans) + 1) then
    raise EPhysicalLocationError.Create('source word index out of range');
  if WordIndex <= Length(Spans) then begin
    Result := Spans[WordIndex - 1];
    if (Result.WordIndex <> WordIndex) or Result.IsEOF or
       (Result.TritEnd <= Result.TritStart) or
       (Result.ByteStart < 0) or (Result.ByteEnd > Length(Physical)) or
       (Result.ByteStart >= Result.ByteEnd) then
      raise EPhysicalLocationError.Create('invalid physical word span');
    Exit;
  end;
  { An expected word at EOF has no trits. The physical byte cursor
    includes final T5M padding; the meaningful trit cursor does not. }
  LastEnd := 0;
  if Length(Spans) > 0 then
    LastEnd := Spans[High(Spans)].TritEnd;
  Result.WordIndex := WordIndex;
  Result.TritStart := LastEnd;
  Result.TritEnd := LastEnd;
  Result.ByteStart := Length(Physical);
  Result.ByteEnd := Length(Physical);
  Result.IsEOF := True;
end;

function ReadD2WithPhysicalLocations(const Physical: RawByteString;
  out Spans: TPhysicalWordSpans): TD2Document;
var W: TExactWords;
    CandidateSpans: TPhysicalWordSpans;
    AtSpan: TPhysicalWordSpan;
begin
  SetLength(Spans, 0);
  DecodeT5MWithLocations(Physical, W, CandidateSpans);
  try
    Result := ParseD2Words(W);
  except
    on E: ED2SourceError do begin
      { Діагностика походить із перевірених ПРИВАТНИХ координат,
        навіть якщо зовнішній out лишається порожнім. }
      AtSpan := LocatePhysicalWord(Physical, CandidateSpans, E.WordIndex);
      raise ED2PhysicalError.CreateAt(E.Message, AtSpan);
    end;
  end;
  Spans := CandidateSpans;
end;
end.
