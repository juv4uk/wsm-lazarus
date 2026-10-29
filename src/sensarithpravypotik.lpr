{ G6.146: canonical packed T5M stdin -> ТОЙ САМИЙ pinned right D5
  WideIR compiler -> ELF64 PIE binary stdout. Не нова семантика SENS.
  На stdout не потрапляють ані human D7 текст, ані часткові ELF.
  Хостовий потік — фрейм від початку до EOF, не мовна форма D2. }
program sensarithpravypotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irarithpravy,wsm.elfgeometry;
const MaxPhysicalBytes=8192;
type EPravyStreamError=class(Exception);

function Uk(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Source: borrowed stdin FD, THandleStream privately owns ONLY wrapper;
  Memory: owned TMemoryStream, owned Result canonical raw bytes.
  Системний Read може повернути менше буфера — жодного Seek,
  відсутність останнього `22` не виводить семантику.
  1) Чому EOF є границею host stdin, а не D2 вузлом?
  2) Чому 8193-й байт відхиляється ще до виклику compiler?
  3) Чому тут ніколи не викликаємо проєкційний D7 reader?
  4) Як FPC звільняє managed RawByteString після exception?
  5) Де перевіряється точна доменна координата D5? }
function ReadPhysicalStdin:RawByteString;
var Source:THandleStream;Buffer:TMemoryStream;
    Chunk:array[0..1023] of Byte;Count:LongInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Buffer:=TMemoryStream.Create;
    try
      repeat
        Count:=Source.Read(Chunk,SizeOf(Chunk));
        if Count<0 then
          raise EPravyStreamError.Create(Uk('помилка читання фізичного stdin'));
        if Count=0 then Break;
        if Buffer.Size>Int64(MaxPhysicalBytes)-Count then
          raise EPravyStreamError.Create(
            Uk('фізичний T5M перевищив квоту 8192 байтів'));
        Buffer.WriteBuffer(Chunk,Count);
      until False;
      if Buffer.Size=0 then
        raise EPravyStreamError.Create(Uk('порожній фізичний stdin'));
      SetLength(Result,SizeInt(Buffer.Size));
      Buffer.Position:=0;
      Buffer.ReadBuffer(Result[1],Length(Result));
    finally Buffer.Free end;
  finally Source.Free end;
end;

{ Physical — owned canonical stdin bytes (not .lisp).
  BuildIRArithPravyELF повторно перевіряє весь packed T5M,
  pinned W5 D5 голови та W12 числа й кожний результат D12.
  Image — owned machine ELF64, G — readonly validated geometry.
  Sink відкриваємо тільки після повної компіляції та перевірки.
  У випадку відмови до Sink НЕ пишемо жодного байта.
  Помилка вже відкритого pipe НЕ є транзакційним записом: stdout
  не обіцяє atomicity після host write failure.
  1) Чому VerifySENSELF64 тут повторюємо після backend?
  2) Чому число D24 не можна обрізати до D12?
  3) Чому D7 проєкція не є джерелом машинної істини?
  4) Чому заголовок ELF не є новою мовною семантикою?
  5) Де закінчується час життя owned Image? }
procedure CompilePhysicalStdin;
var Physical,Image:RawByteString;G:TELFGeometry;Sink:THandleStream;
begin
  Physical:=ReadPhysicalStdin;
  Image:=BuildIRArithPravyELF(Physical,'external/sens');
  VerifySENSELF64(Image,G);
  if (Length(Image)<=120) or (G.Kind<>3) or
     (G.Entry<>120) or (G.FileBytes<>Length(Image)) then
    raise EPravyStreamError.Create(Uk('ELF64 PIE не пройшов host геометрію'));
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try
    Sink.WriteBuffer(Image[1],Length(Image));
  finally Sink.Free end;
end;

begin
  ExitCode:=0;
  if (ParamCount<>1) or
    (RawByteString(ParamStr(1))<>Uk('--правий-потік-D5')) then begin
    WriteLn(StdErr,Uk(
      'Виклик: sensarithpravypotik --правий-потік-D5 < вхід.sens > новий.elf'));
    ExitCode:=64;
  end else begin
    try
      {$IFNDEF LINUX}
      raise EPravyStreamError.Create(Uk('потрібен Linux'));
      {$ENDIF}
      {$IFNDEF CPUX86_64}
      raise EPravyStreamError.Create(Uk('потрібен x86-64'));
      {$ENDIF}
      CompilePhysicalStdin;
    except on E:Exception do begin
      WriteLn(StdErr,Uk('ПРАВИЙ-ПОТІК-ВІДМОВА: '),E.Message);
      ExitCode:=2;
    end end;
  end;
end.
