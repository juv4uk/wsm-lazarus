{ Пакетний фізичний перегляд D12+ з явним профілем.
  Фізичні байти — T5M; українські десяткові токени — тільки проєкція.
  Жодного копіювання законів SENS чи обчислення арифметики. }
program senschyslopaket;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.physloc, wsm.numericplane;
const
  MaxPhysicalBytes = 65536;
  MaxNumericWords = 1024;

function ReadPhysical(const Path: String): RawByteString;
var Stream: TFileStream;
begin
  if LowerCase(ExtractFileExt(Path)) <> '.sens' then
    raise Exception.Create('потрібен канонічний фізичний файл .sens');
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size < 1) or (Stream.Size > MaxPhysicalBytes) then
      raise Exception.Create('фізичний пакет порожній або понад 65536 байтів');
    SetLength(Result, SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1], Length(Result));
  finally
    Stream.Free;
  end;
end;

{ Вхід: позичені канонічні T5M bytes і зовнішній явний domain-width.
  Усі керовані RawByteString/TExactWords/TPhysicalWordSpans живуть у цьому
  виклику; вивід збирається приватно і публікується лише після повного
  допуску. Адреси — 1-based слово, 0-based піввідкриті трити/байти.
  Питання: 1) Чому width не визначає домен? 2) Чому слова повторно
  допускаються через numericplane? 3) Чому stdout відкладається?
  4) Чому тритові й байтові проміжки можуть перекриватися байтом? }
function RenderBatch(const Physical: RawByteString; Width: SizeInt): RawByteString;
var Words, One: TExactWords; Spans: TPhysicalWordSpans;
    I: SizeInt; N: TExplicitNumeric; S: TPhysicalWordSpan;
    Candidate: RawByteString;
begin
  DecodeT5MWithLocations(Physical, Words, Spans);
  if (Length(Words) < 1) or (Length(Words) > MaxNumericWords) or
     (Length(Words) <> Length(Spans)) then
    raise Exception.Create('числових слів не 1..1024');
  SetLength(One, 1);
  Candidate := 'слово'#9'домен'#9'укр'#9'точні-біти'#9'трити'#9'байти'#10;
  for I := 0 to High(Words) do begin
    if Length(Words[I]) <> Width then
      raise Exception.Create('слово '+IntToStr(I+1)+': ширина не збігається з явним D'+IntToStr(Width));
    One[0] := Words[I];
    { Єдиний чинний numeric admission, навіть для нуля і знакового біта. }
    N := ReadNumericPhysical(EncodeT5M(One), Width);
    S := LocatePhysicalWord(Physical, Spans, I+1);
    if (N.DomainWidth <> Width) or (N.ExactBits <> Words[I]) then
      raise Exception.Create('втрачено точний числовий атом');
    Candidate := Candidate +
      IntToStr(S.WordIndex)+#9+'D'+IntToStr(Width)+#9+
      RenderNumericDecimal(N)+#9+N.ExactBits+#9+
      '['+IntToStr(S.TritStart)+','+IntToStr(S.TritEnd)+')'+#9+
      '['+IntToStr(S.ByteStart)+','+IntToStr(S.ByteEnd)+')'+#10;
  end;
  Result := Candidate;
end;

function Main: Integer;
var Width: SizeInt; Physical, Report: RawByteString;
begin
  Result := 64;
  if (ParamCount <> 3) or (ParamStr(1) <> '--перегляд-пакета') then begin
    WriteLn(StdErr,'Використання: senschyslopaket --перегляд-пакета D12 файл.sens');
    Exit;
  end;
  try
    Width := SelectedNumericDomain(RawByteString(ParamStr(2)));
    Physical := ReadPhysical(ParamStr(3));
    Report := RenderBatch(Physical, Width);
    Write(Report); { atomic stdout: після повного admission усіх слів }
    Result := 0;
  except
    on E: Exception do begin
      WriteLn(StdErr,'ЧИСЛОВИЙ-ПАКЕТ-ПОМИЛКА: ',E.Message);
      Result := 2;
    end;
  end;
end;

begin
  Halt(Main);
end.
