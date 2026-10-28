{ SENS Ukrainian surface -> exact domain coordinate; no semantic callability. }
unit wsm.bind;
{$mode objfpc}{$H+}
interface
uses SysUtils, Classes, wsm.domain;
type
  EBindError = class(Exception);
  TDomainSet = array[1..3] of TDomainTable;
procedure LoadPinnedDomains(const Root: RawByteString; out Tables: TDomainSet);
function BindUkrainian(const Tables: TDomainSet; const Name: RawByteString): TDomainKey;
implementation
procedure LoadPinnedDomains(const Root: RawByteString; out Tables: TDomainSet);
var D:Integer; F:TFileStream; Data,Path:RawByteString;
begin
  for D:=1 to 3 do begin
    Path:=IncludeTrailingPathDelimiter(String(Root))+'lib/domains/d'+IntToStr(D)+'.lisp';
    F:=TFileStream.Create(Path,fmOpenRead);
    try
      if F.Size>High(LongInt) then raise EBindError.Create('domain table too large');
      SetLength(Data,F.Size);
      if Length(Data)>0 then F.ReadBuffer(Data[1],Length(Data));
    finally F.Free; end;
    LoadDomainTable(Data,D,Tables[D]);
  end;
end;
function BindUkrainian(const Tables:TDomainSet; const Name:RawByteString):TDomainKey;
var D:Integer; K:TDomainKey; Found:Boolean;
begin
  Found:=False;
  if Name='' then raise EBindError.Create('empty Ukrainian surface');
  for D:=1 to 3 do
    if UkrainianKey(Tables[D],Name,K) then begin
      if Found then raise EBindError.Create('ambiguous Ukrainian surface across domains');
      Result:=K; Found:=True;
    end;
  if not Found then raise EBindError.Create('unknown Ukrainian surface');
end;
end.
