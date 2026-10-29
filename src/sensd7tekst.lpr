{ G1.22 — явний D7 keyboard TEXT FILE ↔ канонічний binary .sens.
  Це host проєкція текстових даних, а не читач .lisp чи SENS REPL. }
program sensd7tekst;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.d7tekst;
const Limit=MaxD7TextBytes;
  OpEncode:RawByteString=#$2D#$2D#$D1#$83#$D0#$BA#$2D#$D1#$83#$2D#$D1#$81#$D0#$B5#$D0#$BD#$D1#$81;
  OpDecode:RawByteString=#$2D#$2D#$D1#$81#$D0#$B5#$D0#$BD#$D1#$81#$2D#$D1#$83#$2D#$D1#$83#$D0#$BA;
  ErrorPrefix:RawByteString=#$D0#$94#$37#$2D#$D0#$A2#$D0#$95#$D0#$9A#$D0#$A1#$D0#$A2#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$3A;
var Operation,Path:RawByteString;
    Alphabet:TD7Alphabet;
    Source,Answer:RawByteString;

function ReadBounded(const Name:RawByteString):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(String(Name),fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=0) or (F.Size>Limit) then
      raise ED7TextError.Create('Порожній або завеликий D7 файл');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure RawOutput(const Bytes:RawByteString);
var F:THandleStream;
begin
  F:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Bytes<>'' then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Використання: sensd7tekst --ук-у-сенс текст.txt',
      ' або --сенс-у-ук дані.sens');
    Halt(64);
  end;
  Operation:=RawByteString(ParamStr(1));
  Path:=RawByteString(ParamStr(2));
  if (Operation<>OpEncode) and (Operation<>OpDecode) then begin
    WriteLn(StdErr,ErrorPrefix+' невідома команда');
    Halt(64);
  end;
  try
    if (Operation=OpDecode) and
       (LowerCase(ExtractFileExt(String(Path)))<>'.sens') then
      raise ED7TextError.Create('Потрібний фізичний файл .sens');
    LoadPinnedD7('external/sens',Alphabet);
    Source:=ReadBounded(Path);
    if Operation=OpEncode then
      Answer:=UkrainianD7ToPhysical(Source,Alphabet)
    else
      Answer:=PhysicalD7ToUkrainian(Source,Alphabet);
    { Жодного часткового stdout до повного pinned/UTF-8/T5M допуску. }
    RawOutput(Answer);
  except on E:Exception do begin
    WriteLn(StdErr,ErrorPrefix,' ',E.Message);
    Halt(2);
  end end;
end.
