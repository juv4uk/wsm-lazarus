{ G6.144 — ФІЗИЧНИЙ stdin T5M → вже перевірений D5 WideIR → ELF64 stdout.
  Не читач проєкцій D7, не другий compiler, не таблиця законів.
  Сталі розміри — квота host-потоку, а не семантика SENS.
  Жодних ELF-байтів у stdout ДО повного admission і перевірки образу. }
program sensarithchainpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irarithchain,wsm.elfgeometry;
const MaxStdinBytes=8192;
type EChainStreamError=class(Exception);

function Uk(const Value:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(Value)); end;

{ Вхід — фізичний stdin, позичений процесом. Source є локальною
  оболонкою fd; Buffer володіє байтами, Result — owned RawByteString.
  Read може повернути будь-яку позитивну довжину (включно з одним
  байтом), EOF визначає тільки host-транспорт, НЕ D2 межу.
  Питання: чому немає Seek/Size? Чому немає текстового D7-декодера?
  Чому 8193-й байт відхиляємо ДО виклику compiler? }
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
        if Count<0 then raise EChainStreamError.Create(
          Uk('помилка читання фізичного stdin'));
        if Count=0 then Break;
        if Buffer.Size>Int64(MaxStdinBytes)-Count then
          raise EChainStreamError.Create(
            Uk('перевищено квоту 8192 байтів фізичного T5M'));
        Buffer.WriteBuffer(Chunk,Count);
      until False;
      if Buffer.Size=0 then
        raise EChainStreamError.Create(Uk('порожній фізичний stdin'));
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

{ Physical — canonical фізична SENS програма; pinned compiler
  повторно перевіряє D2, усі точні D5 голови, числові D12 листки та
  проміжні результати, а також машинну геометрію.
  Sink відкривається ТІЛЬКИ після позитивного VerifySENSELF64;
  host збій уже відкритого pipe не є транзакційною публікацією.
  Питання: де саме відсікається D24 promotion? Чому stdout бінарний?
  Який компонент, а не цей CLI, знає мовні закони? }
procedure CompileStdin;
var Physical,Image:RawByteString;G:TELFGeometry;Sink:THandleStream;
begin
  Physical:=ReadPhysicalStdin;
  Image:=BuildIRArithChainELF(Physical,'external/sens');
  VerifySENSELF64(Image,G);
  if (Length(Image)<=120) or (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Image)) then
    raise EChainStreamError.Create(
      Uk('відхилено геометрію перевіреного ELF64 PIE'));
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
     (RawByteString(ParamStr(1))<>Uk('--ланцюг-потік-D5')) then begin
    WriteLn(StdErr,Uk(
      'Виклик: sensarithchainpotik --ланцюг-потік-D5 < програма.sens > програма.elf'));
    ExitCode:=64;
  end else begin
    try
      {$IFNDEF LINUX}
      raise EChainStreamError.Create(Uk('потрібен Linux'));
      {$ENDIF}
      {$IFNDEF CPUX86_64}
      raise EChainStreamError.Create(Uk('потрібен x86-64'));
      {$ENDIF}
      CompileStdin;
    except
      on E:Exception do begin
        WriteLn(StdErr,Uk('ЛАНЦЮГ-ПОТІК-ВІДМОВА: '),E.Message);
        ExitCode:=2;
      end;
    end;
  end;
end.
