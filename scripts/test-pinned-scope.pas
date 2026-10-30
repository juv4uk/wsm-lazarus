{ G6 — машинна перевірка одноразового scope pinned-таблиць.
  Caller-mutation, інший Root, повторний scope після зміни файла
  не мають права приховати пошкоджену таблицю. }
program test_pinned_scope;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.bind,wsm.domain;
var
  Root:String;
  A,B:TDomainSet;
  D:SizeInt;
  ErrorSeen:Boolean;
  F:TFileStream;
  Bad:RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  Root:=ParamStr(1);
  LoadPinnedDomains(RawByteString(Root),A);
  for D:=FirstDomain to LastDomain do
    if Length(A[D])=0 then Halt(10);

  BeginPinnedLoadScope;
  try
    LoadPinnedDomains(RawByteString(Root),A);
    A[3][0].Ukrainian:='СКОМПРОМЕТОВАНО';
    A[3][0].Key.Bits:=65535;
    LoadPinnedDomains(RawByteString(Root),B);
    if B[3][0].Ukrainian='СКОМПРОМЕТОВАНО' then Halt(11);
    if B[3][0].Key.Bits=65535 then Halt(12);

    ErrorSeen:=False;
    try
      BeginPinnedLoadScope;
    except on E:EBindError do ErrorSeen:=True end;
    if not ErrorSeen then Halt(13);

    ErrorSeen:=False;
    try
      LoadPinnedDomains(RawByteString(Root)+'/інший-корінь',A);
    except on E:EBindError do ErrorSeen:=True end;
    if not ErrorSeen then Halt(14);
    for D:=FirstDomain to LastDomain do
      if Length(A[D])<>0 then Halt(15);
  finally EndPinnedLoadScope end;

  { Фізично пошкоджуємо ЛИШЕ ТИМЧАСОВУ копію pinned D3.
    Відсутність cross-scope cache мусить примусити новий Load
    прочитати її та відмовити. }
  F:=TFileStream.Create(Root+'/lib/domains/d3.lisp',fmOpenWrite or fmShareDenyNone);
  try
    F.Position:=F.Size;
    Bad:=#10'(';
    F.WriteBuffer(Bad[1],Length(Bad));
  finally F.Free end;

  ErrorSeen:=False;
  BeginPinnedLoadScope;
  try
    try
      LoadPinnedDomains(RawByteString(Root),A);
    except on E:Exception do ErrorSeen:=True end;
    if not ErrorSeen then Halt(16);
    for D:=FirstDomain to LastDomain do
      if Length(A[D])<>0 then Halt(17);
  finally EndPinnedLoadScope end;
  Writeln('ПІН-СКОУП-ПРОЙДЕНО domains=10 isolated=так mutation=так errors=так');
end.
