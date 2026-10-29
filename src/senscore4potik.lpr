{ G4.48 — разове реальне виконання фізичних pinned Core4 D2-коренів
  через звичайний raw stdin/stdout. Ні другий reader, ні SENS law.
  На відміну від фреймованого каналу тут EOF закінчує ОДНУ програму. }
program senscore4potik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core4runtime, wsm.core4multiroot;

function Uk(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

{ Вхідні фізичні packed T5M байти належать локальному TMemoryStream.
  Input — запозичений stdin fd; Source/Buffer живуть до return/exception.
  Немає розбору по рядках, UTF-8 чи перекодування двійкової програми.
  Потік обмежено MAX_T5M_FILE_BYTES ДО виділення наступної порції.
  Result — власний managed RawByteString з тими самими байтами.
  Питання: Чому не можна покладатися на Size/Seek звичайного pipe?
  Чому квота перевіряється до WriteBuffer?
  Чому D7 тут не перетворюється на текст?
  Чому EOF не є SENS словом? }
function ReadPhysicalStdin:RawByteString;
var
  Source:THandleStream;
  Buffer:TMemoryStream;
  Chunk:array[0..8191] of Byte;
  Count:LongInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Buffer:=TMemoryStream.Create;
    try
      repeat
        Count:=Source.Read(Chunk,SizeOf(Chunk));
        if Count<0 then
          raise Exception.Create(Uk('помилка фізичного читання stdin'));
        if Count=0 then Break;
        if Buffer.Size>Int64(MAX_T5M_FILE_BYTES)-Count then
          raise Exception.Create(Uk('фізичний потік перевищив обмеження T5M'));
        Buffer.WriteBuffer(Chunk,Count);
      until False;
      if Buffer.Size<1 then
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

{ Відповідь від уже злитого Core4 runtime — packed T5M, НЕ .lisp.
  До повного canonical admission та завершення усіх форм stdout
  взагалі не відкривається. Sink лише позичає stdout fd, не володіє ним.
  На помилках ДО публікації вихід завжди порожній; OS-помилка запису
  в уже розпочатий pipe не може бути транзакцією без host-протоколу.
  Питання: Чому структурний D2 reader не є evaluator?
  Чому D24 opaque навіть за 24 бітами?
  Хто володіє Runtime та Words?
  Чому додавання WriteLn порушить фізичну відповідь? }
procedure ExecutePhysical;
var
  Runtime:TCore4Runtime;
  Sink:THandleStream;
  Physical,Reply:RawByteString;
  Words:TExactWords;
begin
  Physical:=ReadPhysicalStdin;
  Runtime:=TCore4Runtime.Create(ParamStr(2));
  try
    Reply:=ExecuteCore4Roots(Runtime,Physical);
  finally
    Runtime.Free;
  end;
  DecodeT5M(Reply,Words);
  if (Length(Words)<1) or (EncodeT5M(Words)<>Reply) then
    raise Exception.Create(Uk('Core4 повернув неканонічний T5M'));
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try
    Sink.WriteBuffer(Reply[1],Length(Reply));
  finally
    Sink.Free;
  end;
end;

begin
  ExitCode:=0;
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>Uk('--виконати-потік')) or
     (ParamStr(2)='') then
  begin
    WriteLn(StdErr,Uk('Використання: senscore4potik --виконати-потік КОРІНЬ'));
    ExitCode:=64;
  end
  else
    try
      ExecutePhysical;
    except
      on E:Exception do begin
        WriteLn(StdErr,Uk('CORE4-ПОТІК-ПОМИЛКА: '),E.Message);
        ExitCode:=2;
      end;
    end;
end.
