{ Native Core4 source admission only. The SENS pin/law stays upstream.
  The result is structural SIR1, NOT executable Core4 or canonical .sens.
  The existing check-pin.sh verifies the gitlink/refs before this module runs. }
unit wsm.core4source;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes;

type ECore4SourceError = class(Exception);

const Core4SourceLimit: Int64 = 16 * 1024 * 1024;

function Core4PinnedPath(const RepoRoot: string): string;
function ReadPinnedCore4(const RepoRoot: string;
  MaxBytes: Int64 = 16777216): RawByteString;
procedure CompilePinnedCore4Structure(const RepoRoot: string;
  Destination: TStream; MaxBytes: Int64 = 16777216);

implementation
uses wsm.compiler;

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
begin
  if Destination = nil then
    raise ECore4SourceError.Create('missing destination stream');
  RawSource := ReadPinnedCore4(RepoRoot, MaxBytes);
  Scratch := TMemoryStream.Create;
  try
    try
      CompileSource(RawSource, Scratch);
    except
      on E: ECompileError do
        raise ECore4SourceError.Create('Core4 structural source rejected: ' +
          E.Message);
    end;
    { Transfer only after complete structural admission; no partial SIR1
      leaks to the caller on a malformed input. }
    Scratch.Position := 0;
    Destination.CopyFrom(Scratch, Scratch.Size);
  finally
    Scratch.Free;
  end;
end;

end.
