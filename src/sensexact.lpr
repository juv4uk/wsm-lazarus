{ Вузький виконуваний FPC інструмент для приватного ExactIR EIR1.
  Фізичний .sens — першоджерело; EIR1 не є програмою SENS. }
program sensexact;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.bind, wsm.exactir,
  wsm.exactirwire;

type EExactCLIError = class(Exception);

const MaxExactWireBytes: Int64 = 16 + 4*MaxExactIRNodes +
  46*MaxExactIRNodes;

function ReadBounded(const FileName, Extension: String;
  MaxBytes: Int64): RawByteString;
var Stream: TFileStream;
begin
  if LowerCase(ExtractFileExt(FileName)) <> Extension then
    raise EExactCLIError.Create('невірне розширення: очікується ' + Extension);
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size < 1) or (Stream.Size > MaxBytes) then
      raise EExactCLIError.Create('порожній або завеликий фізичний файл');
    SetLength(Result, SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
  end;
end;

procedure WriteNew(const Path: String; const Data: RawByteString);
var Stream: TFileStream;
begin
  if LowerCase(ExtractFileExt(Path)) <> '.eir' then
    raise EExactCLIError.Create('вихідний файл повинен мати суфікс .eir');
  if FileExists(Path) then
    raise EExactCLIError.Create('заборонено перезаписувати наявний EIR1');
  { Весь фізичний файл та повторне звіряння вже пройшли перевірку
    ДО відкриття виходу; некоректні програми не дають partial output. }
  Stream := TFileStream.Create(Path, fmCreate);
  try
    Stream.WriteBuffer(Data[1], Length(Data));
  finally
    Stream.Free;
  end;
end;

procedure Run;
var
  Physical, Encoded: RawByteString;
  Tables: TDomainSet;
  Checked: TExactIR;
begin
  if (ParamCount <> 3) or
     ((ParamStr(1) <> '--створити-ір') and
      (ParamStr(1) <> '--перевірити-ір')) then
    raise EExactCLIError.Create('використання: sensexact --створити-ір файл.sens вихід.eir ' +
      'АБО --перевірити-ір файл.sens вхід.eir');

  Physical := ReadBounded(ParamStr(2), '.sens', MAX_T5M_FILE_BYTES);
  LoadPinnedDomains('external/sens', Tables);
  if ParamStr(1) = '--створити-ір' then begin
    Encoded := EncodePinnedExactIR(Physical, Tables);
    { Self-admission: той самий зовнішній шлях повної перевірки. }
    DecodePinnedExactIR(Physical, Tables, Encoded, Checked);
    WriteNew(ParamStr(3), Encoded);
    WriteLn('ТОЧНЕ-EIR1-СТВОРЕНО вузлів=', Length(Checked.Nodes),
      ' коренів=', Length(Checked.Roots),
      ' звязаних-слів=', Checked.BoundLeaves,
      ' байтів=', Length(Encoded), ' виконання=ні');
  end else begin
    Encoded := ReadBounded(ParamStr(3), '.eir', MaxExactWireBytes);
    DecodePinnedExactIR(Physical, Tables, Encoded, Checked);
    WriteLn('ТОЧНЕ-EIR1-ПЕРЕВІРЕНО вузлів=', Length(Checked.Nodes),
      ' коренів=', Length(Checked.Roots),
      ' звязаних-слів=', Checked.BoundLeaves,
      ' фізичне-походження=так виконання=ні');
  end;
end;

begin
  try Run;
  except
    on E: Exception do begin
      WriteLn(StdErr, 'ТОЧНЕ-EIR1-ВІДХИЛЕНО: ', E.Message);
      Halt(1);
    end;
  end;
end.
