{ G6.83 — один ELF64 із двома машинними діями SUB→ADD над точними D12.
  Закони й перевірки ширини — pinned SENS через вже злиті механізми.
  Жодного нового SENS резидента, проєкційного dispatch або precomputed
  машинного stdout. Машинний код узято лише з двох чинних emitter-ів.

  Питання: чому проміжний результат мусить бути W12?
  Чому копіюємо лише машинний пролог SUB, а не весь його ELF?
  Чому RIP-relative таблиці переживають вставку 5 байтів?
  Чому ELF треба виконати, а не тільки перевірити заголовок? }
unit wsm.elfd12subadd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12SubAddError=class(Exception);
function BuildD12SubAddELF(const FirstPhysical,SecondPhysical,
  ThirdPhysical:RawByteString):RawByteString;
implementation
uses wsm.numericplane,wsm.numericsub,wsm.elfd12sub,wsm.elfd12add,
  wsm.elfgeometry;

const HeaderBytes=120; MovBytes=5; SubBytes=5;

procedure Need(Condition:Boolean;const Message:String);
begin
  if not Condition then raise ED12SubAddError.Create(Message)
end;

{ Image — керований owned RawByteString, Offset — host ELF byte offset.
  Поля PT_LOAD p_filesz та p_memsz мають little-endian 64 біти.
  Це лише формат машинного контейнера, не числовий закон SENS. }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),'ELF поле поза образом');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Запозичені фізичні T5M-буфери — рівно три D12 атоми.
  Вже злитий numeric SUB перевіряє точний закон/підвищення ширини.
  Результат SUB має лишитися D12; навіть дозволене D24 підвищення
  не звужуємо для іншого вузького D12 ADD-backend.
  SubELF починається з MOV EAX,imm32; SUB EAX,imm32.
  AddELF починається з MOV EAX,imm32; ADD EAX,imm32.
  Заміняємо перші 5 байтів AddELF на 10 байтів SUB-прологу:
  далі машинний ADD споживає EAX, а вже перевірений packed T5M
  writer із RIP-relative таблицями лишається на тих самих відстанях.
  Компілятор не друкує літерал: процесор ОБЧИСЛЮЄ обидва кроки.
  Result — owned перевірений ELF64 ET_DYN; звільнення автоматичне. }
function BuildD12SubAddELF(const FirstPhysical,SecondPhysical,
  ThirdPhysical:RawByteString):RawByteString;
var SubImage,AddImage,Intermediate:RawByteString;
    InterNumber:TExplicitNumeric;
    SubGeometry,AddGeometry,FinalGeometry:TELFGeometry;
    OldLength:SizeInt;
begin
  Result:='';
  Intermediate:=SubtractNumericPhysical(FirstPhysical,SecondPhysical,12);
  try
    InterNumber:=ReadNumericPhysical(Intermediate,12);
  except on E:ENumericPlaneError do
    raise ED12SubAddError.Create('проміжний SUB потребує D24: '+E.Message);
  end;
  Need((InterNumber.DomainWidth=12) and
    (Length(InterNumber.ExactBits)=12),'проміжний SUB не D12');
  SubImage:=BuildD12SubELF(FirstPhysical,SecondPhysical);
  AddImage:=BuildD12AddELF(Intermediate,ThirdPhysical);
  VerifySENSELF64(SubImage,SubGeometry);
  VerifySENSELF64(AddImage,AddGeometry);
  Need((SubGeometry.Kind=3) and (AddGeometry.Kind=3) and
    (SubGeometry.Entry=HeaderBytes) and (AddGeometry.Entry=HeaderBytes),
    'вимагаються два перевірені x86-64 PIE backend');
  Need((Length(SubImage)>=HeaderBytes+MovBytes+SubBytes) and
    (Length(AddImage)>=HeaderBytes+MovBytes+5),
    'занадто короткий машинний emitter');
  Need((SubImage[HeaderBytes+1]=#$B8) and
    (SubImage[HeaderBytes+6]=#$2D) and
    (AddImage[HeaderBytes+1]=#$B8) and
    (AddImage[HeaderBytes+6]=#$05),
    'машинний пролог вже злитих emitter-ів змінився');
  OldLength:=Length(AddImage);
  Need(OldLength<1024*1024-SubBytes,'ELF перевищує квоту');
  Result:=Copy(AddImage,1,HeaderBytes)+
    Copy(SubImage,HeaderBytes+1,MovBytes+SubBytes)+
    Copy(AddImage,HeaderBytes+MovBytes+1,
      OldLength-HeaderBytes-MovBytes);
  Need(Length(Result)=OldLength+SubBytes,'втрачено байти машинного образу');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and (FinalGeometry.Entry=HeaderBytes) and
    (FinalGeometry.FileBytes=Length(Result)),
    'невдалий допуск складеного машинного ELF64');
end;
end.
