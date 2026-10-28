{ G1.6: український механічний інтерфейс фізичного T5M і D2.
  Тут немає мовних законів: структуру читають тільки чинні wsm.t5m,
  wsm.d2source і wsm.physloc з pinned SENS. Не виконує форм і Core4.
  Перегляд бітових слів не є українською .lisp-проєкцією. }
program senst5m;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc;

const MAX_WORD_VIEW_BYTES = MAX_T5M_FILE_BYTES * 5 + 1;
type EViewError = class(Exception);

function LoadBounded(const FileName: String; Limit: Int64): RawByteString;
var F: TFileStream;
begin
  F := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size <= 0) or (F.Size > Limit) then
      raise EViewError.Create('порожній або надмірно великий вхідний файл');
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
    if Current = '' then raise EViewError.Create('порожнє двійкове слово');
    if N = Capacity then begin
      if Capacity = 0 then Capacity := 16 else Capacity := Capacity*2;
      SetLength(Result,Capacity);
    end;
    Result[N] := Current;
    Inc(N); Current := '';
  end;
begin
  if (S = '') or (S[Length(S)] <> #10) then
    raise EViewError.Create('перегляд слів повинен закінчуватися одним LF');
  N := 0; Capacity := 0; Current := '';
  SetLength(Result,0);
  for I := 1 to Length(S)-1 do begin
    C := S[I];
    case C of
      '0','1': Current := Current + C;
      ' ': Add;
    else raise EViewError.CreateFmt('недопустимий байт перегляду за зсувом %d', [I-1]);
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
  DecodeT5M(S,Words); { повний фізичний допуск перед stdout }
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
  Physical := EncodeT5M(Words); { валідація до першого байта stdout }
  WritePhysical(Physical);
end;

procedure CheckD2Structure(const FileName: String);
var S: RawByteString; Spans: TPhysicalWordSpans; Doc: TD2Document;
begin
  S := LoadBounded(FileName, MAX_T5M_FILE_BYTES);
  Doc := ReadD2WithPhysicalLocations(S, Spans);
  try
    { Тільки після успішного фізичного та структурного допуску. }
    WriteLn('СТРУКТУРА-ГАРАЗД коренів=', Length(Doc.Roots),
      ' фізичних-байтів=', Length(S), ' двійкових-слів=', Length(Spans));
  finally Doc.Free; end;
end;

var Operation: String;
begin
  if ParamCount <> 2 then begin
    WriteLn(StdErr,'Використання: senst5m --перегляд файл.sens | ',
      '--пакувати-слова файл.words | --перевірити-структуру файл.sens');
    Halt(64);
  end;
  Operation := ParamStr(1);
  if not ((Operation = '--перегляд') or (Operation = '--пакувати-слова') or
          (Operation = '--перевірити-структуру') or
          (Operation = '--view') or (Operation = '--pack-words')) then begin
    WriteLn(StdErr,'Невідома команда фізичного T5M: ',Operation);
    Halt(64);
  end;
  try
    if (Operation = '--перегляд') or (Operation = '--view') then
      ViewPhysical(ParamStr(2))
    else if (Operation = '--пакувати-слова') or (Operation = '--pack-words') then
      PackWordView(ParamStr(2))
    else
      CheckD2Structure(ParamStr(2));
  except
    on E: ED2PhysicalError do begin
      WriteLn(StdErr,'SENST5M-FAIL структура: слово=',E.Span.WordIndex,
        ' байти=[',E.Span.ByteStart,',',E.Span.ByteEnd,') ',
        E.Message);
      Halt(1);
    end;
    on E: Exception do begin
      WriteLn(StdErr,'SENST5M-FAIL фізичний вхід: ',E.Message);
      Halt(1);
    end;
  end;
end.
