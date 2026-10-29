{ G2.27: headless host-перегляд ОДНОЇ exact координати через наявний
  G2.26 wsm.proektsii — pinned каталог, БЕЗ другого reader/закону.
  LISP — історична колонка, D7 — текстові дані, D12+ — окремі числа. }
program sensproekcii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.domain, wsm.proektsii;
const
  Labels: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
var
  Key: TDomainKey;
  Catalog: TProektsiiCatalog;
  Row: TProektsiiaRow;
  I: Integer;
  Value: RawByteString;
begin
  try
    if ParamCount <> 2 then
      raise EProektsiiError.Create('використання: sensproekcii <корінь pinned SENS> <точні біти>');
    Key := ExactKey(RawByteString(ParamStr(2)));
    { Існуючий G2.26 перевіряє pinned таблиці D1–D10 атомарно;
      Catalog має FPC-managed lifetime; читання за (Width, Bits) точне. }
    LoadPinnedProjections(ParamStr(1), Catalog);
    if (Key.Width < 1) or (Key.Width > 10) or
       (Key.Bits >= Length(Catalog[Key.Width])) then
      raise EProektsiiError.Create('невідома фізична координата');
    Row := Catalog[Key.Width][Key.Bits];
    if not SameKey(Key, Row.Key) then
      raise EProektsiiError.Create('порушено pinned точну координату');
    WriteLn(RawByteString('координата: D'), Key.Width, ':', KeyBits(Key));
    for I := 0 to 5 do begin
      Value := Row.Surface[I];
      if Value = '' then Value := '()'; { відсутність проєкції, НЕ D1:0 }
      WriteLn(Labels[I], ': ', Value);
    end;
  except
    on E: Exception do begin
      WriteLn(ErrOutput, RawByteString('ПРОЄКЦІЇ-ПОМИЛКА: '),
        RawByteString(E.Message));
      Halt(2);
    end;
  end;
end.
