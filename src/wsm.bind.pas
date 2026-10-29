{ Read-only SENS Ukrainian projection -> exact (width, bits). No callability. }
unit wsm.bind;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, wsm.domain;
const
  FirstDomain = 1;
  LastDomain = 10;
type
  EBindError = class(Exception);
  TDomainSet = array[FirstDomain..LastDomain] of TDomainTable;
procedure LoadPinnedDomains(const Root: RawByteString; out Tables: TDomainSet);
function BindUkrainian(const Tables: TDomainSet;
  const Name: RawByteString): TDomainKey;
function BindUkrainianInDomain(const Tables: TDomainSet;
  const Name: RawByteString; Domain: Byte): TDomainKey;
implementation
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
  for D:=FirstDomain to LastDomain do begin
    Path:=IncludeTrailingPathDelimiter(String(Root))+'lib/domains/d'+IntToStr(D)+'.lisp';
    { Кілька незалежних компіляторів повинні одночасно читати ОДИН
      pinned D1–D10 корпус. fmOpenRead без явного share може
      заблокувати іншого читача; спільний read lock відхиляє записи.
      Path запозичений; F закривається в finally, Data живе локально.
      Питання: чому pinned читачам не потрібен exclusive lock?
      Чому fmShareDenyWrite не дозволяє запис іншому учаснику?
      Чому це host синхронізація, а не новий SENS закон? }
    F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
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
