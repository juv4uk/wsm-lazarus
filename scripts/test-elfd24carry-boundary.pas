{ G6.260 — фізична матриця знакових меж D24 на наявному ADD→ADC ELF64.
  Немає нового мовного закону: canonical T5M постачає pinned numericplane;
  expected формується окремо математикою Int64, потім кодується pinned.
  Генератор володіє managed ELF і TFileStream; виконує ELF shell тест.
  1) Чому Int64 тут — тільки тестовий оракул арифметики, не SENS law?
  2) Чому D24→D48 до публікації ELF є обов'язковою відмовою?
  3) Де перевірено перенесення молодших 16 бітів?
  4) Хто звільняє TFileStream і TStrings після винятку?
  5) Чому результати має порівнювати ще окремий процес Linux? }
program test_elfd24carry_boundary;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.elfd24carry,wsm.numericplane,
     wsm.numericadd,wsm.elfgeometry;
const
  Lefts:array[0..9] of LongInt=
    (-8388608,-65536,-65535,-1,0,1,65534,65535,65536,8388607);
  Rights:array[0..7] of LongInt=
    (-8388608,-65536,-1,0,1,65535,65536,8388607);
  MinD24=-8388608;
  MaxD24=8388607;
var
  Folder,LabelText:String;
  L,R,Positives,Negatives:Integer;
  S:Int64;
  LeftPhysical,RightPhysical,Expected,Pinned,Image,Previous,
  FirstImage,Recovered:RawByteString;
  Cases:TStringList;
  Geometry:TELFGeometry;
  Failed:Boolean;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('D24-BOUNDARY-ПРОВАЛ: '+Why);
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Accept(const A,B:LongInt;const Sum:Int64);
begin
  { Input — два окремі канонічні фізичні D24 атоми T5M, а не
    українські імена у функціональній позиції й не один D2 виклик.
    Власні Image і Expected лишаються керованими рядками caller. }
  LeftPhysical:=EncodeNumericDecimal(RawByteString(IntToStr(A)),24);
  RightPhysical:=EncodeNumericDecimal(RawByteString(IntToStr(B)),24);
  Expected:=EncodeNumericDecimal(RawByteString(IntToStr(Sum)),24);
  Pinned:=AddNumericPhysical(LeftPhysical,RightPhysical,24);
  Need((Expected=Pinned) and (Length(Expected)=5),
       'host математичне очікування не збігається з pinned D24 T5M');
  Image:=BuildD24CarryAddELF(LeftPhysical,RightPhysical);
  VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.Entry=120) and
       (Geometry.FileBytes=Length(Image)) and
       (Geometry.MachineBytes>0) and (Geometry.MachineBytes<=256),
       'невірна точна ELF64 PIE геометрія');
  Inc(Positives);
  LabelText:=Format('%.2d',[Positives]);
  Save(LabelText+'.elf',Image);
  Save(LabelText+'.expected.sens',Expected);
  Save(LabelText+'.left.sens',LeftPhysical);
  Save(LabelText+'.right.sens',RightPhysical);
  Cases.Add(LabelText);
  if (A=65535) and (B=1) then FirstImage:=Image;
end;

procedure RejectOverflow(const A,B:LongInt);
begin
  LeftPhysical:=EncodeNumericDecimal(RawByteString(IntToStr(A)),24);
  RightPhysical:=EncodeNumericDecimal(RawByteString(IntToStr(B)),24);
  Previous:=Image;
  Failed:=False;
  try
    Image:=BuildD24CarryAddELF(LeftPhysical,RightPhysical);
  except on E:Exception do Failed:=True end;
  Need(Failed and (Image=Previous),
       'переповнення D24 не відхилено атомарно до створення ELF');
  Inc(Negatives);
end;

begin
  Need(ParamCount=1,'очікується приватний каталог результатів');
  Folder:=ParamStr(1);
  Need(DirectoryExists(Folder),'каталог результатів не існує');
  Cases:=TStringList.Create;
  try
    Positives:=0;Negatives:=0;FirstImage:='';Image:='';
    for L:=Low(Lefts) to High(Lefts) do
      for R:=Low(Rights) to High(Rights) do begin
        S:=Int64(Lefts[L])+Int64(Rights[R]);
        if (S>=MinD24) and (S<=MaxD24) then
          Accept(Lefts[L],Rights[R],S)
        else
          RejectOverflow(Lefts[L],Rights[R]);
      end;
    Need((Positives=66) and (Negatives=14) and
         (Length(FirstImage)>120),
         'невірні межі або неповна фізична матриця D24');
    Cases.SaveToFile(Folder+'/cases.txt');
    Recovered:=BuildD24CarryAddELF(EncodeNumericDecimal('65535',24),
                                    EncodeNumericDecimal('1',24));
    Need(Recovered=FirstImage,
         'байтове відновлення ELF після переповнень неідентичне');
    WriteLn('D24-CARRY-BOUNDARY-PASS positives=66 negatives=14 recovery=1');
  finally Cases.Free end;
end.
