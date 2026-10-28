program test_t5m;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m;

procedure Expect(Condition: Boolean; const Why: String);
begin
  if not Condition then begin
    WriteLn(StdErr,'T5M-TEST-FAIL ',Why);
    Halt(1);
  end;
end;

procedure MustReject(const LabelText, Carrier: RawByteString);
var Failed: Boolean; A: TExactWords;
begin
  Failed := False;
  try A := DecodeT5M(Carrier);
  except on E: ET5MError do Failed := True; end;
  Expect(Failed,'decoder accepted '+LabelText);
end;

procedure MustRejectWords(const LabelText: String; const A: TExactWords);
var Failed: Boolean; Bytes: RawByteString;
begin
  Failed := False;
  try Bytes := EncodeT5M(A);
  except on E: ET5MError do Failed := True; end;
  Expect(Failed,'encoder accepted '+LabelText);
end;

procedure CheckRoundtrip(const A: TExactWords);
var B: TExactWords; Bytes: RawByteString; I: SizeInt;
begin
  Bytes := EncodeT5M(A);
  B := DecodeT5M(Bytes);
  Expect(Length(A)=Length(B),'word count changed');
  for I := 0 to High(A) do begin
    Expect(A[I].Width=B[I].Width,'word width changed');
    Expect(A[I].Bits=B[I].Bits,'exact leading zeros changed');
  end;
  Expect(Bytes=EncodeT5M(B),'T5M physical bytes changed in roundtrip');
end;

var
  Words, Decoded: TExactWords;
  Golden, Bits: RawByteString;
  I, J, K, Width, Tests: Integer;
begin
  { Physical bytes are fixed by pinned Zig t5m.zig: five MSB-first base-3
    trits per byte, 2 between words and 0..4 terminal padding trits. }
  Golden := #99#137#6#161;
  Decoded := DecodeT5M(Golden);
  Expect(Length(Decoded)=5,'mixed D2/D3 word count');
  Expect((Decoded[0].Width=2) and (Decoded[0].Bits='10'),'word 1');
  Expect((Decoded[1].Width=3) and (Decoded[1].Bits='001'),'word 2 leading zeros');
  Expect((Decoded[2].Width=2) and (Decoded[2].Bits='00'),'word 3');
  Expect((Decoded[3].Width=3) and (Decoded[3].Bits='000'),'word 4');
  Expect((Decoded[4].Width=2) and (Decoded[4].Bits='01'),'word 5');
  Expect(EncodeT5M(Decoded)=Golden,'mixed-width physical golden mismatch');
  Decoded := DecodeT5M(#161);
  Expect((Length(Decoded)=1) and (Decoded[0].Bits='1')
          and (Decoded[0].Width=1),'single 1 golden');
  Expect(EncodeT5M(Decoded)=#161,'single 1 physical mismatch');
  Decoded := DecodeT5M(#80);
  Expect((Length(Decoded)=1) and (Decoded[0].Bits='0'),'single 0 golden');
  Expect(EncodeT5M(Decoded)=#80,'single 0 physical mismatch');
  Decoded := DecodeT5M(#0);
  Expect((Length(Decoded)=1) and (Decoded[0].Bits='00000'),'five zero bits');
  Expect(EncodeT5M(Decoded)=#0,'zero data is not an empty carrier');
  Decoded := DecodeT5M(#143);
  Expect((Length(Decoded)=2) and (Decoded[0].Bits='1')
          and (Decoded[1].Bits='0'),'word separator golden');
  Expect(EncodeT5M(Decoded)=#143,'separator physical mismatch');

  MustReject('empty file','');
  MustReject('forbidden physical byte 243',#243);
  MustReject('forbidden physical byte 255',#255);
  MustReject('first trit is separator',#162);
  MustReject('adjacent separators',#216);
  MustReject('five terminal padding trits',#161#242);
  MustReject('all terminal padding trits',#242);
  MustReject('more than five terminal padding trits',#242#242);

  SetLength(Words,0);
  MustRejectWords('zero words',Words);
  SetLength(Words,1);
  Words[0].Bits := ''; Words[0].Width := 0;
  MustRejectWords('zero-width word',Words);
  Words[0].Bits := '001'; Words[0].Width := 2;
  MustRejectWords('inconsistent exact width',Words);
  Words[0].Bits := '02'; Words[0].Width := 2;
  MustRejectWords('separator treated as payload bit',Words);
  Words[0].Bits := '0x'; Words[0].Width := 2;
  MustRejectWords('nonbinary bit',Words);

  { Deterministic, language-agnostic mechanical stress. No semantic oracle. }
  Tests := 0;
  for I := 1 to 240 do begin
    SetLength(Words,(I mod 11)+1);
    for J := 0 to High(Words) do begin
      Width := ((I*17 + J*7) mod 37)+1;
      SetLength(Bits,Width);
      for K := 1 to Width do
        if ((I + J*3 + K*11) mod 7) < 3 then Bits[K] := '1'
        else Bits[K] := '0';
      Words[J].Width := Width;
      Words[J].Bits := Bits;
    end;
    CheckRoundtrip(Words);
    Inc(Tests);
  end;
  WriteLn('T5M-OK pinned-zig=1 physical-golden=5 roundtrip-cases=',Tests,
          ' malformed=reject .sens=mechanical-only core4-execution=NOT_PROVED');
end.
