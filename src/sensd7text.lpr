{ G1.22 — явний host CLI D7 «ук/укр» текстових даних ↔ T5M.
  .txt — просто дані D7; тут немає завантаження .lisp як SENS програми. }
program sensd7text;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,BaseUnix,wsm.d7text,wsm.t5m;
var Mode,Root,InputPath,OutputPath,TempPath:String;
    Physical,Answer:RawByteString; Stream:TFileStream;
    Map:TD7Map; Direction:Boolean;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

begin
  TempPath:='';
  if ParamCount<>4 then begin
    WriteLn(StdErr,UA('Використання: sensd7text --кодувати-укр|--читати-укр корінь вхід.txt|sens вихід.sens|txt'));
    Halt(64);
  end;
  Mode:=ParamStr(1);Root:=ParamStr(2);
  InputPath:=ParamStr(3);OutputPath:=ParamStr(4);
  Direction:=RawByteString(Mode)=UA('--кодувати-укр');
  if (not Direction) and (RawByteString(Mode)<>UA('--читати-укр')) then begin
    WriteLn(StdErr,UA('Невідомий явний D7 режим'));Halt(64);
  end;
  if (Direction and ((LowerCase(ExtractFileExt(InputPath))<>'.txt') or
                     (LowerCase(ExtractFileExt(OutputPath))<>'.sens'))) or
     ((not Direction) and
      ((LowerCase(ExtractFileExt(InputPath))<>'.sens') or
       (LowerCase(ExtractFileExt(OutputPath))<>'.txt'))) then begin
    WriteLn(StdErr,UA('D7: потрібні відповідні .txt/.sens, без автоматичної .lisp конверсії'));
    Halt(64);
  end;
  try
    LoadPinnedD7Map(Root,Map);
    Stream:=TFileStream.Create(InputPath,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<1) or (Stream.Size>MAX_T5M_FILE_BYTES) then
        raise ED7TextError.Create('фізичний/текстовий ввід поза межею');
      SetLength(Physical,SizeInt(Stream.Size));
      Stream.ReadBuffer(Physical[1],Length(Physical));
    finally Stream.Free end;
    if Direction then Answer:=EncodeD7Text(Physical,Map,dsUkr)
    else Answer:=DecodeD7Text(Physical,Map,dsUkr);
    if (Length(Answer)<1) or (Length(Answer)>MAX_T5M_FILE_BYTES) then
      raise ED7TextError.Create('фізичний вихід D7 поза межею');
    { UNIX no-clobber: зміни повністю в temp, публікація тільки fpLink.
      Порожній/stale/символьне посилання теж займає цільове ім'я. }
    TempPath:=GetTempFileName(ExtractFilePath(ExpandFileName(OutputPath)),'d7t');
    if TempPath='' then raise ED7TextError.Create('не створено D7 temp');
    Stream:=TFileStream.Create(TempPath,fmCreate);
    try Stream.WriteBuffer(Answer[1],Length(Answer));
    finally Stream.Free end;
    if fpLink(RawByteString(TempPath),RawByteString(OutputPath))<>0 then
      raise ED7TextError.Create('фізичне ім’я зайняте або недоступне');
    DeleteFile(TempPath);TempPath:='';
    WriteLn(UA('Д7-ПРОЄКЦІЯ-ГОТОВО байтів='),Length(Answer));
  except
    on E:Exception do begin
      if TempPath<>'' then DeleteFile(TempPath);
      WriteLn(StdErr,UA('Д7-ПРОЄКЦІЯ-ПОМИЛКА: '),E.Message);
      Halt(2);
    end;
  end;
end.
