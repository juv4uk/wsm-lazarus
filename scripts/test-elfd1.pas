{ G6.8: механічні негативні/позитивні свідки справжнього ELF64.
  Значення літерала перевіряє чинний фізичний SENS evaluator. }
program test_elfd1;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.elfd1;
var
  Physical,Elf:RawByteString;
  Rejected:SizeInt;

function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then begin
    WriteLn(StdErr,UkrBytes('НАТИВНИЙ-ELF-ТЕСТ-ПОМИЛКА: '),Why);
    Halt(1);
  end;
end;

function WordsOf(const Items:array of RawByteString):TExactWords;
var J:SizeInt;
begin
  SetLength(Result,Length(Items));
  for J:=0 to High(Items) do Result[J]:=Items[J];
end;

procedure Save(const Path:String;const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data));
  finally S.Free; end;
end;

procedure Reject(const Words:TExactWords;const Why:String);
var Payload:RawByteString;Output:RawByteString;Seen:Boolean;
begin
  Payload:=EncodeT5M(Words);
  Seen:=False;Output:='';
  try Output:=BuildD1ELF(Payload,'external/sens');
  except on E:EELFD1Error do Seen:=True; end;
  Check(Seen and (Output=''),Why);
  Seen:=False; Output:='';
  try Output:=BuildD1PIE(Payload,'external/sens');
  except on E:EELFD1Error do Seen:=True; end;
  Check(Seen and (Output=''),Why+' (ET_DYN)');
  Inc(Rejected);
end;

