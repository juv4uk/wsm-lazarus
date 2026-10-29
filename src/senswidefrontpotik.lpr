{ G6 — окремий потоковий host-вхід уже перевіреного WideIR компілятора.
  Справжні canonical .sens/T5M байти: stdin -> pinned WideIR -> ELF64 stdout.
  Це НЕ SENS reader за текстом, НЕ новий emitter і НЕ новий закон.
  Вихід відкривається тільки після повного EOF, admission і ELF перевірки. }
program senswidefrontpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidefront,wsm.elfgeometry;

function Uk(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

{ Source лише позичає stdin fd; Buffer володіє накопиченими T5M байтами
  до звільнення у finally. Result — власний managed RawByteString.
  Читаємо порціями, перевіряючи межу 65536 ДО запису в Buffer;
  не перетворюємо T5M у рядкові, D7 або числові host-токени.
  1) Чому Read не припускає, що pipe підтримує Seek/Size?
  2) Чому EOF — лише межа host-потоку, а не бінарний закон SENS?
  3) Хто володіє TMemoryStream і результатом?
  4) Чому 65537-й байт повинен викликати відмову до компіляції? }
function ReadPhysicalStdin:RawByteString;
var Source:THandleStream;Buffer:TMemoryStream;
    Chunk:array[0..4095] of Byte;Count:LongInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Buffer:=TMemoryStream.Create;
    try
      repeat
        Count:=Source.Read(Chunk,SizeOf(Chunk));
        if Count<0 then raise Exception.Create(Uk('не вдалося прочитати stdin'));
        if Count=0 then Break;
        if Buffer.Size>Int64(65536)-Count then
          raise Exception.Create(Uk('перевищено 65536 байтів фізичної програми'));
        Buffer.WriteBuffer(Chunk,Count);
      until False;
      if Buffer.Size=0 then
        raise Exception.Create(Uk('порожній фізичний stdin'));
      SetLength(Result,SizeInt(Buffer.Size));
      Buffer.Position:=0;
      Buffer.ReadBuffer(Result[1],Length(Result));
    finally
      Buffer.Free;
    end;
  finally
    Source.Free;
  end;
end;

{ Physical — власні packed T5M байти; Image — власні ELF64 байти,
  які повернув чинний BuildVerifiedWideELF за pinned external/sens.
  G — локальна структура геометрії, НЕ SENS семантика.
  Sink позичає stdout fd і не закриває власність викликача;
  до завершення перевірки в stdout не пишемо ані байта.
  Після початку запису помилка зламаного OS-pipe не є транзакцією.
  1) Чому всі закони й допуск залишаються у pinned compiler?
  2) Чому ELF не є .sens, хоч обидва формати двійкові?
  3) Чому вихід не друкує текстового статусу?
  4) Чому незалежна перевірка ELF геометрії не є SENS oracle?
  5) Хто володіє Image і коли його пам'ять звільняється? }
procedure CompilePhysical;
var Physical,Image:RawByteString;G:TELFGeometry;Sink:THandleStream;
begin
  Physical:=ReadPhysicalStdin;
  Image:=BuildVerifiedWideELF(Physical,'external/sens');
  VerifySENSELF64(Image,G);
  if (Length(Image)<=120) or (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Image)) then
    raise Exception.Create(Uk('невірна геометрія ELF64 PIE'));
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try
    Sink.WriteBuffer(Image[1],Length(Image));
  finally
    Sink.Free;
  end;
end;

begin
  ExitCode:=0;
  if (ParamCount<>1) or
     (RawByteString(ParamStr(1))<>Uk('--скомпілювати-потік')) then begin
    WriteLn(StdErr,Uk('Використання: senswidefrontpotik --скомпілювати-потік < програма.sens > програма.elf'));
    ExitCode:=64;
  end else begin
    try
      {$IFNDEF LINUX}
      raise Exception.Create(Uk('потрібен Linux'));
      {$ENDIF}
      {$IFNDEF CPUX86_64}
      raise Exception.Create(Uk('потрібен x86-64'));
      {$ENDIF}
      CompilePhysical;
    except
      on E:Exception do begin
        WriteLn(StdErr,Uk('WIDEIR-ПОТІК-ВІДМОВА: '),E.Message);
        ExitCode:=2;
      end;
    end;
  end;
end.
