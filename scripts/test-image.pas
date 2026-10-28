{ Physical FPC tests for G7.4, not SENS semantic tests. }
program test_image;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain, wsm.envframe, wsm.image;

var
  Checks: Integer;
  Root, Child, Loaded: IEnvFrame;
  S, Other: TMemoryStream;
  F: TFileStream;
  Original, Mutant, TempName, Swap: RawByteString;
  Key: TDomainKey;
  Keys: array of TDomainKey;
  ValueHandle: QWord;
  I: Integer;

procedure Expect(OK: Boolean; const Why: String);
begin
  Inc(Checks);
  if not OK then begin
    WriteLn(StdErr, 'IMAGE-FAIL ', Why);
    Halt(1);
  end;
end;

function BytesOf(const Stream: TMemoryStream): RawByteString;
begin
  SetLength(Result, Stream.Size);
  if Stream.Size <> 0 then Move(Stream.Memory^, Result[1], Stream.Size);
end;

function Rechecksum(const Data: RawByteString): RawByteString;
var H: QWord; J: SizeInt;
begin
  Result := Data;
  H := 2166136261;
  for J := 1 to Length(Result)-4 do
    H := ((H xor Ord(Result[J])) * QWord(16777619)) and QWord($FFFFFFFF);
  for J := 0 to 3 do
    Result[Length(Result)-3+J] := AnsiChar((H shr (J*8)) and $FF);
end;

procedure RejectImage(const Data: RawByteString; const Why: String);
var Stream: TMemoryStream; Candidate: IEnvFrame; Raised: Boolean;
begin
  Stream := TMemoryStream.Create;
  try
    if Length(Data) <> 0 then Stream.WriteBuffer(Data[1], Length(Data));
    Stream.Position := 0;
    Raised := False; Candidate := nil;
    try
      Candidate := LoadFrameImage(Stream);
    except
      on E: EImageError do Raised := True;
    end;
    Expect(Raised, Why + ' accepted');
  finally
    Stream.Free;
  end;
end;

procedure RejectSave(const Frame: IEnvFrame;
  const K: array of TDomainKey; const Why: String);
var Stream: TMemoryStream; Raised: Boolean;
begin
  Stream := TMemoryStream.Create;
  try
    Raised := False;
    try
      SaveFrameImage(Frame, K, Stream);
    except
      on E: EImageError do Raised := True;
    end;
    Expect(Raised, Why + ' accepted');
    Expect(Stream.Size = 0, Why + ' wrote a partial image');
  finally
    Stream.Free;
  end;
end;

