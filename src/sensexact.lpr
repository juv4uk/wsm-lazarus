{ Вузький виконуваний FPC інструмент для приватного ExactIR EIR1.
  Фізичний .sens — першоджерело; EIR1 не є програмою SENS. }
program sensexact;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.bind, wsm.exactir,
  wsm.exactirwire{$IFDEF UNIX}, BaseUnix{$ENDIF};

{$IFDEF UNIX}
function CreatePrivateEIRTemp(Template: PChar): cint; cdecl;
  external 'c' name 'mkstemp';
{$ENDIF}

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

{ Приватне EIR1 — host IR, НЕ canonical .sens і НЕ мовний закон.
  Path: запозичений шлях ОС; Data: керований RawByteString із перевіреного
  EncodePinnedExactIR. Temp/fd мають короткий lifetime до завершення виклику.
  mkstemp атомарно створює inode 0600; fpLink публікує лише нове ім'я
  без перезапису звичайних файлів, символьних/висячих посилань.
  Питання: 1) Чому FileExists перед fmCreate — гонка?
  2) Чому mkstemp не можна повторно відкривати через fmCreate?
  3) Як відновити роботу після короткого fpWrite?
  4) Чому EIR1 не можна виконувати замість фізичного SENS? }
procedure WriteNew(const Path: String; const Data: RawByteString);
{$IFDEF UNIX}
var Temp: RawByteString; FD: cint;
    Offset, Written: SizeInt; Created: Boolean;
{$ENDIF}
begin
  if LowerCase(ExtractFileExt(Path)) <> '.eir' then
    raise EExactCLIError.Create('вихідний файл повинен мати суфікс .eir');
  if (Length(Data) < 1) or (Int64(Length(Data)) > MaxExactWireBytes) then
    raise EExactCLIError.Create('неприпустима довжина приватного EIR1');
  {$IFDEF UNIX}
  Temp := ''; FD := -1; Created := False;
  try
    Temp := RawByteString(IncludeTrailingPathDelimiter(
      ExtractFilePath(ExpandFileName(Path))) + 'eirXXXXXX');
    { C mkstemp модифікує шість X; потрібен власний mutable буфер. }
    UniqueString(Temp);
    FD := CreatePrivateEIRTemp(PChar(Temp));
    if FD < 0 then
      raise EExactCLIError.Create('не створено приватний тимчасовий EIR1');
    Created := True;
    Offset := 0;
    while Offset < Length(Data) do begin
      Written := fpWrite(FD, Data[Offset+1], Length(Data)-Offset);
      if Written <= 0 then
        raise EExactCLIError.Create('не записано повний контейнер EIR1');
      Inc(Offset, Written);
    end;
    if fpClose(FD) <> 0 then begin
      FD := -1;
      raise EExactCLIError.Create('не закрито приватний EIR1');
    end;
    FD := -1;
    if fpLink(Temp, RawByteString(Path)) <> 0 then
      raise EExactCLIError.Create('ціль EIR1 уже існує або недоступна');
  finally
    if FD >= 0 then fpClose(FD);
    if Created then fpUnlink(Temp);
  end;
  {$ELSE}
  raise EExactCLIError.Create(
    'безпечна атомарна публікація EIR1 на цій ОС недоступна');
  {$ENDIF}
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
