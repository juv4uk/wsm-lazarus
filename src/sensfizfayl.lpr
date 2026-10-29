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
      raise EPhysicalFileError.Create(#$D0#$B4#$D0#$BE#$D0#$B2#$D0#$B6#$D0#$B8#$D0#$BD#$D0#$B0#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$D0#$B0#$20#$D0#$BF#$D0#$BE#$D0#$B7#$D0#$B0#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D0#$B0#$D0#$BC#$D0#$B8#$20#$31#$2E#$2E#$36#$35#$35#$33#$36#$20#$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$D1#$96#$D0#$B2);
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

function SourcePosition(const Physical:RawByteString;
  const Spans:TPhysicalWordSpans; AtWord:SizeInt):String;
var P:TPhysicalWordSpan;
begin
  P:=LocatePhysicalWord(Physical,Spans,AtWord);
  Result:=#$D1#$81#$D0#$BB#$D0#$BE#$D0#$B2#$D0#$BE#$3D+IntToStr(P.WordIndex)+
    #$20#$D1#$82#$D1#$80#$D0#$B8#$D1#$82#$D0#$B8#$3D#$5B+IntToStr(P.TritStart)+','+IntToStr(P.TritEnd)+
    #$29#$20#$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$D0#$B8#$3D#$5B+IntToStr(P.ByteStart)+','+IntToStr(P.ByteEnd)+')';
  if P.IsEOF then Result:=Result+#$20#$45#$4F#$46#$3D#$D1#$82#$D0#$B0#$D0#$BA;
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
    raise EPhysicalFileError.Create(#$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D0#$B5#$D1#$86#$D1#$8C);
  try
    DecodeT5MWithLocations(Physical,Words,Spans);
  except
    on E:Exception do
      raise EPhysicalFileError.Create(#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$54#$35#$4D#$3A#$20+E.Message);
  end;
  if (Length(Words)=0) or (EncodeT5M(Words)<>Physical) then
    raise EPhysicalFileError.Create(#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9#$20#$54#$35#$4D#$20#$D0#$BD#$D0#$B5#$D0#$BA#$D0#$B0#$D0#$BD#$D0#$BE#$D0#$BD#$D1#$96#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9);
  try
    Doc:=ParseD2WordsWide(Words);
  except
    on E:ED2SourceError do
      raise EPhysicalFileError.Create('D2: '+
        SourcePosition(Physical,Spans,E.WordIndex)+' '+E.Message);
  end;
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxForms) then
      raise EPhysicalFileError.Create(#$D0#$B4#$D0#$BE#$D0#$B7#$D0#$B2#$D0#$BE#$D0#$BB#$D0#$B5#$D0#$BD#$D0#$BE#$20#$D0#$BB#$D0#$B8#$D1#$88#$D0#$B5#$20#$31#$2E#$2E#$36#$34#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D1#$96#$20#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B8);
    for I:=0 to High(Doc.Roots) do begin
      First:=Doc.Roots[I].WordIndex-1;
      Finish:=Doc.Roots[I].EndWordIndexExclusive-1;
      if (First<0) or (Finish<=First) or (Finish>Length(Words)) then
        raise EPhysicalFileError.Create(#$D0#$BD#$D0#$B5#$D0#$BF#$D1#$80#$D0#$B0#$D0#$B2#$D0#$B8#$D0#$BB#$D1#$8C#$D0#$BD#$D1#$96#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D1#$96#$20#$44#$32#$2D#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B5#$D0#$BD#$D1#$8F);
      SetLength(Part,Finish-First);
      for J:=0 to High(Part) do Part[J]:=Words[First+J];
      try
        Reply:=Engine.ExecutePhysicalT5M(EncodeT5M(Part));
        DecodeT5M(Reply,ResponseWords);
        if (Length(ResponseWords)=0) or
           (EncodeT5M(ResponseWords)<>Reply) then
          raise EPhysicalFileError.Create(#$D1#$80#$D0#$B5#$D0#$B7#$D1#$83#$D0#$BB#$D1#$8C#$D1#$82#$D0#$B0#$D1#$82#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D1#$86#$D1#$8F#$20#$D0#$BD#$D0#$B5#$D0#$BA#$D0#$B0#$D0#$BD#$D0#$BE#$D0#$BD#$D1#$96#$D1#$87#$D0#$BD#$D0#$B8#$D0#$B9);
        ReplyDoc:=ParseD2WordsWide(ResponseWords);
        try
          if Length(ReplyDoc.Roots)<>1 then
            raise EPhysicalFileError.Create(
              #$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D0#$B5#$D1#$86#$D1#$8C#$20#$D0#$BF#$D0#$BE#$D0#$B2#$D0#$B5#$D1#$80#$D0#$BD#$D1#$83#$D0#$B2#$20#$D0#$BD#$D0#$B5#$20#$D0#$BE#$D0#$B4#$D0#$B8#$D0#$BD#$20#$44#$32#$2D#$D0#$BA#$D0#$BE#$D1#$80#$D1#$96#$D0#$BD#$D1#$8C);
        finally FreeAndNil(ReplyDoc) end;
        if Length(ResponseWords)>MaxOutputWords-Used then
          raise EPhysicalFileError.Create(#$D0#$BD#$D0#$B0#$D0#$B4#$D0#$BC#$D1#$96#$D1#$80#$D0#$BD#$D0#$B0#$20#$D1#$81#$D1#$83#$D0#$BA#$D1#$83#$D0#$BF#$D0#$BD#$D0#$B0#$20#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BF#$D0#$BE#$D0#$B2#$D1#$96#$D0#$B4#$D1#$8C);
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
          raise EPhysicalFileError.Create(#$D1#$84#$D0#$BE#$D1#$80#$D0#$BC#$D0#$B0#$3D+IntToStr(I+1)+' '+
            SourcePosition(Physical,Spans,Doc.Roots[I].WordIndex)+
            ' '+E.Message);
      end;
    end;
    SetLength(ResultWords,Used);
    Result:=EncodeT5M(ResultWords);
    if (Length(Result)=0) or (Length(Result)>MaxFileBytes) then
      raise EPhysicalFileError.Create(
        #$D1#$81#$D1#$83#$D0#$BA#$D1#$83#$D0#$BF#$D0#$BD#$D0#$B0#$20#$D1#$84#$D1#$96#$D0#$B7#$D0#$B8#$D1#$87#$D0#$BD#$D0#$B0#$20#$D0#$B2#$D1#$96#$D0#$B4#$D0#$BF#$D0#$BE#$D0#$B2#$D1#$96#$D0#$B4#$D1#$8C#$20#$D0#$BF#$D0#$BE#$D0#$B7#$D0#$B0#$20#$D0#$BC#$D0#$B5#$D0#$B6#$D0#$B5#$D1#$8E#$20#$36#$35#$35#$33#$36#$20#$D0#$B1#$D0#$B0#$D0#$B9#$D1#$82#$D1#$96#$D0#$B2);
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
      raise EPhysicalFileError.Create(#$D0#$BF#$D0#$BE#$D0#$BC#$D0#$B8#$D0#$BB#$D0#$BA#$D0#$B0#$20#$D0#$B7#$D0#$B0#$D0#$BF#$D0#$B8#$D1#$81#$D1#$83#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$BE#$D0#$B3#$D0#$BE#$20#$73#$74#$64#$6F#$75#$74);
    Inc(Offset,Count);
  end;
end;

var
  Engine:TBinaryExecutor;
  Physical,Answer:RawByteString;
begin
  if (ParamCount<>2) or (ParamStr(1)<>#$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82#$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8#$2D#$D1#$81#$D0#$B5#$D0#$BD#$D1#$81) or
     (LowerCase(ExtractFileExt(ParamStr(2)))<>'.sens') then begin
    WriteLn(StdErr,#$D0#$92#$D0#$B8#$D0#$BA#$D0#$BE#$D1#$80#$D0#$B8#$D1#$81#$D1#$82#$D0#$B0#$D0#$BD#$D0#$BD#$D1#$8F#$3A#$20#$73#$65#$6E#$73#$66#$69#$7A#$66#$61#$79#$6C#$20#$2D#$2D#$D0#$B7#$D0#$B0#$D0#$B2#$D0#$B0#$D0#$BD#$D1#$82#$D0#$B0#$D0#$B6#$D0#$B8#$D1#$82#$D0#$B8#$2D#$D1#$81#$D0#$B5#$D0#$BD#$D1#$81#$20#$D1#$84#$D0#$B0#$D0#$B9#$D0#$BB#$2E#$73#$65#$6E#$73);
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
      WriteLn(StdErr,#$D0#$A4#$D0#$86#$D0#$97#$D0#$98#$D0#$A7#$D0#$9D#$D0#$98#$D0#$99#$2D#$D0#$A4#$D0#$90#$D0#$99#$D0#$9B#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$3A#$20,E.Message);
      ExitCode:=2;
    end;
  end;
  Engine.Free;
end.
