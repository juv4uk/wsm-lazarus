{ G6.252 — справжні фізичні D24 пари, відмови та машинні ELF64.
  Ухідні canonical .sens атоми створює чинний numericplane, референтний
  локальний pinned numericadd, а FPC ELF виконує арифметику лише на CPU.
  Створені файли/процеси належать shell harness; FPC потоки закриті.
  1) Чому fixture очікування — НЕ незалежний SENS REPL oracle?
  2) Чому 65535+1 перевіряє перенесення між low16/high8?
  3) Чому -8388608-1 вимагає D48 і відмови?
  4) Чому відмови не створюють ELF для публікації?
  5) Чому повернуті exact bytes перевіряє зовнішній Linux процес? }
program test_elfd24carry;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.elfd24carry,wsm.numericplane,
  wsm.numericadd,wsm.elfgeometry;
type
  TCase = record
    LabelText,LeftText,RightText:String;
  end;
const
  Cases:array[0..9] of TCase=(
    (LabelText:'01';LeftText:'65535';RightText:'1'),
    (LabelText:'02';LeftText:'131071';RightText:'1'),
    (LabelText:'03';LeftText:'-65536';RightText:'-1'),
    (LabelText:'04';LeftText:'-1';RightText:'1'),
    (LabelText:'05';LeftText:'-123456';RightText:'234567'),
    (LabelText:'06';LeftText:'8388606';RightText:'1'),
    (LabelText:'07';LeftText:'-8388608';RightText:'1'),
    (LabelText:'08';LeftText:'-65535';RightText:'-2'),
    (LabelText:'09';LeftText:'65535';RightText:'65535'),
    (LabelText:'10';LeftText:'0';RightText:'0')
  );
var Folder:String;
    Index,Positives,Negatives:Integer;
    LeftPhysical,RightPhysical,Expected,Image,Previous:RawByteString;
    M:TStringList;
    G:TELFGeometry;
    Caught:Boolean;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('D24-CARRY-ТЕСТ-ПОМИЛКА: '+Why);
end;

procedure Save(const Name:String;const Content:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try
    if Length(Content)>0 then F.WriteBuffer(Content[1],Length(Content));
  finally F.Free; end;
end;

procedure One(const Row:TCase);
begin
  LeftPhysical:=EncodeNumericDecimal(Row.LeftText,24);
  RightPhysical:=EncodeNumericDecimal(Row.RightText,24);
  Expected:=AddNumericPhysical(LeftPhysical,RightPhysical,24);
  Need(Length(Expected)=5,'expected D24 не фізично п’ятибайтовий');
  Image:=BuildD24CarryAddELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(Image)) and
       (G.MachineBytes<=256),'ELF64 PIE не пройшов геометрію');
  Save(Row.LabelText+'.elf',Image);
  Save(Row.LabelText+'.expected.sens',Expected);
  Save(Row.LabelText+'.left.sens',LeftPhysical);
  Save(Row.LabelText+'.right.sens',RightPhysical);
  Inc(Positives);
end;

procedure Reject(const L,R:RawByteString;const Why:String);
begin
  Previous:=Image;
  Caught:=False;
  try
    Image:=BuildD24CarryAddELF(L,R);
  except on E:Exception do Caught:=True end;
  Need(Caught and (Image=Previous),'неатомарна відмова: '+Why);
  Inc(Negatives);
end;

begin
  Need(ParamCount=1,'потрібен приватний каталог');
  Folder:=ParamStr(1);
  Need(DirectoryExists(Folder),'немає каталогу результатів');
  M:=TStringList.Create;
  try
    Positives:=0;Negatives:=0;
    for Index:=Low(Cases) to High(Cases) do begin
      One(Cases[Index]);
      M.Add(Cases[Index].LabelText);
    end;
    M.SaveToFile(Folder+'/cases.txt');
    Need(Positives=10,'має бути рівно 10 позитивів');
    LeftPhysical:=EncodeNumericDecimal('8388607',24);
    RightPhysical:=EncodeNumericDecimal('1',24);
    Reject(LeftPhysical,RightPhysical,'позитивне переповнення D48');
    LeftPhysical:=EncodeNumericDecimal('-8388608',24);
    RightPhysical:=EncodeNumericDecimal('-1',24);
    Reject(LeftPhysical,RightPhysical,'негативне переповнення D48');
    LeftPhysical:=EncodeNumericDecimal('0',24);
    RightPhysical:=EncodeNumericDecimal('0',24);
    Reject(EncodeNumericDecimal('1',12),RightPhysical,'не D24 ліворуч');
    Reject(LeftPhysical,EncodeNumericDecimal('1',12),'не D24 праворуч');
    Reject(#$FF,RightPhysical,'зіпсований T5M');
    Reject(LeftPhysical,#$FF,'зіпсований другий T5M');
    Reject('',RightPhysical,'порожній фізичний потік');
    Reject(LeftPhysical,'','порожній другий фізичний потік');
    Need(Negatives=8,'має бути рівно 8 негативів');
    One(Cases[0]); { підтверджений recovery після всіх відмов }
    Need(Positives=11,'відновлення після відмов');
    WriteLn('D24-CARRY-ГОТОВО ELF64=10 negative=8 recovery=1 ',
      'T5M=W24-exact CPU=ADD-ADC oracle=LOCAL-PINNED energy=NOT-MEASURED');
  finally M.Free end;
end.
