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
procedure Save(const Filename:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Filename,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free; end;
end;
procedure Positive(const Name,Expected:RawByteString;
  const Items:array of RawByteString;ClauseCount:SizeInt);
var M,Physical:RawByteString;
begin
  Physical:=EncodeT5M(Words(Items));
  Save('build/m0.2/elfcond/'+String(Name)+'.sens',Physical);
  M:=BuildCondELF(Physical,'external/sens');
  Demand((Length(M)>160) and (Length(M)<512),'розмір ELF64');
  Demand((Copy(M,1,4)=#$7F'ELF') and (Ord(M[5])=2) and
         (Ord(M[6])=1) and (Ord(M[17])=2) and (Ord(M[19])=62),
         'ELF64 x86-64 ET_EXEC');
  Demand((Ord(M[65])=1) and (Ord(M[69])=5),
         'один виконуваний RX сегмент');
  Demand((ClauseCount=0) or (Pos(#$83#$F8#$01#$75,M)>0),
         'машинний CMP/JNE, не echo');
  Demand(Copy(M,Length(M)-3,4)=#$31#$FF#$0F#$05,
         'машинний SYS_exit');
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
  Negative(['0'],'один D1 не форма');
  Negative(['10','101','0','1','01'],'EQ не умовна форма');
  Negative(['10','110','10','1','01','01'],'одне поле');
  Negative(['10','110','10','1','0','1','01','01'],'три поля');
  Negative(['10','110','1','01'],'гілка не список');
  Negative(['10','110','10','000','0','01','01'],'D3:000 не false');
  Negative(['10','110','10','1','000','01','01'],'D3:000 не D1 тіло');
  Negative(['10','110','10','000000000000','1','01','01'],
    'D12+ не D1 і не неявний host bool');
  Negative(['10','110','10','0','1','01','10','1','0','01',
    '10','1','1','01','01'],'третя гілка не підтримується');
  Negative(['10','110','10','1','0','01','01','0'],'дві форми');
  Negative(['10','110','10','1','0'],'неповний D2');
  Negative(['10','110','10','1','0','01','0','01'],'крапкова пара');
  NegativeRaw(#243,'недопустимий фізичний T5M');
  NegativeRaw('','порожній фізичний файл');
  Demand((Positives=7) and (Negatives=14),'лічильники свідків');
  WriteLn(UA('МАШИННА-УМОВА-ГАРАЗД машинний-CMP/JNE=так '),
    UA('позитивні='),Positives,UA(' негативні='),Negatives);
  WriteLn(UA('МАШИННА-УМОВА-МЕЖА D1=лише-атоми D12+=відхилено '),
    UA('Core4=ні REPL-оракул=не-доведено'));
end.
