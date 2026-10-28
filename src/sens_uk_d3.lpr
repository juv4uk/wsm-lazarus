{ Нативний командний запуск ВЖЕ ДОПУЩЕНОГО обмеженого D3-механізму.
  Українська .lisp-проєкція — явний людський вхід, НЕ семантичний
  оракул і НЕ канонічний двійковий .sens/T5M.
  Точні закони SENS залишаються в pinned SENS. Тут немає dispatch. }
program sens_uk_d3;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.nativeeval, wsm.source;

const
  MaxVkhidBytes = 16 * 1024 * 1024;
type
  EPomylkaVkhodu = class(Exception);

function ProchytatyFayl(const Shlyakh: String): RawByteString;
var Potik: TFileStream;
begin
  if ExtractFileExt(Shlyakh) <> '.lisp' then
    raise EPomylkaVkhodu.Create(
      'Потрібна українська проєкція .lisp; двійковий .sens тут не підтриманий');
  Potik := TFileStream.Create(Shlyakh, fmOpenRead or fmShareDenyWrite);
  try
    if (Potik.Size <= 0) or (Potik.Size > MaxVkhidBytes) then
      raise EPomylkaVkhodu.Create('Неприпустимий розмір вхідного файлу (1..16 МіБ)');
    SetLength(Result, SizeInt(Potik.Size));
    Potik.ReadBuffer(Result[1], Length(Result));
  finally Potik.Free; end;
end;

{ Пишемо фізичні UTF-8 байти, не залежимо від кодової сторінки
  консольного Text/WriteLn на GitHub-hosted Linux. }
procedure NapisatyStderr(const Tekst: UnicodeString);
var
  Bytes: UTF8String;
  Potik: THandleStream;
begin
  Bytes := UTF8Encode(Tekst + #10);
  Potik := THandleStream.Create(TextRec(StdErr).Handle);
  try
    if Length(Bytes) > 0 then Potik.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    Potik.Free;
  end;
end;

procedure Zapustyty;
var Vkhid, Vidpovid: RawByteString; Vikonavets: TNativeEvaluator;
    Rezhym: UnicodeString;
begin
  { ParamStr повертає байти ОС; явно декодуємо їх з UTF-8,
    інакше FPC може помилково зіставити українські прапорці. }
  Rezhym := UTF8Decode(RawByteString(ParamStr(1)));
  if (ParamCount <> 2) or
     not ((Rezhym = '--вираз-ук') or
          (Rezhym = '--файл-ук')) then begin
    NapisatyStderr('Використання: sens-uk-d3 --вираз-ук ' +
      '''(сполучити так ())'' | --файл-ук шлях.lisp');
    ExitCode := 64;
    Exit;
  end;
  try
    if Rezhym = '--файл-ук' then
      Vkhid := ProchytatyFayl(ParamStr(2))
    else begin
      Vkhid := RawByteString(ParamStr(2));
      if Length(Vkhid) > MaxVkhidBytes then
        raise EPomylkaVkhodu.Create('Вираз перевищив 16 МіБ');
    end;
    Vikonavets := TNativeEvaluator.Create('external/sens');
    try
      { Повна перевірка й виконання ДО будь-якого запису у stdout. }
      Vidpovid := Vikonavets.EvaluateSource(Vkhid);
    finally Vikonavets.Free; end;
    { Тільки точні біти/структура результату; це НЕ файл .sens. }
    WriteLn(Vidpovid);
  except
    on E: ESourceError do begin
      NapisatyStderr('ПОМИЛКА-УК рядок=' + IntToStr(E.Line) +
        ' колонка=' + IntToStr(E.ByteColumn) +
        ' байт=' + IntToStr(E.ByteOffset) +
        ' причина=' + UTF8Decode(RawByteString(E.Message)));
      ExitCode := 2;
    end;
    on E: Exception do begin
      NapisatyStderr('ПОМИЛКА-УК причина=' +
        UTF8Decode(RawByteString(E.Message)));
      ExitCode := 2;
    end;
  end;
end;

begin Zapustyty; end.
