{ Нативний host-лічильник Linux RAPL. Це НЕ SENS-мовний закон, evaluator
  або доказ енерговитрат процесу. Два незалежні знімки зон зіставляються
  за фізичним відносним шляхом; вкладені зони ніколи не підсумовуються.
  Дані — QWord мкДж без округлення. Публікація stdout лише після перевірки. }
program sensrapl;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes;

type
  ENoEnergy = class(Exception);
  TZone = record
    Key, LabelText: String;
    Energy, MaxRange: QWord;
  end;
  TZones = array of TZone;

function StrictNumber(const S: String): QWord;
var I: SizeInt;
begin
  if S = '' then raise Exception.Create('Порожнє число RAPL');
  for I := 1 to Length(S) do
    if (S[I] < '0') or (S[I] > '9') then
      raise Exception.Create('Некоректний десятковий лічильник RAPL');
  if not TryStrToQWord(S, Result) then
    raise Exception.Create('Переповнення QWord RAPL');
end;

function TextField(const FileName: String): String;
var Lines: TStringList;
begin
  if not FileExists(FileName) then
    raise Exception.Create('Відсутнє поле RAPL: ' + FileName);
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    if Lines.Count <> 1 then
      raise Exception.Create('Поле RAPL не є одним рядком');
    Result := Trim(Lines[0]);
    if (Result = '') or (Length(Result) > 128) or
       (Pos(#9, Result) <> 0) then
      raise Exception.Create('Некоректне ім’я/поле зони RAPL');
  finally
    Lines.Free;
  end;
end;

procedure AddZone(var Zones: TZones; const Dir, Key: String);
var Z: TZone; N: SizeInt;
begin
  if Length(Zones) >= 256 then
    raise Exception.Create('Перевищено межу зон RAPL');
  Z.Key := Key;
  Z.LabelText := TextField(Dir + '/name');
  Z.Energy := StrictNumber(TextField(Dir + '/energy_uj'));
  Z.MaxRange := StrictNumber(TextField(Dir + '/max_energy_range_uj'));
  if (Z.MaxRange = 0) or (Z.Energy >= Z.MaxRange) then
    raise Exception.Create('Лічильник RAPL поза фізичним діапазоном');
  N := Length(Zones);
  SetLength(Zones, N + 1);
  Zones[N] := Z;
end;

procedure Scan(const Dir, Relative: String; Depth: Integer; var Zones: TZones);
var R: TSearchRec; Full, Key: String; K: Integer; IsZone: Boolean;
begin
  if Depth > 5 then raise Exception.Create('Надмірна вкладеність зон RAPL');
  K := FindFirst(IncludeTrailingPathDelimiter(Dir) + '*', faAnyFile, R);
  if K <> 0 then Exit;
  try
    repeat
      if (R.Name <> '.') and (R.Name <> '..') then begin
        Full := IncludeTrailingPathDelimiter(Dir) + R.Name;
        if DirectoryExists(Full) then begin
          IsZone := Copy(R.Name, 1, 11) = 'intel-rapl:';
          if IsZone or (R.Name = 'intel-rapl') then begin
            if Relative = '' then Key := R.Name
            else Key := Relative + '/' + R.Name;
            if IsZone then AddZone(Zones, Full, Key);
            Scan(Full, Key, Depth + 1, Zones);
          end;
        end;
      end;
      K := FindNext(R);
    until K <> 0;
  finally
    FindClose(R);
  end;
end;

procedure SortAndCheck(var Zones: TZones);
var I, J: SizeInt; Item: TZone;
begin
  for I := 1 to High(Zones) do begin
    Item := Zones[I];
    J := I;
    while (J > 0) and (CompareStr(Zones[J - 1].Key, Item.Key) > 0) do begin
      Zones[J] := Zones[J - 1];
      Dec(J);
    end;
    Zones[J] := Item;
  end;
  for I := 1 to High(Zones) do
    if Zones[I].Key = Zones[I - 1].Key then
      raise Exception.Create('Дубль фізичного шляху RAPL');
end;

function ValidKey(const S: String): Boolean;
var I: SizeInt;
begin
  Result := (Length(S) > 11) and (Length(S) < 240) and
    (Pos('intel-rapl:', S) > 0) and (Pos('..', S) = 0);
  if not Result then Exit;
  for I := 1 to Length(S) do
    if not (S[I] in ['a'..'z', '0'..'9', '-', ':', '/']) then begin
      Result := False;
      Exit;
    end;
end;

procedure SplitFour(const Line: String; out A, B, C, D: String);
var Tmp: String; I, P: Integer;
begin
  Tmp := Line;
  for I := 1 to 3 do begin
    P := Pos(#9, Tmp);
    if P = 0 then raise Exception.Create('Пошкоджений TSV RAPL');
    case I of
      1: A := Copy(Tmp, 1, P - 1);
      2: B := Copy(Tmp, 1, P - 1);
      3: C := Copy(Tmp, 1, P - 1);
    end;
    Delete(Tmp, 1, P);
  end;
  if Pos(#9, Tmp) <> 0 then raise Exception.Create('Зайва колонка RAPL');
  D := Tmp;
end;

function ReadSnapshot(const FileName: String): TZones;
var Lines: TStringList; I: SizeInt; A, B, C, D: String; Z: TZone;
begin
  SetLength(Result, 0);
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(FileName);
    if (Lines.Count < 2) or (Lines.Count > 257) or
       (Lines[0] <> 'RAPL1') then
      raise Exception.Create('Неканонічний заголовок або кількість зон RAPL');
    for I := 1 to Lines.Count - 1 do begin
      SplitFour(Lines[I], A, B, C, D);
      if (not ValidKey(A)) or (B = '') or (Length(B) > 128) or
         (Pos(#9, B) > 0) then
        raise Exception.Create('Некоректний ключ або назва зони');
      Z.Key := A;
      Z.LabelText := B;
      Z.Energy := StrictNumber(C);
      Z.MaxRange := StrictNumber(D);
      if (Z.MaxRange = 0) or (Z.Energy >= Z.MaxRange) then
        raise Exception.Create('Лічильник поза діапазоном знімка');
      if (I > 1) and (CompareStr(Result[I - 2].Key, Z.Key) >= 0) then
        raise Exception.Create('Повторення або несортований TSV RAPL');
      SetLength(Result, I);
      Result[I - 1] := Z;
    end;
  finally
    Lines.Free;
  end;
end;

procedure Snapshot(const Root: String);
var Zones: TZones; I: SizeInt; Buffer: TStringList;
begin
  if not DirectoryExists(Root) then
    raise ENoEnergy.Create('Немає каталогу Linux powercap');
  SetLength(Zones, 0);
  Scan(Root, '', 0, Zones);
  if Length(Zones) = 0 then
    raise ENoEnergy.Create('Немає доступних зон intel-rapl');
  SortAndCheck(Zones);
  Buffer := TStringList.Create;
  try
    Buffer.Add('RAPL1');
    for I := 0 to High(Zones) do
      Buffer.Add(Zones[I].Key + #9 + Zones[I].LabelText + #9 +
        UIntToStr(Zones[I].Energy) + #9 + UIntToStr(Zones[I].MaxRange));
    Write(Buffer.Text);
  finally
    Buffer.Free;
  end;
end;

procedure Difference(const BeforePath, AfterPath, TimeText, PowerText: String);
var Before, After: TZones; I: SizeInt; Elapsed, MaxWatts, Delta: QWord;
    Buffer: TStringList;
begin
  Elapsed := StrictNumber(TimeText);
  MaxWatts := StrictNumber(PowerText);
  if (Elapsed = 0) or (MaxWatts = 0) or (MaxWatts > 10000) then
    raise Exception.Create('Недопустимий інтервал або фізична верхня межа Вт');
  Before := ReadSnapshot(BeforePath);
  After := ReadSnapshot(AfterPath);
  if Length(Before) <> Length(After) then
    raise Exception.Create('Змінилася кількість зон RAPL');
  Buffer := TStringList.Create;
  try
    Buffer.Add('RAPL-DELTA1' + #9 + 'elapsed_us=' + UIntToStr(Elapsed) +
      #9 + 'max_watts=' + UIntToStr(MaxWatts));
    for I := 0 to High(Before) do begin
      if (Before[I].Key <> After[I].Key) or
         (Before[I].LabelText <> After[I].LabelText) or
         (Before[I].MaxRange <> After[I].MaxRange) then
        raise Exception.Create('Змінено ідентичність або діапазон зони');
      { Інтервал < range/maxW виключає два оберти, навіть якщо
        фактичний лічильник збільшився на неповний діапазон. }
      if Elapsed > (Before[I].MaxRange - 1) div MaxWatts then
        raise Exception.Create('Неоднозначне багаторазове обертання RAPL');
      if After[I].Energy >= Before[I].Energy then
        Delta := After[I].Energy - Before[I].Energy
      else
        Delta := Before[I].MaxRange - Before[I].Energy + After[I].Energy;
      Buffer.Add(Before[I].Key + #9 + Before[I].LabelText + #9 +
        UIntToStr(Before[I].Energy) + #9 + UIntToStr(After[I].Energy) +
        #9 + UIntToStr(Before[I].MaxRange) + #9 + UIntToStr(Delta));
    end;
    Write(Buffer.Text);
  finally
    Buffer.Free;
  end;
end;

begin
  try
    if (ParamCount = 2) and (ParamStr(1) = '--знімок') then
      Snapshot(ParamStr(2))
    else if (ParamCount = 5) and (ParamStr(1) = '--різниця') then
      Difference(ParamStr(2), ParamStr(3), ParamStr(4), ParamStr(5))
    else
      raise Exception.Create('Використання: --знімок каталог | --різниця до.tsv після.tsv мкс верхня_межа_Вт');
  except
    on E: ENoEnergy do begin
      WriteLn(StdErr, 'ENERGY_NOT_MEASURED: ', E.Message);
      ExitCode := 2;
    end;
    on E: Exception do begin
      WriteLn(StdErr, 'RAPL-ВІДМОВА: ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
{ Перевір себе: (1) Чому QWord, не Double? (2) Чому зіставляємо шлях
  і max_range? (3) Чому не додаємо package та core? (4) Як upper bound
  виключає приховані оберти? (5) Чому stdout буферизований до кінця? }
