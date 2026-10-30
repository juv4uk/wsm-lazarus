{ G6.175 — окремий Free Pascal CLI для runtime 2×D24 T5M stdin.
  Вхід — уже реально скомпільований ELF, не текстовий .lisp файл.
  Механізм не визначає арифметики; обидва source-backed D5 тіла
  походять із фізичних .sens файлів, перевірених чинним lowering.
  Питання: 1) Чому власні SENS закони тут не потрібні?
  2) Чому придатний до перетворення лише перевірений ET_EXEC?
  3) Чому оригінальний образ і ELF результат — різні owned буфери?
  4) Чому відмова до PublishNewELF64 гарантує no-clobber?
  5) Чому .lisp лишається тільки людською проєкцією «укр»? }
program sensdvaparamstdinelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.bodytwot5mstdin,wsm.elfpublish,wsm.elfgeometry;
type ETwoD24CLIError=class(Exception);
procedure Need(OK:Boolean;const Why:UnicodeString);
begin if not OK then raise ETwoD24CLIError.Create(UTF8Encode(Why)) end;
function ReadELF(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Need((Path<>'') and (Length(Path)<=4096) and
    (ExtractFileExt(Path)='.elf'),'потрібен фізичний машинний .elf');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Stream.Size>120) and (Stream.Size<=1024*1024),
      'неприпустима довжина фізичного ELF64');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;
procedure ErrorOutput(const Reason:RawByteString);
var F:THandleStream;B:RawByteString;
begin
  B:=Reason+#10;
  F:=THandleStream.Create(TextRec(StdErr).Handle);
  try F.WriteBuffer(B[1],Length(B));finally F.Free end;
end;
procedure Run;
var Image,TargetImage:RawByteString;Target:String;G:TELFGeometry;
begin
  {$IFNDEF LINUX}
  Need(False,'тільки Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  Need(False,'тільки x86-64');
  {$ENDIF}
  Need((ParamCount=3) and
    (RawByteString(ParamStr(1))=
       RawByteString(UTF8Encode(UnicodeString('--два-фізичні-D24-stdin')))),
    'виклик: sensdvaparamstdinelf --два-фізичні-D24-stdin compiled.elf новий.elf');
  Target:=ParamStr(3);
  Need((Target<>'') and (Length(Target)<=4096) and
       (ExtractFileExt(Target)='.elf'),'ціль має бути новим .elf');
  Image:=ReadELF(ParamStr(2));
  TargetImage:=DynamicTwoD24StdinELF(Image);
  PublishNewELF64(Target,TargetImage,2,G);
  Writeln('ДВА-D24-STDIN-ELF-ГОТОВО bytes=',G.FileBytes,
    ' args=2 exact=D24 input=10-byte-T5M result=D24-T5M energy=NOT_MEASURED');
end;
begin
  try Run
  except on E:Exception do begin
    ErrorOutput(RawByteString(UTF8Encode(
      UnicodeString('ДВА-D24-STDIN-ELF-ВІДМОВА: ')))+
      RawByteString(E.Message));
    ExitCode:=2;
  end end;
end.
