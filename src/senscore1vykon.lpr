{ Тонкий host-CLI для спільного TCore1FirstRuntime.
  Доменний допуск і фізичний виклик реалізує лише wsm.core1first. }
program senscore1vykon;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.core1first,wsm.t5m;

function ReadPhysicalFile(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise Exception.Create('фізичний аргумент порожній або завеликий');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally
    F.Free;
  end;
end;

function WrapFirstCall(const NameBits,Argument:RawByteString):RawByteString;
var ArgumentWords,CallWords:TExactWords;
    NameCount,I,P:SizeInt;
begin
  if (Length(NameBits)=0) or ((Length(NameBits) mod 7)<>0) then
    raise Exception.Create('спільний runtime повернув не точний D7 ключ');
  DecodeT5M(Argument,ArgumentWords);
  NameCount:=Length(NameBits) div 7;
  SetLength(CallWords,NameCount+Length(ArgumentWords)+4);
  P:=0;
  CallWords[P]:='10';Inc(P); { зовнішній фізичний виклик }
  CallWords[P]:='10';Inc(P); { exact D7-ім’я з pinned DEFINE }
  for I:=0 to NameCount-1 do begin
    CallWords[P]:=Copy(NameBits,I*7+1,7);
    Inc(P);
  end;
  CallWords[P]:='01';Inc(P); { кінець D7-імені }
  for I:=0 to High(ArgumentWords) do begin
    CallWords[P]:=ArgumentWords[I];
    Inc(P);
  end;
  CallWords[P]:='01';Inc(P); { кінець виклику }
  if P<>Length(CallWords) then
    raise Exception.Create('помилка побудови host-рамки виклику');
  Result:=EncodeT5M(CallWords);
end;

var Runtime:TCore1FirstRuntime;
    Input,Answer:RawByteString;
    Root,PinnedRoot,Path,ErrorMessage:String;
    OutputStream:THandleStream;
begin
  if (ParamCount<>3) or
    (RawByteString(ParamStr(1))<>
     #$2D#$2D#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$2D#$D0#$BF#$D0#$B5#$D1#$80#$D1#$88#$D0#$B8#$D0#$B9) then begin
    WriteLn(StdErr,'Використання: senscore1vykon --виконати-перший КОРІНЬ аргумент.sens');
    Halt(64);
  end;
  Path:=ParamStr(3);
  if LowerCase(ExtractFileExt(Path))<>'.sens' then begin
    WriteLn(StdErr,'CORE1-ВІДМОВА: потрібен фізичний .sens');
    Halt(64);
  end;

  Runtime:=nil;
  ErrorMessage:='';
  try
    Root:=ExcludeTrailingPathDelimiter(ExpandFileName(ParamStr(2)));
    PinnedRoot:=IncludeTrailingPathDelimiter(Root)+'external'+PathDelim+'sens';
    Runtime:=TCore1FirstRuntime.Create(PinnedRoot,Root);
    Input:=ReadPhysicalFile(Path);
    Answer:=Runtime.ExecutePhysicalCall(
      WrapFirstCall(Runtime.FirstIdentifier,Input));
    if Length(Answer)=0 then
      raise Exception.Create('порожній результат виконання');
    OutputStream:=THandleStream.Create(TextRec(Output).Handle);
    try
      OutputStream.WriteBuffer(Answer[1],Length(Answer));
    finally
      OutputStream.Free;
    end;
  except
    on E:Exception do ErrorMessage:=E.Message;
  end;
  FreeAndNil(Runtime);
  if ErrorMessage<>'' then begin
    WriteLn(StdErr,'CORE1-ВІДМОВА: ',ErrorMessage);
    ExitCode:=2;
  end;
end.
