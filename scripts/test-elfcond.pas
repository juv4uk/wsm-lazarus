{ G6.17 — тест механізму генерації ELF для pinned D3:110.
  Вихідний .sens генерується фізичним T5M, не через текстовий dispatch. }
program test_elfcond;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfcond;
var Positives,Negatives:SizeInt;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
procedure Demand(Yes:Boolean;const Why:RawByteString);
begin
  if not Yes then raise Exception.Create(
    UA('МАШИННА-УМОВА-ТЕСТ-ПОМИЛКА: ')+Why);
end;
function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;
{ Будує лише фізичні D2-слова, не змінює семантику pinned D3.
  Winner=-1 означає вичерпання всіх гілок без істинного тесту. }
function Many(Count,Winner:SizeInt;ValueBit:Byte):TExactWords;
var I,P:SizeInt;
begin
  if (Count<0) or (Count>33) or (Winner>=Count) or
     (Winner< -1) or (ValueBit>1) then
    raise Exception.Create('Недопустимі параметри свідка D3:110');
  SetLength(Result,3+4*Count);
  Result[0]:='10'; Result[1]:='110';
  P:=2;
  for I:=0 to Count-1 do begin
    Result[P]:='10'; Inc(P);
    if I=Winner then Result[P]:='1' else Result[P]:='0';
    Inc(P);
    if I=Winner then Result[P]:=AnsiChar(Ord('0')+ValueBit)
    else Result[P]:='1';
    Inc(P);
    Result[P]:='01'; Inc(P);
  end;
  Result[P]:='01';
end;

{ Вкладений D3:101 містить голову та два точних D1-операнди.
  Winner=-1: всі порівняння хибні, отже структурне D3:000. }
function ManyEquality(Count,Winner:SizeInt;ValueBit:Byte):TExactWords;
var I,P:SizeInt;
begin
  if (Count<0) or (Count>32) or (Winner>=Count) or
     (Winner< -1) or (ValueBit>1) then
    raise Exception.Create('Недопустимі параметри фізичного EQ-свідка');
  SetLength(Result,3+8*Count);
  Result[0]:='10';Result[1]:='110';
  P:=2;
  for I:=0 to Count-1 do begin
    Result[P]:='10';Inc(P); { D2-гілка }
    Result[P]:='10';Inc(P); { D2-вкладене EQ }
    Result[P]:='101';Inc(P);
    if I=Winner then Result[P]:='1' else Result[P]:='0';
    Inc(P);
    Result[P]:='1';Inc(P);
    Result[P]:='01';Inc(P);
    if I=Winner then Result[P]:=AnsiChar(Ord('0')+ValueBit)
    else Result[P]:='0';
    Inc(P);
    Result[P]:='01';Inc(P);
  end;
  Result[P]:='01';
end;

{ 32 гілки: кожний expression містить ФІЗИЧНЕ D3:101.
  Тільки останній предикат істинний, отже відповідь EQ
  визначає процес x86-64 при запуску, а не FPC при генерації. }
function ManyExpressionEquality(Count,Winner:SizeInt):TExactWords;
var I,P:SizeInt;
begin
  if (Count<0) or (Count>32) or (Winner>=Count) or (Winner< -1) then
    raise Exception.Create('Недопустимі параметри expression EQ');
  SetLength(Result,3+8*Count);
  Result[0]:='10';Result[1]:='110';P:=2;
  for I:=0 to Count-1 do begin
    Result[P]:='10';Inc(P); { фізична D2-гілка }
    if I=Winner then Result[P]:='1' else Result[P]:='0';
    Inc(P);
    Result[P]:='10';Inc(P); { вибраний expression D3:101 }
    Result[P]:='101';Inc(P);
    if I=Winner then Result[P]:='1' else Result[P]:='0';
    Inc(P);
    Result[P]:='1';Inc(P);
    Result[P]:='01';Inc(P);
    Result[P]:='01';Inc(P);
  end;
  Result[P]:='01';
end;

