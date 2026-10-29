{ G6.92 — один фізичний D12×D12+ D12 як справжній машинний ELF64.
  Вузький host AOT-механізм, НЕ нова SENS функція. Мовні закони,
  точні домени та D24-просування допускають чинні numeric механізми
  з pinned SENS Contract 12.0. Цей модуль НЕ виконує арифметику SENS:
  її результат під час запуску ELF обчислює справжній IMUL→ADD. }
unit wsm.elfd12muladd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12MulAddError=class(Exception);
function BuildD12MulAddELF(const First,Second,Third:RawByteString):RawByteString;
implementation
uses wsm.numericplane,wsm.numericmul,wsm.numericadd,
     wsm.elfd12mul,wsm.elfd12add,wsm.elfd12promote,wsm.elfgeometry;
const HeaderBytes=120; MOVBytes=5; IMULBytes=6;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise ED12MulAddError.Create(Why) end;

{ Image — owned mutable bytes ELF; Offset — zero-based ELF byte position,
  Value — host unsigned little-endian field, НЕ SENS numeral/slot.
  Переписуються тільки p_filesz і p_memsz, не machine semantics.
  Питання: чому сегмент має RX, а стек RW?
  Чому обидва ELF розміри треба синхронізувати?
  Чому 96/104 є ELF координатами, не номером домену? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),
    'поле ELF поза фізичним образом');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ First/Second/Third — borrowed exact canonical packed D12 T5M атоми.
  Product/Sum — owned тимчасові packed числові значення, ТІЛЬКИ для
  перевірки допуску й ширини. Жоден очікуваний результат не записаний
  у машинний образ. Реальне x86-64: MOV EAX,imm32; IMUL EAX,EAX,imm32;
  ADD EAX,imm32; encoder/T5M writer другого вже злитого emitter.
  П'ятибайтовий MOV у готовому ADD ELF замінюється 11-байтовим
  MOV+IMUL. Вставка +6 байтів ПЕРЕД першим RIP-relative LEA та
  таблицями, тому displacement лишається точним; перевірка пізніше.
  Питання: чому не можна сумістити два ELF шляхом конкатенації?
  Чому D24 проміжний добуток не можна мовчки перетворити в D12?
  Чому D24 фінальна сума має власну T5M таблицю?
  Чому результати звіряємо окремим pinned SENS CLI на .sens джерелі?
  Чому немає ні D7-імен, ні власного реєстру законів? }
function BuildD12MulAddELF(const First,Second,Third:RawByteString):RawByteString;
var Product,Sum,MulImage,AddImage:RawByteString;
    ProductValue,SumValue:TExplicitNumeric;
    MulGeometry,AddGeometry,FinalGeometry:TELFGeometry;
    ResultWidth,FinalSize:SizeInt;
begin
  Result:='';
  ReadNumericPhysical(First,12);
  ReadNumericPhysical(Second,12);
  ReadNumericPhysical(Third,12);
  Product:=MultiplyNumericPhysical(First,Second,12);
  ProductValue:=ReadNumericPhysical(Product,12);
  Need((ProductValue.DomainWidth=12) and (Length(ProductValue.ExactBits)=12),
    'проміжне D12 множення вимагає D24 — unsupported fail-closed');
  Sum:=AddNumericPhysical(Product,Third,12);
  try
    SumValue:=ReadNumericPhysical(Sum,12);ResultWidth:=12;
  except on ENumericPlaneError do begin
    SumValue:=ReadNumericPhysical(Sum,24);ResultWidth:=24;
  end end;
  Need((SumValue.DomainWidth=ResultWidth) and
       (Length(SumValue.ExactBits)=ResultWidth),
    'неприпустиме D12/D24 просування фінальної суми');
  { Усі машинні байти беремо тільки із ЗЛИТИХ перевірених emitter.
    MulImage може створювати ELF лише для exact D12 добутку. }
  MulImage:=BuildD12MulELF(First,Second);
  if ResultWidth=12 then AddImage:=BuildD12AddELF(Product,Third)
  else AddImage:=BuildD12PromotedAddELF(Product,Third);
  VerifySENSELF64(MulImage,MulGeometry);
  VerifySENSELF64(AddImage,AddGeometry);
  Need((MulGeometry.Kind=3) and (AddGeometry.Kind=3) and
       (MulGeometry.Entry=HeaderBytes) and
       (AddGeometry.Entry=HeaderBytes),
    'потрібні два реально перевірені Linux ELF64 PIE emitter');
  Need((Length(MulImage)>=HeaderBytes+MOVBytes+IMULBytes) and
       (Length(AddImage)>=HeaderBytes+MOVBytes+5) and
       (MulImage[HeaderBytes+1]=#$B8) and
       (MulImage[HeaderBytes+6]=#$69) and
       (MulImage[HeaderBytes+7]=#$C0) and
       (AddImage[HeaderBytes+1]=#$B8) and
       (AddImage[HeaderBytes+6]=#$05),
    'неочікуваний x86 MOV/IMUL/ADD префікс — fail closed');
  FinalSize:=Length(AddImage)+IMULBytes;
  Need((FinalSize>HeaderBytes+30) and (FinalSize<1024*1024),
    'вихідний ELF за квотою');
  Result:=Copy(AddImage,1,HeaderBytes)+
    Copy(MulImage,HeaderBytes+1,MOVBytes+IMULBytes)+
    Copy(AddImage,HeaderBytes+MOVBytes+1,
         Length(AddImage)-HeaderBytes-MOVBytes);
  Need(Length(Result)=FinalSize,'порушена довжина машинної композиції');
  PutLE64(Result,96,FinalSize); { PT_LOAD.p_filesz }
  PutLE64(Result,104,FinalSize);{ PT_LOAD.p_memsz }
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and
       (FinalGeometry.Entry=HeaderBytes) and
       (FinalGeometry.FileBytes=FinalSize),
    'складений x86-64 ELF64 PIE не пройшов фізичний guard');
end;
end.
