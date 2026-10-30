{ G6.33 — незалежні машинні ELF64 свідки п'яти наявних backend.
  Перевіряємо лише geometry, справжня D3 семантика — native executor.
  Пошкоджені поля або обрізання мають атомарно обнулити out metadata. }
program test_elfgeometry;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.binaryexec,
  wsm.elfquotet5m,wsm.elfatomt5m,wsm.elfeqt5m,
  wsm.elfselectort5m,wsm.elfcondt5m,wsm.elfgeometry;
type TNativeKind=(nkQuote,nkAtom,nkEq,nkSelector,nkCond);
var
  Root,OutputDir:String;
  Positives,Negatives:SizeInt;
  QuoteImage,AtomImage:RawByteString;
  Engine:TBinaryExecutor;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ЕЛФ-ГЕОМЕТРІЯ-ПРОВАЛ: '+Why);
end;

function W(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Save(const Filename:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Filename,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Positive(const LabelText:String;Kind:TNativeKind;
  const SourceWords,ValueWords:array of RawByteString);
var
  Physical,Expected,Image,Again:RawByteString;
  Geo:TElfGeometry;
  TypeExpected:Word;
begin
  Physical:=EncodeT5M(W(SourceWords));
  Expected:=EncodeT5M(W(ValueWords));
  Check(Engine.ExecutePhysicalT5M(Physical)=Expected,
    LabelText+' не відповідає чинному фізичному D3 executor');
  case Kind of
    nkQuote:Image:=BuildQuoteT5MELF(Physical,RawByteString(Root));
    nkAtom:Image:=BuildAtomT5MELF(Physical,RawByteString(Root));
    nkEq:Image:=BuildEqT5MELF(Physical,RawByteString(Root));
    nkSelector:Image:=BuildSelectorT5MELF(Physical,RawByteString(Root));
    nkCond:Image:=BuildCondT5MELF(Physical,RawByteString(Root));
    else raise Exception.Create('Невідомий test host backend');
  end;
  VerifySENSELF64(Image,Geo);
  if Kind in [nkQuote,nkEq,nkSelector] then TypeExpected:=3
  else TypeExpected:=2;
  Check((Geo.Kind=TypeExpected) and
    (Geo.FileBytes=Length(Image)) and
    (Geo.MachineBytes=Length(Image)-120) and
    (Geo.MachineBytes>0) and
    (Geo.Entry=Geo.SegmentBase+120),
    LabelText+' точна фізична метаінформація');
  VerifySENSELF64(Image,Geo);
  Save(OutputDir+'/'+LabelText+'.elf',Image);
  Save(OutputDir+'/'+LabelText+'.expected.sens',Expected);
  if Kind=nkQuote then QuoteImage:=Image;
  if Kind=nkAtom then AtomImage:=Image;
  Inc(Positives);
end;

procedure RejectBad(const Mutated:RawByteString;const Why:String);
var Geo:TElfGeometry;Raised:Boolean;
begin
  FillChar(Geo,SizeOf(Geo),$FF);
  Raised:=False;
  try VerifySENSELF64(Mutated,Geo);
  except on E:EELFGeometryError do Raised:=True end;
  Check(Raised and
    (Geo.Kind=0) and (Geo.Entry=0) and (Geo.SegmentBase=0) and
    (Geo.FileBytes=0) and (Geo.MachineBytes=0),
    Why+' не було атомарно відхилено');
  Inc(Negatives);
end;

procedure Corrupt(const Base:RawByteString;Off:SizeInt;V:Byte;
  const Why:String);
var B:RawByteString;
begin
  Check((Off>=0) and (Off<Length(Base)),Why+' test offset');
  B:=Copy(Base,1,Length(Base));
  Check(Byte(B[Off+1])<>V,Why+' мутація тотожна оригіналу');
  B[Off+1]:=AnsiChar(V);
  RejectBad(B,Why);
end;

{ G6.207: borrow readonly physical ELF; кожна підміна має відмовити
  атомарно, навіть коли зіпсовано старший байт поля. Mutated — власна
  короткоживуча копія RawByteString, виконавчого права не одержує.
  Питання: 1) Чому один біт достатній для регресії кожної позиції?
  2) Чому ET_DYN та ET_EXEC перевіряємо окремо?
  3) Чому out Geometry мусить лишитися нульовою після відмови?
  4) Чому цей тест не доводить SENS-семантику? }
