{ Фізичні фікстури G5.16 з ідентифікаторів реально pinned Core4.
  Генератор не створює мовних законів чи локального словника імен. }
program TestCore4Session;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.core4runtime;

function MakeCall(const Id, Arg: RawByteString): RawByteString;
var
  Words: TExactWords;
  I, N: SizeInt;
begin
  if (Length(Id) = 0) or ((Length(Id) mod 7) <> 0) then
    raise Exception.Create('неповна фізична D7-послідовність');
  SetLength(Words, Length(Id) div 7 + 5);
  N := 0;
  Words[N] := '10'; Inc(N);
  Words[N] := '10'; Inc(N);
  for I := 0 to (Length(Id) div 7) - 1 do
  begin
    Words[N] := Copy(Id, I * 7 + 1, 7);
    Inc(N);
  end;
  Words[N] := '01'; Inc(N);
  Words[N] := Arg; Inc(N);
  Words[N] := '01'; Inc(N);
  SetLength(Words, N);
  Result := EncodeT5M(Words);
end;

function MakeIdentifier(const Id: RawByteString): RawByteString;
var
  Words: TExactWords;
  I: SizeInt;
begin
  if (Length(Id) = 0) or ((Length(Id) mod 7) <> 0) then
    raise Exception.Create('неповна фізична D7-послідовність');
  SetLength(Words, Length(Id) div 7 + 2);
  Words[0] := '10';
  for I := 0 to (Length(Id) div 7) - 1 do
    Words[I + 1] := Copy(Id, I * 7 + 1, 7);
  Words[High(Words)] := '01';
  Result := EncodeT5M(Words);
end;

procedure SavePhysical(const Path: String; const Physical: RawByteString);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Path, fmCreate);
  try
    if Length(Physical) > 0 then
      F.WriteBuffer(Physical[1], Length(Physical));
  finally
    F.Free;
  end;
end;

var
  Runtime: TCore4Runtime;
  Root, Dir, NameBits, UnknownBits, InvalidCall: RawByteString;
  Rejected: Boolean;
begin
  if ParamCount <> 2 then
    raise Exception.Create('потрібні корінь репозиторію та директорія фікстур');
  Root := ParamStr(1);
  Dir := IncludeTrailingPathDelimiter(ParamStr(2));
  Runtime := TCore4Runtime.Create(String(Root));
  try
    if Runtime.BindingCount <> 3 then
      raise Exception.Create('очікуються три перевірені визначення pinned Core4');
    NameBits := Runtime.FirstDefinitionIdentifier;
    SavePhysical(String(Dir) + '01-tak.sens', MakeCall(NameBits, '1'));

    { Невідомий D7-ідентифікатор як негативний фізичний свідок. }
    UnknownBits := NameBits + '1111111';
    InvalidCall := MakeCall(UnknownBits, '1');
    Rejected := False;
    try
      Runtime.ExecutePhysicalCall(InvalidCall);
    except
      on E: ECore4RuntimeError do Rejected := True;
    end;
    if not Rejected then
      raise Exception.Create('генератор не довів невідомий D7 ідентифікатор');
    SavePhysical(String(Dir) + '02-nevidome.sens', InvalidCall);

    SavePhysical(String(Dir) + '03-ni.sens', MakeCall(NameBits, '0'));
    SavePhysical(String(Dir) + '04-d24-argument.sens',
      MakeCall(NameBits, '000000000000000000000001'));
    SavePhysical(String(Dir) + '05-global-d24-0.sens',
      MakeIdentifier(Runtime.BindingIdentifier(1)));
    SavePhysical(String(Dir) + '06-poshkodzhenyi.sens', #243);
    SavePhysical(String(Dir) + '07-global-d24-1.sens',
      MakeIdentifier(Runtime.BindingIdentifier(2)));
    SavePhysical(String(Dir) + '09-povtornyi.sens', MakeCall(NameBits, '1'));
  finally
    Runtime.Free;
  end;
  WriteLn('CORE4-СЕАНС-ФІКСТУРИ-ГАРАЗД');
end.
