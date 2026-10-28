{ G6.13 — машинна перевірка CMP/SETE для вузького фізичного D3:101.
  Першоджерело законів — pinned SENS; це перевірка механізму, не оракул. }
program test_elfeq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfeq;
var Positives,Negatives:SizeInt; M:RawByteString;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
procedure Check(Yes:Boolean;const Why:RawByteString);
begin
  if not Yes then begin
    WriteLn(StdErr,UA('НАТИВНА-ТОТОЖНІСТЬ-ПОМИЛКА: '),Why);
    Halt(1);
  end;
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
procedure Positive(const Name,Expect,First,Second:RawByteString);
var Physical:RawByteString;
begin
  Physical:=EncodeT5M(Words(['10','101',First,Second,'01']));
  Save('build/m0.2/elfeq/'+String(Name)+'.sens',Physical);
  M:=BuildEqELF(Physical,'external/sens');
  Check((Length(M)>150) and (Length(M)<512),'ELF size');
  Check((Copy(M,1,4)=#$7F'ELF') and
     (Ord(M[5])=2) and (Ord(M[6])=1) and
     (Ord(M[17])=2) and (Ord(M[19])=62),'ELF64 ET_EXEC x86-64');
  Check((Ord(M[65])=1) and (Ord(M[69])=5),'single executable RX segment');
  Check(Pos(#$39#$C8#$0F#$94#$C0, M)>0,'native cmp eax,ecx / sete al');
  Check(Pos(#$0F#$B6#$C0#$04#$30, M)>0,'machine D1 ASCII conversion');
  Check(Copy(M,Length(M)-3,4)=#$31#$FF#$0F#$05,'sys_exit');
  { Результат істинності НЕ закодований у машинному шаблоні:
    imm32 мають значення лише фізичних D1 аргументів. }
  Check((Byte(M[121])=$B8) and (Byte(M[122])=Byte(Ord(First[1])-48)) and
        (Byte(M[126])=$B9) and (Byte(M[127])=Byte(Ord(Second[1])-48)),
        'machine exact D1 inputs');
  Save('build/m0.2/elfeq/'+String(Name)+'.expected.elf',M);
  Save('build/m0.2/elfeq/'+String(Name)+'.expected.out',Expect+#10);
  Inc(Positives);
end;
procedure Negative(const Items:array of RawByteString; const Why:RawByteString);
var R:RawByteString;Rejected:Boolean;
begin
  Rejected:=False;R:='';
  try R:=BuildEqELF(EncodeT5M(Words(Items)),'external/sens');
  except on E:EElfEqError do Rejected:=True; end;
  Check(Rejected and (R=''),Why);
  Inc(Negatives);
end;
procedure NegativeRaw(const Physical,Why:RawByteString);
var R:RawByteString;Rejected:Boolean;
begin
  Rejected:=False;R:='';
  try R:=BuildEqELF(Physical,'external/sens');
  except on E:EElfEqError do Rejected:=True; end;
  Check(Rejected and (R=''),Why);
  Inc(Negatives);
end;
begin
  ForceDirectories('build/m0.2/elfeq');
  Positives:=0;Negatives:=0;
  Positive('тотожні-нулі','1','0','0');
  Positive('нуль-один','0','0','1');
  Positive('один-нуль','0','1','0');
  Positive('тотожні-одиниці','1','1','1');
  Negative(['0'],'голий D1 не є D3:101');
  Negative(['10','111','0','1','01'],'CONS не D3:101');
  Negative(['10','010','0','01'],'ATOM не D3:101');
  Negative(['10','101','0','01'],'бракує аргументу');
  Negative(['10','101','0','1','0','01'],'зайвий аргумент');
  Negative(['10','101','000','1','01'],'D3 порожнеча не D1:0');
  Negative(['10','101','10','01','1','01'],'D2 порожній список не D1');
  Negative(['10','101','10','111','0','1','01','1','01'],
     'CONС-пара не атом');
  Negative(['10','101','10','101','0','0','01','1','01'],
     'не допускати вкладений EQ як атомарний аргумент');
  Negative(['10','101','000000000000','0','01'],'D12 не D1');
  Negative(['10','101','0','11','1','01'],'крапкова D2 форма');
  Negative(['10','101','0','1','01','0'],'дві фізичні форми');
  Negative(['10','101','0','1'],'D2 EOF');
  NegativeRaw(#243,'T5M заборонений фізичний байт');
  NegativeRaw('','порожній фізичний потік');
  Check((Positives=4) and (Negatives=15),'кількість тестових свідків');
  WriteLn(UA('НАТИВНА-ТОТОЖНІСТЬ-ГАРАЗД D3:101=машинний CMP/SETE '),
    UA('позитивні='),Positives,UA(' негативні='),Negatives);
  WriteLn(UA('НАТИВНА-ТОТОЖНІСТЬ-МЕЖА D1=лише-атоми '),
    UA('D12=відхилено Core4=не-підтримано SENS-REPL=не-перевірено'));
end.
