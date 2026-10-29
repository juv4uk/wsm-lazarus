{ G6.83 — один x86-64 ELF64 з двох реально виконуваних операцій D12.
  Композиція ADD→NEG є host-механізмом, НЕ SENS resident чи закон.
  Домен та арифметика допускаються лише pinned числовими операціями.
  Питання: чому результат не можна взяти з precomputed literal?
  Чому проміжне D24 не можна відкинути? Чому RIP таблиці не міняють
  displacement? Чому перевірки точної фізичної ширини перед емісією? }
unit wsm.elfd12addneg;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12AddNegError=class(Exception);
function BuildD12AddNegELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.numericplane,wsm.numericadd,wsm.numericmul,
     wsm.elfd12add,wsm.elfd12neg,wsm.elfd12promote,wsm.elfgeometry;
const HeaderBytes=120; MovBytes=5; AddBytes=5; NegBytes=2;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ED12AddNegError.Create(Why) end;

{ Image — власний managed ELF64; Offset — host координата, НЕ SENS.
  p_filesz та p_memsz зсуваються разом з кодом; LEA та таблиці
  рухаються разом, тому RIP displacement не змінюється.
  Питання: чому запис little endian? Чому перевірка меж? Чому
  96 і 104 — ELF поля, а не мовні слоти? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset+8<=Length(Image)),'ELF поле поза образом');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ Borrowed canonical packed D12 atoms => OWNED executable ELF.
  Гілка 1: сума W12 — беремо чинний ADD і замінюємо тільки MOV
  з чинного NEG emitter десятьма байтами MOV+ADD. Далі NEG та
  byte-exact T5M writer без жодного повторного host evaluator.
  Гілка 2: сума W24 — беремо чинний promoted ADD і перед writer
  вставляємо лише два машинні байти NEG. Після вставки LEA і T5M
  lookup-таблиці зсуваються на однакову довжину.
  Expected не записується в ELF: тільки admission ширини із
  ратифікованих AddNumericPhysical і MultiplyNumericPhysical.
  Питання: що робить CPU при -2048 + 0? Що при 2047 + 1?
  Чому W12->W24 через NEG не можна вважати wrapped W12?
  Чому всі машинні байти узгоджуємо з уже перевіреними emitter?
  Чому вихід перевіряє незалежний SENS REPL? }
function BuildD12AddNegELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var Sum,NegativeOne,Expected,AddImage,NegImage:RawByteString;
    SumWidth,ResultWidth:SizeInt; Inspect:TExplicitNumeric;
    AddGeometry,NegGeometry,FinalGeometry:TELFGeometry;
begin
  Result:='';
  { Параметр 12 є ЯВНИМ, а не виведеним із тексту чи байтової довжини. }
  Inspect:=ReadNumericPhysical(LeftPhysical,12);
  Need(Inspect.DomainWidth=12,'лівий атом не D12');
  Inspect:=ReadNumericPhysical(RightPhysical,12);
  Need(Inspect.DomainWidth=12,'правий атом не D12');
  Sum:=AddNumericPhysical(LeftPhysical,RightPhysical,12);
  try
    Inspect:=ReadNumericPhysical(Sum,12); SumWidth:=12;
  except
    on ENumericPlaneError do begin
      Inspect:=ReadNumericPhysical(Sum,24); SumWidth:=24;
    end;
  end;
  Need(Inspect.DomainWidth=SumWidth,'невідома ширина проміжної суми');
  NegativeOne:=EncodeNumericDecimal('-1',SumWidth);
  Expected:=MultiplyNumericPhysical(NegativeOne,Sum,SumWidth);
  try
    Inspect:=ReadNumericPhysical(Expected,12); ResultWidth:=12;
  except
    on ENumericPlaneError do begin
      Inspect:=ReadNumericPhysical(Expected,24); ResultWidth:=24;
    end;
  end;
  Need((ResultWidth in [12,24]) and (Inspect.DomainWidth=ResultWidth),
       'неприпустима ширина фінального D12/D24');

  if SumWidth=12 then begin
    AddImage:=BuildD12AddELF(LeftPhysical,RightPhysical);
    NegImage:=BuildD12NegELF(Sum);
    VerifySENSELF64(AddImage,AddGeometry);
    VerifySENSELF64(NegImage,NegGeometry);
    Need((AddGeometry.Kind=3) and (NegGeometry.Kind=3) and
         (AddGeometry.Entry=HeaderBytes) and (NegGeometry.Entry=HeaderBytes),
         'потрібні перевірені ELF64 PIE профілі');
    Need((Length(AddImage)>=HeaderBytes+MovBytes+AddBytes) and
         (Length(NegImage)>=HeaderBytes+MovBytes+NegBytes) and
         (AddImage[HeaderBytes+1]=#$B8) and
         (AddImage[HeaderBytes+6]=#$05) and
         (NegImage[HeaderBytes+1]=#$B8) and
         (NegImage[HeaderBytes+6]=#$F7) and
         (NegImage[HeaderBytes+7]=#$D8),
         'змінено перевірений MOV/ADD/NEG префікс');
    Result:=Copy(NegImage,1,HeaderBytes)+
      Copy(AddImage,HeaderBytes+1,MovBytes+AddBytes)+
      Copy(NegImage,HeaderBytes+MovBytes+1,
           Length(NegImage)-HeaderBytes-MovBytes);
    Need(Length(Result)=Length(NegImage)+AddBytes,
         'помилка довжини складеного ELF');
  end else begin
    Need(ResultWidth=24,'широка сума не повинна звузитися до D12');
    AddImage:=BuildD12PromotedAddELF(LeftPhysical,RightPhysical);
    VerifySENSELF64(AddImage,AddGeometry);
    Need((AddGeometry.Kind=3) and (AddGeometry.Entry=HeaderBytes) and
         (Length(AddImage)>=HeaderBytes+MovBytes+AddBytes+4) and
         (AddImage[HeaderBytes+1]=#$B8) and
         (AddImage[HeaderBytes+6]=#$05) and
         (AddImage[HeaderBytes+11]=#$48),
         'змінено verified promoted ADD або його стековий пролог');
    Result:=Copy(AddImage,1,HeaderBytes+MovBytes+AddBytes)+
      #$F7#$D8+
      Copy(AddImage,HeaderBytes+MovBytes+AddBytes+1,
           Length(AddImage)-HeaderBytes-MovBytes-AddBytes);
    Need(Length(Result)=Length(AddImage)+NegBytes,
         'помилка довжини розширеного ELF');
  end;
  Need(Length(Result)<1024*1024,'завеликий ELF64');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and (FinalGeometry.Entry=HeaderBytes)
       and (FinalGeometry.FileBytes=Length(Result)),
       'складений ELF64 не пройшов перевірку геометрії');
end;
end.
