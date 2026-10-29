{ G6.141 — фізичний regression для двох ВЖЕ ІСНУЮЧИХ Core1 DEFINE.
  16 наборів по три signed D12, дві фактичні Core1 runtime функції,
  один compiler ELF64 (дві ALU ISA), 10 незалежних негативів.
  Тестові десяткові числа — fixture projection, а не SENS authority.
  1) Хто є канонічним джерелом двох бібліотечних тіл?
  2) Чому T5M порівнюємо ПОБАЙТОВО?
  3) Чому відмова D12→D24 у проміжному кроці правильна?
  4) Які дані у fixture власні, а які borrowed? }
program test_lowercore1twocalls;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.lowercore1twocalls,wsm.elfgeometry;
var Repo,Dir:String;Ledger:TStringList;PositiveCount,NegativeCount:SizeInt;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ЯДРО1-ДВА-ТЕСТ-ВІДМОВА: '+Why);
end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
function One(const Bits:RawByteString):TExactWords;
begin SetLength(Result,1);Result[0]:=Bits end;
function Two(const A,B:RawByteString):TExactWords;
begin SetLength(Result,2);Result[0]:=A;Result[1]:=B end;

procedure CasePositive(const Tag,A,B,C,Wanted:RawByteString);
var PA,PB,PC,Expected,Actual,ELF:RawByteString;G:TELFGeometry;
begin
  PA:=EncodeNumericDecimal(A,12);
  PB:=EncodeNumericDecimal(B,12);
  PC:=EncodeNumericDecimal(C,12);
  Expected:=EncodeNumericDecimal(Wanted,12);
  Actual:=PinnedCore1TwoCallsAnswer(Repo,PA,PB,PC);
  Need(Actual=Expected,
    'два реальні Core1 виклики відрізняються від expected: '+String(Tag));
  ELF:=BuildPinnedCore1TwoCallsELF(Repo,PA,PB,PC);
  Need(ELF=BuildPinnedCore1TwoCallsELF(Repo,PA,PB,PC),
    'компілятор не детермінований: '+String(Tag));
  VerifySENSELF64(ELF,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(ELF)),
    'пошкоджено ELF64 PIE геометрію: '+String(Tag));
  Save(String(Tag)+'.a.sens',PA);
  Save(String(Tag)+'.b.sens',PB);
  Save(String(Tag)+'.c.sens',PC);
  Save(String(Tag)+'.expected.sens',Expected);
  Save(String(Tag)+'.reference.elf',ELF);
  Ledger.Add(String(Tag)+#9+String(A)+#9+String(B)+#9+
    String(C)+#9+String(Wanted));
  Inc(PositiveCount);
end;

procedure CaseNegative(const Why:String;
  const A,B,C:RawByteString);
var Rejected:Boolean;Image:RawByteString;
begin
  Rejected:=False;Image:='';
  try Image:=BuildPinnedCore1TwoCallsELF(Repo,A,B,C)
  except on E:Exception do Rejected:=E.Message<>'' end;
  Need(Rejected and (Image=''),'не відхилено: '+Why);
  Inc(NegativeCount);
end;

var Z,O,N,Z24:RawByteString;
begin
  Need(ParamCount=2,'потрібен корінь і фізичний каталог');
  Repo:=ParamStr(1);Dir:=ParamStr(2);
  Need(ForceDirectories(Dir),'немає фізичного каталогу');
  Ledger:=TStringList.Create;
  try
    PositiveCount:=0;NegativeCount:=0;
    CasePositive('01','5','7','3','9');
    CasePositive('02','0','0','0','0');
    CasePositive('03','100','20','50','70');
    CasePositive('04','-100','20','-10','-70');
    CasePositive('05','2047','-2048','-1','0');
    CasePositive('06','-2048','2047','-1','0');
    CasePositive('07','-1000','500','500','-1000');
    CasePositive('08','1000','1000','2047','-47');
    CasePositive('09','-1500','-500','-2000','0');
    CasePositive('10','17','19','30','6');
    CasePositive('11','-1','-1','-1','-1');
    CasePositive('12','123','-45','67','11');
    CasePositive('13','10','11','-30','51');
    CasePositive('14','-2048','0','0','-2048');
    CasePositive('15','2047','0','0','2047');
    CasePositive('16','-2000','1000','-1000','0');
    Z:=EncodeNumericDecimal('0',12);
    O:=EncodeNumericDecimal('1',12);
    N:=EncodeNumericDecimal('-1',12);
    Z24:=EncodeNumericDecimal('0',24);
    CaseNegative('перший D1',EncodeT5M(One('1')),O,Z);
    CaseNegative('другий D24',Z,Z24,Z);
    CaseNegative('третій D24',Z,Z,Z24);
    CaseNegative('порожній перший','',O,Z);
    CaseNegative('порожній другий',Z,'',Z);
    CaseNegative('порожній третій',Z,O,'');
    CaseNegative('не-T5M',#$FF,O,Z);
    CaseNegative('два перші атоми',
      EncodeT5M(Two('000000000000','000000000001')),O,Z);
    CaseNegative('D7 за розміром',EncodeT5M(One('0000000')),O,Z);
    CaseNegative('перший крок переходить D12→D24',
      EncodeNumericDecimal('2047',12),O,Z);
    CaseNegative('другий крок переходить D12→D24',
      EncodeNumericDecimal('-2048',12),Z,O);
    Need((PositiveCount=16) and (NegativeCount=11),
      'неповна матриця фізичних і негативних свідків');
    Ledger.SaveToFile(Dir+'/cases.tsv');
    WriteLn(RawByteString(UTF8Encode(UnicodeString(
      'ЯДРО1-ДВА-ГОТОВО позитивів=16 відмов=11'))));
  finally Ledger.Free end;
end.
