{ G2.27/G2.30: FPC огляд pinned шести проєкцій exact D1–D10.
  Звичайний режим друкує одну координату; --домен і --всі —
  лише повний фізично адресований каталог. Жодного dispatch, oracle
  чи нового мовного закону. D7 — текст, числова площина починається D12+. }
program sensproekcii;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.proektsii,
  wsm.t5m, wsm.d2source, wsm.physloc;
const
  Labels: array[0..5] of RawByteString =
    ('ук', 'укр', 'san', 'en', 'LISP', 'sym');
  { Host-аргументи приходять байтами UTF-8. Без ANSI/Unicode порівняння. }
  AllMode:RawByteString='--'+#$D0#$B2#$D1#$81#$D1#$96;
  DomainMode:RawByteString='--'+#$D0#$B4#$D0#$BE#$D0#$BC+#$D0#$B5+#$D0#$BD;
  FileMode:RawByteString='--'+#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB;
  MaxProjectionPhysicalBytes=65536;
  MaxProjectionWords=4096;
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

{ Єдина явна UTF-8 проєкція host-діагностики. Не кодує D7,
  не перетворює spelling на мовне значення. }
function Uk(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Тільки фізичний огляд: .sens — T5M, а НЕ текстове .lisp.
  Вхід: Path до 64 КіБ, borrowed перевірений pinned Catalog.
  Words: TExactWords (managed бітові рядки), Spans: 0-based інтервали
  тритів/байтів, Doc: власний D2 AST, Report: власний буфер рядків.
  До stdout нічого не потрапляє до повного physical + D2 admission.
  Ширина W12+ НЕ перетворюється на математичне значення D12+. }
procedure ViewPhysicalFile(const Path:String;
  const Tables:TProektsiiCatalog);
var
  F:TFileStream;
  Physical,V,Line:RawByteString;
  Words:TExactWords;
  Spans:TPhysicalWordSpans;
  Doc:TD2Document;
  Report:TStringList;
  W,I,J:SizeInt;
  K:TDomainKey;
  R:TProektsiiaRow;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise EProektsiiError.Create('вхід має бути канонічним файлом .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxProjectionPhysicalBytes) then
      raise EProektsiiError.Create('розмір .sens поза фізичною межею 1..65536');
    SetLength(Physical,SizeInt(F.Size));
    F.ReadBuffer(Physical[1],Length(Physical));
  finally F.Free end;
  DecodeT5MWithLocations(Physical,Words,Spans);
  if Length(Words)>MaxProjectionWords then
    raise EProektsiiError.Create('понад 4096 фізичних слів');
  Doc:=nil;
  Report:=TStringList.Create;
  try
    try
      Doc:=ParseD2WordsWide(Words);
    except on E:ED2SourceError do
      raise EProektsiiError.Create(String(Uk('синтаксис D2: слово=')+
        RawByteString(IntToStr(E.WordIndex))+' '+RawByteString(E.Message)));
    end;
    Report.Add(String(Uk('СТРУКТУРА-ГАРАЗД коренів=')+
      RawByteString(IntToStr(Length(Doc.Roots)))+
      Uk(' фізичних-байтів=')+RawByteString(IntToStr(Length(Physical)))+
      Uk(' точних-слів=')+RawByteString(IntToStr(Length(Words)))));
    for I:=0 to High(Words) do begin
      W:=Length(Words[I]);
      Line:=Uk('слово=')+RawByteString(IntToStr(I+1))+
        ' W'+RawByteString(IntToStr(W))+':'+Words[I]+
        Uk(' трити=[')+RawByteString(IntToStr(Spans[I].TritStart))+','+
        RawByteString(IntToStr(Spans[I].TritEnd))+')'+Uk(' байти=[')+
        RawByteString(IntToStr(Spans[I].ByteStart))+','+
        RawByteString(IntToStr(Spans[I].ByteEnd))+')';
      Report.Add(String(Line));
      if (W>=1) and (W<=10) then begin
        K:=ExactKey(Words[I]);
        if (K.Bits>=Length(Tables[W])) or
           not SameKey(K,Tables[W][K.Bits].Key) then
          raise EProektsiiError.Create('неузгоджена pinned координата');
        R:=Tables[W][K.Bits];
        for J:=0 to 5 do begin
          V:=R.Surface[J];
          if V='' then V:='()';
          Report.Add(String(Labels[J]+': '+V));
        end;
      end else
        Report.Add(String(Uk('проєкції: поза D1–D10; точна ширина W')+
          RawByteString(IntToStr(W))+
          Uk(' не є доказом числової чи викличної семантики')));
    end;
    for I:=0 to Report.Count-1 do WriteLn(Report[I]);
  finally
    Doc.Free;
    Report.Free;
  end;
end;

begin
  try
    Mode:=RawByteString(ParamStr(2));
    if (ParamCount<2) or (ParamCount>3) then
      raise EProektsiiError.Create(
        'використання: sensproekcii ROOT БІТИ | ROOT --всі | ROOT --домен 1..10 | ROOT --файл файл.sens');
    if (ParamCount=3) and (Mode=FileMode) then begin
      LoadPinnedProjections(ParamStr(1),Catalog);
      ViewPhysicalFile(ParamStr(3),Catalog);
    end else if (ParamCount=2) and (Mode<>AllMode) then begin
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
