{ G6.35 — перевірений ELF64 публікується тільки після повного admission.
  Джерело семантики — pinned фізичний SENS через чинні emitters.
  Негативні поля ELF, хибний host тип і O_EXCL не лишають виходу. }
program test_elfpublish;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.elfquotet5m,
  wsm.elfatomt5m,wsm.elfeqt5m,wsm.elfgeometry,wsm.elfpublish;
var
  Root,Dir:String;
  QuoteImage,AtomImage,EqImage,Temp:RawByteString;
  Positives,Negatives:SizeInt;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ПУБЛІКАЦІЯ-ELF-ПОМИЛКА: '+Why);
end;

function Words(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;

function ReadAll(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result,SizeInt(F.Size));
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure Positive(const LabelText:String;const Image,Answer:RawByteString;
  HostKind:Word);
var Geo:TELFGeometry;Path:String;
begin
  Path:=Dir+'/'+LabelText+'.elf';
  Check(not FileExists(Path),'Неочікувана наявна ціль: '+LabelText);
  FillChar(Geo,SizeOf(Geo),$FF);
  PublishNewELF64(Path,Image,HostKind,Geo);
  Check((Geo.Kind=HostKind) and (Geo.FileBytes=Length(Image)) and
    (Geo.MachineBytes=Length(Image)-120) and
    (Geo.Entry=Geo.SegmentBase+120) and
    (ReadAll(Path)=Image),'Не опубліковано точний повний ELF: '+LabelText);
  Save(Dir+'/'+LabelText+'.expected.sens',Answer);
  Inc(Positives);
end;

procedure Rejected(const Why:String;const Image:RawByteString;Kind:Word);
var
  Geo:TELFGeometry;RejectedError:Boolean;Path:String;
begin
  Path:=Dir+'/відмова-'+IntToStr(Negatives)+'.elf';
  Check(not FileExists(Path),'Неочікуваний тестовий файл');
  FillChar(Geo,SizeOf(Geo),$FF);
  RejectedError:=False;
  try PublishNewELF64(Path,Image,Kind,Geo);
  except on E:EELFPublishError do RejectedError:=True end;
  Check(RejectedError and (not FileExists(Path)) and
    (Geo.Kind=0) and (Geo.Entry=0) and
    (Geo.SegmentBase=0) and (Geo.FileBytes=0) and
    (Geo.MachineBytes=0),Why+' — мала бути атомарна відмова');
  Inc(Negatives);
end;

procedure Mutate(const Why:String;Offset:SizeInt;Value:Byte);
var Bytes:RawByteString;
begin
  Bytes:=Copy(QuoteImage,1,Length(QuoteImage));
  Check((Offset>=0) and (Offset<Length(Bytes)),'Тестовий offset');
  Check(Byte(Bytes[Offset+1])<>Value,'Немутований тест '+Why);
  Bytes[Offset+1]:=AnsiChar(Value);
  Rejected(Why,Bytes,3);
end;

procedure TestAlreadyExists;
var
  Geo:TELFGeometry;Raised:Boolean;Path:String;
begin
  Path:=Dir+'/цитата-д7.elf'; { позитив уже створив цей ELF }
  FillChar(Geo,SizeOf(Geo),$FF);
  Raised:=False;
  try PublishNewELF64(Path,EqImage,3,Geo);
  except on E:EELFPublishError do Raised:=True end;
  Check(Raised and (Geo.Kind=0) and (Geo.FileBytes=0) and
    (ReadAll(Path)=QuoteImage),
    'O_EXCL не зберіг існуючий ELF байт-в-байт');
  Inc(Negatives);
end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Потрібні: pinned SENS і тека свідків');Halt(64);
  end;
  Root:=ParamStr(1);Dir:=ParamStr(2);
  Check(ForceDirectories(Dir),'Створення каталогу');
  Positives:=0;Negatives:=0;
  QuoteImage:=BuildQuoteT5MELF(
    EncodeT5M(Words(['10','001','0010110','01'])),RawByteString(Root));
  AtomImage:=BuildAtomT5MELF(
    EncodeT5M(Words(['10','010','0','01'])),RawByteString(Root));
  EqImage:=BuildEqT5MELF(
    EncodeT5M(Words(['10','101','0','1','01'])),RawByteString(Root));

  Positive('цитата-д7',QuoteImage,
    EncodeT5M(Words(['0010110'])),3);
  Positive('атом-д1',AtomImage,
    EncodeT5M(Words(['1'])),2);
  Positive('тотожність-д1',EqImage,
    EncodeT5M(Words(['0'])),3);

  Rejected('порожній файл','',3);
  Rejected('обрізаний файл',Copy(QuoteImage,1,Length(QuoteImage)-1),3);
  Rejected('зайвий хвостовий байт',QuoteImage+#0,3);
  Mutate('магія ELF',0,0);
  Mutate('не ELF64',4,1);
  Mutate('великий endian',5,2);
  Mutate('невірний x86-64',18,3);
  Mutate('помилковий ET_EXEC',16,2);
  Mutate('змінено entry',24,119);
  Mutate('не RX',68,7);
  Mutate('file size',96,1);
  Mutate('memory size',104,1);
  Mutate('вирівнювання',112,1);
  Rejected('неправильний явний host тип',QuoteImage,2);
  Rejected('неправильний atom host тип',AtomImage,3);
  Rejected('непідтриманий host тип',QuoteImage,0);
  Temp:=Copy(QuoteImage,1,Length(QuoteImage));
  SetLength(Temp,1024*1024+1);
  Rejected('понад host квоту',Temp,3);
  TestAlreadyExists;
  Check((Positives=3) and (Negatives=18),'Неточні лічильники');
  WriteLn('ПЕРЕВІРЕНА-ПУБЛІКАЦІЯ-ELF-ГАРАЗД файлів=',Positives,
    ' негативних=',Negatives,' геометрія=спільна O_EXCL=так T5M=точний');
end.
