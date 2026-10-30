{ G6.240 — тільки фізичні D5 ADD/SUB W12 донори та x86 host-frame.
  Pinned Contract 12.0 і канонічний T5M codec визначають закон/байти.
  Числові очікування — чинні FPC numeric helpers, НЕ незалежний REPL.
  Три owned RawByteString ELF, атомарні негативи й незалежне звірення.
  1) Чому 6 байтів stdin не є одним .sens документом?
  2) Чому QUOT мусить отримувати незагорнутий донор?
  3) Чим відрізняється D12:2047 від D24:2048?
  4) Чому repeated x64 host-prefix слід відхилити?
  5) Де саме здійснюється pinned D5 admission? }
program TestAdaptiveFrame;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
  wsm.numericsub,wsm.elfd12addpotikadaptive,wsm.x64frameio,
  wsm.elfgeometry;
var OutDir:String;Cases:Integer;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('адаптивний кадр: '+Why) end;

procedure Save(const Name:String;const Data:RawByteString);
var FileStream:TFileStream;
begin
  FileStream:=TFileStream.Create(OutDir+'/'+Name,fmCreate);
  try if Data<>'' then FileStream.WriteBuffer(Data[1],Length(Data));
  finally FileStream.Free end;
end;

function BitsOf(const N:RawByteString):RawByteString;
var Value:TExplicitNumeric;
begin
  Value:=ReadNumericPhysical(EncodeNumericDecimal(N,12),12);
  Need((Value.DomainWidth=12) and (Length(Value.ExactBits)=12),
    'втрачено точний D12');
  Result:=Value.ExactBits;
end;

function Pack(const B:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(B));
  for I:=0 to High(B) do W[I]:=B[I];
  Result:=EncodeT5M(W);
end;

procedure CheckELF(const Image:RawByteString);
var G:TELFGeometry;
begin
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Image)),'ELF64 PIE geometry');
end;

procedure CheckContract(const IsSub:Boolean);
var Anchor,Donor,Framed,Repeated:RawByteString;
    Rejected:Boolean;
begin
  if IsSub then begin
    Anchor:=Pack(['10','01011',BitsOf('7'),BitsOf('2'),'01']);
    Donor:=BuildAdaptiveD12SubStreamELF(Anchor,'external/sens');
    Framed:=BuildAdaptiveD12SubFramedELF(Anchor,'external/sens');
    Repeated:=BuildAdaptiveD12SubFramedELF(Anchor,'external/sens');
    Save('sub.anchor.sens',Anchor);
  end else begin
    Anchor:=Pack(['10','01010',BitsOf('1'),BitsOf('1'),'01']);
    Donor:=BuildAdaptiveD12AddStreamELF(Anchor,'external/sens');
    Framed:=BuildAdaptiveD12AddFramedELF(Anchor,'external/sens');
    Repeated:=BuildAdaptiveD12AddFramedELF(Anchor,'external/sens');
    Save('add.anchor.sens',Anchor);
  end;
  Need((Length(Framed)>Length(Donor)) and (Framed=Repeated),
    'загорнутий EOF ELF недетермінований');
  Need((Copy(Donor,125,2)=#$31#$C0) and
       (Copy(Framed,125,3)=#$45#$31#$D2),
    'донорський пролог або frame-read змінився');
  CheckELF(Donor);CheckELF(Framed);
  Rejected:=False;
  try
    Repeated:=WrapExactSixByteFrame(Framed)
  except on E:EFrameIO do Rejected:=True end;
  Need(Rejected,'дозволено подвійний EOF prefix');
end;

procedure CaseD12(const LabelName,LeftDec,RightDec,Wanted:RawByteString;
  const IsSub:Boolean;Width:SizeInt);
var L,R,Expected,Actual:RawByteString;N:TExplicitNumeric;
begin
  L:=EncodeNumericDecimal(LeftDec,12);
  R:=EncodeNumericDecimal(RightDec,12);
  if IsSub then Actual:=SubtractNumericPhysical(L,R,12)
  else Actual:=AddNumericPhysical(L,R,12);
  Expected:=EncodeNumericDecimal(Wanted,Width);
  N:=ReadNumericPhysical(Actual,Width);
  Need((N.DomainWidth=Width) and (Actual=Expected),
    'числове очікування не відповідає чинному D12/D24 механізму');
  Save(String(LabelName)+'.frame',L+R);
  Save(String(LabelName)+'.expected.sens',Expected);
  Inc(Cases);
end;

{ Звіт є borrowed host stdout, а не текстова семантика SENS.
  FPC 3.2.2 WriteLn може перетворювати UTF-8 кирилицю на '?';
  явний UTF8Encode + WriteBuffer зберігає точні байти.
  Output stream borrowed, THandleStream звільняється в finally.
  1) Чому кодова сторінка не повинна псувати CI свідок?
  2) Чим stdout технічного тесту відрізняється від .sens?
  3) Хто володіє THandleStream після повернення? }
procedure ReportUTF8(const Message:UnicodeString);
var Data:RawByteString;Stream:THandleStream;
begin
  Data:=RawByteString(UTF8Encode(Message))+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Data[1],Length(Data))
  finally Stream.Free end;
end;

begin
  Need(ParamCount=1,'потрібен один вихідний каталог');
  OutDir:=ParamStr(1);
  Need(DirectoryExists(OutDir),'немає вихідного каталогу');
  Cases:=0;
  CheckContract(False);
  CheckContract(True);
  CaseD12('add-small','1','1','2',False,12);
  CaseD12('add-wide','2047','1','2048',False,24);
  CaseD12('sub-small','7','2','5',True,12);
  CaseD12('sub-wide','-2048','1','-2049',True,24);
  Need(Cases=4,'очікувано чотири фізичні справи');
  ReportUTF8('АДАПТИВНЕ-КАДР-СВІДКИ-ГОТОВО profiles=2 cases=4 donor=raw framed=once double=reject');
end.
