{ G5.63 — пакетний фізичний файловий D3-зріз SENS.
  Вхід: один канонічний packed T5M .sens з 1..64 D2-коренями.
  Вихід: один packed T5M з відповідями всіх виконаних D3-коренів.
  Тільки раніше злиті T5M/D2 reader, exact binder, native D3 evaluator.
  НЕ Core4 loader, НЕ REPL, НЕ числова D12+ арифметика. }
program sensfizfayl;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d2source,
     wsm.physloc, wsm.binaryexec;

const
  MaxFileBytes = 65536;  { приватна host-квота, не закон SENS }
  MaxForms = 64;
  MaxOutputWords = 100000;

type
  EPhysicalFileError = class(Exception);

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxFileBytes) then
      raise EPhysicalFileError.Create('довжина файла поза межами 1..65536 байтів');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

function SourcePosition(const Physical:RawByteString;
  const Spans:TPhysicalWordSpans; AtWord:SizeInt):String;
var P:TPhysicalWordSpan;
begin
  P:=LocatePhysicalWord(Physical,Spans,AtWord);
  Result:='слово='+IntToStr(P.WordIndex)+
    ' трити=['+IntToStr(P.TritStart)+','+IntToStr(P.TritEnd)+
    ') байти=['+IntToStr(P.ByteStart)+','+IntToStr(P.ByteEnd)+')';
  if P.IsEOF then Result:=Result+' EOF=так';
end;

{ Physical: borrowed packed bytes. SourceWords, Part, ResponseWords і
  ResultWords: керовані FPC масиви точної ширини; D2 документи owned і
  звільняються у finally. Result: нові канонічні packed bytes після
  виконання ВСІХ коренів, жодного проміжного stdout. Той самий Engine
  використовується послідовно; лексична персистентність не заявлена.
  Питання: Чому не можна розрізати T5M за байтовими межами?
  Хто перевіряє D2 межі? Чому форма=2 — host-індекс, не D12?
  Коли звільняються TD2Document? Чому пізня відмова не пише stdout? }
function ExecuteFile(Engine:TBinaryExecutor;
  const Physical:RawByteString):RawByteString;
var
  Words,Part,ResponseWords,ResultWords:TExactWords;
  Spans:TPhysicalWordSpans;
  Doc,ReplyDoc:TD2Document;
  First,Finish,I,J,Used,Capacity,NextCapacity:SizeInt;
  Reply:RawByteString;
begin
  Result:=''; Doc:=nil; ReplyDoc:=nil;
  Words:=nil; Part:=nil; ResponseWords:=nil; ResultWords:=nil;
  Used:=0; Capacity:=0;
  if Engine=nil then
    raise EPhysicalFileError.Create('відсутній нативний виконавець');
  try
    DecodeT5MWithLocations(Physical,Words,Spans);
  except
    on E:Exception do
      raise EPhysicalFileError.Create('фізичний T5M: '+E.Message);
  end;
  if (Length(Words)=0) or (EncodeT5M(Words)<>Physical) then
    raise EPhysicalFileError.Create('фізичний T5M неканонічний');
  try
    Doc:=ParseD2WordsWide(Words);
  except
    on E:ED2SourceError do
      raise EPhysicalFileError.Create('D2: '+
        SourcePosition(Physical,Spans,E.WordIndex)+' '+E.Message);
  end;
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxForms) then
      raise EPhysicalFileError.Create('дозволено лише 1..64 фізичні форми');
    for I:=0 to High(Doc.Roots) do begin
      First:=Doc.Roots[I].WordIndex-1;
      Finish:=Doc.Roots[I].EndWordIndexExclusive-1;
      if (First<0) or (Finish<=First) or (Finish>Length(Words)) then
        raise EPhysicalFileError.Create('неправильні межі D2-кореня');
      SetLength(Part,Finish-First);
      for J:=0 to High(Part) do Part[J]:=Words[First+J];
      try
        Reply:=Engine.ExecutePhysicalT5M(EncodeT5M(Part));
        DecodeT5M(Reply,ResponseWords);
        if (Length(ResponseWords)=0) or
           (EncodeT5M(ResponseWords)<>Reply) then
          raise EPhysicalFileError.Create('результат виконавця неканонічний');
        ReplyDoc:=ParseD2WordsWide(ResponseWords);
        try
          if Length(ReplyDoc.Roots)<>1 then
            raise EPhysicalFileError.Create(
              'виконавець повернув не один D2-корінь');
        finally FreeAndNil(ReplyDoc) end;
        if Length(ResponseWords)>MaxOutputWords-Used then
          raise EPhysicalFileError.Create('надмірна сукупна відповідь');
        if Used+Length(ResponseWords)>Capacity then begin
          NextCapacity:=Capacity;
          if NextCapacity=0 then NextCapacity:=16;
          while NextCapacity<Used+Length(ResponseWords) do begin
            if NextCapacity>MaxOutputWords div 2 then
              NextCapacity:=MaxOutputWords
            else NextCapacity:=NextCapacity*2;
          end;
          SetLength(ResultWords,NextCapacity);
          Capacity:=NextCapacity;
        end;
        for J:=0 to High(ResponseWords) do
          ResultWords[Used+J]:=ResponseWords[J];
        Inc(Used,Length(ResponseWords));
      except
        on E:Exception do
          raise EPhysicalFileError.Create('форма='+IntToStr(I+1)+' '+
            SourcePosition(Physical,Spans,Doc.Roots[I].WordIndex)+
            ' '+E.Message);
      end;
    end;
    SetLength(ResultWords,Used);
    Result:=EncodeT5M(ResultWords);
    if (Length(Result)=0) or (Length(Result)>MaxFileBytes) then
      raise EPhysicalFileError.Create(
        'сукупна фізична відповідь поза межею 65536 байтів');
  finally
    ReplyDoc.Free;
    Doc.Free;
  end;
end;

{ Bytes: повністю перевірені owned packed T5M. Лише тут дозволена
  публікація; partial OS write не відкотити, але семантичний fail уже
  неможливий. Return: лише двійкові байти, без тексту/newline.
  Питання: чому не WriteLn? Чому loop враховує short write?
  Де відбулася повна перевірка всіх D2-коренів? }
procedure WritePhysical(const Bytes:RawByteString);
var Offset,Count:SizeInt;
begin
  Offset:=0;
  while Offset<Length(Bytes) do begin
    Count:=FileWrite(TTextRec(Output).Handle,Bytes[Offset+1],
      Length(Bytes)-Offset);
    if Count<=0 then
      raise EPhysicalFileError.Create('помилка запису двійкового stdout');
    Inc(Offset,Count);
  end;
end;

var
  Engine:TBinaryExecutor;
  Physical,Answer:RawByteString;
begin
  if (ParamCount<>2) or (ParamStr(1)<>'--завантажити-сенс') or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') then begin
    WriteLn(StdErr,'Використання: sensfizfayl --завантажити-сенс файл.sens');
    Halt(64);
  end;
  Engine:=nil;
  try
    Physical:=ReadPhysical(ParamStr(2));
    Engine:=TBinaryExecutor.Create('external/sens');
    Answer:=ExecuteFile(Engine,Physical);
    WritePhysical(Answer);
  except
    on E:Exception do begin
      WriteLn(StdErr,'ФІЗИЧНИЙ-ФАЙЛ-ПОМИЛКА: ',E.Message);
      ExitCode:=2;
    end;
  end;
  Engine.Free;
end.
