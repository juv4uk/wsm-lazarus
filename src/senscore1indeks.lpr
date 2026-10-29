{ Core1.3 — тільки host CLI для pinned фізичного індексу Core1.
  D7 ідентичність передається як canonical T5M, ніяких .lisp назв.
  Ні DEFINE evaluation, ні власної пам'яті замикань чи GC. }
program senscore1indeks;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.core1index;

function Uk(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure WritePhysical(const S:RawByteString; ToError:Boolean);
var Sink:THandleStream;
begin
  if ToError then Sink:=THandleStream.Create(TextRec(StdErr).Handle)
  else Sink:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(S)>0 then Sink.WriteBuffer(S[1],Length(S));
  finally
    Sink.Free;
  end;
end;

function ReadPhysicalFile(const Path:String):RawByteString;
var FileData:TFileStream;
begin
  FileData:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (FileData.Size<=0) or (FileData.Size>MAX_T5M_FILE_BYTES) then
      raise ECore1IndexError.Create('фізичний ключ не проходить бюджет');
    SetLength(Result,SizeInt(FileData.Size));
    FileData.ReadBuffer(Result[1],Length(Result));
  finally
    FileData.Free;
  end;
end;

function OrdinalParam(const S:String):SizeInt;
var N:Int64;
begin
  if not TryStrToInt64(S,N) or (N<1) or (N>256) then
    raise ECore1IndexError.Create('неприпустимий індекс визначення');
  Result:=SizeInt(N);
end;

procedure Execute;
var
  Op,Answer:RawByteString;
  Index:TCore1Index;
  Number:SizeInt;
  D:TCore1Definition;
begin
  if (ParamCount<2) or (ParamCount>3) then
    raise ECore1IndexError.Create('потрібна команда, корінь і параметр');
  Op:=RawByteString(ParamStr(1));
  if (Op=Uk('--опис')) then begin
    if ParamCount<>2 then
      raise ECore1IndexError.Create('опис не приймає порядковий номер');
  end else if (Op=Uk('--форма')) or (Op=Uk('--ключ')) or
              (Op=Uk('--знайти')) then begin
    if ParamCount<>3 then
      raise ECore1IndexError.Create('бракує параметра запиту');
  end else
    raise ECore1IndexError.Create('невідома команда Core1 індексу');
  Index:=TCore1Index.Create(ParamStr(2));
  try
    if Op=Uk('--опис') then begin
      D:=Index.Definition(1);
      Answer:=Uk('CORE1-ІНДЕКС-ГАРАЗД визначень=')+
        IntToStr(Index.Count)+Uk(' унікальних=')+
        IntToStr(Index.Count)+
        Uk(' перше-слово=')+IntToStr(D.StartWord)+
        Uk(' пошук=D7 виконання=ні')+#10;
    end else if Op=Uk('--знайти') then
      Answer:=Index.FindPhysicalDefinition(ReadPhysicalFile(ParamStr(3)))
    else begin
      Number:=OrdinalParam(ParamStr(3));
      if Op=Uk('--форма') then
        Answer:=Index.PhysicalDefinition(Number)
      else
        Answer:=Index.PhysicalIdentifier(Number);
    end;
    { Транзакційний output: весь ParseD2/індекс/пошук завершено
      до відкриття stdout. ByteStream не додає LF до T5M. }
    WritePhysical(Answer,False);
  finally
    Index.Free;
  end;
end;

begin
  try
    Execute;
  except
    on E:Exception do begin
      WritePhysical(Uk('CORE1-ІНДЕКС-ВІДМОВА: ')+
        Uk(UnicodeString(E.Message))+#10,True);
      Halt(2);
    end;
  end;
end.