begin
  Checks := 0;
  Root := NewEnvFrame(nil);
  Root.InstallLocal(ExactKey('0'), 0);
  Root.InstallLocal(ExactKey('01'), 42);
  Root.InstallLocal(ExactKey('001'), High(QWord));
  Child := NewEnvFrame(Root);
  Child.InstallLocal(ExactKey('001'), 123); { capture the nearest shadow }

  SetLength(Keys, 3);
  Keys[0] := ExactKey('01');
  Keys[1] := ExactKey('001');
  Keys[2] := ExactKey('0');
  S := TMemoryStream.Create;
  Other := TMemoryStream.Create;
  try
    SaveFrameImage(Child, Keys, S);
    Original := BytesOf(S);
    Expect(Length(Original) = 8+4+3*11+4, 'fixed physical byte length');
    Expect(Copy(Original,1,7) = 'WSMIMG1', 'private image magic');
    Expect(Ord(Original[8]) = 0, 'private image version terminator');

    { Enumeration order is not a property of the checkpoint. }
    Keys[0] := ExactKey('0');
    Keys[1] := ExactKey('01');
    Keys[2] := ExactKey('001');
    SaveFrameImage(Child, Keys, Other);
    Expect(BytesOf(Other) = Original, 'non-deterministic key ordering');

    S.Position := 0;
    Loaded := LoadFrameImage(S);
    Expect(Loaded.Resolve(ExactKey('0')) = 0, 'zero is a valid cell');
    Expect(Loaded.Resolve(ExactKey('01')) = 42, 'D2 cell restored');
    Expect(Loaded.Resolve(ExactKey('001')) = 123, 'captured shadow restored');
    Expect(not Loaded.TryResolve(ExactKey('1'), ValueHandle),
      'unselected lexical binding must not appear');
    Expect(not Loaded.TryResolve(ExactKey('0001'), ValueHandle),
      'different exact domain must not alias');

    TempName := IncludeTrailingPathDelimiter(GetTempDir(False)) +
      'wsm-image-physical-' + IntToStr(Random(1000000000)) + '.img';
    F := TFileStream.Create(String(TempName), fmCreate);
    try
      F.WriteBuffer(Original[1], Length(Original));
    finally F.Free; end;
    try
      F := TFileStream.Create(String(TempName), fmOpenRead);
      try
        Loaded := LoadFrameImage(F);
        Expect(Loaded.Resolve(ExactKey('001')) = 123,
          'real disk image restored wrong shadow');
        Expect(Loaded.Resolve(ExactKey('0')) = 0,
          'real disk image lost zero');
      finally F.Free; end;
    finally
      DeleteFile(String(TempName));
    end;

    Mutant := Original;
    Mutant[1] := 'X';
    RejectImage(Rechecksum(Mutant), 'wrong magic');
    RejectImage(Copy(Original,1,Length(Original)-1), 'truncation');
    RejectImage(Original+#0, 'trailing bytes');
    Mutant := Original;
    Mutant[20] := AnsiChar(Ord(Mutant[20]) xor 1);
    RejectImage(Mutant, 'accidental payload corruption');
    Mutant := Original;
    Mutant[13] := #0;  { first width }
    RejectImage(Rechecksum(Mutant), 'zero width even with matching checksum');
    Mutant := Original;
    Mutant[14] := #2;  { first D1 bits: 2 is out of range }
    RejectImage(Rechecksum(Mutant), 'out-of-range domain bits');
    Mutant := Original;
    Move(Mutant[13], Mutant[24], 11);
    RejectImage(Rechecksum(Mutant), 'duplicate exact key');
    Mutant := Original;
    Swap := Copy(Mutant,13,11);
    Move(Mutant[24], Mutant[13], 11);
    Move(Swap[1], Mutant[24], 11);
    RejectImage(Rechecksum(Mutant), 'noncanonical key order');
    Mutant := Original;
    Mutant[9] := #255; { count mismatch / excessive count }
    RejectImage(Rechecksum(Mutant), 'forged count');
    RejectImage('', 'empty physical image');

    SetLength(Keys, 0);
    RejectSave(Child, Keys, 'empty selection');
    SetLength(Keys, 1);
    Keys[0] := ExactKey('111');
    RejectSave(Child, Keys, 'unbound selected coordinate');
    Keys[0].Width := 0;
    RejectSave(Child, Keys, 'invalid zero-width input');
    Keys[0].Width := 2; Keys[0].Bits := 4;
    RejectSave(Child, Keys, 'out-of-range input bits');
    SetLength(Keys, 2);
    Keys[0] := ExactKey('0'); Keys[1] := ExactKey('0');
    RejectSave(Child, Keys, 'duplicate requested keys');
    SetLength(Keys, MaxImageBindings+1);
    for I := 0 to High(Keys) do Keys[I] := ExactKey('0');
    RejectSave(Child, Keys, 'over-limit key selection');

    Key := ExactKey('0');
    SetLength(Keys, 1); Keys[0] := Key;
    RejectSave(nil, Keys, 'missing source environment');
    Expect(True, 'completed finite physical witness');
    WriteLn('IMAGE-SNAPSHOT-OK checks=', Checks,
      ' disk=restored deterministic=yes invalid=reject ',
      'SENS-system-image=NOT_IMPLEMENTED');
  finally
    Other.Free;
    S.Free;
  end;
end.
