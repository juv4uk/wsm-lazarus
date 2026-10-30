{ G6.102 — лише машинний стековий кодер Linux x86-64.
  Чинний TX64Code зберігає власний managed RawByteString, квота 256 байтів.
  Кодер не інтерпретує Dn, .sens, українські проєкції чи закони SENS.
  Кожна відмова лишає вхідний буфер незмінним.

  Питання: 1) Чому PUSH/POP RSP заборонені для цього механізму?
  2) Чому ABI alignment не доводиться одним кодувальником?
  3) Чому вибір imm8/imm32 залежить від signed-діапазону?
  4) Чому відмова повинна передувати конкатенації буфера?
  5) Хто володіє байтами TX64Code після повернення? }
unit wsm.x64stack;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.x64code;

procedure X64StackPush(var Code:TX64Code; Reg:TX64Reg);
procedure X64StackPop(var Code:TX64Code; Reg:TX64Reg);
procedure X64StackSubtract(var Code:TX64Code; Bytes:SizeInt);
procedure X64StackAdd(var Code:TX64Code; Bytes:SizeInt);
procedure X64StackStore(var Code:TX64Code; Reg:TX64Reg; Offset:SizeInt);
procedure X64StackLoad(var Code:TX64Code; Reg:TX64Reg; Offset:SizeInt);

implementation
const MaxHostBytes=256;
      MaxStackDelta=4096;

procedure Need(Good:Boolean;const Why:String);
begin
  if not Good then raise EX64CodeError.Create(Why);
end;

procedure Append(var Code:TX64Code;const Part:RawByteString);
begin
  Need((Length(Part)>0) and (Length(Part)<=MaxHostBytes) and
       (Length(Code.Bytes)<=MaxHostBytes-Length(Part)),
       'стек: перевищено host-квоту 256 байтів');
  Code.Bytes:=Code.Bytes+Part;
end;

procedure NeedDataReg(Reg:TX64Reg);
begin
  Need((Ord(Reg)>=0) and (Ord(Reg)<=7) and (Reg<>xrSP),
       'стек: недопустимий host-регістр RSP або поза r0..r7');
end;

{ PUSH/POP: позичений Code; запис одного байта лише після всіх перевірок.
  RSP не допускаємо, бо його спеціальна поведінка руйнує очікування
  caller-а щодо життєвого циклу кадру. Це host policy, не SENS закон. }
procedure X64StackPush(var Code:TX64Code;Reg:TX64Reg);
begin
  NeedDataReg(Reg);
  Append(Code,AnsiChar($50+Ord(Reg)));
end;

procedure X64StackPop(var Code:TX64Code;Reg:TX64Reg);
begin
  NeedDataReg(Reg);
  Append(Code,AnsiChar($58+Ord(Reg)));
end;

{ Слово Bytes — host кількість байтів, а не двійковий Dn атом.
  Операції з кадром допускають 8..4096 байтів, кратні восьми.
  Imm8 знак-розширюється: 128 мусить кодуватися через imm32.
  Питання: 1) Чому 128 не imm8? 2) Де перевірка квоти?
  3) Чи гарантує локальна операція правильну 16-byte ABI alignment? }
procedure Adjust(var Code:TX64Code;Bytes:SizeInt;Subtract:Boolean);
var Part:RawByteString;Op8,Op32:AnsiChar;Word32:LongWord;
begin
  Need((Bytes>=8) and (Bytes<=MaxStackDelta) and ((Bytes mod 8)=0),
       'стек: зміна RSP має бути кратною 8 у межах 8..4096');
  if Subtract then begin Op8:=#$EC;Op32:=#$EC end
  else begin Op8:=#$C4;Op32:=#$C4 end;
  if Bytes<=127 then
    Part:=#$48#$83+Op8+AnsiChar(Byte(Bytes))
  else begin
    Word32:=LongWord(Bytes);
    Part:=#$48#$81+Op32+
      AnsiChar(Byte(Word32 and $FF))+
      AnsiChar(Byte((Word32 shr 8) and $FF))+
      AnsiChar(Byte((Word32 shr 16) and $FF))+
      AnsiChar(Byte((Word32 shr 24) and $FF));
  end;
  Append(Code,Part);
end;

procedure X64StackSubtract(var Code:TX64Code;Bytes:SizeInt);
begin Adjust(Code,Bytes,True) end;

procedure X64StackAdd(var Code:TX64Code;Bytes:SizeInt);
begin Adjust(Code,Bytes,False) end;

{ G6: STORE для того самого ОБМЕЖЕНОГО spill-слота, що й LOAD.
  Існуючий x64code вже реалізує байти MOV [rsp+disp8],r64; тут
  лише однакові з LOAD умови [0..120], крок 8, заборона RSP та
  сильна гарантія: перевірки ПЕРЕД будь-яким записом Code.Bytes.
  Фрейм належить caller; без frame allocation це не адреса пам'яті.
  1) Чому 7 і 127 не є придатними spill offsets?
  2) Чому незмінний x64code використовується повторно?
  3) Чому output Code лишається незмінним за винятку?
  4) Чому spill slot не має SENS D12 закону? }
procedure X64StackStore(var Code:TX64Code;Reg:TX64Reg;Offset:SizeInt);
begin
  NeedDataReg(Reg);
  Need((Offset>=0) and (Offset<=120) and ((Offset mod 8)=0),
       'стек: збереження qword поза вирівняним disp8');
  X64StoreRspQword(Code,Reg,Offset);
end;

{ MOV r64,[rsp+disp8] — лише механічне завантаження qword.
  Offset 0..120 із кроком 8; без даних про allocation/lifetime кадру
  caller не має права вважати адресу безпечною. Буфер owned у Code.
  Питання: 1) Навіщо SIB 24 для RSP? 2) Чому offset=0 має mod=00?
  3) Чому не пишемо голови SENS за назвами регістрів?
  4) Як GNU as доводить правильність машинного формату? }
procedure X64StackLoad(var Code:TX64Code;Reg:TX64Reg;Offset:SizeInt);
var Part:RawByteString;
begin
  NeedDataReg(Reg);
  Need((Offset>=0) and (Offset<=120) and ((Offset mod 8)=0),
       'стек: зміщення qword поза вирівняним disp8');
  if Offset=0 then
    Part:=#$48#$8B+AnsiChar((Ord(Reg) shl 3) or $04)+#$24
  else
    Part:=#$48#$8B+AnsiChar($40 or (Ord(Reg) shl 3) or $04)+
      #$24+AnsiChar(Byte(Offset));
  Append(Code,Part);
end;
end.
