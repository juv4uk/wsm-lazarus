{ G6.63 — механічний паспорт уже створеного native ELF64-x86-64.
  Вхід тільки .elf; жодної семантики SENS чи декодування D7/D12+.
  Геометрія та точка входу — лише через чинний VerifySENSELF64.
  Для енергетичних вимірювань ці поля є provenance, НЕ джоулями. }
program senselfpasport;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.elfgeometry;

const MaxImageBytes = 1024 * 1024;

type EELFPassportError = class(Exception);

function ReadBoundedELF(const Path: String): RawByteString;
var Stream: TFileStream;
begin
  Result := '';
  if (Path='') or (Length(Path)>4096) or
     (ExtractFileExt(Path)<>'.elf') then
    raise EELFPassportError.Create('потрібен файл .elf, а не .sens/.lisp');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>MaxImageBytes) then
      raise EELFPassportError.Create('ELF файл поза межею 1..1048576 байтів');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

procedure Run;
var Image: RawByteString; Geometry: TELFGeometry;
begin
  if (ParamCount<>2) or (ParamStr(1)<>'--геометрія') then
    raise EELFPassportError.Create(
      'Виклик: senselfpasport --геометрія файл.elf');
  Image:=ReadBoundedELF(ParamStr(2));
  VerifySENSELF64(Image,Geometry);
  { Єдина публікація після ВСІХ фізичних і структурних перевірок.
    Тип 2/3 є host ELF ABI, а не домен D2/D3 мови SENS. }
  WriteLn('ЕЛЬФ-ПАСПОРТ-ГАРАЗД тип=',Geometry.Kind,
    ' байтів=',Geometry.FileBytes,
    ' код-байтів=',Geometry.MachineBytes,
    ' точка-входу=',Geometry.Entry);
end;

begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'ЕЛЬФ-ПАСПОРТ-ПОМИЛКА: ',E.Message);
    ExitCode:=2;
  end end;
end.