procedure CheckELF(const Bits:RawByteString;const Path:String);
var P,Pie:RawByteString;N,J:SizeInt;
begin
  P:=EncodeT5M(WordsOf([Bits]));
  Save('build/m0.2/elfd1/'+String(Bits)+'.sens',P);
  N:=Length(P);
  Check((N=1) and
    ((Bits='0') and (Ord(P[1])=80) or
     (Bits='1') and (Ord(P[1])=161)),
    'золотий фізичний T5M D1');
  Elf:=BuildD1ELF(P,'external/sens');
  Check(Elf=BuildExactLiteralELF(P,'external/sens'),
    'нове API змінило золотий ELF D1');
  Check(Length(Elf)=172,'неправильна довжина мінімального ELF');
  Check((Copy(Elf,1,4)=#$7F'ELF') and
    (Ord(Elf[5])=2) and (Ord(Elf[6])=1),
    'не ELF64 little-endian');
  Check((Ord(Elf[17])=2) and (Ord(Elf[19])=62) and
    (Ord(Elf[57])=1),'ELF64 не ET_EXEC/x86-64/1 PT_LOAD');
  Check((Ord(Elf[65])=1) and (Ord(Elf[69])=5),
    'ELF PT_LOAD не RX');
  Check((Elf[171]=Bits[1]) and (Elf[172]=#10),
    'згенерований ELF не містить підтверджений D1 і LF');
  { G6.225: самі x86-64 opcode після syscall гарантують, що
    ні короткий host write, ні від'ємний -errno не дають exit(0).
    Це не змінює фізичний D1 T5M або pinned виконавця.
    Підтверджуємо 64-bit CMP RAX,RDX і точно 9-байтовий JNE.
    1) Чому EAX не досить для перевірки -errno?
    2) Чому Linux sys_write зберігає довжину у RDX?
    3) Чому PIE мусить мати той самий машинний код?
    4) Чому stderr не містить вигаданого D1 значення? }
  Check((Copy(Elf,145,5)=#$48#$39#$D0#$75#$09) and
    (Copy(Elf,150,9)=#$B8#$3C#0#0#0#$31#$FF#$0F#$05) and
    (Copy(Elf,159,12)=#$B8#$3C#0#0#0#$BF#$02#0#0#0#$0F#$05),
    'немає machine CMP RAX,RDX / JNE / Linux exit(2)');
  Save(Path,Elf);
  Pie:=BuildD1PIE(P,'external/sens');
  Check(Length(Pie)=172,'ET_DYN не має точних 172 байтів');
  Check((Ord(Pie[17])=3) and (Ord(Pie[18])=0) and
    (Ord(Pie[25])=120) and (Copy(Pie,26,7)=#0#0#0#0#0#0#0) and
    (Copy(Pie,81,16)=StringOfChar(#0,16)) and
    (Copy(Pie,121,50)=Copy(Elf,121,50)) and
    (Pie[171]=Bits[1]) and (Pie[172]=#10),
    'ET_DYN змінив opcode або не перемістив базу');
  { Тільки e_type, e_entry та два поля PT_LOAD відрізняються. }
  for J:=1 to Length(Pie) do
    if not ((J>=17) and (J<=18)) and
       not ((J>=25) and (J<=32)) and
       not ((J>=81) and (J<=96)) then
      Check(Pie[J]=Elf[J],'ET_DYN містить сторонню зміну шаблону');
  Save(Path+'.pie',Pie);
end;

procedure CheckEmptyD3;
var P,NativeELF:RawByteString;
begin
  P:=EncodeT5M(WordsOf(['000']));
  Check((Length(P)=1) and (Ord(P[1])=8),
    'фізична порожня координата D3:000 має інший T5M байт');
  Save('build/m0.2/elfd1/empty.sens',P);
  NativeELF:=BuildExactLiteralELF(P,'external/sens');
  Check(Length(NativeELF)=173,'порожній D3 має породити 173 байти ELF');
  Check((Copy(NativeELF,1,4)=#$7F'ELF') and
    (Ord(NativeELF[5])=2) and (Ord(NativeELF[6])=1) and
    (Ord(NativeELF[139])=3) and
    (Copy(NativeELF,145,5)=#$48#$39#$D0#$75#$09),
    'заголовок ELF або fail-closed sys_write D3');
  Check((Copy(NativeELF,171,3)='()'+#10),
    'неправильний вивід D3:000; D1:0 не дорівнює порожньому D3');
  Check(Length(NativeELF)<>172,'D3 і D1 ELF фізично сплутано');
  Save('build/m0.2/elfd1/empty.expected.elf',NativeELF);
end;

begin
  ForceDirectories('build/m0.2/elfd1');
  Rejected:=0;
  CheckELF('0','build/m0.2/elfd1/zero.expected.elf');
  CheckELF('1','build/m0.2/elfd1/one.expected.elf');
  CheckEmptyD3;
  Save('build/m0.2/elfd1/many.sens',
    EncodeT5M(WordsOf(['0','1'])));
  Save('build/m0.2/elfd1/quote.sens',
    EncodeT5M(WordsOf(['10','001','0','01'])));

  Reject(WordsOf(['000']),'D3:000 сплутано з D1:0');
  Reject(WordsOf(['10','0','01']),'D2 форма прийнята як D1');
  Reject(WordsOf(['0','1']),'два корені прийнято як один');
  Reject(WordsOf(['111']),'сторонній D3 прийнято як літерал');
  { Нове API не дозволяє будь-яку непорожню D3-координату. }
  Physical:=EncodeT5M(WordsOf(['111'])); Elf:='';
  try Elf:=BuildExactLiteralELF(Physical,'external/sens');
  except on E:EELFD1Error do begin Check(Elf='','сторонній D3 повернув ELF'); end; end;
  Check(Elf='','сторонній D3 не відхилено'); Inc(Rejected);
  Reject(WordsOf(['01']),'помилкова закривна D2 дужка');
  Reject(WordsOf(['10','0']),'незакритий список D2');
  Reject(WordsOf(['1111111111']),'непідтверджена ширина D10');
  Physical:=#$F3; Elf:=''; Inc(Rejected);
  try Elf:=BuildD1ELF(Physical,'external/sens');
  except on E:EELFD1Error do begin Check(Elf='','зіпсований T5M повернув ELF'); end; end;
  Check(Elf='','байт 243 не відхилено');
  Physical:='';Elf:='';Inc(Rejected);
  try Elf:=BuildD1ELF(Physical,'external/sens');
  except on E:EELFD1Error do begin Check(Elf='','порожній T5M повернув ELF'); end; end;
  Check(Elf='','порожній T5M не відхилено');
  WriteLn(UkrBytes('НАТИВНИЙ-ELF-ДОПУСК-ГАРАЗД D1=0,1 ELF64=172 D3:000=173 ET_DYN=так негативні='),Rejected,
    UkrBytes(' D3=відмова багатоформовість=відмова pinned=так'));
end.