procedure AuditAllHeaderBytes(const Image:RawByteString;const LabelText:String);
var I:SizeInt; Mutated:RawByteString;
begin
  Check(Length(Image)>120,LabelText+' немає machine payload');
  for I:=0 to 119 do begin
    Mutated:=Copy(Image,1,Length(Image));
    Mutated[I+1]:=AnsiChar(Byte(Mutated[I+1]) xor 1);
    RejectBad(Mutated,LabelText+' зіпсований байт '+IntToStr(I));
  end;
end;

var Temp:RawByteString;
begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'Потрібен pinned корінь SENS та каталог ELF');Halt(64);
  end;
  Root:=ParamStr(1);OutputDir:=ParamStr(2);
  Check(ForceDirectories(OutputDir),'створення каталогу');
  Positives:=0;Negatives:=0;
  Engine:=TBinaryExecutor.Create(RawByteString(Root));
  try
    Positive('цитата-д7',nkQuote,
      ['10','001','0010110','01'],['0010110']);
    Positive('атом-д1',nkAtom,['10','010','0','01'],['1']);
    Positive('тотожність-д1',nkEq,['10','101','0','1','01'],['0']);
    Positive('перше-сполучення',nkSelector,
      ['10','100','10','111','0','1','01','01'],['0']);
    Positive('істинна-умова',nkCond,
      ['10','110','10','1','1','01','01'],['1']);
  finally Engine.Free end;

  { Підміна одиничних байтів від НЕЗМІННОГО valid ET_DYN. }
  Corrupt(QuoteImage,0,0,'ELF magic');
  Corrupt(QuoteImage,4,1,'не ELF64 class');
  Corrupt(QuoteImage,5,2,'не little endian');
  Corrupt(QuoteImage,6,2,'ident version');
  Corrupt(QuoteImage,7,3,'OSABI');
  Corrupt(QuoteImage,8,1,'ABI version');
  Corrupt(QuoteImage,15,1,'reserved ident');
  Corrupt(QuoteImage,16,2,'ET_EXEC під чужою базою');
  Corrupt(QuoteImage,18,3,'не EM_X86_64');
  Corrupt(QuoteImage,20,2,'ELF header version');
  Corrupt(QuoteImage,24,119,'entry перед machine code');
  Corrupt(QuoteImage,32,0,'немає program headers');
  Corrupt(QuoteImage,40,1,'зайві section headers');
  Corrupt(QuoteImage,48,1,'ELF flags');
  Corrupt(QuoteImage,52,63,'e_ehsize');
  Corrupt(QuoteImage,54,55,'e_phentsize');
  Corrupt(QuoteImage,56,2,'другий program header');
  Corrupt(QuoteImage,58,64,'section header entry size');
  Corrupt(QuoteImage,60,1,'section count');
  Corrupt(QuoteImage,62,1,'section string index');
  Corrupt(QuoteImage,64,2,'PT_LOAD type');
  Corrupt(QuoteImage,68,7,'RWX segment замість RX');
  Corrupt(QuoteImage,72,1,'segment file offset');
  Corrupt(QuoteImage,80,1,'ET_DYN segment base');
  Corrupt(QuoteImage,88,1,'ET_DYN physical address');
  Corrupt(QuoteImage,96,1,'неповний file payload');
  Corrupt(QuoteImage,104,1,'неповний memory payload');
  Corrupt(QuoteImage,112,1,'p_align');
  Corrupt(AtomImage,16,3,'ET_DYN із адресами ET_EXEC');
  Corrupt(AtomImage,80,1,'ET_EXEC p_vaddr');
  Corrupt(AtomImage,24,119,'ET_EXEC entry не 0x400078');

  Temp:=Copy(QuoteImage,1,Length(QuoteImage)-1);
  RejectBad(Temp,'обрізано payload');
  Temp:=QuoteImage+#0;
  RejectBad(Temp,'дописано байт поза p_filesz');
  RejectBad('','порожній ELF');
  Temp:=Copy(QuoteImage,1,120);
  RejectBad(Temp,'немає машинної інструкції');
  Temp:=QuoteImage;
  SetLength(Temp,1024*1024+1);
  RejectBad(Temp,'перевищено host бюджет');

  AuditAllHeaderBytes(QuoteImage,'ET_DYN');
  AuditAllHeaderBytes(AtomImage,'ET_EXEC');

  Check((Positives=5) and (Negatives=276),
    'фіксовані лічильники позитивних та негативних тестів');
  WriteLn('ЕЛФ64-ГЕОМЕТРІЯ-ГАРАЗД чинних-backend=',Positives,
    ' негативів=',Negatives,
    ' ET_EXEC+ET_DYN=так RX=так T5M=точний статистика=атомарна');
end.
