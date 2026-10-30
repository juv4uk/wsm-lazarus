{ G6.26 — позитивні та негативні фізичні свідки машинних D3-селекторів. }
program test_elfselectort5m;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.binaryexec,wsm.elfselectort5m;
var Good,Bad:SizeInt;Root,OutputDir:String;Engine:TBinaryExecutor;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Check(Yes:Boolean;const Why:String);
begin if not Yes then raise Exception.Create('МАШИННИЙ-СЕЛЕКТОР-T5M-ПРОВАЛ: '+Why) end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Positive(const Title,Selector,Left,Right,Selected:RawByteString);
var Source,Image,Expected,Actual:RawByteString;Decoded:TExactWords;
begin
  Source:=EncodeT5M(Words(['10',Selector,'10','111',Left,Right,'01','01']));
  Image:=BuildSelectorT5MELF(Source,RawByteString(Root));
  Expected:=EncodeT5M(Words([Selected]));
  Actual:=Engine.ExecutePhysicalT5M(Source);
  Check(Actual=Expected,'нативне фізичне виконання: '+String(Title));
  DecodeT5M(Actual,Decoded);
  Check((Length(Decoded)=1) and (Decoded[0]=Selected),
    'точне D1 слово: '+String(Title));
  Check((Length(Image)=204) and (Copy(Image,1,4)=#$7F'ELF') and
    (Byte(Image[17])=3) and (Byte(Image[19])=62),
    'ELF64 ET_DYN x86-64: '+String(Title));
  Check((Pos(#$48#$89#$04#$24,Image)>0) and
    (Pos(#$48#$89#$4C#$24#$08,Image)>0) and
    (Pos(#$48#$8B#$56,Image)>0) and
    (Pos(#$6B#$D2,Image)>0),
    'дві QWord комірки та фізична упаковка: '+String(Title));
  { Попередній 193-байтовий ELF мав безумовний exit(0) після write.
    Єдиний verified host postpass дописує 11 bytes checked-exit,
    а вихід лишається фізичним D1, не ASCII. Borrowed Image без мутацій.
    1) Чому тут 204 bytes? 2) Чому перевіряємо хвіст, а не тільки ELF magic?
    3) Хто визначає закон селектора? 4) Хто перевірить ENOSPC при запуску? }
  Check(Copy(Image,Length(Image)-10,11)=
        #$39#$D0#$40#$0F#$95#$C7#$6A#$3C#$58#$0F#$05,
    'Linux sys_write має перевіряти повний фізичний D1 запис: '+String(Title));
  Check(BuildSelectorT5MELF(Source,RawByteString(Root))=Image,
    'детермінізм машинних байтів: '+String(Title));
  Save(OutputDir+'/'+String(Title)+'.sens',Source);
  Save(OutputDir+'/'+String(Title)+'.elf',Image);
  Save(OutputDir+'/'+String(Title)+'.expected.sens',Expected);
  Save(OutputDir+'/'+String(Title)+'.native.sens',Actual);
  Inc(Good);
end;

procedure NegativeRaw(const Physical:RawByteString;const Why:String);
var Image:RawByteString;Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try Image:=BuildSelectorT5MELF(Physical,RawByteString(Root));
  except on E:EElfSelectorT5MError do Rejected:=True end;
  Check(Rejected and (Image=''),Why);
  Inc(Bad);
end;

procedure Negative(const Items:array of RawByteString;const Why:String);
begin NegativeRaw(EncodeT5M(Words(Items)),Why) end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Використання: test-elfselectort5m pinned-sens тека');
    Halt(64);
  end;
  Root:=ParamStr(1);OutputDir:=ParamStr(2);
  Check(ForceDirectories(OutputDir),'каталог свідків');
  Good:=0;Bad:=0;
  Engine:=TBinaryExecutor.Create(RawByteString(Root));
  try
    Positive('перше-00','100','0','0','0');
    Positive('перше-01','100','0','1','0');
    Positive('перше-10','100','1','0','1');
    Positive('перше-11','100','1','1','1');
    Positive('решта-00','011','0','0','0');
    Positive('решта-01','011','0','1','1');
    Positive('решта-10','011','1','0','0');
    Positive('решта-11','011','1','1','1');

    Negative(['0'],'голий D1 не є викликом');
    Negative(['10','101','10','111','0','1','01','01'],'D3:101 не селектор');
    Negative(['10','100','10','101','0','1','01','01'],'EQ не CONS');
    Negative(['10','100','10','111','0','01','01'],'неповна CONS');
    Negative(['10','011','10','111','0','1','0','01','01'],'зайва арність');
    Negative(['10','100','10','111','000','1','01','01'],'D3:000 не D1');
    Negative(['10','100','10','111','000000000000','1','01','01'],'D12 не D1');
    Negative(['10','100','10','111','0','1','01'],'D2 EOF');
    Negative(['10','100','10','111','0','1','01','01','0'],'дві форми');
    NegativeRaw(#$F3,'неприпустимий T5M байт');
    NegativeRaw('','порожній фізичний файл');
    Check((Good=8) and (Bad=11),'лічильники');
    WriteLn('МАШИННИЙ-СЕЛЕКТОР-T5M-ГАРАЗД позитивні=',Good,
      ' негативні=',Bad,' D3=100/011 CONS=дві-QWord вихід=фізичний-T5M');
  finally Engine.Free end;
end.
