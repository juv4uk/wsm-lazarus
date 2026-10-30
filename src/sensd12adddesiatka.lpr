{ G6.x — CLI: програма «(додати 2 3)» → ELF64, який сам додає
  інструкцією add і друкує десятковий результат.
  Текстова форма — лише канонічна українська; жодного англійського
  синоніма й жодного прихованого семантичного dispatch.
  Питання: 1) Чому .lisp не є фізичним джерелом? 2) Хто гарантує
  не-перезапис ELF? 3) Де відділено host-діагностику від машинних
  байтів? 4) Чому десятковий stdout — це не SENS-проєкція? }
program sensd12adddesiatka;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.elfd12adddesiatka, wsm.elfpublish,
  wsm.elfgeometry;

function UA(const S: UnicodeString): RawByteString;
begin
  Result := RawByteString(UTF8Encode(S));
end;

{ Діагностика йде точними UTF-8 байтами в позичений handle,
  без системного перетворення AnsiString у WriteLn. }
procedure Say(const Text: RawByteString; ToError: Boolean);
var
  B: RawByteString;
  F: THandleStream;
begin
  B := Text + #10;
  if ToError then
    F := THandleStream.Create(TextRec(ErrOutput).Handle)
  else
    F := THandleStream.Create(TextRec(Output).Handle);
  try
    F.WriteBuffer(B[1], Length(B));
  finally
    F.Free;
  end;
end;

procedure Run;
var
  ProgramText, LeftDecimal, RightDecimal, Image: RawByteString;
  Geometry: TELFGeometry;
begin
  {$IFNDEF LINUX}
  raise EDesiatkaError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EDesiatkaError.Create('потрібен x86-64');
  {$ENDIF}
  if (ParamCount <> 3) or
     (RawByteString(ParamStr(1)) <> UA('--додати-десятково')) or
     (ExtractFileExt(ParamStr(3)) <> '.elf') then
    raise EDesiatkaError.Create(
      'виклик: sensd12adddesiatka --додати-десятково "(додати 2 3)" новий.elf');
  ProgramText := RawByteString(ParamStr(2));
  if not ParseAddProgram(ProgramText, LeftDecimal, RightDecimal) then
    raise EDesiatkaError.Create('форму не прийнято');
  Image := BuildD12AddDecimalELF(LeftDecimal, RightDecimal);
  { Верифікатор геометрії й атомарний no-clobber publisher уже існують. }
  PublishNewELF64(ParamStr(3), Image, 3, Geometry);
  Say(UA('ELF-D12-ДЕСЯТКОВО-ГОТОВО байтів=') + IntToStr(Geometry.FileBytes) +
    UA(' опкод-add=01d8 зсув-у-файлі=') +
    IntToStr(D12DesiatkaHeaderBytes + D12DesiatkaAddOpcodeAt) +
    UA(' stdout=десятковий'), False);
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      Say(UA('ELF-D12-ДЕСЯТКОВО-ВІДМОВА: ') + RawByteString(E.Message), True);
      ExitCode := 2;
    end;
  end;
end.
