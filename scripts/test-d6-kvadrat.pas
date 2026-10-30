{ G6.128 — фізичні golden .sens D6:010111(D12,D24:2), native ELF.
  Всі очікувані фізичні байти збирає чинний T5M/numericmul механізм;
  незалежний реальний pinned SENS oracle доданий окремим CI етапом.
  Managed records/strings звільняє FPC; потоки — через try/finally.
  1) Чому очікувані байти не можуть замінити незалежний REPL?
  2) Чому показник фіксується у D24, а не D12?
  3) Хто гарантує no partial ELF при відмові?
  4) Чому D12 переповнення не тотожне помилці при D24 result? }
program testd6kvadrat;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericmul,
     wsm.ird6kvadrat,wsm.elfgeometry;
const
  Bases:array[0..11] of RawByteString=
    ('0','1','-1','2','-2','3','-7','31','-128','127','2047','-2048');
var Dir,LabelName:String;I,Good,Bad:SizeInt;
    BasePhysical,BaseBits,PowerBits,Physical,ELF,Expected:RawByteString;
    B,P:TExplicitNumeric;G:TELFGeometry;Cases:TStringList;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('Д6-КВАДРАТ-ТЕСТ: '+Why) end;
function Pack(const Items:array of RawByteString):RawByteString;
var W:TExactWords;J:SizeInt;
begin
  SetLength(W,Length(Items));
  for J:=0 to High(Items) do W[J]:=Items[J];
  Result:=EncodeT5M(W);
end;
procedure Save(const Name:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;
{ UnicodeString свідомо кодуємо у UTF-8 перед host stdout:
  FPC default WriteLn не гарантує збереження української проєкції.
  Потік позичений у процесу; обгортка звільняється через finally. }
procedure SayUTF8(const Message:UnicodeString);
var Bytes:RawByteString;Stream:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;
procedure Refuse(const Why:String;const Input:RawByteString);
var Image:RawByteString;Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try Image:=BuildIRD6KvadratELF(Input,'external/sens')
  except on E:Exception do Rejected:=E.Message<>'' end;
  Need(Rejected and (Image=''),'допущено '+Why);
  Inc(Bad);
end;
begin
  Need(ParamCount=1,'потрібен каталог свідків');
  Dir:=ParamStr(1);Need(DirectoryExists(Dir),'немає каталогу');
  Cases:=TStringList.Create;
  try
    Good:=0;Bad:=0;
    P:=ReadNumericPhysical(EncodeNumericDecimal('2',24),24);
    PowerBits:=P.ExactBits;
    Need(Length(PowerBits)=24,'D24:2 не має 24 бітів');
    for I:=0 to High(Bases) do begin
      LabelName:=Format('%.2d',[I+1]);
      BasePhysical:=EncodeNumericDecimal(Bases[I],12);
      B:=ReadNumericPhysical(BasePhysical,12);
      BaseBits:=B.ExactBits;
      Physical:=Pack(['10','010111',BaseBits,PowerBits,'01']);
      Expected:=MultiplyNumericPhysical(BasePhysical,BasePhysical,12);
      ELF:=BuildIRD6KvadratELF(Physical,'external/sens');
      VerifySENSELF64(ELF,G);
      Need((G.Kind=3) and (G.Entry=120) and
           (G.FileBytes=Length(ELF)),'невірна геометрія ELF');
      Need(BuildIRD6KvadratELF(Physical,'external/sens')=ELF,
           'недетермінований машинний образ');
      Save(LabelName+'.sens',Physical);
      Save(LabelName+'.expected.sens',Expected);
      Save(LabelName+'.elf',ELF);
      Cases.Add(LabelName+#9+String(Bases[I])+#9+
        IntToStr(Int64(StrToInt(String(Bases[I])))*Int64(StrToInt(String(Bases[I])))));
      Inc(Good);
    end;
    B:=ReadNumericPhysical(EncodeNumericDecimal('3',12),12);
    BaseBits:=B.ExactBits;
    Refuse('іншу D6 голову',
      Pack(['10','010110',BaseBits,PowerBits,'01']));
    Refuse('D5 голову замість D6',
      Pack(['10','10110',BaseBits,PowerBits,'01']));
    Refuse('D12 показник 2',
      Pack(['10','010111',BaseBits,
        ReadNumericPhysical(EncodeNumericDecimal('2',12),12).ExactBits,'01']));
    Refuse('D24 основу',
      Pack(['10','010111',PowerBits,PowerBits,'01']));
    Refuse('D1 основу',Pack(['10','010111','1',PowerBits,'01']));
    Refuse('відсутній показник',Pack(['10','010111',BaseBits,'01']));
    Refuse('зайвий операнд',
      Pack(['10','010111',BaseBits,PowerBits,BaseBits,'01']));
    Refuse('два корені',
      Pack(['10','010111',BaseBits,PowerBits,'01','0']));
    Refuse('вкладена основа',
      Pack(['10','010111','10',BaseBits,'01',PowerBits,'01']));
    Refuse('обірвану форму',Pack(['10','010111',BaseBits,PowerBits]));
    Refuse('неканонічний T5M',#$FF);
    Refuse('порожній .sens','');
    for I:=0 to 3 do begin
      case I of
        0:LabelName:='0';
        1:LabelName:='1';
        2:LabelName:='3';
        else LabelName:='-1';
      end;
      Refuse('непідтриманий D24 показник '+LabelName,
        Pack(['10','010111',BaseBits,
          ReadNumericPhysical(EncodeNumericDecimal(RawByteString(LabelName),24),24).ExactBits,'01']));
    end;
    Need((Good=12) and (Bad=16),'лічильники свідків порушені');
    Cases.SaveToFile(Dir+'/cases.tsv');
    SayUTF8('Д6-КВАДРАТ-СВІДКИ-ГОТОВО позитивів='+
      UnicodeString(IntToStr(Good))+' негативів='+UnicodeString(IntToStr(Bad))+
      ' результат=фізичний-T5M компілятор=IMUL');
  finally Cases.Free end;
end.
