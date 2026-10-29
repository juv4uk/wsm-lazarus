{ G6.67 — фізичні FPC свідки нативного третього елемента.
  Цей host тест не є самодостатнім семантичним oracle; для кожного
  D1 результату shell запускає також незалежний pinned SENS. }
program test_ird5third;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.ird5third;
var Root,Dir:String; Positives,Negatives,I:SizeInt; Source,Image:RawByteString;
function Words(const Items:array of RawByteString):TExactWords;
var K:SizeInt;
begin
  SetLength(Result,Length(Items));
  for K:=0 to High(Items) do Result[K]:=Items[K];
end;
{ У FPC 3.2.2 WriteLn має host codepage: українська може стати '?'.
  Цей байтовий UTF-8 вихід — лише діагностика, не SENS проєкція.
  Питання: чому RawByteString і UnicodeString не тотожні?
  Чому лог не є джерелом мовного закону? }
procedure WriteUtf8Line(const S:UnicodeString);
var Raw:UTF8String; Stream:THandleStream;
begin
  Raw:=UTF8Encode(S+#10);
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try if Length(Raw)>0 then Stream.WriteBuffer(Raw[1],Length(Raw))
  finally Stream.Free end;
end;
procedure Need(Good:Boolean;const Why:String);
begin if not Good then raise Exception.Create('D5-ELF-ТЕСТ: '+Why) end;
procedure Save(const Filename:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(IncludeTrailingPathDelimiter(Dir)+Filename,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
function Bit(N:SizeInt):RawByteString;
begin
  if N=0 then Result:='0' else Result:='1';
end;
function Form(const A,B,C:RawByteString):RawByteString;
begin
  Result:=EncodeT5M(Words(['10','10011','10','1110',A,B,C,'01','01']));
end;
procedure Reject(const Data:RawByteString;const Why:String);
var Got:RawByteString; Failed:Boolean;
begin
  Got:='';Failed:=False;
  try Got:=BuildPinnedIRThirdELF(Data,RawByteString(Root))
  except on E:EIRThirdError do Failed:=True end;
  Need(Failed and (Got=''),'прийнято '+Why);
  Inc(Negatives);
end;
begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);Dir:=ParamStr(2);
  Need(ForceDirectories(Dir),'каталог тестових файлів');
  Positives:=0;Negatives:=0;
  for I:=0 to 7 do begin
    Source:=Form(Bit((I shr 2) and 1),Bit((I shr 1) and 1),Bit(I and 1));
    Image:=BuildPinnedIRThirdELF(Source,RawByteString(Root));
    Need((Length(Image)>180) and (Copy(Image,1,4)=#$7F'ELF') and
         (Ord(Image[17])=3) and (Ord(Image[19])=62),
         'ELF64 PIE не має правильної машини');
    Need(BuildPinnedIRThirdELF(Source,RawByteString(Root))=Image,
         'два компіляторні проходи породили різні байти');
    Save('третє-'+IntToStr(I)+'.sens',Source);
    Save('третє-'+IntToStr(I)+'.expected.sens',
         EncodeT5M(Words([Bit(I and 1)])));
    Save('третє-'+IntToStr(I)+'.elf',Image);
    Inc(Positives);
  end;
  Reject(EncodeT5M(Words(['0'])),'голий D1');
  Reject(EncodeT5M(Words(['10','1001','10','1110','0','1','0','01','01'])),
    'D4:1001 не D5:10011');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','01','01'])),
    'лише два елементи');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','0','1','01','01'])),
    'чотири елементи поза вузьким AOT профілем');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','000','01','01'])),
    'D3 порожній не є D1');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','0010110','01','01'])),
    'D7 не є D1');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','000000000000','01','01'])),
    'D12 не є D1');
  Reject(EncodeT5M(Words(['10','10011','10','1111','0','1','0','01','01'])),
    'чужий D4 list-конструктор');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','0','11','01','01'])),
    'dotted pair не proper-list');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','0','01'])),
    'обірвана D2 форма');
  Reject(EncodeT5M(Words(['10','10011','10','1110','0','1','0','01','01','0'])),
    'другий фізичний корінь');
  Reject(AnsiChar(243),'фізично неприпустимий байт');
  Reject('','порожній T5M');
  Source:=Form('1','0','1');
  Need(BuildPinnedIRThirdELF(Source,RawByteString(Root))=
       BuildPinnedIRThirdELF(Source,RawByteString(Root)),
       'немає відновлення після 13 відмов');
  Need((Positives=8) and (Negatives=13),'лічильники тестів');
  WriteUtf8Line('D5-ТРЕТЄ-FPC-ГАРАЗД ELF=8 негативи=13 '+
    'D5=10011 D4=1110 D1=точний відновлення=так');
end.
