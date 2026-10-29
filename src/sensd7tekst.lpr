{ G1.22 — явний D7 keyboard TEXT FILE ↔ канонічний binary .sens.
  Це host проєкція текстових даних, а не читач .lisp чи SENS REPL. }
program sensd7tekst;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.d7tekst;
const Limit=MaxD7TextBytes;
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
  if (Operation<>'--ук-у-сенс') and (Operation<>'--сенс-у-ук') then begin
    WriteLn(StdErr,'Д7-ТЕКСТ-ПОМИЛКА: невідома команда');
    Halt(64);
  end;
  try
    if (Operation='--сенс-у-ук') and
       (LowerCase(ExtractFileExt(String(Path)))<>'.sens') then
      raise ED7TextError.Create('Потрібний фізичний файл .sens');
    LoadPinnedD7('external/sens',Alphabet);
    Source:=ReadBounded(Path);
    if Operation='--ук-у-сенс' then
      Answer:=UkrainianD7ToPhysical(Source,Alphabet)
    else
      Answer:=PhysicalD7ToUkrainian(Source,Alphabet);
    { Жодного часткового stdout до повного pinned/UTF-8/T5M допуску. }
    RawOutput(Answer);
  except on E:Exception do begin
    WriteLn(StdErr,'Д7-ТЕКСТ-ПОМИЛКА: ',E.Message);
    Halt(2);
  end end;
end.
