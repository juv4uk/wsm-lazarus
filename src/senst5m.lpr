{ G1.4 standalone exact-word T5M physical tool.
  Not a .lisp translator, evaluator, or source of SENS language laws.
  --view reads binary .sens and emits 0/1 words; --pack-words accepts only
  canonical one-space-separated ASCII words with one final LF.
  Output is stdout only; the caller chooses whether to redirect to a file. }
program senst5m;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m;

const MAX_WORD_VIEW_BYTES = MAX_T5M_FILE_BYTES * 5 + 1;
type EViewError = class(Exception);

function LoadBounded(const FileName: String; Limit: Int64): RawByteString;
var F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size <= 0) or (F.Size > Limit) then
      raise EViewError.Create('empty or oversized input file');
    SetLength(Result, SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free; end;
end;

function ParseExactWordView(const S: RawByteString): TExactWords;
var
  I, Capacity, N: SizeInt;
  Current: RawByteString;
  C: AnsiChar;
  procedure Add;
  begin
    if Current = '' then raise EViewError.Create('empty exact binary word');
    if N = Capacity then begin
      if Capacity = 0 then Capacity := 16 else Capacity := Capacity*2;
      SetLength(Result,Capacity);
    end;
    Result[N] := Current;
    Inc(N); Current := '';
  end;
begin
  if (S = '') or (S[Length(S)] <> #10) then
    raise EViewError.Create('word view requires one terminal LF');
  N := 0; Capacity := 0; Current := '';
  SetLength(Result,0);
  for I := 1 to Length(S)-1 do begin
    C := S[I];
    case C of
      '0','1': Current := Current + C;
      ' ': Add;
    else raise EViewError.CreateFmt('invalid word-view byte at offset %d', [I-1]);
    end;
  end;
  Add;
  SetLength(Result,N);
end;

procedure WritePhysical(const S: RawByteString);
var W: THandleStream;
begin
  if S = '' then Exit;
  W := THandleStream.Create(TextRec(Output).Handle);
  try W.WriteBuffer(S[1],Length(S));
  finally W.Free; end;
end;

procedure ViewPhysical(const FileName: String);
var Words: TExactWords; S: RawByteString; I: SizeInt;
begin
  S := LoadBounded(FileName,MAX_T5M_FILE_BYTES);
  DecodeT5M(S,Words); { complete physical admission BEFORE stdout }
  for I := 0 to High(Words) do begin
    if I <> 0 then Write(' ');
    Write(Words[I]);
  end;
  Write(#10);
end;

procedure PackWordView(const FileName: String);
var S, Physical: RawByteString; Words: TExactWords;
begin
  S := LoadBounded(FileName,MAX_WORD_VIEW_BYTES);
  Words := ParseExactWordView(S);
  Physical := EncodeT5M(Words); { complete validation BEFORE stdout }
  WritePhysical(Physical);
end;

begin
  if (ParamCount <> 2) or
     not ((ParamStr(1) = '--view') or (ParamStr(1) = '--pack-words')) then begin
    WriteLn(StdErr,'usage: senst5m --view input.sens | --pack-words input.words');
    Halt(64);
  end;
  try
    if ParamStr(1) = '--view' then ViewPhysical(ParamStr(2))
    else PackWordView(ParamStr(2));
  except
    on E: Exception do begin
      WriteLn(StdErr,'SENST5M-FAIL ',E.Message);
      Halt(1);
    end;
  end;
end.