procedure Save(const Filename:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Filename,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free; end;
end;
procedure Positive(const Name,Expected:RawByteString;
  const Items:array of RawByteString;ClauseCount:SizeInt;
  ExpectMachineEquality:Boolean=False;
  ExpectComputedExpression:Boolean=False);
var M,Physical:RawByteString;
begin
  Physical:=EncodeT5M(Words(Items));
  Save('build/m0.2/elfcond/'+String(Name)+'.sens',Physical);
  M:=BuildCondELF(Physical,'external/sens');
  Demand((Length(M)>160) and (Length(M)<5000),'розмір ELF64');
  Demand((Copy(M,1,4)=#$7F'ELF') and (Ord(M[5])=2) and
         (Ord(M[6])=1) and (Ord(M[17])=2) and (Ord(M[19])=62),
         'ELF64 x86-64 ET_EXEC');
  Demand((Ord(M[65])=1) and (Ord(M[69])=5),
         'один виконуваний RX сегмент');
  Demand((ClauseCount=0) or (Pos(#$83#$F8#$01#$75,M)>0),
         'машинний CMP/JNE, не echo');
  if ExpectMachineEquality then
    Demand(Pos(#$39#$C8#$0F#$94#$C0#$0F#$B6#$C0,M)>0,
      'вкладене EQ має реальний CMP/SETE/MOVZX в ELF');
  if ExpectComputedExpression then
    Demand(Pos(#$04#$30#$48#$83#$EC#$08#$88#$04#$24,M)>0,
      'вираз EQ обчислює AL у машині, а не Pascal writer');
  { Після кожного Linux sys_write потрібен повний RAX=2|3; остання
    команда exit(2) відрізняє host помилку від D1 і D3:000. }
  Demand((ClauseCount=0) or (Pos(#$48#$83#$F8#$02#$75#$09,M)>0),
    'machine повний write(2) / JNE для гілкової форми');
  Demand((Expected<>'()') or (Pos(#$48#$83#$F8#$03#$75#$09,M)>0),
    'machine повний write(3) / JNE для D3:000');
  Demand(Copy(M,Length(M)-11,12)=#$B8#$3C#0#0#0#$BF#$02#0#0#0#$0F#$05,
         'machine host exit(2) після невдалого write');
  Demand(BuildCondELF(Physical,'external/sens')=M,
         'детермінізм ELF, байт у байт');
  Save('build/m0.2/elfcond/'+String(Name)+'.expected.elf',M);
  Save('build/m0.2/elfcond/'+String(Name)+'.expected.out',Expected+#10);
  Inc(Positives);
end;
procedure Negative(const Items:array of RawByteString;
  const Why:RawByteString);
var Produced:RawByteString;Rejected:Boolean;
begin
  Produced:='';Rejected:=False;
  try Produced:=BuildCondELF(EncodeT5M(Words(Items)),'external/sens');
  except on E:EElfCondError do Rejected:=True; end;
  Demand(Rejected and (Produced=''),Why);
  Inc(Negatives);
end;
procedure NegativeRaw(const Physical,Why:RawByteString);
var Produced:RawByteString;Rejected:Boolean;
begin
  Produced:='';Rejected:=False;
  try Produced:=BuildCondELF(Physical,'external/sens');
  except on E:EElfCondError do Rejected:=True; end;
  Demand(Rejected and (Produced=''),Why);
  Inc(Negatives);
end;
begin
  ForceDirectories('build/m0.2/elfcond');
  Positives:=0;Negatives:=0;
  Positive('без-гілок','()',['10','110','01'],0);
  Positive('одна-істинна','1',
    ['10','110','10','1','1','01','01'],1);
  Positive('одна-істинна-ні','0',
    ['10','110','10','1','0','01','01'],1);
  Positive('одна-хибна','()',
    ['10','110','10','0','1','01','01'],1);
  Positive('дві-друга-істинна','1',
    ['10','110','10','0','0','01','10','1','1','01','01'],2);
  Positive('дві-перша-істинна','0',
    ['10','110','10','1','0','01','10','1','1','01','01'],2);
  Positive('дві-хибні','()',
    ['10','110','10','0','1','01','10','0','0','01','01'],2);
  { Третя, шістнадцята та тридцять друга гілки справді
    виконуються машинним CMP/JNE; вичерпання лишається D3:000. }
  Positive('три-остання-істинна','1',Many(3,2,1),3);
  Positive('три-вичерпано','()',Many(3,-1,1),3);
  Positive('шістнадцять-остання-істинна','0',Many(16,15,0),16);
  Positive('шістнадцять-вичерпано','()',Many(16,-1,0),16);
  Positive('тридцять-дві-остання-істинна','1',Many(32,31,1),32);
  Positive('тридцять-дві-перша-істинна','0',Many(32,0,0),32);
  Positive('тридцять-дві-вичерпано','()',Many(32,-1,1),32);
  Positive('рівність-00','1',
    ['10','110','10','10','101','0','0','01','1','01','01'],1,True);
  Positive('рівність-01','()',
    ['10','110','10','10','101','0','1','01','1','01','01'],1,True);
  Positive('рівність-10','()',
    ['10','110','10','10','101','1','0','01','1','01','01'],1,True);
  Positive('рівність-11','0',
    ['10','110','10','10','101','1','1','01','0','01','01'],1,True);
  Positive('дві-рівності-друга','0',
    ['10','110',
      '10','10','101','0','1','01','1','01',
      '10','10','101','1','1','01','0','01','01'],2,True);
  Positive('дві-рівності-перша','1',
    ['10','110',
      '10','10','101','0','0','01','1','01',
      '10','10','101','1','1','01','0','01','01'],2,True);
  Positive('тридцять-дві-рівності','1',ManyEquality(32,31,1),32,True);
  Positive('тридцять-дві-рівності-порожньо','()',
    ManyEquality(32,-1,1),32,True);
  { G6.24: EQ тепер можна обчислювати в ОБРАНОМУ expression.
    Жодна із відповідей нижче не береться з Pascal host dispatch. }
  Positive('вираз-рівність-00','1',
    ['10','110','10','1','10','101','0','0','01','01','01'],
    1,True,True);
  Positive('вираз-рівність-01','0',
    ['10','110','10','1','10','101','0','1','01','01','01'],
    1,True,True);
  Positive('вираз-рівність-10','0',
    ['10','110','10','1','10','101','1','0','01','01','01'],
    1,True,True);
  Positive('вираз-рівність-11','1',
    ['10','110','10','1','10','101','1','1','01','01','01'],
    1,True,True);
  Positive('вираз-хибна-гілка','()',
    ['10','110','10','0','10','101','0','0','01','01','01'],
    1,True,True);
  Positive('вираз-друга-гілка','1',
    ['10','110',
      '10','0','10','101','0','1','01','01',
      '10','1','10','101','1','1','01','01','01'],
    2,True,True);
  Positive('вираз-перша-гілка','0',
    ['10','110',
      '10','1','10','101','0','1','01','01',
      '10','1','10','101','1','1','01','01','01'],
    2,True,True);
  Positive('вираз-тест-і-відповідь','0',
    ['10','110','10',
      '10','101','0','0','01',
      '10','101','1','0','01',
      '01','01'],
    1,True,True);
  Positive('вираз-хибний-тест-рівність','()',
    ['10','110','10',
      '10','101','1','0','01',
      '10','101','1','1','01',
      '01','01'],
    1,True,True);
  Positive('вираз-тридцять-дві-рівності','1',
    ManyExpressionEquality(32,31),32,True,True);

  Negative(['0'],'один D1 не форма');
  Negative(['10','101','0','1','01'],'EQ не умовна форма');
  Negative(['10','110','10','1','01','01'],'одне поле');
  Negative(['10','110','10','1','0','1','01','01'],'три поля');
  Negative(['10','110','1','01'],'гілка не список');
  Negative(['10','110','10','000','0','01','01'],'D3:000 не false');
  Negative(['10','110','10','1','000','01','01'],'D3:000 не D1 тіло');
  Negative(['10','110','10','000000000000','1','01','01'],
    'D12+ не D1 і не неявний host bool');
  Negative(Many(33,32,1),
    '33 гілки перевищують обмеження backend, не мовний закон');
  Negative(['10','110','10','1','0','01','01','0'],'дві форми');
  Negative(['10','110','10','1','0'],'неповний D2');
  Negative(['10','110','10','1','0','01','0','01'],'крапкова пара');
  Negative(['10','110','10','10','101','0','01','1','01','01'],
    'вкладена рівність без другого операнда');
  Negative(['10','110','10','10','101','0','0','1','01','1','01','01'],
    'вкладена рівність з трьома операндами');
  Negative(['10','110','10','10','010','0','0','01','1','01','01'],
    'вкладений ATOM не є EQ');
  Negative(['10','110','10','10','101','000000000000','0','01',
    '1','01','01'],'D12 не атом D1 для EQ');
  Negative(['10','110','10','10','101','000','0','01','1','01','01'],
    'D3:000 не є D1:0 у порівнянні');
  Negative(['10','110','10','1','10','010','0','0','01','01','01'],
    'ATOM не дозволений як вираз EQ цього backend');
  Negative(['10','110','10','1','10','101','0','01','01','01'],
    'EQ expression без другого точного D1');
  Negative(['10','110','10','1','10','101','0','0','1','01','01','01'],
    'EQ expression з трьома операндами');
  Negative(['10','110','10','1','10','101','000000000000','0','01',
    '01','01'],'D12 не є D1 операндом expression EQ');
  Negative(['10','110','10','1','10','101','000','0','01',
    '01','01'],'D3:000 не є D1:0 у expression EQ');
  Negative(['10','110','10','1','10','101','10','101','0','0','01',
    '1','01','01','01'],'вкладений expression-операнд EQ непідтриманий');
  Negative(['10','110','10','10','101','10','101','0','0','01',
    '1','01','1','01','01'],'операнд EQ не є вкладеним викликом');
  NegativeRaw(#243,'недопустимий фізичний T5M');
  NegativeRaw('','порожній фізичний файл');
  Demand((Positives=32) and (Negatives=26),'лічильники свідків');
  WriteLn(UA('МАШИННА-УМОВА-ГАРАЗД машинний-CMP/JNE=так '),
    UA('позитивні='),Positives,UA(' негативні='),Negatives);
  WriteLn(UA('МАШИННА-РІВНІСТЬ-УМОВА CMP/SETE/MOVZX=так '),
    UA('рівностей=8, D1-не-сплутано-з-D3:000'));
  WriteLn(UA('МАШИННА-ВИРАЗ-РІВНІСТЬ-ГАРАЗД вираз=машинний-CMP/SETE/MOVZX '),
    UA('обраний=так гілок=32'));
  WriteLn(UA('МАШИННА-УМОВА-МЕЖА D1=лише-атоми D12+=відхилено '),
    UA('Core4=ні REPL-оракул=не-доведено'));
end.
