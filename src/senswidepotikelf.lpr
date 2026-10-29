{ G6.151 — фізичний stdin → ТОЙ САМИЙ pinned WideIR → ELF64 stdout.
  Це host-потік байтів T5M, не новий reader, evaluator чи закон SENS.
  Доступний лише перевірений профіль BuildVerifiedWideELF.
  Усі повідомлення людини — українською; stdout містить лише ELF. }
program senswidepotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidefront,wsm.elfgeometry;
const MaxPhysicalBytes=65536;
type EWidePipeError=class(Exception);

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Borrowed host stdin FD, owned Source wrapper and Buffer.
  Result — owned packed T5M bytes з точними ширинами; EOF host визначає
  межу однієї програми, але не замінює D2 рамку. Ні текстового
  читання проєкції «укр», ні неявного перетворення .lisp.
  1) Чому читання частинами не може змінювати T5M-домени?
  2) Чому 65537-й байт відкидається до компіляції?
  3) Чому host EOF не вважаємо SENS-операцією?
  4) Хто звільняє Buffer і Source при винятку? }
function ReadPhysical:RawByteString;
var Source:THandleStream;Buffer:TMemoryStream;
    Chunk:array[0..1023] of Byte;N:LongInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Buffer:=TMemoryStream.Create;
    try
      repeat
        N:=Source.Read(Chunk,SizeOf(Chunk));
        if N<0 then
          raise EWidePipeError.Create(Ukr('не вдалося прочитати stdin'));
        if N=0 then Break;
        if Buffer.Size>Int64(MaxPhysicalBytes)-N then
          raise EWidePipeError.Create(Ukr('фізичний T5M перевищив 65536 байтів'));
        Buffer.WriteBuffer(Chunk,N);
      until False;
      if Buffer.Size=0 then
        raise EWidePipeError.Create(Ukr('порожній фізичний потік'));
      SetLength(Result,SizeInt(Buffer.Size));
      Buffer.Position:=0;
      Buffer.ReadBuffer(Result[1],Length(Result));
    finally Buffer.Free end;
  finally Source.Free end;
end;

{ Text is owned UTF-8 status. Stream wraps borrowed stderr descriptor;
  never mix host diagnostics with machine ELF stdout.
  1) Чому відмову не можна надрукувати в ELF stdout?
  2) Чи змінює український текст ратифіковані координати? }
procedure FailMessage(const Text:RawByteString);
var Err:THandleStream;S:RawByteString;
begin
  S:=Ukr('ШИРОКИЙ-ПОТІК-ВІДМОВА: ')+Text+#10;
  Err:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try Err.WriteBuffer(S[1],Length(S));
  finally Err.Free end;
end;

{ Physical та Image — owned RawByteString, verified Geometry — stack.
  Лише ПІСЛЯ повного pinned T5M/D2/WideIR і ELF64 PIE admission
  відкриваємо borrowed stdout FD; failure під час запису OS pipe
  може лишити префікс ELF — транзакційність після write НЕ обіцяємо.
  1) Де перевіряються exact pinned координати D5/D6?
  2) Чому SIR1 не підміняє перевірений ELF?
  3) Чому перевірка geometry не є доказом семантики?
  4) Чим відрізняється host write error від compiler reject?
  5) Кому належить пам'ять Image після повернення? }
procedure Compile;
var Physical,Image:RawByteString;G:TELFGeometry;Sink:THandleStream;
begin
  Physical:=ReadPhysical;
  Image:=BuildVerifiedWideELF(Physical,'external/sens');
  VerifySENSELF64(Image,G);
  if (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Image)) or (Length(Image)<=120) then
    raise EWidePipeError.Create(Ukr('ELF64 PIE не пройшов остаточний допуск'));
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Image[1],Length(Image));
  finally Sink.Free end;
end;

begin
  ExitCode:=0;
  if (ParamCount<>1) or
     (RawByteString(ParamStr(1))<>Ukr('--скомпілювати-фізичний-потік')) then
  begin
    FailMessage(Ukr('виклик: senswidepotikelf --скомпілювати-фізичний-потік < вхід.sens > результат.elf'));
    ExitCode:=64;
  end
  else
    try
      {$IFNDEF LINUX}
      raise EWidePipeError.Create(Ukr('потрібен Linux'));
      {$ENDIF}
      {$IFNDEF CPUX86_64}
      raise EWidePipeError.Create(Ukr('потрібен x86-64'));
      {$ENDIF}
      Compile;
    except on E:Exception do begin
      FailMessage(Ukr(UnicodeString(E.Message)));
      ExitCode:=2;
    end end;
end.
