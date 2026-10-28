{ Native Core4 source admission only. The SENS pin/law stays upstream.
  The result is structural SIR1, NOT executable Core4 or canonical .sens.
  The existing check-pin.sh verifies the gitlink/refs before this module runs. }
unit wsm.core4source;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;

type ECore4SourceError = class(Exception)
public
  { For syntax errors, positions are 1-based source bytes. For file/IO errors
    these fields are zero; callers must not invent a location. }
  ByteOffset, Line, ByteColumn: SizeInt;
  constructor CreateAt(const Problem: String;
    AOffset, ALine, AColumn: SizeInt);
end;

const Core4SourceLimit: Int64 = 16 * 1024 * 1024;

function Core4PinnedPath(const RepoRoot: string): string;
function ReadPinnedCore4(const RepoRoot: string;
  MaxBytes: Int64 = 16777216): RawByteString;
procedure CompilePinnedCore4Structure(const RepoRoot: string;
  Destination: TStream; MaxBytes: Int64 = 16777216);

implementation
uses wsm.compiler, wsm.source;

constructor ECore4SourceError.CreateAt(const Problem: String;
  AOffset, ALine, AColumn: SizeInt);
begin
  inherited Create(Problem);
  ByteOffset := AOffset;
  Line := ALine;
  ByteColumn := AColumn;
end;

function Core4PinnedPath(const RepoRoot: string): string;
begin
  if RepoRoot = '' then
    raise ECore4SourceError.Create('empty repository root');
  Result := IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot)) +
            'external' + PathDelim + 'sens' + PathDelim + 'lib' +
            PathDelim + 'core4.lisp';
end;

function ReadPinnedCore4(const RepoRoot: string;
  MaxBytes: Int64): RawByteString;
var
  Source: TFileStream;
  SourcePath: string;
begin
  if (MaxBytes < 1) or (MaxBytes > Core4SourceLimit) then
    raise ECore4SourceError.Create('invalid Core4 byte budget');
  SourcePath := Core4PinnedPath(RepoRoot);
  try
    Source := TFileStream.Create(SourcePath, fmOpenRead or fmShareDenyNone);
  except
    on E: Exception do
      raise ECore4SourceError.Create('pinned Core4 source not readable: ' +
        E.Message);
  end;
  try
    if (Source.Size < 1) or (Source.Size > MaxBytes) then
      raise ECore4SourceError.Create('empty or oversized pinned Core4 source');
    SetLength(Result, SizeInt(Source.Size));
    Source.ReadBuffer(Result[1], Length(Result));
  finally
    Source.Free;
  end;
end;

procedure CompilePinnedCore4Structure(const RepoRoot: string;
  Destination: TStream; MaxBytes: Int64);
var
  RawSource: RawByteString;
  Scratch: TMemoryStream;
  Parsed: TSourceDocument;
begin
  if Destination = nil then
    raise ECore4SourceError.Create('missing destination stream');
  RawSource := ReadPinnedCore4(RepoRoot, MaxBytes);
  { The structural SIR1 tokenizer alone does not validate UTF-8, control
    bytes or nesting depth. Use the already merged STRICT source reader as
    an admission precondition before producing any downstream bytes. }
  try
    Parsed := ReadUkrainianSource(RawSource);
  except
    on E: ESourceError do
      raise ECore4SourceError.CreateAt(
        'Core4 source rejected: ' + E.Message,
        E.ByteOffset, E.Line, E.ByteColumn);
  end;
  try
    if Length(Parsed.Forms) = 0 then
      raise ECore4SourceError.Create('Core4 source contains no forms');
  finally
    Parsed.Free;
  end;
  Scratch := TMemoryStream.Create;
  try
    try
      CompileSource(RawSource, Scratch);
    except
      on E: ECompileError do
        raise ECore4SourceError.Create('Core4 structural source rejected: ' +
          E.Message);
    end;
    { Re-read the emitted private IR with the existing strict verifier.
      Malformed input or a malformed SIR1 can NEVER enter Destination. }
    Scratch.Position := 0;
    try
      VerifySIR1(Scratch);
    except
      on E: ECompileError do
        raise ECore4SourceError.Create(
          'Core4 structural IR rejected: ' + E.Message);
    end;
    Scratch.Position := 0;
    Destination.CopyFrom(Scratch, Scratch.Size);
  finally
    Scratch.Free;
  end;
end;

end.
