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

  TPhysicalNodeSpan = record
    WordStart: SizeInt;          { 1-based включний індекс першого слова }
    WordEndExclusive: SizeInt;   { 1-based межа одразу після останнього слова }
    TritStart: SizeInt;          { 0-based напіввідкритий фізичний інтервал тритів }
    TritEnd: SizeInt;
    ByteStart: SizeInt;          { 0-based напіввідкритий інтервал байтів }
    ByteEnd: SizeInt;
    { Якщо сусідні слова ділять байт, тритові межі точніші за цей envelope. }
  end;

  ED2PhysicalError = class(Exception)
  public
    Span: TPhysicalWordSpan;
    constructor CreateAt(const Problem: String; const AtSpan: TPhysicalWordSpan);
  end;

procedure DecodeT5MWithLocations(const Physical: RawByteString;
  out Words: TExactWords; out Spans: TPhysicalWordSpans);
function LocatePhysicalWord(const Physical: RawByteString;
  const Spans: TPhysicalWordSpans; WordIndex: SizeInt): TPhysicalWordSpan;
function LocatePhysicalNodeSpan(const Physical: RawByteString;
  const Spans: TPhysicalWordSpans; Node: TD2Node): TPhysicalNodeSpan;
function ReadD2WithPhysicalLocations(const Physical: RawByteString;
  out Spans: TPhysicalWordSpans): TD2Document;
{ Явно широкий фізичний reader: W1..W192 лише механічні слова.
  Не додає викличних законів чи numeric-D12+ допуску. }
function ReadD2WideWithPhysicalLocations(const Physical: RawByteString;
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
    { G1.55: навіть переданий ззовні span не може виходити за фізичні
      трити або суперечити точному byte envelope. Не декодуємо T5M
      повторно; це лише структурний запобіжник, не доказ provenance. }
    if (Result.TritStart < 0) or
       (Result.TritEnd > Length(Physical) * 5) then
      raise EPhysicalLocationError.Create('physical trit span out of range');
    if (Result.ByteStart <> Result.TritStart div 5) or
       (Result.ByteEnd <> (Result.TritEnd + 4) div 5) then
      raise EPhysicalLocationError.Create('physical byte/trit span mismatch');
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

function LocatePhysicalNodeSpan(const Physical: RawByteString;
  const Spans: TPhysicalWordSpans; Node: TD2Node): TPhysicalNodeSpan;
var FirstWord, LastWord: TPhysicalWordSpan;
begin
  if Node = nil then
    raise EPhysicalLocationError.Create('nil D2 node');
  if (Node.WordIndex < 1) or
     (Node.EndWordIndexExclusive <= Node.WordIndex) then
    raise EPhysicalLocationError.Create('invalid D2 node word interval');
  if Node.EndWordIndexExclusive > Length(Spans) + 1 then
    raise EPhysicalLocationError.Create('D2 node interval out of range');

  { Each endpoint is checked against the existing exact T5M location map.
    The end-exclusive AST boundary resolves through the final included word. }
  FirstWord := LocatePhysicalWord(Physical, Spans, Node.WordIndex);
  LastWord := LocatePhysicalWord(Physical, Spans,
    Node.EndWordIndexExclusive - 1);
  if (FirstWord.TritStart > LastWord.TritStart) or
     (FirstWord.ByteStart > LastWord.ByteStart) or
     (FirstWord.TritEnd > LastWord.TritEnd) or
     (FirstWord.ByteEnd > LastWord.ByteEnd) then
    raise EPhysicalLocationError.Create('unordered D2 node physical span');

  Result.WordStart := Node.WordIndex;
  Result.WordEndExclusive := Node.EndWordIndexExclusive;
  Result.TritStart := FirstWord.TritStart;
  Result.TritEnd := LastWord.TritEnd;
  Result.ByteStart := FirstWord.ByteStart;
  Result.ByteEnd := LastWord.ByteEnd;
end;

{ Обидва режими споживають ТОЙ САМИЙ фізичний T5M і D2-граматику.
  Wide:boolean — ЛИШЕ host-вибір квоти точного слова (W9/W192).
  out Spans очищається до декодування; приватний staged buffer
  публікується лише після успішного повного D2-парсингу.
  Діагностика ED2PhysicalError походить виключно з exact physical
  location і 1-based E.WordIndex, не з Unicode-проєкції чи opcode. }
function ReadD2PhysicalBounded(const Physical: RawByteString;
  out Spans: TPhysicalWordSpans; Wide: Boolean): TD2Document;
var W: TExactWords;
    CandidateSpans: TPhysicalWordSpans;
    AtSpan: TPhysicalWordSpan;
begin
  SetLength(Spans, 0);
  DecodeT5MWithLocations(Physical, W, CandidateSpans);
  try
    if Wide then Result := ParseD2WordsWide(W)
    else Result := ParseD2Words(W);
  except
    on E: ED2SourceError do begin
      AtSpan := LocatePhysicalWord(Physical, CandidateSpans, E.WordIndex);
      raise ED2PhysicalError.CreateAt(E.Message, AtSpan);
    end;
  end;
  Spans := CandidateSpans;
end;

function ReadD2WithPhysicalLocations(const Physical: RawByteString;
  out Spans: TPhysicalWordSpans): TD2Document;
begin
  Result := ReadD2PhysicalBounded(Physical,Spans,False);
end;

function ReadD2WideWithPhysicalLocations(const Physical: RawByteString;
  out Spans: TPhysicalWordSpans): TD2Document;
begin
  Result := ReadD2PhysicalBounded(Physical,Spans,True);
end;
end.
