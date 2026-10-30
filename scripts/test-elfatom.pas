{ G6.9 — фізичний FPC-тест D3:010→x86-64, лише pinned свідки. }
program test_elfatom;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfatom;
var
  CountGood,CountBad:SizeInt;
  Physical,Machine:RawByteString;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then begin
    WriteLn(StdErr,UA('НАТИВНИЙ-АТОМ-ТЕСТ-ПОМИЛКА: '),Why);
    Halt(1);
  end;
end;
function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;
procedure Save(const P:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(P,fmCreate);
  try if B<>'' then F.WriteBuffer(B[1],Length(B));
  finally F.Free; end;
end;
procedure Positive(const LabelText,Expect:RawByteString;
  const W:TExactWords);
var C:RawByteString;
begin
  C:=EncodeT5M(W);
  Save('build/m0.2/elfatom/'+String(LabelText)+'.sens',C);
  Machine:=BuildCheckedAtomELF(C,'external/sens');
  Check((Length(Machine)>=170) and (Length(Machine)<=2170),
    'Неправильна довжина машинного ELF');
  Check((Copy(Machine,1,4)=#$7F'ELF') and (Ord(Machine[5])=2) and
    (Ord(Machine[6])=1) and (Ord(Machine[17])=2) and
    (Ord(Machine[19])=62) and (Ord(Machine[57])=1),
    'Порушено ELF64 ET_EXEC x86-64');
  Check((Ord(Machine[65])=1) and (Ord(Machine[69])=5),
    'Машинний PT_LOAD не RX');
  Check(Pos(#$83#$E0#$03#$83#$F8#$03#$0F#$95#$C0,Machine)>0,
    'Не згенеровано runtime and/cmp/setne для D3:010');
  Check(Pos(#$48#$81#$EC#0#$08#0#0#$49#$89#$E4,Machine)>0,
    'Не зарезервовано точну 2048-байтову машинну пару-арену');
  if Expect='0' then
    Check((Pos(#$49#$89#$0C#$24,Machine)>0) and
      (Pos(#$49#$89#$44#$24#$08,Machine)>0) and
      (Pos(#$49#$8D#$04#$24,Machine)>0),
      'D3:111 не матеріалізовано як два runtime QWord');
  { Після перевіреного ELF host postpass: тільки повний write(1,2)
    дозволяє exit(0). Суфікс зберігає точні bytes CMP/SETNE/exit,
    а SENS D3 закон та всі 14 admission негативів незмінні.
    Чому suffix перевіряємо на owned ELF, а не на .lisp проєкції? }
  Check(Copy(Machine,Length(Machine)-10,11)=
    #$39#$D0#$40#$0F#$95#$C7#$6A#$3C#$58#$0F#$05,
    'ELF не має перевіреного Linux sys_write exit епілогу');
  Save('build/m0.2/elfatom/'+String(LabelText)+'.expected.elf',Machine);
  Save('build/m0.2/elfatom/'+String(LabelText)+'.expected.out',Expect+#10);
  Inc(CountGood);
end;
procedure Negative(const W:TExactWords;const Why:String);
var B,Output:RawByteString;Rejected:Boolean;
begin
  B:=EncodeT5M(W);Output:='';Rejected:=False;
  try Output:=BuildAtomELF(B,'external/sens');
  except on E:EElfAtomError do Rejected:=True; end;
  Check(Rejected and (Output=''),Why);
  Inc(CountBad);
end;
begin
  ForceDirectories('build/m0.2/elfatom');
  CountGood:=0;CountBad:=0;
  Positive('atom-zero','1',Words(['10','010','0','01']));
  Positive('atom-one','1',Words(['10','010','1','01']));
  Positive('atom-empty','1',Words(['10','010','10','01','01']));
  Positive('atom-d3-empty','1',Words(['10','010','000','01']));
  Positive('atom-cons','0',
    Words(['10','010','10','111','0','1','01','01']));
  Positive('atom-cons-empty','0',
    Words(['10','010','10','111','0','000','01','01']));
  Positive('atom-cons-cons','0',
    Words(['10','010','10','111','10','111','1','000','01','0','01','01']));
  Positive('atom-atom-cons','1',
    Words(['10','010','10','010','10','111','0','000','01','01','01']));
  Positive('atom-atom','1',
    Words(['10','010','10','010','0','01','01']));
  Positive('atom-nested-cons','0',
    Words(['10','010','10','111','10','010','1','01','0','01','01']));
  Negative(Words(['0']),'D1 без ATOM став виконуваним D3');
  Negative(Words(['10','111','0','1','01']),'кореневий CONS допущено');
  Negative(Words(['10','010','10','100','0','01','01']),'CAR не підтверджений');
  Negative(Words(['10','010','10','011','0','01','01']),'CDR не підтверджений');
  Negative(Words(['10','010','10','001','0','01','01']),'QUOTE не підтверджена');
  Negative(Words(['10','010','000000000000','01']),'D12 не D3:000');
  Negative(Words(['10','010','01']),'АТОМ без аргумента');
  Negative(Words(['10','010','0','1','01']),'АТОМ з двома аргументами');
  Negative(Words(['10','010','10','000','0','01','01']),
    'D3:000 не є викличною головою');
  Negative(Words(['10','010','10','111','0','10','111','1','01','01','01']),
    'неприпустима арність вкладеної пари');
  Negative(Words(['10','010','0','01','1']),'два корені');
  Negative(Words(['10','010','10','1','11','0','01','01']),'крапкова пара');
  Physical:=#$F3;Machine:='';Inc(CountBad);
  try Machine:=BuildAtomELF(Physical,'external/sens');
  except on E:EElfAtomError do begin end; end;
  Check(Machine='','пошкоджений T5M пройшов');
  Physical:='';Machine:='';Inc(CountBad);
  try Machine:=BuildAtomELF(Physical,'external/sens');
  except on E:EElfAtomError do begin end; end;
  Check(Machine='','порожній T5M пройшов');
  WriteLn(UA('НАТИВНИЙ-АТОМ-ДОПУСК-ГАРАЗД D3:010=машинний позитивні='),
    CountGood,UA(' негативні='),CountBad,
    UA(' CMP-SETNE=перевірено pinned=так'));
end.
