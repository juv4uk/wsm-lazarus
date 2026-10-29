{ G6.25 — машинне D3:101 повертає ФІЗИЧНИЙ T5M, не ASCII.
  Всі мовні допуски належать уже перевіреному pinned wsm.elfeq;
  цей unit замінює лише Linux stdout transport. }
unit wsm.elfeqt5m;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfEqT5MError=class(Exception);
function BuildEqT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.elfeq,wsm.t5m;
const HeaderBytes=120;
function BuildEqT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Image,Machine,EncodedZero,EncodedOne:RawByteString;
  Words:TExactWords;
  Total,I:SizeInt;
  Delta:Byte;
  procedure PutSize(Offset:SizeInt;Size:QWord);
  var J:SizeInt;
  begin
    if (Offset<0) or (Offset>Length(Result)-8) then
      raise EElfEqT5MError.Create('Пошкоджена межа ELF');
    for J:=0 to 7 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(Size and $FF));
      Size:=Size shr 8;
    end;
  end;
begin
  Result:='';
  try
    { BuildEqPIE повторно використовує канонічний T5M/D2, pinned
      exact-domain binder, виконання D3 і перевірку ВСІХ 61 машинних
      байтів CMP/SETE. ET_DYN не містить host-адрес і relocation. }
    Image:=BuildEqPIE(Physical,AuthorityRoot);
    if (Length(Image)<>HeaderBytes+61) or (Ord(Image[17])<>3) or
       (Copy(Image,121,1)<>#$B8) or
       (Copy(Image,126,1)<>#$B9) or
       (Copy(Image,131,8)<>#$39#$C8#$0F#$94#$C0#$0F#$B6#$C0) then
      raise EElfEqT5MError.Create('Змінено перевірений машинний шаблон D3:101');
    { Транспортні байти обчислюються чинним codec, а не вгадуються
      з числової інтерпретації домену. Два відомі виходи D1 — 0/1.
      Лише РІЗНИЦЯ стає imm8 для множення машинного результату. }
    SetLength(Words,1);
    Words[0]:='0'; EncodedZero:=EncodeT5M(Words);
    Words[0]:='1'; EncodedOne:=EncodeT5M(Words);
    if (Length(EncodedZero)<>1) or (Length(EncodedOne)<>1) or
       (Ord(EncodedZero[1])>127) or
       (Ord(EncodedOne[1])<=Ord(EncodedZero[1])) or
       (Ord(EncodedOne[1])-Ord(EncodedZero[1])>127) then
      raise EElfEqT5MError.Create('Однобайтова T5M проєкція D1 змінилася');
    Delta:=Ord(EncodedOne[1])-Ord(EncodedZero[1]);
    { Вхід: EAX=0/1 після реального CMP/SETE/MOVZX x86-64.
      imul eax,eax,Delta; add eax,EncodedZero; запис AL — один
      канонічний фізичний T5M байт, НЕ текст і НЕ число D12.
      Стек: тимчасові 8 host-байтів від sub rsp до sys_exit,
      ніякого heap allocation в машинному коді. }
    Machine:=Copy(Image,HeaderBytes+1,18)+
      #$6B#$C0+AnsiChar(Delta)+
      #$83#$C0+EncodedZero[1]+
      #$48#$83#$EC#$08+#$88#$04#$24+
      #$B8#$01#0#0#0+#$BF#$01#0#0#0+
      #$48#$89#$E6+#$BA#$01#0#0#0+
      #$0F#$05+#$B8#$3C#0#0#0+#$31#$FF#$0F#$05;
    if (Length(Machine)<40) or (Length(Machine)>128) then
      raise EElfEqT5MError.Create('Машинний T5M код поза межею');
    Total:=HeaderBytes+Length(Machine);
    SetLength(Result,Total);
    for I:=1 to HeaderBytes do Result[I]:=Image[I];
    for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
    { ELF64 єдина RX-ділянка: p_filesz/p_memsz змінюються транзакційно
      разом із реальним машинним payload. Entry offset 120 незмінний. }
    PutSize(96,QWord(Total));
    PutSize(104,QWord(Total));
  except
    on E:EElfEqT5MError do raise;
    on E:Exception do raise EElfEqT5MError.Create(
      'Машинний T5M-зріз відхилено: '+E.Message);
  end;
end;
{ Перевірка розуміння:
  1. Чому точна тотожність D1 доводиться до генерації ELF?
  2. Чому байти 0/1 беруться з EncodeT5M, а не з ASCII?
  3. Яка машинна інструкція обчислює результат рівності під час запуску?
  4. Чому зміна ELF p_filesz не змінює мовний закон SENS? }
end.
