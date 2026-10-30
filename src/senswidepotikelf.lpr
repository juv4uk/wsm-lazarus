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

{ Borrowed host stdin FD, owned Source wrapper та один RawByteString.
  Буфер росте 1024→2048→...→65536 без окремого TMemoryStream і
  повторного повного копіювання фізичного потоку; UTF-8 проєкцій немає.
  Result — owned packed T5M байти фактичної довжини; EOF host відмежовує
  одну програму, але не замінює D2 рамку чи pinned перевірку.
  1) Чому читання частинами не змінює T5M-домени?
  2) Чому переповнення перевіряємо ДО SetLength та Move?
  3) Чому host EOF не вважаємо SENS-операцією?
  4) Хто володіє Result після успіху, а Source після винятку?
  5) Чому Reserved не є шириною домену чи довжиною канонічного .sens? }
function ReadPhysical:RawByteString;
var Source:THandleStream;
    Chunk:array[0..1023] of Byte;N:LongInt;
    Used,Reserved,Next:SizeInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Used:=0;
    Reserved:=0;
    repeat
      N:=Source.Read(Chunk,SizeOf(Chunk));
      if N<0 then
        raise EWidePipeError.Create(Ukr('не вдалося прочитати stdin'));
      if N=0 then Break;
      { Невідомий або надмірний host-ввід відхиляємо ДО виділення:
        MaxPhysicalBytes — межа транспорту, не домен SENS. }
      if Used>MaxPhysicalBytes-N then
        raise EWidePipeError.Create(Ukr('фізичний T5M перевищив 65536 байтів'));
      Next:=Used+N;
      if Next>Reserved then begin
        if Reserved=0 then Reserved:=SizeOf(Chunk);
        while Reserved<Next do begin
          if Reserved<=MaxPhysicalBytes div 2 then
            Reserved:=Reserved*2
          else
            Reserved:=MaxPhysicalBytes;
        end;
        SetLength(Result,Reserved);
      end;
      Move(Chunk[0],Result[Used+1],N);
      Used:=Next;
    until False;
    if Used=0 then
      raise EWidePipeError.Create(Ukr('порожній фізичний потік'));
    { Точно фактична кількість packed T5M байтів, без нульового хвоста. }
    SetLength(Result,Used);
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

{ Root — позичений абсолютний host-шлях pinned SENS, НЕ D7 і не
  текстова проєкція. За старого 1-аргументного CLI корінь залежить від
  cwd; 3-аргументний режим призначено для IDE та інших викликачів.
  Перевірка actual pin/contract виконується check-pin.sh та чинним
  pinned loader, а не тут через людський текст.
  1) Чому шлях не визначає семантичний закон SENS?
  2) Чому відносний корінь заборонено в явному режимі?
  3) Чому перевірка відбувається раніше за фізичний stdin?
  4) Хто володіє повернутим RawByteString? }
function AuthorityRoot:RawByteString;
var P:String;
begin
  if ParamCount=1 then Exit('external/sens');
  if (ParamCount<>3) or
     (RawByteString(ParamStr(2))<>Ukr('--корінь-sens')) then
    raise EWidePipeError.Create(Ukr('потрібен явний --корінь-sens'));
  P:=ParamStr(3);
  if (P='') or (Length(P)>4096) or (P[1]<>'/') then
    raise EWidePipeError.Create(Ukr('корінь SENS має бути абсолютним шляхом'));
  P:=ExcludeTrailingPathDelimiter(ExpandFileName(P));
  if (not DirectoryExists(P)) or
     (not FileExists(P+'/contracts/language-contract-12.lisp')) then
    raise EWidePipeError.Create(Ukr('немає фізичного каталогу контракту SENS 12.0'));
  Result:=RawByteString(P);
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
procedure Compile(const Root:RawByteString);
var Physical,Image:RawByteString;G:TELFGeometry;Sink:THandleStream;
begin
  Physical:=ReadPhysical;
  Image:=BuildVerifiedWideELF(Physical,Root);
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
  if ((ParamCount<>1) and (ParamCount<>3)) or
     (RawByteString(ParamStr(1))<>Ukr('--скомпілювати-фізичний-потік')) then
  begin
    FailMessage(Ukr('виклик: senswidepotikelf --скомпілювати-фізичний-потік [--корінь-sens /absolute/external/sens] < вхід.sens > результат.elf'));
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
      Compile(AuthorityRoot);
    except on E:Exception do begin
      FailMessage(Ukr(UnicodeString(E.Message)));
      ExitCode:=2;
    end end;
end.
