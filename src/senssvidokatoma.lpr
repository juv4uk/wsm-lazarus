{ G2.51 — фізичний свідок ОДНОГО точного атома за ЯВНО обраним доменом.
  D7: шість pinned людських поверхонь; D12+: явна десяткова проєкція.
  Це НЕ reader програм, evaluator, числова арифметика чи закон SENS. }
program senssvidokatoma;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.physloc, wsm.domain,
  wsm.proektsii, wsm.numericplane;

const
  SurfaceNames:array[0..5] of RawByteString =
    ('ук','укр','san','en','LISP','sym');
  MaxAtomicFileBytes=64;

{ Path — host-шлях (borrowed). Result — FPC-managed оригінальні T5M
  байти (власник caller), без UTF-8 перетворення або доменного вгадування.
  Питання: хто володіє Result? Чому текстова .lisp тут заборонена?
  Чому обмеження 64 байти не визначає мовний закон? }
function ReadPhysicalAtom(const Path:String):RawByteString;
var F:TFileStream;
begin
  if LowerCase(ExtractFileExt(Path))<>'.sens' then
    raise Exception.Create('дозволено лише фізичний двійковий .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxAtomicFileBytes) then
      raise Exception.Create('неприпустимий розмір фізичного атома');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Bytes — власний packed T5M, DomainName — явний host-тег,
  Words/Spans — керовані масиви, отримані з існуючого фізичного reader.
  Report — локальна транзакційна UTF-8 проєкція; stdout тільки після
  повного допуску всіх полів. D7 не набуває викличності, D12+ — арифметики.
  Питання: чому W7 не є числом? Що робить SameKey?
  Чому байтові адреси — envelope? Де точні тритові межі? }
function BuildWitness(const Root:String;const DomainName:RawByteString;
  const Bytes:RawByteString):RawByteString;
var Words:TExactWords; Spans:TPhysicalWordSpans;
    Catalog:TProektsiiCatalog; Row:TProektsiiaRow;
    Key:TDomainKey; N:TExplicitNumeric;
    Width,J:SizeInt; Surface:RawByteString;
begin
  Result:='';
  if DomainName='D7' then Width:=7
  else Width:=SelectedNumericDomain(DomainName);
  DecodeT5MWithLocations(Bytes,Words,Spans);
  if (Length(Words)<>1) or (Length(Spans)<>1) then
    raise Exception.Create('потрібен рівно один фізичний атом');
  if Length(Words[0])<>Width then
    raise Exception.Create('точна ширина атома не відповідає явному домену');
  { Pinned root обов'язковий: жоден випадковий host каталог не є
    мовним авторитетом. Вибір проєкції не змінює packed слова. }
  if not FileExists(IncludeTrailingPathDelimiter(Root)+
    'lib/domains/d7.lisp') then
    raise Exception.Create('недоступна pinned таблиця SENS D7');
  if DomainName='D7' then begin
    LoadPinnedProjections(Root,Catalog);
    Key:=ExactKey(Words[0]);
    if (Key.Width<>7) or (Key.Bits>=Length(Catalog[7])) or
      not SameKey(Key,Catalog[7][Key.Bits].Key) then
      raise Exception.Create('невідома точна D7 координата');
    Row:=Catalog[7][Key.Bits];
  end else begin
    N:=ReadNumericPhysical(Bytes,Width);
    { RenderNumericDecimal не є SENS арифметикою. }
    Surface:=RenderNumericDecimal(N);
  end;
  Result:='домен: '+DomainName+LineEnding+
    'біти: '+Words[0]+LineEnding+
    'слово: 1'+LineEnding+
    'трити: ['+RawByteString(IntToStr(Spans[0].TritStart))+','+
      RawByteString(IntToStr(Spans[0].TritEnd))+')'+LineEnding+
    'байти: ['+RawByteString(IntToStr(Spans[0].ByteStart))+','+
      RawByteString(IntToStr(Spans[0].ByteEnd))+')'+LineEnding;
  if DomainName='D7' then begin
    Result:=Result+'викличність: не-перевірено (D7 — дані)'+LineEnding;
    for J:=0 to 5 do
      Result:=Result+SurfaceNames[J]+': '+
        RawByteString(SurfaceForDisplay(Row.Surface[J]))+LineEnding;
  end else Result:=Result+'укр-число: '+Surface+LineEnding+
    'арифметика: не-виконувалася'+LineEnding;
end;

var Bytes,Report,DomainName:RawByteString;
begin
  try
    if (ParamCount<>4) or (ParamStr(2)<>'--атом') then
      raise Exception.Create(
        'використання: senssvidokatoma ROOT --атом D7|D12|D24|D48|D96|D192 файл.sens');
    DomainName:=RawByteString(ParamStr(3));
    Bytes:=ReadPhysicalAtom(ParamStr(4));
    Report:=BuildWitness(ParamStr(1),DomainName,Bytes);
    Write(Report); { лише одна точка публікації після повного допуску }
  except on E:Exception do begin
    WriteLn(ErrOutput,'СВІДОК-АТОМА-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end;end;
end.
