{ G5.66 — канонічний фізичний пакет 1..64 Core1-викликів.
  Одне живе замикання — TCore1FirstRuntime із pinned core1.sens.
  D2/T5M є транспортом, а не ще одним evaluator чи семантикою. }
program senscore1paket;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.core1first;

const
  MaxPacketRoots = 64;

function Uk(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Фізичні bytes stdin за EOF (не Text/UTF8); запозичений fd переживає
  обидва короткоживучі TStream. Розмір перевіряємо ДО WriteBuffer.
  Result — owned managed packed bytes; ніяких проміжних .lisp.
  Питання: чому Size/Seek не працює для pipe?
  Чому quota перевіряється перед записом у MemoryStream?
  Чому D7 тут лишається двійковим?
  Що відбувається з Buffer на exception? }
function ReadPhysicalStdin:RawByteString;
var Source:THandleStream; Buffer:TMemoryStream;
    Chunk:array[0..8191] of Byte; Got:LongInt;
begin
  Result:='';
  Source:=THandleStream.Create(TextRec(Input).Handle);
  try
    Buffer:=TMemoryStream.Create;
    try
      repeat
        Got:=Source.Read(Chunk,SizeOf(Chunk));
        if Got<0 then raise Exception.Create(Uk('фізичний stdin не прочитано'));
        if Got=0 then Break;
        if Buffer.Size>Int64(MAX_T5M_FILE_BYTES)-Got then
          raise Exception.Create(Uk('пакет перевищує фізичну межу T5M'));
        Buffer.WriteBuffer(Chunk,Got);
      until False;
      if Buffer.Size=0 then
        raise Exception.Create(Uk('порожній фізичний пакет Core1'));
      SetLength(Result,SizeInt(Buffer.Size));
      Buffer.Position:=0;
      Buffer.ReadBuffer(Result[1],Length(Result));
    finally Buffer.Free end;
  finally Source.Free end;
end;

{ Borrowed TD2Document/Root не залишає scope. Exact word spans беруться
  ТІЛЬКИ з wsm.d2source, [WordIndex,EndWordIndexExclusive) — 1-based.
  Кожен виклик отримує ВЛАСНИЙ packed T5M; між формами той самий Runtime.
  Динамічний output накопичується в words; EncodeT5M ОДИН раз наприкінці.
  Відмови до stdout транзакційні. Після syscall частковий pipe-write
  відкотити неможливо без host-протоколу.
  Питання: чому не можна з'єднувати готові packed T5M байти?
  Хто володіє фізичним деревом та замиканням?
  Чому 65 коренів — host quota, а не закон SENS?
  Де припиняємо роботу при пізній відмові?
  Чому успішна відповідь — T5M, а не 64 рядки тексту? }
procedure ExecutePacket(const RootPath:String);
var
  Runtime:TCore1FirstRuntime;
  Doc:TD2Document;
  AllWords,CallWords,AnswerWords,OutWords,VerifyWords:TExactWords;
  Physical,CallPhysical,Answer,Published:RawByteString;
  Root:TD2Node;
  I,J,StartWord,FinishWord,Count,Used,Capacity,NextCap:SizeInt;
  Sink:THandleStream;
begin
  Runtime:=nil;Doc:=nil;
  Physical:=ReadPhysicalStdin;
  DecodeT5M(Physical,AllWords);
  if EncodeT5M(AllWords)<>Physical then
    raise Exception.Create(Uk('пакет неканонічний за T5M'));
  Doc:=ParseD2WordsWide(AllWords);
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxPacketRoots) then
      raise Exception.Create(Uk('пакет повинен містити 1..64 D2-корені'));
    Runtime:=TCore1FirstRuntime.Create(
      IncludeTrailingPathDelimiter(ExpandFileName(RootPath))+
      'external'+PathDelim+'sens', RootPath);
    try
      SetLength(OutWords,0);Used:=0;Capacity:=0;
      for I:=0 to High(Doc.Roots) do begin
        Root:=Doc.Roots[I];
        if Root=nil then raise Exception.Create(Uk('відсутній D2-корінь'));
        StartWord:=Root.WordIndex-1;
        FinishWord:=Root.EndWordIndexExclusive-1;
        if (StartWord<0) or (FinishWord<=StartWord) or
           (FinishWord>Length(AllWords)) then
          raise Exception.Create(Uk('недопустимий інтервал фізичного кореня'));
        Count:=FinishWord-StartWord;
        SetLength(CallWords,Count);
        for J:=0 to Count-1 do CallWords[J]:=AllWords[StartWord+J];
        CallPhysical:=EncodeT5M(CallWords);
        try
          Answer:=Runtime.ExecutePhysicalCall(CallPhysical);
          DecodeT5M(Answer,AnswerWords);
          if (Length(AnswerWords)<1) or (EncodeT5M(AnswerWords)<>Answer) then
            raise Exception.Create(Uk('виконавець повернув неканонічний T5M'));
        except
          on E:Exception do raise Exception.Create(Uk('форма=')+
            IntToStr(I+1)+' '+E.Message);
        end;
        if (Length(AnswerWords)>MaxD2Words-Used) then
          raise Exception.Create(Uk('завеликий фізичний результат пакета'));
        if Used+Length(AnswerWords)>Capacity then begin
          NextCap:=Capacity;
          if NextCap=0 then NextCap:=16;
          while NextCap<Used+Length(AnswerWords) do begin
            if NextCap>MaxD2Words div 2 then begin
              NextCap:=MaxD2Words;Break
            end;
            NextCap:=NextCap*2;
          end;
          Capacity:=NextCap;
          SetLength(OutWords,Capacity);
        end;
        for J:=0 to High(AnswerWords) do
          OutWords[Used+J]:=AnswerWords[J];
        Inc(Used,Length(AnswerWords));
      end;
      SetLength(OutWords,Used);
      Published:=EncodeT5M(OutWords);
      if (Length(Published)<1) or (Length(Published)>MAX_T5M_FILE_BYTES) then
        raise Exception.Create(Uk('пакетна відповідь за межею фізичного T5M'));
      DecodeT5M(Published,VerifyWords);
      if (Length(VerifyWords)<>Used) or
         (EncodeT5M(VerifyWords)<>Published) then
        raise Exception.Create(Uk('помилка канонічного фінального пакування'));
    finally Runtime.Free end;
  finally Doc.Free end;
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Published[1],Length(Published))
  finally Sink.Free end;
end;

begin
  ExitCode:=0;
  if (ParamCount<>2) or
     (RawByteString(ParamStr(1))<>Uk('--виконати-пакет')) or
     (ParamStr(2)='') then begin
    WriteLn(StdErr,Uk('Використання: senscore1paket --виконати-пакет КОРІНЬ'));
    ExitCode:=64;
  end else
    try ExecutePacket(ParamStr(2))
    except
      on E:Exception do begin
        WriteLn(StdErr,Uk('CORE1-ПАКЕТ-ПОМИЛКА: '),E.Message);
        ExitCode:=2;
      end;
    end;
end.
