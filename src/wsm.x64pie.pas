{ G6.244 — спільний host-only конструктор Linux x86-64 ELF64 PIE.
  Вхід: позичений TX64Code (RawByteString машинного коду, 1..256 байтів),
  який уже згенерував codegen; функція НЕ розбирає SENS, .sens, D7 або D12.
  Вихід: власний RawByteString ELF64 ET_DYN: рівно 120 байтів ELF/PHDR
  і всі машинні байти без жодної їх зміни, один RX PT_LOAD, entry=120.
  На винятку немає публікації часткового ELF; borrowed Code не змінено.
  Lifetime машинного стека/регістрових значень визначає caller, не ELF.
  Цей модуль НЕ перевіряє ISA, поведінку sys_write чи коректність SENS.
  Для них існують незалежний GNU as, native tests та pinned SENS oracle.
  Питання: 1) Чому ET_DYN має базу p_vaddr=0, на відміну від ET_EXEC?
  2) Чому ELF64 має програмний заголовок з 56 байтів, а не секції?
  3) Чому точне машинне тіло копіюємо без трансляції доменів?
  4) Чому геометрію перевіряємо перед публікацією результату?
  5) Чому 256 — host квота кодера, а не закон SENS Dn? }
unit wsm.x64pie;
{$mode objfpc}{$H+}
interface
uses SysUtils,wsm.x64code;
type EX64PIEError=class(Exception);
function BuildX64PIE(const Code:TX64Code):RawByteString;

implementation
uses wsm.elfgeometry;
const HeaderBytes=120;
      MaxMachineBytes=256;

procedure Need(Good:Boolean;const Why:String);
begin
  if not Good then raise EX64PIEError.Create(Why);
end;

{ Поле At — нульова адреса HOST ELF, Count — число host байтів,
  Value — малий little-endian host integer, не SENS числовий домен.
  Candidate — належний builder, публікується лише після валідації.
  1) Чому перевірка діапазону передує запису?
  2) Що гарантує порядок little endian?
  3) Де межа між машинним форматом і мовним контрактом? }
procedure PutLE(var Candidate:RawByteString;At:SizeInt;
                Value:QWord;Count:SizeInt);
var I:SizeInt;
begin
  Need((At>=0) and (Count>=1) and (Count<=8) and
       (At<=Length(Candidate)-Count),
       'PIE: поле ELF64 поза фізичним образом');
  for I:=0 to Count-1 do begin
    Candidate[At+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

function BuildX64PIE(const Code:TX64Code):RawByteString;
var Candidate:RawByteString;
    Geometry:TELFGeometry;
    N:SizeInt;
begin
  Result:='';
  N:=Length(Code.Bytes);
  Need((N>=1) and (N<=MaxMachineBytes),
       'PIE: потрібні 1..256 перевірених host machine bytes');
  SetLength(Candidate,HeaderBytes+N);
  FillChar(Candidate[1],Length(Candidate),0);
  { Ті самі машинні поля, що і перевірений профіль wsm.elfgeometry.
    Немає program interpreter/sections, relocation чи offset patching. }
  PutLE(Candidate,0,$464C457F,4);        { ELFMAG }
  PutLE(Candidate,4,2,1);                { ELFCLASS64 }
  PutLE(Candidate,5,1,1);                { little endian }
  PutLE(Candidate,6,1,1);                { ident version }
  PutLE(Candidate,16,3,2);               { ET_DYN / PIE }
  PutLE(Candidate,18,62,2);              { EM_X86_64 }
  PutLE(Candidate,20,1,4);               { EV_CURRENT }
  PutLE(Candidate,24,HeaderBytes,8);     { e_entry }
  PutLE(Candidate,32,64,8);              { program header offset }
  PutLE(Candidate,52,64,2);              { e_ehsize }
  PutLE(Candidate,54,56,2);              { e_phentsize }
  PutLE(Candidate,56,1,2);               { e_phnum }
  PutLE(Candidate,64,1,4);               { PT_LOAD }
  PutLE(Candidate,68,5,4);               { PF_R | PF_X }
  PutLE(Candidate,96,Length(Candidate),8);  { p_filesz }
  PutLE(Candidate,104,Length(Candidate),8); { p_memsz }
  PutLE(Candidate,112,$1000,8);            { p_align }
  Move(Code.Bytes[1],Candidate[HeaderBytes+1],N);
  VerifySENSELF64(Candidate,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=HeaderBytes) and
       (Geometry.FileBytes=HeaderBytes+N) and
       (Geometry.MachineBytes=N) and
       (Copy(Candidate,HeaderBytes+1,N)=Code.Bytes),
       'PIE: втрачено точні машинні байти чи геометрію');
  Result:=Candidate;
end;
end.
