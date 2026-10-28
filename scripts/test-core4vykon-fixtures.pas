{ Фізичні T5M-свідки для зовнішнього CLI. Імена взяті з pinned Core4
  через чинний TCore4Runtime; механізм не створює словник законів SENS. }
program TestCore4CliFixtures;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.core4runtime, wsm.t5m, wsm.physloc,
  wsm.d2source;

procedure Save(const Path: String; const Bytes: RawByteString);
var S: TFileStream;
begin
  S := TFileStream.Create(Path, fmCreate);
  try
    if Length(Bytes) > 0 then S.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    S.Free;
  end;
end;

function Exact(const Bits: RawByteString): RawByteString;
var W: TExactWords;
begin
  SetLength(W, 1); W[0] := Bits;
  Result := EncodeT5M(W);
end;

function CallPhysical(const Id, Arg: RawByteString): RawByteString;
var W: TExactWords; I, N: SizeInt;
begin
  if (Length(Id) = 0) or ((Length(Id) mod 7) <> 0) then
    raise Exception.Create('порушена точна D7-послідовність');
  SetLength(W, Length(Id) div 7 + 5);
  N := 0; W[N] := '10'; Inc(N); W[N] := '10'; Inc(N);
  for I := 0 to (Length(Id) div 7) - 1 do
  begin
    W[N] := Copy(Id, I * 7 + 1, 7); Inc(N);
  end;
  W[N] := '01'; Inc(N);
  W[N] := Arg; Inc(N);
  W[N] := '01'; Inc(N);
  SetLength(W, N);
  Result := EncodeT5M(W);
end;

function GlobalPhysical(const Id: RawByteString): RawByteString;
var W: TExactWords; I: SizeInt;
begin
  if (Length(Id) = 0) or ((Length(Id) mod 7) <> 0) then
    raise Exception.Create('порушене глобальне D7-ім’я');
  SetLength(W, Length(Id) div 7 + 2);
  W[0] := '10';
  for I := 0 to (Length(Id) div 7) - 1 do
    W[I + 1] := Copy(Id, I * 7 + 1, 7);
  W[High(W)] := '01';
  Result := EncodeT5M(W);
end;

function BatchPhysical(const Calls: array of RawByteString):RawByteString;
var ResultWords,CallWords:TExactWords; I,J,N:SizeInt;
begin
  SetLength(ResultWords,0);
  for I:=0 to High(Calls) do begin
    DecodeT5M(Calls[I],CallWords);
    N:=Length(ResultWords);
    SetLength(ResultWords,N+Length(CallWords));
    for J:=0 to High(CallWords) do ResultWords[N+J]:=CallWords[J];
  end;
  Result:=EncodeT5M(ResultWords);
end;

{ Очікувані адреси беруться з ПОЧАТКОВОГО спільного фізичного .sens,
  а не з повторно упакованої третьої форми із локальним нульовим offset. }
procedure SaveThirdRootAddress(const Path: String;const Physical:RawByteString);
var
  W:TExactWords; Spans:TPhysicalWordSpans;
  D:TD2Document; At:TPhysicalWordSpan;
  TextValue:RawByteString;
begin
  DecodeT5MWithLocations(Physical,W,Spans);
  D:=ParseD2WordsWide(W);
  try
    if Length(D.Roots)<>3 then
      raise Exception.Create('свідок має не три фізичні корені');
    At:=LocatePhysicalWord(Physical,Spans,D.Roots[2].WordIndex);
    if At.IsEOF or (At.WordIndex<=1) or (At.ByteStart<=0) then
      raise Exception.Create('третя форма мусить мати реальне зміщення');
    TextValue:='форма=3 початок-слово='+IntToStr(At.WordIndex)+
      ' трити=['+IntToStr(At.TritStart)+','+IntToStr(At.TritEnd)+
      ') байти=['+IntToStr(At.ByteStart)+','+IntToStr(At.ByteEnd)+')';
    Save(Path,TextValue);
  finally D.Free end;
end;

var
  Runtime: TCore4Runtime;
  Id, Altered: RawByteString;
  Dest: String;
  Parts: array of RawByteString;
  I: SizeInt;
  FaultPhysical:RawByteString;
begin
  if ParamCount <> 2 then
  begin
    WriteLn(StdErr, 'Використання: test-core4vykon-fixtures КОРІНЬ ТЕКА');
    Halt(64);
  end;
  Dest := IncludeTrailingPathDelimiter(ParamStr(2));
  Runtime := TCore4Runtime.Create(ParamStr(1));
  try
    if Runtime.BindingCount <> 3 then
      raise Exception.Create('відсутні три pinned Core4 визначення');
    Id := Runtime.FirstDefinitionIdentifier;
    Save(Dest + 'tak.sens', CallPhysical(Id, '1'));
    Save(Dest + 'tak-chek.sens', Exact('1'));
    Save(Dest + 'ni.sens', CallPhysical(Id, '0'));
    Save(Dest + 'ni-chek.sens', Exact('0'));
    Save(Dest + 'd24.sens', CallPhysical(Id, '000000000000000000000000'));
    Save(Dest + 'd24-chek.sens', Exact('000000000000000000000000'));
    Save(Dest + 'global.sens', GlobalPhysical(Runtime.BindingIdentifier(2)));
    Save(Dest + 'global-chek.sens', Exact('000000000000000000000001'));
    Save(Dest + 'nepidtrymano.sens', CallPhysical(Id, '000'));
    Altered := Copy(Id, 1, Length(Id));
    if Altered[7] = '0' then Altered[7] := '1'
    else Altered[7] := '0';
    Save(Dest + 'nevidome.sens', CallPhysical(Altered, '1'));
    { Спільне T5M пакування без конкатенації байтових контейнерів. }
    SetLength(Parts,3);
    Parts[0]:=CallPhysical(Id,'1');
    Parts[1]:=CallPhysical(Id,'0');
    Parts[2]:=GlobalPhysical(Runtime.BindingIdentifier(1));
    Save(Dest+'paket.sens',BatchPhysical(Parts));
    Save(Dest+'paket-chek.sens',BatchPhysical([
      Exact('1'),Exact('0'),Exact('000000000000000000000000')]));
    Parts[2]:=CallPhysical(Altered,'1');
    FaultPhysical:=BatchPhysical(Parts);
    Save(Dest+'paket-piznia-pomylka.sens',FaultPhysical);
    SaveThirdRootAddress(Dest+'paket-piznia-adresa.txt',FaultPhysical);
    SetLength(Parts,65);
    for I:=0 to High(Parts) do Parts[I]:=CallPhysical(Id,'1');
    Save(Dest+'paket-zavelykyi.sens',BatchPhysical(Parts));
    Save(Dest + 'poshkodzheno.sens', AnsiChar(243));
    Save(Dest + 'porozhnie.sens', '');
    Save(Dest + 'zainiate.sens', 'НЕ ЧІПАТИ');
    WriteLn('CORE4-СВІДКИ-ГОТОВО: фізичні-T5M=11');
  finally
    Runtime.Free;
  end;
end.
