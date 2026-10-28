{ G6.19 — позитивні й негативні фізичні свідки машинного D3:100/011.
  Це перевірки механізму над pinned SENS, не новий мовний oracle. }
program test_elfselector;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfselector;

var Positives,Negatives:SizeInt;
    Machine,Again:RawByteString;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

procedure Check(Yes:Boolean;const Why:RawByteString);
begin
  if not Yes then begin
    WriteLn(StdErr,UA('МАШИННИЙ-ВИБІР-ТЕСТ-ПОМИЛКА: '),Why);
    Halt(1);
  end;
end;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free; end;
end;

procedure Positive(const LabelText,Head,Left,Right,Expected:RawByteString);
var Physical:RawByteString;
begin
  Physical:=EncodeT5M(Words(['10',Head,'10','111',Left,Right,'01','01']));
  Save('build/m0.2/elfselector/'+String(LabelText)+'.sens',Physical);
  Machine:=BuildSelectorELF(Physical,'external/sens');
  Again:=BuildSelectorELF(Physical,'external/sens');
  Check((Machine=Again) and (Length(Machine)=195),'детермінізм машинного ELF64');
  Check((Copy(Machine,1,4)=#$7F'ELF') and
    (Ord(Machine[5])=2) and (Ord(Machine[6])=1) and
    (Ord(Machine[17])=2) and (Ord(Machine[19])=62),
    'точний ELF64 ET_EXEC x86-64');
  Check((Byte(Machine[65])=1) and (Byte(Machine[69])=5),
    'один виконуваний PT_LOAD');
  Check((Byte(Machine[144])=$48) and (Byte(Machine[148])=$48),
    'втрачено 64-бітне машинне адресування пари');
  Check((Byte(Machine[121])=$B8) and
    (Byte(Machine[122])=Byte(Ord(Left[1])-48)) and
    (Byte(Machine[126])=$B9) and
    (Byte(Machine[127])=Byte(Ord(Right[1])-48)),
    'дві окремі машинні D1-координати');
  { Перевіряємо ПОВНИЙ порядок реальних x86-64 записів/читань:
    дві незалежні QWord-адреси, LEA на матеріалізовану пару,
    вибір адреси через disp8, а не регістрове копіювання. }
  Check(Copy(Machine,131,17)=
    #$48#$83#$EC#$10+                   { sub rsp,16 }
    #$48#$89#$04#$24+                   { mov [rsp],rax }
    #$48#$89#$4C#$24#$08+              { mov [rsp+8],rcx }
    #$48#$8D#$34#$24,                   { lea rsi,[rsp] }
    'не згенеровано реальну машинну пару з 2 QWord');
  Check(Copy(Machine,148,4)=
    #$48#$8B#$56+
    AnsiChar(Ord(Head='011')*8),
    'машинний селектор не читає [адреса пари+0/8]');
  Check((Pos(#$89#$C2,Copy(Machine,131,21))=0) and
        (Pos(#$89#$CA,Copy(Machine,131,21))=0),
    'залишився старий регістровий псевдоселектор');
  Check(Pos(#$80#$C2#$30,Machine)>0,'машинна конверсія D1 в ASCII');
  Check(Copy(Machine,Length(Machine)-3,4)=#$31#$FF#$0F#$05,
    'машинний Linux exit');
  Save('build/m0.2/elfselector/'+String(LabelText)+'.expected.elf',Machine);
  Save('build/m0.2/elfselector/'+String(LabelText)+'.expected.out',Expected+#10);
  Inc(Positives);
end;

procedure NegativeRaw(const Physical,Why:RawByteString);
var R:RawByteString;Rejected:Boolean;
begin
  R:='';Rejected:=False;
  try R:=BuildSelectorELF(Physical,'external/sens');
  except on E:EElfSelectorError do Rejected:=True; end;
  Check(Rejected and (R=''),Why);
  Inc(Negatives);
end;

procedure Negative(const Items:array of RawByteString;Why:RawByteString);
begin NegativeRaw(EncodeT5M(Words(Items)),Why); end;

begin
  ForceDirectories('build/m0.2/elfselector');
  Positives:=0;Negatives:=0;
  Positive('перше-00','100','0','0','0');
  Positive('перше-01','100','0','1','0');
  Positive('перше-10','100','1','0','1');
  Positive('перше-11','100','1','1','1');
  Positive('решта-00','011','0','0','0');
  Positive('решта-01','011','0','1','1');
  Positive('решта-10','011','1','0','0');
  Positive('решта-11','011','1','1','1');

  Negative(['0'],'один D1 атом не виклик селектора');
  Negative(['10','101','10','111','0','1','01','01'],'D3:101 не селектор');
  Negative(['10','100','0','01'],'відсутня побудова пари');
  Negative(['10','100','10','111','01','01'],'CONS без двох полів');
  Negative(['10','100','10','111','0','01','01'],'CONS одне поле');
  Negative(['10','011','10','111','0','1','0','01','01'],'CONS три поля');
  Negative(['10','100','10','111','000','1','01','01'],'порожнеча D3 не D1:0');
  Negative(['10','011','10','111','000000000000','1','01','01'],'D12 не D1');
  Negative(['10','100','10','111','10','111','0','1','01','0','01','01'],
    'вкладена пара замість атома');
  Negative(['10','100','10','111','0','11','1','01','01'],'D2 точкова форма');
  Negative(['10','100','10','111','0','1','01','01','0'],'два корені');
  Negative(['10','100','10','111','0','1','01'],'незакрите D2');
  NegativeRaw(#243,'фізичний заборонений T5M байт');
  NegativeRaw('','порожній T5M');
  Check((Positives=8) and (Negatives=14),'точна кількість тестових випадків');
  WriteLn(UA('МАШИННИЙ-ВИБІР-ТЕСТ-ГАРАЗД D3:100/011 D3:111 позитивні='),
    Positives,UA(' негативні='),Negatives);
  WriteLn(UA('МАШИННИЙ-ВИБІР-МЕЖА D1=атоми, D12=відхилено Core4=не-підтримано SENS-REPL=не-доведено'));
end.
