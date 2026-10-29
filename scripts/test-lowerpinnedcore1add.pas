{ G6.135 — реальні фізичні свідки pinned Core1 DEFINE/LAMBDA
  -> двоаргументна спеціалізація -> compiled WideIR -> native ELF64.
  Тестова таблиця десяткових значень — ЛИШЕ контрольні свідки;
  незалежний SENS REPL перевіряє їх ще раз у CI.
  1) Чому pinned Core1 має фізично містити саме тіло?
  2) Чому W12 операнди перевіряються до спеціалізації?
  3) Як зберігаються D24 overflow?
  4) Чому Core1 runtime — окремий oracle від machine code?
  5) Чому негатив не повинен віддавати жодних ELF-байтів? }
program test_lowerpinnedcore1add;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.lowerpinnedcore1add,wsm.elfgeometry;
var Dir,Repo:String;Cases:TStringList;Good,Bad:SizeInt;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('ЯДРО1-ELF-ТЕСТ: '+Why) end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;
procedure Positive(const Tag,L,R,Wanted:RawByteString;Width:SizeInt;IsSub:Boolean);
var Left,Right,Expected,Oracle,Image,HeadBits:RawByteString;G:TELFGeometry;
begin
  Left:=EncodeNumericDecimal(L,12);
  Right:=EncodeNumericDecimal(R,12);
  Expected:=EncodeNumericDecimal(Wanted,Width);
  if IsSub then begin
    Oracle:=PinnedCore1SubCall(Repo,Left,Right);
    Image:=BuildPinnedCore1SubELF(Repo,Left,Right);
    Need(Image=BuildPinnedCore1SubELF(Repo,Left,Right),
      'віднімання компілюється невідтворювано '+String(Tag));
  end else begin
    Oracle:=PinnedCore1AddCall(Repo,Left,Right);
    Image:=BuildPinnedCore1AddELF(Repo,Left,Right);
    Need(Image=BuildPinnedCore1AddELF(Repo,Left,Right),
      'додавання компілюється невідтворювано '+String(Tag));
  end;
  Need(Oracle=Expected,
    'фізичний pinned Core1 runtime не збігається з очікуванням '+String(Tag));
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(Image)),
    'неправильна фізична геометрія '+String(Tag));
  Save(String(Tag)+'.left.sens',Left);
  Save(String(Tag)+'.right.sens',Right);
  Save(String(Tag)+'.expected.sens',Expected);
  Save(String(Tag)+'.native.elf',Image);
  if IsSub then HeadBits:='01011' else HeadBits:='01010';
  Cases.Add(String(Tag)+#9+String(HeadBits)+#9+String(L)+#9+String(R)+#9+
    String(Wanted)+#9+IntToStr(Width));
  Inc(Good);
end;
procedure Refuse(const Why:String;const L,R:RawByteString;IsSub:Boolean);
var Image:RawByteString;Rejected:Boolean;
begin
  Image:='';Rejected:=False;
  try
    if IsSub then Image:=BuildPinnedCore1SubELF(Repo,L,R)
    else Image:=BuildPinnedCore1AddELF(Repo,L,R)
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
    Positive('01','0','0','0',12,False);
    Positive('02','31','42','73',12,False);
    Positive('03','-12','7','-5',12,False);
    Positive('04','-2048','2047','-1',12,False);
    Positive('05','2047','-2048','-1',12,False);
    Positive('06','2047','1','2048',24,False);
    Positive('07','-2048','-1','-2049',24,False);
    Positive('08','2047','2047','4094',24,False);
    Positive('09','-2048','-2048','-4096',24,False);
    Positive('10','-2047','-1','-2048',12,False);
    Positive('11','1023','1024','2047',12,False);
    Positive('12','-1024','1023','-1',12,False);
    { Ті самі pinned Core1 D4 DEFINE/LAMBDA та дві точні D7 позиції,
      але фізичне тіло D5:01011, без локального визначення SUB. }
    Positive('13','0','0','0',12,True);
    Positive('14','31','42','-11',12,True);
    Positive('15','-12','7','-19',12,True);
    Positive('16','-2048','-2048','0',12,True);
    Positive('17','2047','2047','0',12,True);
    Positive('18','2047','-1','2048',24,True);
    Positive('19','-2048','1','-2049',24,True);
    Positive('20','2047','-2048','4095',24,True);
    Positive('21','-2048','2047','-4095',24,True);
    Positive('22','-2047','-1','-2046',12,True);
    Positive('23','1023','1024','-1',12,True);
    Positive('24','-1024','1023','-2047',12,True);
    Z:=EncodeNumericDecimal('0',12);
    O:=EncodeNumericDecimal('1',12);
    B24:=EncodeNumericDecimal('1',24);
    Refuse('ліва D1',EncodeT5M(OneWord('1')),O,False);
    Refuse('права D24',Z,B24,False);
    Refuse('порожня ліва','',O,False);
    Refuse('порожня права',Z,'',False);
    Refuse('пошкоджений T5M',#$FF,O,False);
    Refuse('неканонічний D7',EncodeT5M(OneWord('0001011')),O,False);
    Refuse('два D12 атоми зліва',
      EncodeT5M(TwoWords('000000000000','000000000001')),O,False);
    Refuse('ліва D3 порожнеча',EncodeT5M(OneWord('000')),O,False);
    Refuse('віднімання: ліва D1',EncodeT5M(OneWord('1')),O,True);
    Refuse('віднімання: права D24',Z,B24,True);
    Refuse('віднімання: порожня ліва','',O,True);
    Refuse('віднімання: порожня права',Z,'',True);
    Refuse('віднімання: пошкоджений T5M',#$FF,O,True);
    Refuse('віднімання: неканонічний D7',EncodeT5M(OneWord('0001011')),O,True);
    Refuse('віднімання: два D12 атоми зліва',
      EncodeT5M(TwoWords('000000000000','000000000001')),O,True);
    Refuse('віднімання: ліва D3 порожнеча',EncodeT5M(OneWord('000')),O,True);
    Need((Good=24) and (Bad=16),'неповна матриця тестів');
    Cases.SaveToFile(Dir+'/cases.tsv');
    WriteLn('ЯДРО1-ELF-СВІДКИ-ГОТОВО positive=24 negative=16 D24=8');
  finally Cases.Free end;
end.
