program BuildSensLoop;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.elfd12loop, wsm.elfpublish, wsm.elfgeometry;

const
  Count = 8388361;

var
  Words: TExactWords;
  Atom, Image, Bits: RawByteString;
  Stream: TFileStream;
  Geometry: TELFGeometry;
  I: Integer;

begin
  SetLength(Bits, 24);
  for I := 1 to 24 do Bits[I] := '0';
  for I := 1 to 24 do
    if (Count and (1 shl (24 - I))) <> 0 then Bits[I] := '1';
  SetLength(Words, 1);
  Words[0] := Bits;
  Atom := EncodeT5M(Words);
  Stream := TFileStream.Create(ParamStr(1) + '.sens', fmCreate);
  try
    Stream.WriteBuffer(Atom[1], Length(Atom));
  finally
    Stream.Free;
  end;
  Image := BuildD12SumLoopELF(Atom);
  PublishNewELF64(ParamStr(1) + '.elf', Image, 2, Geometry);
end.
