{ G6.26 — фізичний T5M вихід машинного D3:100/011 над D3:111.
  Жодного дублювання SENS законів: вхід уже допускає чинний
  BuildSelectorELF з pinned T5M/D2/domain binder і native D3 executor.
  Цей модуль лише перевіряє машинний шаблон і змінює stdout transport. }
unit wsm.elfselectort5m;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfSelectorT5MError=class(Exception);
function BuildSelectorT5MELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.elfselector,wsm.t5m,wsm.elfwriteguard;
const
  HeaderBytes=120;
  OriginalMachineBytes=75;

function BuildSelectorT5MELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Image,Code,Expected,Machine,Zero,One:RawByteString;
  Values:TExactWords;
  LeftBit,RightBit,Offset,Delta:Byte;
  Total,I:SizeInt;

  function GetLE(At,N:SizeInt):QWord;
  var J:SizeInt;
  begin
    if (At<0) or (N<1) or (N>8) or (At>Length(Image)-N) then
      raise EElfSelectorT5MError.Create('Пошкоджена геометрія базового ELF');
    Result:=0;
    for J:=N-1 downto 0 do
      Result:=(Result shl 8) or Byte(Image[At+J+1]);
  end;

  procedure PutLE(At:SizeInt; Value:QWord; N:SizeInt);
  var J:SizeInt;
  begin
    if (At<0) or (N<1) or (N>8) or (At>Length(Result)-N) then
      raise EElfSelectorT5MError.Create('Порушена межа фізичного ELF');
    for J:=0 to N-1 do begin
      Result[At+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';
  try
    { Наявний emitter повністю перевіряє pinned координати та виконує
      допустиму форму тим самим native D3 executor ДО нашої упаковки. }
    Image:=BuildSelectorELF(Physical,AuthorityRoot);
    if (Length(Image)<>HeaderBytes+OriginalMachineBytes) or
       (Copy(Image,1,4)<>#$7F'ELF') or
       (GetLE(4,1)<>2) or (GetLE(5,1)<>1) or
       (GetLE(16,2)<>2) or (GetLE(18,2)<>62) or
       (GetLE(24,8)<>$400000+HeaderBytes) or
       (GetLE(32,8)<>64) or (GetLE(52,2)<>64) or
       (GetLE(54,2)<>56) or (GetLE(56,2)<>1) or
       (GetLE(64,4)<>1) or (GetLE(68,4)<>5) or
       (GetLE(80,8)<>$400000) or (GetLE(88,8)<>$400000) or
       (GetLE(96,8)<>QWord(Length(Image))) or
       (GetLE(104,8)<>QWord(Length(Image))) or
       (GetLE(112,8)<>$1000) then
      raise EElfSelectorT5MError.Create('Змінилася геометрія перевіреного ELF');

    Code:=Copy(Image,HeaderBytes+1,OriginalMachineBytes);
    LeftBit:=Byte(Code[2]);
    RightBit:=Byte(Code[7]);
    Offset:=Byte(Code[31]);
    if (LeftBit>1) or (RightBit>1) or
       ((Offset<>0) and (Offset<>8)) then
      raise EElfSelectorT5MError.Create('Невірні машинні D1-поля або адреса CONS');

    { Доводимо ВСІ 75 байтів базового ELF, а не лише характерні
      інструкції. Два QWord справді зберігаються в стековій CONS-парі,
      а селектор дістає фізичне значення з [rsi+0] або [rsi+8]. }
    Expected:=
      #$B8+AnsiChar(LeftBit)+#0#0#0+
      #$B9+AnsiChar(RightBit)+#0#0#0+
      #$48#$83#$EC#$10+
      #$48#$89#$04#$24+
      #$48#$89#$4C#$24#$08+
      #$48#$8D#$34#$24+
      #$48#$8B#$56+AnsiChar(Offset)+
      #$80#$C2#$30+
      #$48#$83#$EC#$08+
      #$88#$14#$24+
      #$C6#$44#$24#$01#$0A+
      #$B8#$01#0#0#0+
      #$BF#$01#0#0#0+
      #$48#$89#$E6+
      #$BA#$02#0#0#0+
      #$0F#$05+
      #$B8#$3C#0#0#0+
      #$31#$FF#$0F#$05;
    if (Length(Expected)<>OriginalMachineBytes) or (Code<>Expected) then
      raise EElfSelectorT5MError.Create('Машинний шаблон CONS/селектор змінився');

    { Фізичні 0/1 кодує тільки наявний канонічний T5M codec. }
    SetLength(Values,1);
    Values[0]:='0'; Zero:=EncodeT5M(Values);
    Values[0]:='1'; One:=EncodeT5M(Values);
    if (Length(Zero)<>1) or (Length(One)<>1) or
       (Byte(Zero[1])>127) or (Byte(One[1])<=Byte(Zero[1])) or
       (Byte(One[1])-Byte(Zero[1])>127) then
      raise EElfSelectorT5MError.Create('Змінено фізичний D1 T5M codec');
    Delta:=Byte(One[1])-Byte(Zero[1]);

    { Після машинного mov rdx,[rsi+offset] значення — точне D1 0/1.
      imul edx,edx,Delta; add edx,Zero — T5M-байт, не ASCII.
      Відповідь НЕ обчислюємо в Pascal, machine memory CONS збережена.
      Потім Linux write(1,rsp,1), і лише повний syscall-результат
      дозволяє host exit(0); це не закон D3. }
    Machine:=Copy(Code,1,31)+
      #$6B#$D2+AnsiChar(Delta)+
      #$83#$C2+Zero[1]+
      #$48#$83#$EC#$08+
      #$88#$14#$24+
      #$B8#$01#0#0#0+
      #$BF#$01#0#0#0+
      #$48#$89#$E6+
      #$BA#$01#0#0#0+
      #$0F#$05+
      #$B8#$3C#0#0#0+
      #$31#$FF#$0F#$05;
    if Length(Machine)<>73 then
      raise EElfSelectorT5MError.Create('Неочікувана довжина машинної програми');

    Total:=HeaderBytes+Length(Machine);
    SetLength(Result,Total);
    for I:=1 to HeaderBytes do Result[I]:=Image[I];
    for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];

    { Machine code адресується лише через rsp та регістри, тому
      виконується також як ET_DYN із базою 0, без PT_INTERP/relocation.
      Під час допуску жоден частковий ELF не публікується. }
    PutLE(16,3,2);
    PutLE(24,HeaderBytes,8);
    PutLE(80,0,8);
    PutLE(88,0,8);
    PutLE(96,Total,8);
    PutLE(104,Total,8);

    { Позичений фізичний PIE вже має перевірений машинний epilogue
      «sys_write; mov eax,60; xor edi,edi; syscall».
      Спільний bounded postpass зберігає код CONS/селектор та міняє
      лише завершення на перевірку повного 1-байтового T5M запису.
      Результат — новий owned RawByteString ELF64; немає часткового
      ELF у разі host-помилки, pinned семантика D3 незмінна.
      1) Чому саме один фізичний байт T5M?
      2) Чому Linux sys_write може повернути -ENOSPC або -EBADF?
      3) Чому не дублюємо writer у цьому selector backend?
      4) Чому host exit code не є SENS D1? }
    Result:=RequireCompleteNativeWrite(Result);
  except
    on E:EElfSelectorT5MError do raise;
    on E:Exception do raise EElfSelectorT5MError.Create(
      'Машинний фізичний селектор відхилено: '+E.Message);
  end;
end;

{ Типи та час життя:
  Physical/AuthorityRoot — незмінні байтові рядки; Image/Code/Machine —
  приватні reference-counted host буфери, звільняються при виході.
  В машині пара має 2*QWord на стеку до SYS_exit; результат — 1 T5M байт.
  Результат BuildSelectorT5MELF — цілий ELF64 ET_DYN, НЕ SENS програма.
  Питання на розуміння:
  1. Чому GetLE перевіряє старий ELF до зміни транспортних байтів?
  2. Чому selector читає дві QWord комірки, а не готову Pascal відповідь?
  3. Чому 0x50/0xA1 отримуємо через EncodeT5M?
  4. Чому ET_DYN тут не свідчить про повну підтримку Core4? }
end.
