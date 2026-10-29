{ G2.27/G2.30: FPC огляд pinned шести проєкцій exact D1–D10.
  Звичайний режим друкує одну координату; --домен і --всі —
  лише повний фізично адресований каталог. Жодного dispatch, oracle
  чи нового мовного закону. D7 — текст, числова площина починається D12+. }
program sensproekcii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.domain, wsm.proektsii;
const
  Labels: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
  { Host-аргументи приходять байтами UTF-8. Без ANSI/Unicode порівняння. }
  AllMode:RawByteString='--'+#$D0#$B2#$D1#$81#$D1#$96;
  DomainMode:RawByteString='--'+#$D0#$B4#$D0#$BE#$D0#$BC+#$D0#$B5+#$D0#$BD;
var
  Key: TDomainKey;
  Catalog: TProektsiiCatalog;
  Row: TProektsiiaRow;
  I,D,FirstDomain,LastDomain: Integer;
  Requested: String;
  Mode:RawByteString;

{ R — позичений рядок вже повністю перевіреного pinned каталогу.
  Surface — 6 FPC-managed UTF-8 байтових проєкцій, не runtime-виклики.
  Результат — сім рядків stdout, без алокації нових мовних значень. }
procedure PrintRow(const R:TProektsiiaRow);
var J:Integer; Value:RawByteString;
begin
  WriteLn(RawByteString('координата: D'),R.Key.Width,':',KeyBits(R.Key));
  for J:=0 to 5 do begin
    Value:=R.Surface[J];
    if Value='' then Value:='()'; { відсутня проєкція, не D1:0 }
    WriteLn(Labels[J],': ',Value);
  end;
end;

begin
  try
    Mode:=RawByteString(ParamStr(2));
    if (ParamCount<2) or (ParamCount>3) then
      raise EProektsiiError.Create(
        'використання: sensproekcii ROOT БІТИ | ROOT --всі | ROOT --домен 1..10');
    if (ParamCount=2) and (Mode<>AllMode) then begin
      Key:=ExactKey(RawByteString(ParamStr(2)));
      { До першого байта stdout допущено ВСІ pinned таблиці D1–D10. }
      LoadPinnedProjections(ParamStr(1),Catalog);
      if (Key.Width<1) or (Key.Width>10) or
         (Key.Bits>=Length(Catalog[Key.Width])) then
        raise EProektsiiError.Create('невідома фізична координата');
      Row:=Catalog[Key.Width][Key.Bits];
      if not SameKey(Key,Row.Key) then
        raise EProektsiiError.Create('порушено pinned точну координату');
      PrintRow(Row);
    end else begin
      if (ParamCount=2) and (Mode=AllMode) then begin
        FirstDomain:=1;LastDomain:=10;
      end else if (ParamCount=3) and (Mode=DomainMode) then begin
        Requested:=ParamStr(3);
        { Тільки канонічні десяткові host-ширини, НЕ числовий літерал SENS. }
        if (Requested='') or (Length(Requested)>2) or
           (Requested[1]='0') then
          raise EProektsiiError.Create('неканонічна ширина домену 1..10');
        for I:=1 to Length(Requested) do
          if not (Requested[I] in ['0'..'9']) then
            raise EProektsiiError.Create('домен має бути десятковою host-шириною');
        FirstDomain:=StrToInt(Requested);
        if (FirstDomain<1) or (FirstDomain>10) then
          raise EProektsiiError.Create('дозволено лише D1–D10, не D12+');
        LastDomain:=FirstDomain;
      end else
        raise EProektsiiError.Create('невідома команда огляду проєкцій');
      { Окремої таблиці ідентичності не створюємо: точні біти й порядок
        проходять існуючий атомарний LoadPinnedProjections. }
      LoadPinnedProjections(ParamStr(1),Catalog);
      for D:=FirstDomain to LastDomain do
        for I:=0 to High(Catalog[D]) do
          PrintRow(Catalog[D][I]);
    end;
  except
    on E:Exception do begin
      WriteLn(ErrOutput,RawByteString('ПРОЄКЦІЇ-ПОМИЛКА: '),
        RawByteString(E.Message));
      ExitCode:=2; { Не оминати cleanup heaptrc після діагностики. }
    end;
  end;
end.
