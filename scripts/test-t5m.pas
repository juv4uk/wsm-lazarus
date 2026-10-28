program test_t5m;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m;

procedure Require(Ok: Boolean; const Why: String);
begin
  if not Ok then begin
    WriteLn(StdErr, 'T5M-FAIL ', Why);
    Halt(1);
  end;
end;

function Bytes(const B: array of Byte): RawByteString;
var I: SizeInt;
begin
  SetLength(Result, Length(B));
  for I := 0 to High(B) do Result[I+1] := AnsiChar(B[I]);
end;

procedure Check(const Input: array of RawByteString; const B: array of Byte);
var W, Decoded: TExactWords; I: SizeInt; Encoded: RawByteString;
begin
  SetLength(W, Length(Input));
  for I := 0 to High(Input) do W[I] := Input[I];
  Encoded := EncodeT5M(W);
  Require(Encoded = Bytes(B), 'fixed upstream base-3 byte vector mismatch');
  DecodeT5M(Encoded, Decoded);
  Require(Length(Decoded) = Length(Input), 'word boundaries lost');
  for I := 0 to High(Input) do
    Require(Decoded[I] = Input[I], 'exact bit width/payload changed');
  Require(EncodeT5M(Decoded) = Encoded,
    'physical encoding noncanonical round-trip');
end;

procedure BadPhysical(const Physical: RawByteString; const MessagePart: String);
var W: TExactWords; Rejected: Boolean;
begin
  Rejected := False;
  try
    DecodeT5M(Physical, W);
  except
    on E: ET5MError do begin
      Require(Pos(MessagePart, E.Message) > 0,
        'wrong physical negative error: ' + E.Message);
      Rejected := True;
    end;
  end;
  Require(Rejected, 'invalid physical .sens bytes accepted');
end;

procedure BadWords(const Input: array of RawByteString);
var W: TExactWords; I: SizeInt; S: RawByteString; Rejected: Boolean;
begin
  SetLength(W, Length(Input));
  for I := 0 to High(Input) do W[I] := Input[I];
  Rejected := False;
  try
    S := EncodeT5M(W);
  except
    on E: ET5MError do Rejected := True;
  end;
  Require(Rejected, 'invalid word sequence accepted by encoder');
end;

var W: TExactWords;
begin
  { Physical vectors independently computed from current upstream
    sens_t5_t5m_codec.py encode_t5m_projection, not guessed domain IDs. }
  Check(['0'], [80]);
  Check(['1'], [161]);
  Check(['000'], [8]);
  Check(['10','01'], [100]);
  Check(['10','00','01'], [99,179]);
  Check(['0','00','000'], [56,8]);
  Check(['001','000'], [15,26]);
  Check(['101010101010101010101010'], [91,30,91,30,92]);
  Check(['01'], [53]); { stand-alone CLOSE is transport-valid, D2-invalid }
  Check(['00000000','000000000'], [0,6,0,8]);

  { Never turn physical width into semantic identity or callability. }
  DecodeT5M(Bytes([100]), W);
  Require((Length(W) = 2) and (W[0] = '10') and (W[1] = '01'),
    'D2-shaped word bytes changed');
  DecodeT5M(Bytes([0]), W);
  Require((Length(W)=1) and (W[0]='00000'), 'raw zero byte lost exact W5');

  BadPhysical('', 'empty');
  BadPhysical(Bytes([243]), 'invalid');
  BadPhysical(Bytes([255]), 'invalid');
  BadPhysical(Bytes([242]), 'padding');
  BadPhysical(Bytes([162]), 'leading');
  BadPhysical(Bytes([72]), 'repeated');
  BadPhysical(Bytes([80,0]), 'repeated');
  BadPhysical(StringOfChar(#0, MAX_T5M_FILE_BYTES + 1), 'oversized');

  BadWords([]);
  BadWords(['']);
  BadWords(['2']);
  BadWords(['10','']);
  BadWords(['10','0X1']);

  WriteLn('T5M-OK FPC physical=canonical bytes 0..242 exact-word-roundtrip=1 malformed=reject; d2-grammar=NOT_VALIDATED; sens-law=NOT_PROVEN');
end.
