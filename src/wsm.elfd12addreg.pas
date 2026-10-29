{ G6.96 — машинна інтеграція спільного ALU в чинний D12 ADD.
  ЖОДНОГО нового SENS закону, доменного dispatch чи другої таблиці T5M.
  BuildD12AddELF спочатку здійснює повне точне числове admission і
  випускає вже перевірений ELF. Міняємо ВИКЛЮЧНО 10 байтів прологу:
  B8 imm32; 05 imm32 -> B8 imm32; B9 imm32; 01 C8.
  RIP-relative LEA та обидві таблиці рухаються разом на +2 байти,
  тому їхні ЗАПИСАНІ 32-bit rel-значення залишаються незмінні.
  Вхід: borrowed фізичні packed T5M D12 атоми; вихід: власний managed
  ELF64 ET_DYN; при помилці жодних часткових байтів не публікується.
  1) Хто виконує числову семантику/перевіряє D12→D24?
  2) Чому можна зберегти RIP-rel displacement?
  3) Чому машинні MOV/ADD не є власним реєстром D5?
  4) Чому p_filesz і p_memsz змінюються разом?
  5) Чим фізичний T5M відрізняється від host immediate? }
unit wsm.elfd12addreg;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type ED12RegisterELFError=class(Exception);
function BuildD12RegisterAddELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
implementation
uses wsm.elfd12add,wsm.elfgeometry,wsm.x64code,wsm.x64alu;
const HeaderBytes=120; OldPrefixBytes=10; NewPrefixBytes=12;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise ED12RegisterELFError.Create(Why);
end;

function ReadLE32(const Bytes:RawByteString;Off:SizeInt):LongWord;
var J:SizeInt;
begin
  Need((Off>=0) and (Off<=Length(Bytes)-4),'вийшли за машинний immediate');
  Result:=0;
  for J:=3 downto 0 do
    Result:=(Result shl 8) or LongWord(Byte(Bytes[Off+J+1]));
end;

procedure PutLE64(var Bytes:RawByteString;Off:SizeInt;Val:QWord);
var J:SizeInt;
begin
  Need((Off>=0) and (Off<=Length(Bytes)-8),'поза ELF розміром');
  for J:=0 to 7 do begin
    Bytes[Off+J+1]:=AnsiChar(Byte(Val and $FF));
    Val:=Val shr 8;
  end;
end;

function BuildD12RegisterAddELF(const LeftPhysical,RightPhysical:RawByteString):RawByteString;
var OldImage,Head:RawByteString; G:TELFGeometry; Writer:TX64Code;
    LeftImm,RightImm:LongWord;
begin
  Result:='';
  { Успішне повернення означає, що original admission і numeric
    overflow guard вже пройдено. Ніяких host законів D12 тут немає. }
  OldImage:=BuildD12AddELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(OldImage,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (Length(OldImage)>HeaderBytes+OldPrefixBytes+36),
       'попередній ELF64 не відповідає перевіреному профілю');
  Need((OldImage[HeaderBytes+1]=#$B8) and
       (OldImage[HeaderBytes+6]=#$05) and
       (OldImage[HeaderBytes+11]=#$25),
       'змінився пролог D12 ADD: відмова без машинного патчу');
  LeftImm:=ReadLE32(OldImage,HeaderBytes+1);
  RightImm:=ReadLE32(OldImage,HeaderBytes+6);
  X64Reset(Writer);
  X64MovImm32(Writer,xrAX,LeftImm);
  X64MovImm32(Writer,xrCX,RightImm);
  X64ALU32(Writer,xaAdd,xrAX,xrCX);
  Head:=X64Image(Writer);
  Need((Length(Head)=NewPrefixBytes) and (Head[11]=#$01) and
       (Head[12]=#$C8),'host ALU не породив точний ADD EAX,ECX');

  Result:=Copy(OldImage,1,HeaderBytes)+Head+
          Copy(OldImage,HeaderBytes+OldPrefixBytes+1,
               Length(OldImage)-HeaderBytes-OldPrefixBytes);
  Need(Length(Result)=Length(OldImage)+NewPrefixBytes-OldPrefixBytes,
       'нова фізична довжина ELF неправильна');
  PutLE64(Result,96,QWord(Length(Result)));
  PutLE64(Result,104,QWord(Length(Result)));
  { Усі rel32 у хвості залишаються точними: відстані до lookup
    таблиць не змінено, зміщено лише початок коду та таблиці. }
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)),'оновлений ELF64 не пройшов guard');
end;
end.
