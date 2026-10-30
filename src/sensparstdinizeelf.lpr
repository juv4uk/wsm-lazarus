{ G6.161 — композиційний FPC CLI, який перетворює вже створений
  фізичними .sens тілами ELF на ОДИН повторно використовуваний ELF64.
  Не читає назв D7 або текстової .lisp, не визначає законів SENS.
  Результат — машинний read(0, 5) → точний D24 → обидві компільовані
  функції → машинний canonical T5M stdout.
  Питання: 1) Чому програма не читає .sens для повторної компіляції?
  2) Чому невідомий ELF відхиляє wsm.bodyt5mstdin?
  3) Хто володіє буферами після TFileStream.Free?
  4) Чому output публікуємо тільки через спільний no-clobber механізм?
  5) Чому D7/«укр» ніяк не впливають на machine ABI? }
program sensparstdinizeelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.bodyt5mstdin,wsm.elfpublish,wsm.elfgeometry;

type EStdinizeError=class(Exception);

procedure Need(OK:Boolean;const Message:UnicodeString);
begin if not OK then raise EStdinizeError.Create(UTF8Encode(Message)) end;

{ Path — host-шлях (borrowed); Result — managed/owned byte image.
  Успішна перевірка фізичних ELF-полів відбувається в postpass,
  а не при довірі суфіксу файла. }
function ReadImage(const Path:String):RawByteString;
var Input:TFileStream;
begin
  Need((Path<>'') and (Length(Path)<=4096) and
    (ExtractFileExt(Path)='.elf'),'потрібен вихідний ELF64 .elf');
  Input:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Input.Size>120) and (Input.Size<=1024*1024),
      'вихідний машинний ELF перевищує квоту або порожній');
    SetLength(Result,SizeInt(Input.Size));
    Input.ReadBuffer(Result[1],Length(Result));
  finally Input.Free end;
end;

procedure SayError(const Text:RawByteString);
var Stream:THandleStream;Msg:RawByteString;
begin
  Msg:=Text+#10;
  Stream:=THandleStream.Create(TextRec(StdErr).Handle);
  try Stream.WriteBuffer(Msg[1],Length(Msg));finally Stream.Free end;
end;

procedure Run;
var Original,Dynamic:RawByteString;G:TELFGeometry;Target:String;
begin
  {$IFNDEF LINUX}
  Need(False,'потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  Need(False,'потрібен x86-64');
  {$ENDIF}
  Need((ParamCount=3) and
    (RawByteString(ParamStr(1))=RawByteString(UTF8Encode(
      UnicodeString('--фізичний-D24-stdin')))),
    'виклик: sensparstdinizeelf --фізичний-D24-stdin наявний.elf новий.elf');
  Target:=ParamStr(3);
  Need((Target<>'') and (Length(Target)<=4096) and
    (ExtractFileExt(Target)='.elf'),'потрібна нова ціль .elf');
  Original:=ReadImage(ParamStr(2));
  Dynamic:=DynamicD24T5MStdinELF(Original);
  PublishNewELF64(Target,Dynamic,2,G);
  Writeln('ФІЗИЧНИЙ-D24-STDIN-ELF-ГОТОВО: bytes=',G.FileBytes,
    ' input=5-byte-T5M runtime=yes result=D24-T5M energy=NOT_MEASURED');
end;

begin
  try Run
  except on E:Exception do begin
    SayError(RawByteString(UTF8Encode(UnicodeString(
      'ФІЗИЧНИЙ-D24-STDIN-ELF-ВІДМОВА: ')))+
      RawByteString(E.Message));
    ExitCode:=2;
  end end;
end.
