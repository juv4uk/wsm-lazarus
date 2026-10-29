{ G3.19 — одноразовий фізичний stdin/stdout канал D3.
  ЖОДНОГО Lisp/Unicode парсингу у потоці: приймаємо й повертаємо
  лише незмінні паковані T5M байти, pinned закони виконує wsm.d3batch.
  Це не постійний REPL і не Core4. }
program senspotikd3;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d3batch;

function Ukr(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure Run;
var
  Source, Sink:THandleStream;
  Chunk:array[0..4095] of Byte;
  Physical, Answer:RawByteString;
  Words:TExactWords;
  Got, Used, Count:SizeInt;
begin
  if (ParamCount<>2) or (RawByteString(ParamStr(1))<>Ukr('--потік'))
    or (ParamStr(2)='') then begin
    WriteLn(StdErr,Ukr('ПОМИЛКА-ПОТІК-D3: використання senspotikd3 --потік корінь-sens; stdin/stdout=тільки-фізичний-T5M'));
    ExitCode:=64;
    Exit;
  end;

  { Фізичний stdin читається ДО виконання. EOF не означає кінець
    окремої форми: тільки D2-обрамлення задає корені пакета. }
  Source:=nil; Sink:=nil; Used:=0; Physical:=''; Answer:='';
  try
    Source:=THandleStream.Create(TextRec(Input).Handle);
    repeat
      Got:=Source.Read(Chunk,SizeOf(Chunk));
      if Got=0 then Break;
      if (Got<0) or (Got>MAX_T5M_FILE_BYTES-Used) then
        raise Exception.Create('вхідний фізичний потік більший за межу T5M');
      SetLength(Physical,Used+Got);
      Move(Chunk[0],Physical[Used+1],Got);
      Inc(Used,Got);
    until False;
    FreeAndNil(Source);

    { Успіх усіх форм — єдина умова публікації stdout.
      Вихідні байти будуються лише на наявному pinned D3 evaluator. }
    ExecutePhysicalD3Batch(Physical,RawByteString(ParamStr(2)),Answer,Count);
    if (Count<1) or (Count>64) or (Length(Answer)<1) or
       (Length(Answer)>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('некоректний результат обмеженого D3 пакета');
    DecodeT5M(Answer,Words);
    if (Length(Words)=0) or (EncodeT5M(Words)<>Answer) then
      raise Exception.Create('відповідь не є канонічним фізичним T5M');

    { Не друкувати лог у stdout. Heaptrc (-gh) у цьому executable
      також ЗАБОРОНЕНИЙ: він домішав би свій текст до двійкових байтів.
      Якщо ОС зірве сам WriteBuffer, частковий OS pipe не відкочується. }
    Sink:=THandleStream.Create(TextRec(Output).Handle);
    Sink.WriteBuffer(Answer[1],Length(Answer));
  except
    on E:ED3BatchError do begin
      WriteLn(StdErr,Ukr('ПОМИЛКА-ПОТІК-D3 форма='),E.FormIndex,
        Ukr(' слово='),E.WordIndex,': ',E.Message);
      ExitCode:=2;
    end;
    on E:Exception do begin
      WriteLn(StdErr,Ukr('ПОМИЛКА-ПОТІК-D3: '),E.Message);
      ExitCode:=2;
    end;
  end;
  Sink.Free;
  Source.Free;
end;

begin
  Run;
end.
