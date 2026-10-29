{ G6.73 CLI: фізичний D12 `.sens` → нативний ELF64 із циклом навантаження.
  Режим (латинський, щоб розбір argv не залежав від локалі):
    --build <K.sens> <N> <out.elf>
  На відмові stdout порожній, діагностика в stderr, код 2. }
program sensd12loop;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.elfd12loop, wsm.elfpublish, wsm.elfgeometry;

const
  MaxInputBytes = 65536;

procedure Fail(const MessageText: UnicodeString);
begin
  Writeln(StdErr, 'SENS-D12LOOP-ВІДМОВА: ', MessageText);
  Writeln(StdErr, 'SENS-D12LOOP-REFUSED');
  Halt(2);
end;

function ReadPhysical(const Filename: String): RawByteString;
var
  Stream: TFileStream;
begin
  Result := '';
  try
    Stream := TFileStream.Create(Filename, fmOpenRead or fmShareDenyWrite);
  except
    on E: Exception do Fail('не відкрито фізичний атом: ' + E.Message);
  end;
  try
    if (Stream.Size <= 0) or (Stream.Size > MaxInputBytes) then
      Fail('фізичний атом порожній або завеликий');
    SetLength(Result, SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
  end;
end;

function ParseCount(const Text: String): LongWord;
var
  Value: QWord;
  I: SizeInt;
begin
  Value := 0;
  if (Text = '') or (Length(Text) > 10) then
    Fail('неприпустима кількість ітерацій');
  for I := 1 to Length(Text) do begin
    if (Text[I] < '0') or (Text[I] > '9') then
      Fail('кількість ітерацій має бути десятковим числом');
    Value := Value * 10 + QWord(Ord(Text[I]) - Ord('0'));
    if Value > High(LongWord) then Fail('кількість ітерацій поза межею');
  end;
  Result := LongWord(Value);
end;

var
  Mode, AtomPath, OutPath, Upstream: String;
  Count: LongWord;
  Physical, Image: RawByteString;
  Geometry: TELFGeometry;
begin
  if ParamCount < 3 then begin
    Writeln(StdErr, 'вжиток: sensd12loop --build <K.sens> <N> <out.elf>');
    Writeln(StdErr, '        sensd12loop --sum <N.sens> <out.elf>');
    Halt(64);
  end;
  Mode := ParamStr(1);
  if (Mode <> '--build') and (Mode <> '--sum') then
    Fail('невідомий режим: ' + Mode);
  AtomPath := ParamStr(2);
  if Mode = '--sum' then begin
    if ParamCount < 3 then Fail('потрібен шлях вихідного ELF');
    OutPath := ParamStr(3);
    Physical := ReadPhysical(AtomPath);
    try
      Image := BuildD12SumLoopELF(Physical);
    except
      on E: Exception do Fail('ELF не збудовано: ' + E.Message);
    end;
    try
      PublishNewELF64(OutPath, Image, 2, Geometry);
    except
      on E: Exception do Fail('ELF не опубліковано: ' + E.Message);
    end;
    Writeln('SENS-D12LOOP-SUM-BUILT bytes=', Length(Image), ' path=', OutPath);
    Halt(0);
  end;
  if ParamCount < 4 then Fail('потрібні кількість ітерацій і шлях ELF');
  Count := ParseCount(ParamStr(3));
  OutPath := ParamStr(4);
  Physical := ReadPhysical(AtomPath);
  try
    Image := BuildD12LoopELF(Physical, Count);
  except
    on E: Exception do Fail('ELF не збудовано: ' + E.Message);
  end;
  try
    PublishNewELF64(OutPath, Image, 2, Geometry);
  except
    on E: Exception do Fail('ELF не опубліковано: ' + E.Message);
  end;
  Writeln('SENS-D12LOOP-BUILT bytes=', Length(Image), ' iterations=', Count,
    ' path=', OutPath);
end.
