program test_core4source;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.core4source;

var
  RawA, RawB, Path, TempRoot, Malformed: RawByteString;
  A, B, Before: TMemoryStream;
  F: TFileStream;
  Header: array[0..3] of AnsiChar;
  Failed: Boolean;

procedure Require(Condition: Boolean; const Context: string);
begin
  if not Condition then begin
    WriteLn(StdErr, 'CORE4-SOURCE-FAIL ', Context);
    Halt(1);
  end;
end;

procedure WriteBytes(const Filename: string; const Content: RawByteString);
var W: TFileStream;
begin
  W := TFileStream.Create(Filename, fmCreate);
  try
    if Length(Content) > 0 then
      W.WriteBuffer(Content[1], Length(Content));
  finally
    W.Free;
  end;
end;

begin
  RawA := ReadPinnedCore4('.');
  RawB := ReadPinnedCore4('.');
  Require(Length(RawA) > 0, 'pinned Core4 is empty');
  Require(RawA = RawB, 'source bytes unstable');

  A := TMemoryStream.Create;
  B := TMemoryStream.Create;
  Before := TMemoryStream.Create;
  TempRoot := 'build/m0.2/core4-source-negative';
  try
    CompilePinnedCore4Structure('.', A);
    CompilePinnedCore4Structure('.', B);
    Require(A.Size >= 9, 'no structural SIR1 emitted');
    Require(A.Size = B.Size, 'SIR1 size nondeterministic');
    Require(CompareMem(A.Memory, B.Memory, SizeInt(A.Size)),
      'SIR1 bytes nondeterministic');
    A.Position := 0;
    A.ReadBuffer(Header, 4);
    Require((Header[0] = 'S') and (Header[1] = 'I') and
            (Header[2] = 'R') and (Header[3] = '1'), 'SIR1 magic absent');

    Failed := False;
    try RawB := ReadPinnedCore4('.', 1);
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'oversize budget accepted');
    Failed := False;
    try RawB := ReadPinnedCore4('.', 0);
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'invalid budget accepted');
    Failed := False;
    try RawB := ReadPinnedCore4('');
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'empty root accepted');
    Failed := False;
    try RawB := ReadPinnedCore4('absent-repository');
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'absent Core4 accepted');

    Path := String(TempRoot) + '/external/sens/lib';
    Require(ForceDirectories(String(Path)), 'cannot make negative fixture');
    Malformed := String(Path) + '/core4.lisp';
    WriteBytes(String(Malformed), '');
    Failed := False;
    try RawB := ReadPinnedCore4(String(TempRoot));
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'empty Core4 accepted');

    WriteBytes(String(Malformed), '(незакритий');
    Before.WriteBuffer(Header, 4);
    Failed := False;
    try CompilePinnedCore4Structure(String(TempRoot), Before);
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'malformed Core4 accepted');
    Require(Before.Size = 4, 'partial structural bytes escaped on failure');
    Before.Position := 0;
    Before.ReadBuffer(Header, 4);
    Require((Header[0] = 'S') and (Header[1] = 'I') and
      (Header[2] = 'R') and (Header[3] = '1'), 'destination changed after failure');
    Failed := False;
    try CompilePinnedCore4Structure('.', nil);
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'nil destination accepted');

    WriteLn('CORE4-SOURCE-OK bytes=', Length(RawA),
      ' structural-ir=', A.Size,
      ' pinned-source-and-negative-tests=pass execution=NOT_IMPLEMENTED');
  finally
    Before.Free;
    B.Free;
    A.Free;
    DeleteFile(String(Malformed));
    RemoveDir(String(Path));
    RemoveDir(String(TempRoot) + '/external/sens');
    RemoveDir(String(TempRoot) + '/external');
    RemoveDir(String(TempRoot));
  end;
end.
