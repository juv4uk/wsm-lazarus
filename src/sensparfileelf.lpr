{ G6.156 — файловий AOT двох ФІЗИЧНИХ взаємно-рекурсивних тіл.
  ЖОДНИХ законів SENS у Pascal: цей host CLI тільки допускає точні
  packed T5M файли, перевіряє конфлікти D7 і викликає злитий lowering.
  Результат — реальний ET_EXEC зі stdout рівно одного D24 T5M слова.

  Питання: 1) Чому ні назва файла, ні D7 напис не визначають семантику?
  2) Хто володіє фізичними рядками і коли вони звільняються?
  3) Чому D1:1 не перетворюється на D24:+1 мовчки?
  4) Чому ELF публікуємо тільки після перевіреного postpass?
  5) Чому вхідні .lisp не є канонічними машинними байтами? }
program sensparfileelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.lowerd24,
  wsm.bodyt5mstdout,wsm.elfpublish,wsm.elfgeometry;
type EParFileError = class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(Ok:Boolean;const Msg:UnicodeString);
begin if not Ok then raise EParFileError.Create(String(UA(Msg))) end;

{ Path: borrowed host-only file name; Result: owned canonical bytes.
  Quota is enforced before allocation. Decode/Encode: exact identity.
  1) Why avoid interpreting .sens as UTF-8?
  2) Why does fmOpenRead not permit output publication? }
function ReadPhysical(const Path:String;MaxBytes:SizeInt):RawByteString;
var Stream:TFileStream;Words:TExactWords;
begin
  Need((Path<>'') and (Length(Path)<=4096) and
    (ExtractFileExt(Path)='.sens'),
    'тільки канонічний фізичний файл .sens');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Stream.Size>=1) and (Stream.Size<=MaxBytes),
      'фізичний файл порожній або перевищив квоту');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
  DecodeT5M(Result,Words);
  Need(EncodeT5M(Words)=Result,'не канонічне фізичне кодування T5M');
end;

{ Exact D7 name: D2:10 [W7+] D2:01; фізичні слова borrowed,
  Result є owned бітовим ключем, жодної текстової поверхні.
  1) Why must every glyph have precisely seven bits?
  2) Why can neither width nor spelling alone admit a function? }
function NameBits(const Physical:RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  DecodeT5M(Physical,Words);
  Need((Length(Words)>=3) and (Words[0]='10') and
    (Words[High(Words)]='01'),'очікується D2-обрамлене імʼя D7');
  Result:='';
  for I:=1 to High(Words)-1 do begin
    Need(Length(Words[I])=7,'імʼя повинне містити лише слова D7');
    Result:=Result+Words[I];
  end;
  Need(Result<>'','порожнє імʼя D7 недопустиме');
end;

procedure CheckNumeric(const Physical:RawByteString);
var Number:TExplicitNumeric;
begin
  Number:=ReadNumericPhysical(Physical,24);
  Need((Number.DomainWidth=24) and (Length(Number.ExactBits)=24),
    'аргумент має бути саме exact D24');
end;

procedure SayError(const Msg:RawByteString);
var S:THandleStream;Data:RawByteString;
begin
  Data:=Msg+#10;
  S:=THandleStream.Create(TextRec(StdErr).Handle);
  try S.WriteBuffer(Data[1],Length(Data));finally S.Free end;
end;

procedure Run;
var BodyA,NameA,BodyB,NameB,Parameter,Argument,Image:RawByteString;
  KeyA,KeyB,KeyParam:RawByteString;
  Target:String;Geometry:TELFGeometry;
begin
  {$IFNDEF LINUX}
  Need(False,'потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  Need(False,'потрібен x86-64');
  {$ENDIF}
  Need((ParamCount=8) and
    (RawByteString(ParamStr(1))=UA('--скомпілювати-фізичну-пару')),
    'виклик: sensparfileelf --скомпілювати-фізичну-пару тіло-А.sens імʼя-А.sens тіло-Б.sens імʼя-Б.sens параметр.sens аргумент-D24.sens новий.elf');
  Target:=ParamStr(8);
  Need((Target<>'') and (Length(Target)<=4096) and
    (ExtractFileExt(Target)='.elf'),'потрібна нова ELF-ціль .elf');

  { Усі входи owned до завершення LowerPairELF; source не змінюється.
    Не виконуємо функції тут — вони виконаються в реальному x86-64 ELF.
    Питання: чому відмова можлива тільки ДО PublishNewELF64?
    Чому ключ параметра не повинен затьмарити обидва імені? }
  BodyA:=ReadPhysical(ParamStr(2),8192);
  NameA:=ReadPhysical(ParamStr(3),512);
  BodyB:=ReadPhysical(ParamStr(4),8192);
  NameB:=ReadPhysical(ParamStr(5),512);
  Parameter:=ReadPhysical(ParamStr(6),512);
  Argument:=ReadPhysical(ParamStr(7),64);
  KeyA:=NameBits(NameA);
  KeyB:=NameBits(NameB);
  KeyParam:=NameBits(Parameter);
  Need(KeyA<>KeyB,'обидві функції не можуть мати однаковий ключ D7');
  Need((KeyParam<>KeyA) and (KeyParam<>KeyB),
    'лексичний параметр не може затьмарювати імена функцій');
  CheckNumeric(Argument);

  Image:=LowerPairELF(BodyA,NameA,BodyB,NameB,Parameter,Argument);
  Image:=BodyD24T5MStdoutELF(Image);
  PublishNewELF64(Target,Image,2,Geometry);
  Writeln('SENS-ПАРА-ELF64-ГОТОВО: bytes=',Geometry.FileBytes,
    ' functions=2 exact=D7-D24 result=D24_T5M_STDOUT energy=NOT_MEASURED');
end;

begin
  try Run
  except on E:Exception do begin
    SayError(UA('SENS-ПАРА-ELF64-ВІДМОВА: ')+RawByteString(E.Message));
    ExitCode:=2;
  end end;
end.
