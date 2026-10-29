{ G6.63 — механічний паспорт уже створеного native ELF64-x86-64.
  Вхід тільки .elf; жодної семантики SENS чи декодування D7/D12+.
  Геометрія та точка входу — лише через чинний VerifySENSELF64.
  Для енергетичних вимірювань ці поля є provenance, НЕ джоулями. }
program senselfpasport;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.elfgeometry;

const MaxImageBytes = 1024 * 1024;
  { Лише host CLI UTF-8, не SENS D7 та не проєкція слів програми. }
  KGeometry=#$2D#$2D#$D0#$B3#$D0#$B5#$D0#$BE#$D0#$BC#$D0#$B5+
    #$D1#$82#$D1#$80#$D1#$96#$D1#$8F;

type EELFPassportError = class(Exception);

procedure WriteUTF8Line(const MessageText: UnicodeString; IsError: Boolean);
var Encoded:UTF8String; Stream:THandleStream; LF:AnsiChar;
begin
  Encoded:=UTF8Encode(MessageText);
  if IsError then Stream:=THandleStream.Create(TextRec(StdErr).Handle)
  else Stream:=THandleStream.Create(TextRec(Output).Handle);
  LF:=#10;
  try
    if Length(Encoded)>0 then
      Stream.WriteBuffer(Encoded[1],Length(Encoded));
    Stream.WriteBuffer(LF,1);
  finally Stream.Free end;
end;

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
  if (ParamCount<>2) or (RawByteString(ParamStr(1))<>KGeometry) then
    raise EELFPassportError.Create(
      'Виклик: senselfpasport --геометрія файл.elf');
  Image:=ReadBoundedELF(ParamStr(2));
  VerifySENSELF64(Image,Geometry);
  { Єдина публікація після ВСІХ фізичних і структурних перевірок.
    Тип 2/3 є host ELF ABI, а не домен D2/D3 мови SENS. }
  WriteUTF8Line('ЕЛЬФ-ПАСПОРТ-ГАРАЗД тип='+
    UnicodeString(IntToStr(Geometry.Kind))+
    ' байтів='+UnicodeString(IntToStr(Geometry.FileBytes))+
    ' код-байтів='+UnicodeString(IntToStr(Geometry.MachineBytes))+
    ' точка-входу='+UnicodeString(UIntToStr(Geometry.Entry)),False);
end;

begin
  try Run
  except on E:Exception do begin
    WriteUTF8Line('ЕЛЬФ-ПАСПОРТ-ПОМИЛКА: '+UTF8Decode(E.Message),True);
    ExitCode:=2;
  end end;
end.
