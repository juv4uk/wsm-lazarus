{ G6.93 — нативний рекурсивний fib: збірка ELF із точного D24 `.sens`
  і звірка виходу з НЕЗАЛЕЖНИМ оракулом. Негативні випадки: відʼємний,
  завеликий і не-D24 аргумент — явна відмова, без часткового образу. }
program test_elffib;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix, wsm.t5m, wsm.elffib;

var
  Failures: SizeInt = 0;
  Checks: SizeInt = 0;

procedure Check(Ok: Boolean; const Why: String);
begin
  Inc(Checks);
  if Ok then Writeln('ELFFIB-OK   ', Why)
  else begin Writeln('ELFFIB-ЗБІЙ ', Why); Inc(Failures); end;
end;

function D24(Value: LongWord): RawByteString;
var
  Bits: String;
  I: SizeInt;
begin
  SetLength(Bits, 24);
  for I := 1 to 24 do
    if (Value and (LongWord(1) shl (24 - I))) <> 0 then Bits[I] := '1'
    else Bits[I] := '0';
  Result := RawByteString(Bits);
end;

function RunELF(const Image: RawByteString; out ExitCode: SizeInt): Boolean;
var
  Path: String;
  Stream: TFileStream;
  Status: LongInt;
begin
  Result := False;
  ExitCode := -1;
  Path := GetTempDir(False) + 'sens-elffib-' + IntToStr(Random(1000000)) + '.elf';
  Stream := TFileStream.Create(Path, fmCreate);
  try
    if Length(Image) > 0 then Stream.WriteBuffer(Image[1], Length(Image));
  finally
    Stream.Free;
  end;
  if fpChmod(Path, &755) <> 0 then begin DeleteFile(Path); Exit; end;
  Status := fpSystem(PChar(Path));
  if WIFEXITED(Status) then begin
    ExitCode := WEXITSTATUS(Status);
    Result := True;
  end;
  DeleteFile(Path);
end;

procedure Positive(const N: LongWord);
var
  Image: RawByteString;
  Words: TExactWords;
  Code: SizeInt;
  Expected: QWord;
  Ok: Boolean;
begin
  SetLength(Words, 1);
  Words[0] := D24(N);
  Image := BuildD24FibELF(EncodeT5M(Words));
  Expected := FibOracle(N) and 255;
  Ok := RunELF(Image, Code);
  Check(Ok and (QWord(Code) = Expected),
    'fib(' + IntToStr(N) + ') native=' + IntToStr(Code) +
    ' oracle=' + IntToStr(Expected));
end;

procedure Negative(const Value: LongWord; const Why: String);
var
  Words: TExactWords;
  Refused: Boolean;
begin
  SetLength(Words, 1);
  Words[0] := D24(Value);
  Refused := False;
  try
    BuildD24FibELF(EncodeT5M(Words));
  except
    on E: Exception do Refused := True;
  end;
  Check(Refused, Why);
end;

var
  Words: TExactWords;
  Refused: Boolean;
begin
  Randomize;
  Positive(0);
  Positive(1);
  Positive(2);
  Positive(3);
  Positive(10);
  Positive(15);
  Positive(20);
  Positive(25);
  Positive(30);
  Positive(35);

  Negative($800000, 'negative D24 refused');
  Negative(36, 'n beyond host limit refused');

  SetLength(Words, 1);
  Words[0] := '000000000001';
  Refused := False;
  try
    BuildD24FibELF(EncodeT5M(Words));
  except
    on E: Exception do Refused := True;
  end;
  Check(Refused, 'non-D24 argument refused');

  if Failures > 0 then begin
    Writeln('ELFFIB-FAIL');
    Halt(1);
  end;
  Writeln('ELFFIB-PASS checks=', Checks);
  Writeln('ELFFIB-LIMIT=host-fib-body-not-sens-lowering-no-GC-no-REPL');
end.
