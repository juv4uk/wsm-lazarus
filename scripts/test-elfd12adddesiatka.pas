{ G6.x — свідки текстової форми для десяткового D12-додавача.
  Генератор НЕ є семантичним oracle: він лише пише канонічні текстові
  форми «(додати ...)» й очікуваний stdout і перевіряє, що розбирач
  приймає рівно канонічний запис і відмовляє все інше.
  Питання: 1) Чому очікуваний stdout — не число з Pascal-арифметики?
  2) Чому англійська голова — відмова, а не синонім?
  3) Хто перевіряє самі машинні байти? }
program test_elfd12adddesiatka;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.elfd12adddesiatka;
var
  Dir: String;
  Positives, Negatives, BuildRejects: SizeInt;

function UA(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

{ Підсумок свідків друкуємо точними UTF-8 байтами в позичений
  stdout, а не через системну кодову сторінку: інакше в не-UTF-8
  локалі рядок у лог прогону приходить із «?» замість кирилиці. }
procedure Say(const Text: RawByteString);
var
  B: RawByteString;
  F: THandleStream;
begin
  B := Text + #10;
  F := THandleStream.Create(TextRec(Output).Handle);
  try
    F.WriteBuffer(B[1], Length(B));
  finally
    F.Free;
  end;
end;

procedure Save(const Name: String; const Bytes: RawByteString);
var
  F: TFileStream;
begin
  F := TFileStream.Create(Dir + '/' + Name, fmCreate);
  try
    if Length(Bytes) > 0 then F.WriteBuffer(Bytes[1], Length(Bytes));
  finally
    F.Free;
  end;
end;

{ Позитивний випадок: форма мусить розібратися у два десяткові тексти. }
procedure Positive(const Name, ProgramText, WantedLeft, WantedRight,
  WantedStdout: RawByteString);
var
  Left, Right: RawByteString;
begin
  Save(String(Name) + '.prohrama', ProgramText);
  Save(String(Name) + '.stdout', WantedStdout);
  if not ParseAddProgram(ProgramText, Left, Right) then
    raise EDesiatkaError.Create('канонічну форму не прийнято: ' + String(Name));
  if (Left <> WantedLeft) or (Right <> WantedRight) then
    raise EDesiatkaError.Create('доданки розібрано невірно: ' + String(Name));
  Inc(Positives);
end;

{ Негативний випадок: розбирач мусить відмовити ще до ELF. }
procedure Negative(const Name, ProgramText: RawByteString);
var
  Left, Right: RawByteString;
  Refused: Boolean;
begin
  Save(String(Name) + '.prohrama', ProgramText);
  Refused := False;
  try
    ParseAddProgram(ProgramText, Left, Right);
  except
    on E: EDesiatkaError do Refused := True;
  end;
  if not Refused then
    raise EDesiatkaError.Create('хибну форму прийнято: ' + String(Name));
  Inc(Negatives);
end;

{ Форма канонічна, але сума виходить за D12: відмова на рівні збірки. }
procedure BuildReject(const Name, ProgramText: RawByteString);
var
  Left, Right: RawByteString;
begin
  Save(String(Name) + '.prohrama', ProgramText);
  if not ParseAddProgram(ProgramText, Left, Right) then
    raise EDesiatkaError.Create('форма мусить розібратися: ' + String(Name));
  Inc(BuildRejects);
end;

begin
  if ParamCount <> 1 then Halt(64);
  Dir := ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  Positives := 0; Negatives := 0; BuildRejects := 0;

  { Вимога задачі: (додати 2 3) → stdout «5». }
  Positive('01', UA('(додати 2 3)'), '2', '3', '5'#10);
  Positive('02', UA('(додати 0 0)'), '0', '0', '0'#10);
  Positive('03', UA('(додати -7 2)'), '-7', '2', '-5'#10);
  Positive('04', UA('(додати 2047 0)'), '2047', '0', '2047'#10);
  Positive('05', UA('(додати -2048 0)'), '-2048', '0', '-2048'#10);
  Positive('06', UA('(додати -2048 2047)'), '-2048', '2047', '-1'#10);

  Negative('n01', UA('(додати 2)'));
  Negative('n02', UA('(додати 2 3 4)'));
  Negative('n03', UA('(add 2 3)'));
  Negative('n04', UA('(додати 2.5 3)'));
  Negative('n05', UA('(додати 2 3'));
  Negative('n06', UA('додати 2 3'));
  Negative('n07', UA('(додати 4096 0)'));
  Negative('n08', '');
  Negative('n09', UA('(додати 2 3) зайве'));

  BuildReject('o01', UA('(додати 2047 1)'));
  BuildReject('o02', UA('(додати -2048 -1)'));

  Say(UA('ELF-D12-ДЕСЯТКОВО-СВІДКИ-ПЕРЕВІРЕНО позитивних=') +
    RawByteString(IntToStr(Positives)) + UA(' розбір-відмов=') +
    RawByteString(IntToStr(Negatives)) + UA(' збірка-відмов=') +
    RawByteString(IntToStr(BuildRejects)) + UA(' опкод-add-зсув=') +
    RawByteString(IntToStr(D12DesiatkaAddOpcodeAt)));
end.
