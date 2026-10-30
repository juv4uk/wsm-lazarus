{ G6.9: фізичні FPC механічні свідки справжнього багатокореневого ELF.
  Порівняння мовного результату — чинний FPC фізичний виконавець. }
program test_elfbatch;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.elfbatch, wsm.elfd1;

var Checks, Rejected:SizeInt;
    Output, Physical:RawByteString;
    Large:TExactWords;
    I:SizeInt;

function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

procedure Check(Good:Boolean; const Why:UnicodeString);
begin
  Inc(Checks);
  if not Good then begin
    WriteLn(StdErr,UkrBytes('ELF-ПАКЕТ-ТЕСТ-ПОМИЛКА: '),UkrBytes(Why));
    Halt(1);
  end;
end;

function WordsOf(const Values:array of RawByteString):TExactWords;
var J:SizeInt;
begin
  SetLength(Result,Length(Values));
  for J:=0 to High(Values) do Result[J]:=Values[J];
end;

procedure Save(const Name:String; const Bytes:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Name,fmCreate);
  try if Length(Bytes)>0 then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free; end;
end;

procedure RejectPhysical(const Bytes:RawByteString; const Why:UnicodeString);
var
  Generated:RawByteString;
  Failed:Boolean;
begin
  Generated:='';
  Failed:=False;
  try Generated:=BuildD1BatchELF(Bytes,'external/sens');
  except on E:EELFBatchError do Failed:=True; end;
  Check(Failed,Why);
  Check(Generated='','Жодного часткового ELF після відмови');
  Inc(Rejected);
end;

procedure RejectWords(const W:array of RawByteString; const Why:UnicodeString);
begin RejectPhysical(EncodeT5M(WordsOf(W)),Why); end;

procedure CheckNative(const W:array of RawByteString;
  const Expected:RawByteString; const Name:String);
var
  Bytes, ELF:RawByteString;
  RootCount, J, DataOffset:SizeInt;
begin
  Bytes:=EncodeT5M(WordsOf(W));
  Save('build/m0.2/elfbatch/'+Name+'.sens',Bytes);
  ELF:=BuildD1BatchELF(Bytes,'external/sens');
  RootCount:=Length(Expected) div 2;
  Check(Length(Expected)=2*RootCount,'Довжина очікуваних рядків');
  Check(Length(ELF)=141+36*RootCount,'Розмір двійкового ELF');
  Check(Copy(ELF,1,4)=#$7F'ELF','ELF magic');
  Check((Ord(ELF[5])=2) and (Ord(ELF[6])=1),'ELF64 little-endian');
  Check((Ord(ELF[17])=2) and (Ord(ELF[19])=62),'ET_EXEC x86-64');
  Check((Ord(ELF[65])=1) and (Ord(ELF[69])=5),'PT_LOAD RX');
  DataOffset:=141+34*RootCount;
  for J:=0 to RootCount-1 do begin
    Check(ELF[DataOffset+2*J+1]=Expected[2*J+1],
      'Біт фізичного кореня у власній адресі машинного коду');
    Check(ELF[DataOffset+2*J+2]=#10,'LF після кожного кореня');
  end;
  { Доводимо, що КОЖЕН root має machine CMP RAX,2; JNE rel32,
    а не лише останній. Таблиця 0/1 залишається pinned D1/D2.
    1) Чому для кореня N не можна перевірити write тільки наприкінці?
    2) Чим host exit(2) відрізняється від SENS D1:0?
    3) Чому old one-root ABI зберігається через базовий emitter? }
  for J:=0 to RootCount-1 do
    Check(Copy(ELF,120+34*J+25,6)=#$48#$83#$F8#$02#$0F#$85,
      'кожний sys_write D1 має machine CMP RAX,2 / JNE');
  Check(Copy(ELF,120+34*RootCount+10,12)=
      #$B8#$3C#0#0#0#$BF#$02#0#0#0#$0F#$05,
      'спільний Linux exit(2) після неповного write');
  Save('build/m0.2/elfbatch/'+Name+'.expected.elf',ELF);
  Save('build/m0.2/elfbatch/'+Name+'.expected.out',Expected);
  Check(BuildD1BatchELF(Bytes,'external/sens')=ELF,
    'Детермінованість двох збірок ELF');
end;

begin
  Checks:=0; Rejected:=0;
  ForceDirectories('build/m0.2/elfbatch');
  { Для одного кореня байти EXACTLY збігаються з раніше злитим G6.8. }
  Physical:=EncodeT5M(WordsOf(['0']));
  Check(BuildD1BatchELF(Physical,'external/sens')=
    BuildD1ELF(Physical,'external/sens'),
    'Побайтовий збіг нового та початкового ELF для D1:0');
  Physical:=EncodeT5M(WordsOf(['1']));
  Check(BuildD1BatchELF(Physical,'external/sens')=
    BuildD1ELF(Physical,'external/sens'),
    'Побайтовий збіг нового та початкового ELF для D1:1');

  CheckNative(['0','1','0','1'],'0'+#10+'1'+#10+'0'+#10+'1'+#10,
    'alternating');
  CheckNative(['0','00','1','00','0'],'0'+#10+'1'+#10+'0'+#10,
    'separated');

  SetLength(Large,MaxELFBatchRoots);
  Output:='';
  for I:=0 to High(Large) do begin
    if (I mod 2)=0 then Large[I]:='0' else Large[I]:='1';
    Output:=Output+Large[I]+#10;
  end;
  Physical:=EncodeT5M(Large);
  Save('build/m0.2/elfbatch/maximum.sens',Physical);
  Save('build/m0.2/elfbatch/maximum.expected.out',Output);
  Physical:=BuildD1BatchELF(Physical,'external/sens');
  Check(Length(Physical)=141+36*MaxELFBatchRoots,
    'Максимум 1024 коренів, точний розмір ELF');
  Save('build/m0.2/elfbatch/maximum.expected.elf',Physical);

  SetLength(Large,MaxELFBatchRoots+1);
  Large[MaxELFBatchRoots]:='0';
  RejectPhysical(EncodeT5M(Large),'1025 коренів відхилено');
  RejectWords(['000'],'D3:000 не є D1:0');
  RejectWords(['111'],'D3 callable заборонено');
  RejectWords(['0','000'],'Третій домен у другому корені');
  RejectWords(['0','10','01'],'D2 список у другій формі');
  RejectWords(['10','0','01'],'D2 список замість D1');
  RejectWords(['10','0'],'Незакрита D2 структура');
  RejectWords(['0','01'],'Зайва D2 закривальна форма');
  RejectWords(['0','10','001','0','01'],'D3 цитата у другому корені');
  RejectWords(['1111111111'],'Непідтверджена ширина D10');
  RejectWords(['0','11','1'],'Крапка поза списком');
  RejectPhysical(#$F3,'Заборонений фізичний T5M байт 243');
  RejectPhysical('','Порожній фізичний вхід');
  Check(BuildD1BatchELF(EncodeT5M(WordsOf(['1','0'])),
    'external/sens')<>'','Відновлення після всіх помилок');
  WriteLn(UkrBytes('НАТИВНИЙ-ELF-ПАКЕТ-ГАРАЗД коренів=1024'),
    UkrBytes(' виконання=окремі_x86-64_write'),
    UkrBytes(' побайтово_один_корінь=так негативні='),Rejected,
    UkrBytes(' перевірок='),Checks);
end.
