{ G6.83: ФІЗИЧНІ тестові D12/D24 атоми, а не новий SENS evaluator.
  Expected отримується тільки з уже чинного числового механізму;
  справжній oracle — pinned незалежний SENS REPL у shell.
  Питання: чому W12 і W24 різні ідентичності?
  Чому середнє W24 не можна мовчки звузити до D12?
  Чому у .sens фізичні байти, а не текстова людиночитана проєкція?
  Чому матриця перевіряє обидва маршрути машинного lowering? }
program test_d12_addneg_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.numericadd,wsm.numericmul,wsm.t5m;
var Dir:String; Count,MiddleWide,Wide:SizeInt;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Save споживає borrowed bytes; власний файл відкрито короткочасно
  і закрито в finally; результат canonical packed .sens.
  Питання: хто володіє file stream? Чому немає вихідного .lisp?
  Що доводить незалежна byte-exact перевірка? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure CaseOf(const LabelText:String;const L,R:RawByteString);
var A,B,Sum,NegativeOne,Answer:RawByteString; Check:TExplicitNumeric;
    MidWidth,OutWidth:SizeInt;
begin
  A:=EncodeNumericDecimal(L,12);
  B:=EncodeNumericDecimal(R,12);
  Sum:=AddNumericPhysical(A,B,12);
  try Check:=ReadNumericPhysical(Sum,12);MidWidth:=12;
  except on ENumericPlaneError do begin
    Check:=ReadNumericPhysical(Sum,24);MidWidth:=24;
    Inc(MiddleWide);
  end end;
  NegativeOne:=EncodeNumericDecimal('-1',MidWidth);
  Answer:=MultiplyNumericPhysical(NegativeOne,Sum,MidWidth);
  try Check:=ReadNumericPhysical(Answer,12);OutWidth:=12;
  except on ENumericPlaneError do begin
    Check:=ReadNumericPhysical(Answer,24);OutWidth:=24;
    Inc(Wide);
  end end;
  Save(LabelText+'-a.sens',A);
  Save(LabelText+'-b.sens',B);
  Save(LabelText+'-expected.sens',Answer);
  WriteLn(LabelText,#9,L,#9,R,#9,MidWidth,#9,OutWidth);
  Inc(Count);
end;

var Words:TExactWords;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Dir) then Halt(2);
  SetTextCodePage(Output,CP_UTF8);
  SetTextCodePage(StdErr,CP_UTF8);
  Count:=0;MiddleWide:=0;Wide:=0;
  CaseOf('01','0','0');
  CaseOf('02','7','8');
  CaseOf('03','-17','4');
  CaseOf('04','-2048','0');
  CaseOf('05','-2048','1');
  CaseOf('06','2047','0');
  CaseOf('07','2047','1');
  CaseOf('08','-2048','-1');
  CaseOf('09','2047','2047');
  CaseOf('10','-2048','-2048');
  CaseOf('11','2047','-2048');
  CaseOf('12','100','200');
  CaseOf('13','-1024','-1024');
  CaseOf('14','-100','101');
  SetLength(Words,1);Words[0]:='1';
  Save('bad-d1.sens',EncodeT5M(Words));
  Words[0]:='0010110';
  Save('bad-d7.sens',EncodeT5M(Words));
  Save('bad-d24.sens',EncodeNumericDecimal('1',24));
  Save('bad-byte.sens',#$FF);
  Save('empty.sens','');
  Save('fake.lisp',UA('(додати 1 2)')+#10);
  if (Count<>14) or (MiddleWide<>4) or (Wide<>6) then Halt(4);
  WriteLn(StdErr,UA('D12-ДВІ-ДІЇ-СВІДКИ-ГАРАЗД форм='),Count,
          UA(' проміжних-D24='),MiddleWide,UA(' кінцевих-D24='),Wide);
end.
