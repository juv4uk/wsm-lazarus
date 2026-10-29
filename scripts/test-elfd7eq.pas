{ G6.54: ТІЛЬКИ фізичні T5M свідки та машинні ELF64;
  незалежний pinned SENS oracle запускається у shell на тих самих файлах. }
program test_elfd7eq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfd7eq;
var Root,Dir:String;Passed,Rejected:SizeInt;

function Pack(const Parts:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Parts));
  for I:=0 to High(Parts) do W[I]:=Parts[I];
  Result:=EncodeT5M(W);
end;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('ELF-Д7-ПРОВАЛ: '+Why);
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

{ На вході два позичені точні W7, на виході — 3 власні файли test.
  Фізична відповідь у .expected.sens є packed T5M, не ASCII 0/1.
  ELF відповідає ET_DYN, реально порівнює біти на Linux x86-64. }
procedure Positive(const LabelText:String;
  const Left,Right,Expected:RawByteString);
var Physical,Elf,ExpectedPhysical:RawByteString;
    I,Offset:SizeInt;
begin
  Physical:=Pack(['10','101','10','001',Left,'01',
                      '10','001',Right,'01','01']);
  Elf:=BuildQuotedD7EqELF(Physical,RawByteString(Root));
  ExpectedPhysical:=Pack([Expected]);
  Need((Length(Elf)>160) and (Length(Elf)<400),'ELF довжина: '+LabelText);
  Need((Copy(Elf,1,4)=#$7F'ELF') and (Ord(Elf[5])=2) and
    (Ord(Elf[17])=3) and (Ord(Elf[19])=62),
    'ELF64 ET_DYN x86-64: '+LabelText);
  Need((Ord(Elf[121])=$31) and (Ord(Elf[122])=$C0),
    'машинний accumulator: '+LabelText);
  for I:=0 to 6 do begin
    Offset:=123+I*7;
    Need((Ord(Elf[Offset])=$B1) and
      (Ord(Elf[Offset+2])=$80) and
      (Ord(Elf[Offset+3])=$F1) and
      (Ord(Elf[Offset+5])=$08) and
      (Ord(Elf[Offset+6])=$C8),
      'відсутній машинний XOR/OR для біта '+IntToStr(I+1));
    Need(Ord(Elf[Offset+1]) in [0,1],
      'лівий W7 біт поза фізичним 0/1');
    Need(Ord(Elf[Offset+4]) in [0,1],
      'правий W7 біт поза фізичним 0/1');
  end;
  Need(Pos(#$84#$C0#$0F#$94#$C0#$0F#$B6#$C0,Elf)>0,
    'CPU не виконує TEST/SETE/MOVZX');
  Need(BuildQuotedD7EqELF(Physical,RawByteString(Root))=Elf,
    'недетермінований ELF');
  Save(Dir+'/'+LabelText+'.sens',Physical);
  Save(Dir+'/'+LabelText+'.elf',Elf);
  Save(Dir+'/'+LabelText+'.expected.sens',ExpectedPhysical);
  Save(Dir+'/'+LabelText+'.expected.txt',Expected+#10);
  Inc(Passed);
end;

procedure NegativeRaw(const Physical:RawByteString;const Why:String);
var Img:RawByteString;Denied:Boolean;
begin
  Img:='';Denied:=False;
  try Img:=BuildQuotedD7EqELF(Physical,RawByteString(Root));
  except on E:EELFD7EqError do Denied:=True end;
  Need(Denied and (Img=''),Why);
  Inc(Rejected);
end;

procedure Negative(const Parts:array of RawByteString;const Why:String);
begin NegativeRaw(Pack(Parts),Why) end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Потрібні: pinned-корінь та тека результатів');Halt(64);
  end;
  Root:=ParamStr(1);Dir:=ParamStr(2);
  Need(ForceDirectories(Dir),'не створено тести');
  Passed:=0;Rejected:=0;
  Positive('син-однакові','0010110','0010110','1');
  Positive('син-різні','0010110','0000000','0');
  Positive('старший-однакові','1111111','1111111','1');
  Positive('старший-різні','1111111','0010110','0');
  Positive('нулі-однакові','0000001','0000001','1');
  Positive('нулі-різні','0000001','0000010','0');
  Negative(['1'],'D1 без D3 голови');
  Negative(['10','0010110','1','01'],'D7 не виклична голова');
  Negative(['10','101','0010110',
    '10','001','0010110','01','01'],'нецитований лівий W7');
  Negative(['10','101','10','001','0010110','01',
    '0010110','01'],'нецитований правий W7');
  Negative(['10','101','10','001','000000000000','01',
    '10','001','0010110','01','01'],'D12 не є D7');
  Negative(['10','101','10','001','0010110','01',
    '1','01'],'D1 не можна неявно прийняти як D7');
  Negative(['10','101','10','001','0010110','01',
    '10','001','0010110','01','1','01'],'зайва арність');
  Negative(['10','101','10','001','0010110','01',
    '01'],'неповна арність');
  Negative(['10','101','10','001','0010110','01',
    '10','001','0010110','01','01','1'],'другий корінь');
  Negative(['10','101','10','001','000','01',
    '10','001','0010110','01','01'],'D3:000 не D7');
  NegativeRaw(#$F3,'неканонічний T5M');
  NegativeRaw('','порожній файл');
  Need((Passed=6) and (Rejected=12),'кількість свідків');
  WriteLn('ЕЛФ-Д7-ТОТОЖНІСТЬ-ГАРАЗД x86-64=ET_DYN машинних=6',
    ' негативів=12 D7=7-бітні-дані T5M=канонічний',
    ' XOR=7-на-кожен-ELF D12=не-допущено');
end.
