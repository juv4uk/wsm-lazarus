{ G3.20 — вузький файл укр -> точний T5M -> вже злитий D3 runtime.
  .lisp — тільки повна людська проєкція укр, не машинний канон.
  Ніякого власного evaluator, Core4, D12+ або dispatch за назвами. }
program sensukrvykon;
{$mode objfpc}{$H+}{$codepage utf8}

uses SysUtils, Classes, BaseUnix, wsm.bind, wsm.ukroundtrip,
  wsm.d3batch, wsm.t5m;

const MaxUkrBytes = 1024*1024;

function Ua(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

function ReadUkrFile(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxUkrBytes) then
      raise Exception.Create('порожня або надмірна українська проєкція');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally
    F.Free;
  end;
end;

procedure Run;
var
  Root,InputPath,OutputPath,TempPath:String;
  Source,Physical,Again,Answer,Printable:RawByteString;
  Tables:TDomainSet;
  Longs:TLongProjection;
  Forms:SizeInt;
  F:TFileStream;
begin
  ExitCode:=64;
  if (ParamCount<>4) or
     (RawByteString(ParamStr(1))<>Ua('--виконати-укр')) then begin
    WriteLn(StdErr,Ua('ПОМИЛКА-УКР-ВИКОНАННЯ: Використання: sensukrvykon --виконати-укр корінь-sens вхід.lisp новий-результат.sens'));
    Exit;
  end;
  Root:=ParamStr(2);
  InputPath:=ParamStr(3);
  OutputPath:=ParamStr(4);
  if (Root='') or (InputPath='') or (OutputPath='') or
     (LowerCase(ExtractFileExt(InputPath))<>'.lisp') or
     (LowerCase(ExtractFileExt(OutputPath))<>'.sens') then begin
    WriteLn(StdErr,Ua('ПОМИЛКА-УКР-ВИКОНАННЯ: потрібні корінь SENS, вхід.lisp і новий вихід.sens'));
    Exit;
  end;

  ExitCode:=2;
  TempPath:='';
  try
    { Єдиний авторитет координат: pinned SENS, включно з D7 як даними. }
    LoadPinnedDomains(RawByteString(Root),Tables);
    LoadPinnedLongProjection(RawByteString(Root),Tables,Longs);
    Source:=ReadUkrFile(InputPath);
    Physical:=UkrainianToPhysical(Source,Tables,Longs);
    { Канонізація не дозволяє текстовому входу видати інші біти.
      Довільні пробіли/коментарі можуть зникнути лише у проєкції. }
    Printable:=PhysicalToUkrainian(Physical,Tables,Longs);
    Again:=UkrainianToPhysical(Printable,Tables,Longs);
    if Again<>Physical then
      raise Exception.Create('побайтовий укр/T5M round-trip не збігся');
    { Справжнє обчислення — тільки вже існуючий двійковий evaluator.
      Всі 1..64 форми виконуються до першого байта публікації. }
    ExecutePhysicalD3Batch(Physical,RawByteString(Root),Answer,Forms);
    if (Answer='') or (Length(Answer)>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('неприпустима довжина фізичної відповіді');

    { POSIX temp + hard link: атомарно створюємо ТІЛЬКИ нову ціль.
      Існуючі файли та навіть dangling symlink не перезаписуються. }
    TempPath:=GetTempFileName(
      ExtractFilePath(ExpandFileName(OutputPath)),'ukv');
    if TempPath='' then
      raise Exception.Create('не вдалося створити тимчасовий файл');
    F:=TFileStream.Create(TempPath,fmCreate);
    try
      F.WriteBuffer(Answer[1],Length(Answer));
    finally F.Free; end;
    if fpLink(PChar(TempPath),PChar(OutputPath))<>0 then
      raise Exception.Create('результат існує або недоступний для створення');
    DeleteFile(TempPath);
    TempPath:='';
    WriteLn(Ua('УКР-ФІЗИЧНЕ-ВИКОНАННЯ-ГАРАЗД форм='),Forms,
      Ua(' байтів='),Length(Answer),
      Ua(' джерело=проєкція-укр відповідь=канонічний-T5M'));
    ExitCode:=0;
  except
    on E:ED3BatchError do
      WriteLn(StdErr,Ua('ПОМИЛКА-УКР-ВИКОНАННЯ форма='),E.FormIndex,
        Ua(' слово='),E.WordIndex,': ',E.Message);
    on E:Exception do
      WriteLn(StdErr,Ua('ПОМИЛКА-УКР-ВИКОНАННЯ: '),E.Message);
  end;
  if TempPath<>'' then DeleteFile(TempPath);
end;

begin
  Run;
end.
