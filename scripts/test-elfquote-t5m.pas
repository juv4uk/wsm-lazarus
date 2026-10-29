{ G6.28. Незалежні механічні позитиви/негативи ELF фізичної цитати.
  Очікувані байти походять з точних фізичних слів, а не з ASCII Render. }
program test_elfquote_t5m;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.binaryexec,wsm.elfquotet5m;
var
  AuthorityRoot,OutputDir:String;
  Positives,Negatives:SizeInt;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('ПЕРЕВІРКА-ЦИТАТИ-ПРОВАЛ: '+Why);
end;

procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

function ReadLE(const Data:RawByteString;Off,N:SizeInt):QWord;
var I:SizeInt;
begin
  Check((N>0) and (N<=8) and (Off>=0) and
    (Off<=Length(Data)-N),'поле ELF за межами файла');
  Result:=0;
  for I:=N-1 downto 0 do
    Result:=(Result shl 8) or Ord(Data[Off+I+1]);
end;

procedure Positive(const Name:RawByteString;
  const FormWords,ValueWords:array of RawByteString);
var Source,Expected,Image,Got:RawByteString;
    Engine:TBinaryExecutor;
begin
  Source:=EncodeT5M(Words(FormWords));
  Expected:=EncodeT5M(Words(ValueWords));
  Engine:=TBinaryExecutor.Create(RawByteString(AuthorityRoot));
  try Got:=Engine.ExecutePhysicalT5M(Source);
  finally Engine.Free end;
  Check(Got=Expected,'розходження з чинним D3 виконавцем '+String(Name));
  Image:=BuildQuoteT5MELF(Source,RawByteString(AuthorityRoot));
  Check(Length(Image)=153+Length(Expected),'загальна довжина ELF');
  Check((Copy(Image,1,4)=#$7F'ELF') and
    (Ord(Image[5])=2) and (ReadLE(Image,16,2)=3) and
    (ReadLE(Image,18,2)=62) and (ReadLE(Image,24,8)=120) and
    (ReadLE(Image,64,4)=1) and (ReadLE(Image,68,4)=5) and
    (ReadLE(Image,96,8)=QWord(Length(Image))) and
    (ReadLE(Image,104,8)=QWord(Length(Image))),
    'неповний ELF64 ET_DYN');
  Check(Copy(Image,121,3)=#$B8#$01#0,'Linux write syscall');
  Check(Copy(Image,131,3)=#$48#$8D#$35,'RIP-relative lea');
  Check(ReadLE(Image,133,4)=16,'RIP displacement');
  Check(ReadLE(Image,138,4)=QWord(Length(Expected)),
    'точна довжина фізичного машинного stdout');
  Check(Copy(Image,154,Length(Expected))=Expected,
    'фізичний T5M літерал не збігся');
  Check(BuildQuoteT5MELF(Source,RawByteString(AuthorityRoot))=Image,
    'генерація ELF не детермінована');
  Save(OutputDir+'/'+String(Name)+'.elf',Image);
  Save(OutputDir+'/'+String(Name)+'.expected.sens',Expected);
  Inc(Positives);
end;

procedure NegativeRaw(const Source:RawByteString;const Why:String);
var Image:RawByteString; Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try Image:=BuildQuoteT5MELF(Source,RawByteString(AuthorityRoot));
  except on E:EELFQuoteT5MError do Rejected:=True end;
  Check(Rejected and (Image=''),Why);
  Inc(Negatives);
end;

procedure Negative(const FormWords:array of RawByteString;const Why:String);
begin NegativeRaw(EncodeT5M(Words(FormWords)),Why) end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Потрібні: корінь pinned SENS та каталог свідків');Halt(64);
  end;
  AuthorityRoot:=ParamStr(1);
  OutputDir:=ParamStr(2);
  Check(ForceDirectories(OutputDir),'створення каталогу свідків');
  Positives:=0;Negatives:=0;
  Positive('д1-нуль',['10','001','0','01'],['0']);
  Positive('д1-один',['10','001','1','01'],['1']);
  Positive('д3-порожньо',['10','001','000','01'],['000']);
  Positive('д7-керування',['10','001','0010110','01'],['0010110']);
  Positive('д9-нулі',['10','001','000000001','01'],['000000001']);
  Positive('список',['10','001','10','0','1','01','01'],
                      ['10','0','1','01']);
  Positive('вкладений',['10','001','10','1','10','0','01','01','01'],
                        ['10','1','10','0','01','01']);
  Negative(['0'],'голий D1 — не D3:001');
  Negative(['10','111','0','01'],'чужа голова D3:111');
  Negative(['10','001','01'],'порожня арність');
  Negative(['10','001','0','1','01'],'два аргументи');
  Negative(['10','001','0'],'незакрита форма');
  Negative(['10','001','000000000001','01'],'непідтриманий D12');
  Negative(['10','001','10','0','11','1','01'],
           'крапкова цитата ще не виконується');
  NegativeRaw(#243,'неканонічний транспортний байт');
  NegativeRaw('','порожня програма');
  Check((Positives=7) and (Negatives=9),'неповний набір свідків');
  WriteLn('ЦИТАТА-ЕЛФ-ГАРАЗД позитивні=',Positives,
    ' негативні=',Negatives,' виконавець=чинний T5M=точний ELF=ET_DYN');
end.
