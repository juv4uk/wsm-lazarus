{ Read-only SENS Ukrainian projection -> exact (width, bits). No callability. }
unit wsm.bind;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, Classes, wsm.domain;
const
  FirstDomain = 1;
  LastDomain = 10;
type
  EBindError = class(Exception);
  TDomainSet = array[FirstDomain..LastDomain] of TDomainTable;
procedure BeginPinnedLoadScope;
procedure EndPinnedLoadScope;
procedure LoadPinnedDomains(const Root: RawByteString; out Tables: TDomainSet);
function BindUkrainian(const Tables: TDomainSet;
  const Name: RawByteString): TDomainKey;
function BindUkrainianInDomain(const Tables: TDomainSet;
  const Name: RawByteString; Domain: Byte): TDomainKey;
implementation
type
  PPinnedLoadContext=^TPinnedLoadContext;
  TPinnedLoadContext=record
    Root:RawByteString;
    Tables:TDomainSet;
    Loaded:Boolean;
  end;
threadvar ActivePinnedLoad:PPinnedLoadContext;

{ Цей scope є THREAD-LOCAL і триває тільки один BuildVerifiedWideELF.
  Він не є міжпрограмним кешем, не переживає нативної компіляції.
  Перша спроба LoadPinnedDomains читає/валідує ВСІ D1..D10 з диска.
  Після повного success наступний запит ТОГО САМОГО root у межах
  того самого виклику одержує окремі динамічні масиви таблиць.
  1) Чому snapshot не переносимо на наступну SENS програму?
  2) Чому не можна створювати scope повторно в тому самому потоці?
  3) Хто звільняє snapshot після compile exception?
  4) Чому це host-оптимізація, а не нове право викличності? }
procedure BeginPinnedLoadScope;
begin
  if ActivePinnedLoad<>nil then
    raise EBindError.Create('nested pinned load scope forbidden');
  New(ActivePinnedLoad);
  ActivePinnedLoad^.Loaded:=False;
  ActivePinnedLoad^.Root:='';
end;

procedure EndPinnedLoadScope;
var Old:PPinnedLoadContext;
begin
  if ActivePinnedLoad=nil then
    raise EBindError.Create('pinned load scope missing');
  Old:=ActivePinnedLoad;
  ActivePinnedLoad:=nil;
  Dispose(Old);
end;

{ Caller отримує ВЛАСНІ dynamic arrays; row string користується FPC
  copy-on-write, не переносить мутований набір назад у scoped cache.
  Це не повторний розбір pinned таблиць і не англомовний dispatch.
  1) Чому просте Tables:=Cache могло б поділити mutable масив?
  2) Хто володіє скопійованими RawByteString?
  3) Чому немає межі валідності cache поза scope? }
procedure ClonePinnedTables(const Source:TDomainSet;out Dest:TDomainSet);
var D,I:SizeInt;
begin
  for D:=FirstDomain to LastDomain do begin
    SetLength(Dest[D],Length(Source[D]));
    for I:=0 to High(Source[D]) do Dest[D][I]:=Source[D][I];
  end;
end;

const
  { Межа host-ресурсу для однієї pinned проєкційної таблиці,
    НЕ новий закон Dn. Десятий домен SENS має 1024 рядки,
    що вміщуються значно нижче одного МіБ. Відмова — до SetLength. }
  MaxPinnedDomainTableBytes = 1024*1024;

procedure LoadPinnedDomains(const Root: RawByteString; out Tables: TDomainSet);
var D:Integer; F:TFileStream; Data,Path:RawByteString;
    Candidate:TDomainSet;
begin
  { Повний pinned набір публікується лише один раз, після D10.
    За пізньої відмови зовнішній out-масив має бути порожнім. }
  for D:=FirstDomain to LastDomain do begin
    SetLength(Tables[D],0);
    SetLength(Candidate[D],0);
  end;
  if (ActivePinnedLoad<>nil) and ActivePinnedLoad^.Loaded then begin
    if ActivePinnedLoad^.Root<>Root then
      raise EBindError.Create('pinned scope: інший корінь авторитету');
    ClonePinnedTables(ActivePinnedLoad^.Tables,Tables);
    Exit;
  end;
  for D:=FirstDomain to LastDomain do begin
    Path:=IncludeTrailingPathDelimiter(String(Root))+'lib/domains/d'+IntToStr(D)+'.lisp';
    { Кілька незалежних компіляторів повинні одночасно читати ОДИН
      pinned D1–D10 корпус. fmOpenRead без явного share може
      заблокувати іншого читача; спільний read lock відхиляє записи.
      Path запозичений; F закривається в finally, Data живе локально.
      Питання: чому pinned читачам не потрібен exclusive lock?
      Чому fmShareDenyWrite не дозволяє запис іншому учаснику?
      Чому це host синхронізація, а не новий SENS закон? }
    { Адресна host-відмова ДО читання: файл Dn може бути відсутнім.
      Жодного часткового набору Tables не публікуємо. Виняток зберігає
      початкову I/O причину та точний домен, не створює SENS законів. }
    try
      F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    except
      on E:EFOpenError do
        raise EBindError.CreateFmt('pinned D%d: IO-OPEN: не вдалося відкрити таблицю %s: %s',
          [D,String(Path),E.Message]);
    end;
    try
      if F.Size <= 0 then
        raise EBindError.CreateFmt('pinned D%d: порожня таблиця', [D]);
      if F.Size > MaxPinnedDomainTableBytes then
        raise EBindError.CreateFmt(
          'pinned D%d: файл перевищує 1 МіБ до виділення пам''яті', [D]);
      SetLength(Data,F.Size);
      if Length(Data)>0 then F.ReadBuffer(Data[1],Length(Data));
    finally F.Free; end;
    LoadDomainTable(Data,D,Candidate[D]);
  end;
  Tables:=Candidate;
  if ActivePinnedLoad<>nil then begin
    ClonePinnedTables(Candidate,ActivePinnedLoad^.Tables);
    ActivePinnedLoad^.Root:=Root;
    ActivePinnedLoad^.Loaded:=True;
  end;
end;
function BindUkrainian(const Tables:TDomainSet;
  const Name:RawByteString):TDomainKey;
var D:Integer; K:TDomainKey; Found:Boolean;
begin
  Found:=False;
  if Name='' then raise EBindError.Create('empty Ukrainian surface');
  for D:=FirstDomain to LastDomain do
    if UkrainianKey(Tables[D],Name,K) then begin
      if Found then raise EBindError.Create('ambiguous Ukrainian surface across domains');
      Result:=K; Found:=True;
    end;
  if not Found then raise EBindError.Create('unknown Ukrainian surface');
end;
function BindUkrainianInDomain(const Tables:TDomainSet;
  const Name:RawByteString; Domain:Byte):TDomainKey;
begin
  if (Domain<FirstDomain) or (Domain>LastDomain) then
    raise EBindError.Create('unsupported domain width');
  if Name='' then raise EBindError.Create('empty Ukrainian surface');
  if not UkrainianKey(Tables[Domain],Name,Result) then
    raise EBindError.Create('surface not defined in requested domain');
end;
end.
