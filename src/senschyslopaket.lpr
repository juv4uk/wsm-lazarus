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
    raise Exception.Create(#$D0#$BF#$D0#$BE#$D1#$82#$D1#$80#$D1#$96#$D0#$B1#$D0#$B5#$D0#$BD#$20#$D0#$BA#$D0#$B0#$D0#$BD#$D0#$BE#$D0#$BD#$D1#$96#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$20#$2E#$73#$65#$6E#$73);
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size < 1) or (Stream.Size > MaxPhysicalBytes) then
      raise Exception.Create(#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82#$20#$D0#$BF#$D0#$BE#$D1#$80#$D0#$BE#$D0#$B6#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$B0#$D0#$B1#$D0#$BE#$20#$D0#$BF#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B4#$20#$36#$35#$35#$33#$36#$20#$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$D1#$96#$D0#$B2);
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
    Row: RawByteString;
    Buffer: TMemoryStream;
begin
  DecodeT5MWithLocations(Physical, Words, Spans);
  if (Length(Words) < 1) or (Length(Words) > MaxNumericWords) or
     (Length(Words) <> Length(Spans)) then
    raise Exception.Create(#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B8#$D1#$85#$20#$D1#$81#$D0#$BB#$D1#$96#$D0#$B2#$20#$D0#$BD#$D0#$B5#$20#$31#$2E#$2E#$31#$30#$32#$34);
  SetLength(One, 1);
  { Вихід: власний TMemoryStream, тимчасові рядки Row. Один запис
    на перевірене фізичне слово; публікація тільки після всіх 1024.
    Немає дублювання раніше зібраних рядків у кожній ітерації.
    Чому буфер живе тільки всередині RenderBatch?
    Чому друк до останнього слова зламав би fail-closed?
    Чому індекс і адреси — фізичні дані, а не числові закони?
    Як гарантується звільнення буфера за винятком? }
  Buffer := TMemoryStream.Create;
  try
    Row := #$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#9#$D0#$B4#$D0#$BE#$D0#$BC#$D0#$B5#$D0#$BD#9#$D1#$83#$D0#$BA#$D1#$80#9#$D1#$82#$D0#$BE#$D1#$87#$D0#$BD#$D1#$96#$2D#$D0#$B1#$D1#$96#$D1#$82#$D0#$B8#9#$D1#$82#$D1#$80#$D0#$B8#$D1#$82#$D0#$B8#9#$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$D0#$B8#10;
    Buffer.WriteBuffer(Row[1], Length(Row));
    for I := 0 to High(Words) do begin
    if Length(Words[I]) <> Width then
      raise Exception.Create(#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$20+IntToStr(I+1)+#$3A#$20#$D1#$88#$D0#$B8#$D1#$80#$D0#$B8#$D0#$BD#$D0#$B0#$20#$D0#$BD#$D0#$B5#$20#$D0#$B7#$D0#$B1#$D1#$96#$D0#$B3#$D0#$B0#$D1#$94#$D1#$82#$D1#$8C#$D1#$81#$D1#$8F#$20#$D0#$B7#$20#$D1#$8F#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$BC#$20#$44+IntToStr(Width));
    One[0] := Words[I];
    { Єдиний чинний numeric admission, навіть для нуля і знакового біта. }
    N := ReadNumericPhysical(EncodeT5M(One), Width);
    S := LocatePhysicalWord(Physical, Spans, I+1);
    if (N.DomainWidth <> Width) or (N.ExactBits <> Words[I]) then
      raise Exception.Create(#$D0#$B2#$D1#$82#$D1#$80#$D0#$B0#$D1#$87#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D1#$82#$D0#$BE#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D1#$87#$D0#$B8#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$B0#$D1#$82#$D0#$BE#$D0#$BC);
    Row :=
      IntToStr(S.WordIndex)+#9+'D'+IntToStr(Width)+#9+
      RenderNumericDecimal(N)+#9+N.ExactBits+#9+
      '['+IntToStr(S.TritStart)+','+IntToStr(S.TritEnd)+')'+#9+
      '['+IntToStr(S.ByteStart)+','+IntToStr(S.ByteEnd)+')'+#10;
      Buffer.WriteBuffer(Row[1], Length(Row));
    end;
    { Усі точні рядки вже перевірено; копіюємо один раз. }
    SetLength(Result, SizeInt(Buffer.Size));
    Buffer.Position := 0;
    Buffer.ReadBuffer(Result[1], Length(Result));
  finally
    Buffer.Free;
  end;
end;

function Main: Integer;
var Width: SizeInt; Physical, Report: RawByteString;
begin
  Result := 64;
  if (ParamCount <> 3) or (ParamStr(1) <> #$2D#$2D#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B3#$D0#$BB#$D1#$8F#$D0#$B4#$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82#$D0#$B0) then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$63#$68#$79#$73#$6C#$6F#$70#$61#$6B#$65#$74#$20#$2D#$2D#$D0#$BF#$D0#$B5#$D1#$80#$D0#$B5#$D0#$B3#$D0#$BB#$D1#$8F#$D0#$B4#$2D#$D0#$BF#$D0#$B0#$D0#$BA#$D0#$B5#$D1#$82#$D0#$B0#$20#$44#$31#$32#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$2E#$73#$65#$6E#$73);
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
      WriteLn(StdErr,#$D0#$A7#$D0#$98#$D0#$A1#$D0#$9B#$D0#$9E#$D0#$92#$D0#$98#$D0#$99#$2D#$D0#$9F#$D0#$90#$D0#$9A#$D0#$95#$D0#$A2#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$3A#$20,E.Message);
      Result := 2;
    end;
  end;
end;

begin
  Halt(Main);
end.
