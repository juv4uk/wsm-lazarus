{ G6.142 — реальні фізичні свідки pinned Core1 DEFINE/LAMBDA
  -> двоаргументна спеціалізація -> pinned checked WideIR -> real IMUL -> native ELF64.
  Тестова таблиця десяткових значень — ЛИШЕ контрольні свідки;
  незалежний SENS REPL перевіряє їх ще раз у CI.
  1) Чому pinned Core1 має фізично містити саме тіло?
  2) Чому W12 операнди перевіряються до спеціалізації?
  3) Як зберігаються D24 overflow?
  4) Чому Core1 runtime — окремий oracle від machine code?
  5) Чому негатив не повинен віддавати жодних ELF-байтів? }
program test_lowerpinnedcore1mul;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.lowerpinnedcore1mul,wsm.elfgeometry;
var Dir,Repo:String;Cases:TStringList;Good,Bad:SizeInt;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('ЯДРО1-МНОЖЕННЯ-ELF-ТЕСТ: '+Why) end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;
procedure Positive(const Tag,L,R,Wanted:RawByteString;Width:SizeInt);
var Left,Right,Expected,Oracle,Image:RawByteString;G:TELFGeometry;
begin
  Left:=EncodeNumericDecimal(L,12);
  Right:=EncodeNumericDecimal(R,12);
  Expected:=EncodeNumericDecimal(Wanted,Width);
  Oracle:=PinnedCore1MulCall(Repo,Left,Right);
  Need(Oracle=Expected,
    'фізичний pinned Core1 runtime не збігається з очікуванням '+String(Tag));
  Image:=BuildPinnedCore1MulELF(Repo,Left,Right);
  Need(Image=BuildPinnedCore1MulELF(Repo,Left,Right),
    'компіляція невідтворювана '+String(Tag));
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(Image)),
    'неправильна фізична геометрія '+String(Tag));
  Save(String(Tag)+'.left.sens',Left);
  Save(String(Tag)+'.right.sens',Right);
  Save(String(Tag)+'.expected.sens',Expected);
  Save(String(Tag)+'.native.elf',Image);
  Cases.Add(String(Tag)+#9+String(L)+#9+String(R)+#9+
    String(Wanted)+#9+IntToStr(Width));
  Inc(Good);
end;
procedure Refuse(const Why:String;const L,R:RawByteString);
var Image:RawByteString;Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try Image:=BuildPinnedCore1MulELF(Repo,L,R)
  except on E:Exception do Rejected:=E.Message<>'' end;
  Need(Rejected and (Image=''),'не відхилено: '+Why);
  Inc(Bad);
end;
function OneWord(const Bits:RawByteString):TExactWords;
begin SetLength(Result,1);Result[0]:=Bits end;
function TwoWords(const A,B:RawByteString):TExactWords;
begin SetLength(Result,2);Result[0]:=A;Result[1]:=B end;
var Z,O,B24:RawByteString;
begin
  Need(ParamCount=2,'потрібен корінь репозиторію та каталог свідків');
  Repo:=ParamStr(1);Dir:=ParamStr(2);
  Need(ForceDirectories(Dir),'не створено каталог свідків');
  Cases:=TStringList.Create;
  try
    Good:=0;Bad:=0;
    Positive('01','0','0','0',12);
    Positive('02','31','42','1302',12);
    Positive('03','-12','7','-84',12);
    Positive('04','-2048','1','-2048',12);
    Positive('05','2047','1','2047',12);
    Positive('06','2047','2','4094',24);
    Positive('07','-2048','-1','2048',24);
    Positive('08','2047','2047','4190209',24);
    Positive('09','-2048','-2048','4194304',24);
    Positive('10','-2047','1','-2047',12);
    Positive('11','1023','2','2046',12);
    Positive('12','-1024','3','-3072',24);
    Z:=EncodeNumericDecimal('0',12);
    O:=EncodeNumericDecimal('1',12);
    B24:=EncodeNumericDecimal('1',24);
    Refuse('ліва D1',EncodeT5M(OneWord('1')),O);
    Refuse('права D24',Z,B24);
    Refuse('порожня ліва','',O);
    Refuse('порожня права',Z,'');
    Refuse('пошкоджений T5M',#$FF,O);
    Refuse('неканонічний D7',EncodeT5M(OneWord('0001011')),O);
    Refuse('два D12 атоми зліва',
      EncodeT5M(TwoWords('000000000000','000000000001')),O);
    Refuse('ліва D3 порожнеча',EncodeT5M(OneWord('000')),O);
    Need((Good=12) and (Bad=8),'неповна матриця тестів');
    Cases.SaveToFile(Dir+'/cases.tsv');
    WriteLn('ЯДРО1-ELF-СВІДКИ-ГОТОВО positive=12 negative=8 D24=5');
  finally Cases.Free end;
end.
