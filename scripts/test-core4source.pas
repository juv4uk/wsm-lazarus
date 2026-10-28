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

{ Run each physically malformed fixture through the REAL Core4 admission.
  Invalid byte offsets are 1-based; output must remain unchanged. }
procedure RejectSyntax(const Fixture: RawByteString; const CaseName: String;
  ExpectedOffset, ExpectedLine, ExpectedColumn: SizeInt);
var Caught: Boolean; OldSize: Int64;
begin
  WriteBytes(String(Malformed), Fixture);
  OldSize := Before.Size;
  Caught := False;
  try
    CompilePinnedCore4Structure(String(TempRoot), Before);
  except
    on E: ECore4SourceError do begin
      Caught := True;
      Require(E.ByteOffset = ExpectedOffset, CaseName + ' byte offset');
      Require(E.Line = ExpectedLine, CaseName + ' line');
      Require(E.ByteColumn = ExpectedColumn, CaseName + ' byte column');
    end;
  end;
  Require(Caught, CaseName + ' accepted');
  Require(Before.Size = OldSize, CaseName + ' polluted output');
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

    { These inputs are structurally plausible to the old SIR1 tokenizer,
      but the upstream-derived strict UTF-8 reader MUST reject them. }
    RejectSyntax('(' + #$C0#$AF + ')', 'overlong utf8', 2, 1, 2);
    RejectSyntax('(' + #$E0#$80#$80 + ')', 'three-byte overlong', 2, 1, 2);
    RejectSyntax('(' + #$ED#$A0#$80 + ')', 'surrogate utf8', 2, 1, 2);
    RejectSyntax('(' + #$F4#$90#$80#$80 + ')', 'out-of-range utf8', 2, 1, 2);
    RejectSyntax('(' + #$D0 + ')', 'invalid continuation', 3, 1, 3);
    RejectSyntax('(' + 'а' + #0 + ')', 'NUL in source', 4, 1, 4);
    RejectSyntax('(' + #1 + ')', 'control in source', 2, 1, 2);
    RejectSyntax('(' + #10 + #$C0#$AF + ')',
      'second line invalid utf8', 3, 2, 1);
    { No actual forms: a comment-only source is NOT an admitted library. }
    WriteBytes(String(Malformed), '; тільки коментар' + #10);
    Failed := False;
    try CompilePinnedCore4Structure(String(TempRoot), Before);
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'empty AST/comment-only Core4 accepted');
    Require(Before.Size = 4, 'comment-only Core4 polluted output');
    { A valid source must still admit across independent calls. }
    WriteBytes(String(Malformed), '(як-є ())');
    B.Clear;
    CompilePinnedCore4Structure(String(TempRoot), B);
    Require(B.Size > 9, 'valid synthetic Ukrainian Core4 shape rejected');
    Failed := False;
    try CompilePinnedCore4Structure('.', nil);
    except on E:ECore4SourceError do Failed := True; end;
    Require(Failed, 'nil destination accepted');

    WriteLn('CORE4-SOURCE-OK bytes=', Length(RawA),
      ' structural-ir=', A.Size,
      ' strict-utf8-ast=pass sir1-verified=pass negatives=pass execution=NOT_IMPLEMENTED');
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
