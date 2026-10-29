{ G6.80: фізичні TEST-фікстури, не власний SENS evaluator.
  Зіставлення кожного результату через незалежний pinned REPL.
  Питання: чому у файлі саме T5M, а не текстова десяткова константа?
  Чому D24 результат лишається D24 при порівнянні?
  Чому немає неявного перетворення D1→D12?
  Чому переповнення проміжної D12-суми має відмовляти? }
program test_d12_addmul_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.numericadd,wsm.numericmul,wsm.t5m;
var Dir:String; Count,Widen:SizeInt;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

{ L/R/C — тестові десяткові літерали. Canonical packed фізичні байти
  передаються у ВЖЕ pinned-механізми, не у новий opcode registry.
  Result — один T5M atom у D12 або D24. }
procedure CaseOf(const LabelText:String;const L,R,C:RawByteString);
var A,B,Third,Sum,Product:RawByteString;
    Verify:TExplicitNumeric; Width:SizeInt;
begin
  A:=EncodeNumericDecimal(L,12);
  B:=EncodeNumericDecimal(R,12);
  Third:=EncodeNumericDecimal(C,12);
  Sum:=AddNumericPhysical(A,B,12);
  Verify:=ReadNumericPhysical(Sum,12);
  if Verify.DomainWidth<>12 then Halt(3);
  Product:=MultiplyNumericPhysical(Sum,Third,12);
  try Verify:=ReadNumericPhysical(Product,12);Width:=12;
  except on E:ENumericPlaneError do begin
    Verify:=ReadNumericPhysical(Product,24);Width:=24;
    Inc(Widen);
  end end;
  Save(LabelText+'-a.sens',A);
  Save(LabelText+'-b.sens',B);
  Save(LabelText+'-c.sens',Third);
  Save(LabelText+'-expected.sens',Product);
  WriteLn(LabelText,#9,L,#9,R,#9,C,#9,Width);
  Inc(Count);
end;

var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Dir) then Halt(2);
  Count:=0;Widen:=0;
  SetTextCodePage(Output,CP_UTF8);SetTextCodePage(StdErr,CP_UTF8);
  CaseOf('01','2','3','4');
  CaseOf('02','-2','1','3');
  CaseOf('03','2047','-1','2');
  CaseOf('04','-2048','1','1');
  CaseOf('05','100','200','-3');
  CaseOf('06','-1024','-1024','-1');
  CaseOf('07','0','0','2047');
  CaseOf('08','2047','-2047','2047');
  CaseOf('09','-2048','2047','-2048');
  CaseOf('10','2000','-1','-2');
  CaseOf('11','2047','0','-1');
  CaseOf('12','-2048','0','-1');
  SetLength(Words,1);Words[0]:='1';
  Save('bad-d1.sens',EncodeT5M(Words));
  Save('bad-d24.sens',EncodeNumericDecimal('1',24));
  Save('corrupt.sens',#$FF);
  Save('fake.lisp',UA('(додати 1 2)')+#10);
  Save('overflow-up.sens',EncodeNumericDecimal('2047',12));
  Save('overflow-down.sens',EncodeNumericDecimal('-2048',12));
  Save('one.sens',EncodeNumericDecimal('1',12));
  Save('minus-one.sens',EncodeNumericDecimal('-1',12));
  if (Count<>12) or (Widen<2) then Halt(4);
  WriteLn(StdErr,UA('D12-КОМПОЗИЦІЯ-СВІДКИ-ГАРАЗД пар='),Count,
    UA(' широкий-результат='),Widen);
end.
