{ G6.27 — 10 фізичних D3:010 форм, машинний T5M та fail-closed.
  Тест не проголошує загальної SENS конформності: лише чинний вузький
  exact D3 backend із pinned таблицями і реальним ELF64. }
program test_elfatomt5m;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfatom,wsm.elfatomt5m;

var Positives,Negatives:SizeInt;
    Root,OutputDir:String;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then
    raise Exception.Create('D3-АТОМ-T5M-ТЕСТ-ПОМИЛКА: '+Why);
end;

procedure Save(const Path:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Data<>'' then Stream.WriteBuffer(Data[1],Length(Data));
  finally Stream.Free end;
end;

function LoadBytes(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Check((Stream.Size>=1) and (Stream.Size<=MAX_T5M_FILE_BYTES),
      'Немає bounded pinned фізичного свідка: '+Path);
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

function ReadQWord(const Bytes:RawByteString;Offset:SizeInt):QWord;
var I:SizeInt;
begin
  Check((Offset>=0) and (Offset+8<=Length(Bytes)),'ELF header bounds');
  Result:=0;
  for I:=7 downto 0 do
    Result:=(Result shl 8) or QWord(Ord(Bytes[Offset+I+1]));
end;

procedure Positive(const Name,Expected:RawByteString;
                   const Items:array of RawByteString);
var Physical,Elf,Legacy,ExpectedPhysical:RawByteString;
begin
  Physical:=EncodeT5M(Words(Items));
  Legacy:=BuildAtomELF(Physical,RawByteString(Root));
  Elf:=BuildAtomT5MELF(Physical,RawByteString(Root));
  ExpectedPhysical:=EncodeT5M(Words([Expected]));
  Check((Length(Elf)>150) and (Length(Elf)<2200),
    'ELF довжина: '+String(Name));
  Check((Copy(Elf,1,4)=#$7F'ELF') and (Ord(Elf[5])=2) and
    (Ord(Elf[6])=1) and (Ord(Elf[17])=2) and
    (Ord(Elf[19])=62) and (Ord(Elf[65])=1) and
    (Ord(Elf[69])=5),
    'ELF64 ET_EXEC AMD64 RX: '+String(Name));
  Check((ReadQWord(Elf,96)=QWord(Length(Elf))) and
    (ReadQWord(Elf,104)=QWord(Length(Elf))),
    'Неправильний файл або memory payload size');
  Check((Length(Elf)<>Length(Legacy)) and
    (Copy(Elf,1,96)=Copy(Legacy,1,96)) and
    (Copy(Elf,113,8)=Copy(Legacy,113,8)),
    'Не збережено існуючий ELF64 ABI');
  Check(Pos(#$83#$E0#$03#$83#$F8#$03#$0F#$95#$C0,Elf)>0,
    'Немає реальних AND/CMP/SETNE D3:010');
  Check(Pos(#$0F#$B6#$C0,Elf)>0,'Немає MOVZX D3:010');
  Check(Pos(#$6B#$C0,Elf)>0,'Немає машинного IMUL пакування T5M');
  Check(Pos(#$48#$81#$EC#0#$08#0#0#$49#$89#$E4,Elf)>0,
    'Не збережено машинну 2048-byte CONS arena');
  if Expected='0' then
    Check((Pos(#$49#$89#$0C#$24,Elf)>0) and
      (Pos(#$49#$89#$44#$24#$08,Elf)>0) and
      (Pos(#$49#$8D#$04#$24,Elf)>0),
      'CONS має справжню матеріальну пару QWord');
  { Незмінна фізична D3:010 відповідь, але не unconditional exit(0):
    спільний машинний postpass дописує 11-byte Linux guard.
    ELF загалом managed RawByteString, Test не володіє новим runtime.
    1) Чому треба звіряти всю машинну команду, не тільки syscall?
    2) Чому вихід D1 рівно 1 байт? 3) Що перевіряє ENOSPC?
    4) Де зберігається pinned semantic admission? }
  Check(Copy(Elf,Length(Elf)-10,11)=
        #$39#$D0#$40#$0F#$95#$C7#$6A#$3C#$58#$0F#$05,
    'Немає перевірки повного Linux sys_write перед exit');
  Check((Length(ExpectedPhysical)=1) and
    (BuildAtomT5MELF(Physical,RawByteString(Root))=Elf),
    'Детермінізм T5M машинного виходу');
  Save(OutputDir+'/'+String(Name)+'.elf',Elf);
  Save(OutputDir+'/'+String(Name)+'.expected.sens',ExpectedPhysical);
  Save(OutputDir+'/'+String(Name)+'.legacy.elf',Legacy);
  Save(OutputDir+'/'+String(Name)+'.expected.ascii',Expected+#10);
  Inc(Positives);
end;

procedure NegativeRaw(const Physical:RawByteString;const Why:String);
var Image:RawByteString;Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try Image:=BuildAtomT5MELF(Physical,RawByteString(Root));
  except on E:EElfAtomT5MError do Rejected:=True end;
  Check(Rejected and (Image=''),Why);
  Inc(Negatives);
end;

procedure Negative(const Items:array of RawByteString;const Why:String);
begin NegativeRaw(EncodeT5M(Words(Items)),Why) end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Вкажіть корінь pinned SENS та теку свідків');
    Halt(64);
  end;
  Root:=ParamStr(1);OutputDir:=ParamStr(2);
  Check(ForceDirectories(OutputDir),'Створення каталогу');
  Positives:=0;Negatives:=0;
  Positive('атом-нуль','1',['10','010','0','01']);
  Positive('атом-один','1',['10','010','1','01']);
  Positive('атом-порожній','1',['10','010','10','01','01']);
  Positive('атом-д3-порожній','1',['10','010','000','01']);
  Positive('атом-пара','0',['10','010','10','111','0','1','01','01']);
  Positive('атом-пара-порожній','0',
    ['10','010','10','111','0','000','01','01']);
  Positive('атом-пара-пар','0',
    ['10','010','10','111','10','111','1','000','01','0','01','01']);
  Positive('атом-вкладений-атом-пари','1',
    ['10','010','10','010','10','111','0','000','01','01','01']);
  Positive('атом-атома','1',['10','010','10','010','0','01','01']);
  Positive('атом-вкладена-пара','0',
    ['10','010','10','111','10','010','1','01','0','01','01']);
  Negative(['0'],'Голий D1 не є викликом ATOM');
  Negative(['10','111','0','1','01'],'Користувацький CONS без ATOM');
  Negative(['10','010','10','100','0','01','01'],'Непідтриманий CAR');
  Negative(['10','010','10','011','0','01','01'],'Непідтриманий CDR');
  Negative(['10','010','10','001','0','01','01'],'Непідтриманий QUOTE');
  Negative(['10','010','000000000000','01'],'D12 не D3:000');
  Negative(['10','010','000000000000000000000000','01'],
    'D24 не D3:000');
  Negative(['10','010','01'],'ATOM без аргумента');
  Negative(['10','010','0','1','01'],'ATOM із зайвим аргументом');
  Negative(['10','010','10','000','0','01','01'],
    'D3:000 не виклична голова');
  Negative(['10','010','10','111','0','10','111','1','01','01','01'],
    'Некоректна арність CONS');
  Negative(['10','010','0','01','1'],'Два корені');
  Negative(['10','010','10','1','11','0','01','01'],'Крапкова пара');
  NegativeRaw(#$F3,'Непридатний T5M 243');
  NegativeRaw('','Порожній фізичний виклик');
  NegativeRaw(LoadBytes(OutputDir+'/pinned.sens'),
    'Pinned повний D3:101/ATOM закон не належить вузькому backend');
  Check((Positives=10) and (Negatives=16),'Точні лічильники');
  WriteLn('АТОМ-T5M-ДОПУСК-ГАРАЗД ELF64=10 ',
    'негативних=',Negatives,' D3:010=машинний D1=точний ',
    'CONS=фізичні-комірки T5M=канонічний');
end.
