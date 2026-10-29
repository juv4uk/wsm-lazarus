{ G6.131 — фізичні D5+ D12 свідки для вже існуючого спільного
  WideIR → ELF64. Тільки тестовий host-генератор, не evaluator SENS.
  Закон і викличність — pinned external/sens Contract 12.0.
  1) Чому два W12 без ратифікованої голови не становлять операцію?
  2) Чому D24 результат не можна записувати у W12?
  3) Яка роль exact T5M на відміну від української .lisp проєкції?
  4) Хто володіє TExactWords, файловими потоками й TStringList? }
program test_widefront_arithmetic;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;

var Dir:String; Ledger:TStringList; Positives:SizeInt;

{ Діагностичні UTF-8 байти — людська проєкція, не канонічні SENS.
  1) Чому UnicodeString конвертується явно?
  2) Чому кодер не торкається фізичних T5M свідків?
  3) Хто володіє поверненим керованим рядком? }
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('Д5-СПІЛЬНИЙ-ТЕСТ-ПОМИЛКА: '+Why);
end;

procedure Save(const Name:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally
    Stream.Free;
  end;
end;

{ Bits — позичені двійкові слова з уже визначеними фізичними ширинами.
  Result — власна packed T5M послідовність із D2 framing.
  1) Чому '10'/'01' — D2, а не числа D12?
  2) Чому не серіалізуємо ASCII-рядок функції?
  3) Що гарантує збереження провідних нулів? }
function Pack(const Bits:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Bits));
  for I:=0 to High(Bits) do Words[I]:=Bits[I];
  Result:=EncodeT5M(Words);
end;

{ Kind — приватний індекс тестової таблиці, НЕ dispatch програми SENS.
  У самій фізичній програмі існує лише exact D5 head + два W12.
  Очікування НЕ є оракулом; незалежний pinned SENS REPL перевіряє
  кожний випадок окремо у CI.
  1) Хто вибирає закон за (domain,width,bits)?
  2) Чому перевіряємо machine stdout, а не Pascal результат?
  3) Як виявляється D12→D24? }
procedure CasePhysical(const Tag,Kind,LDec,RDec,Wanted:RawByteString;
                       Width:SizeInt);
var Head,LBits,RBits,Source:RawByteString;
    LNum,RNum:TExplicitNumeric;
begin
  if Kind='add' then Head:='01010'
  else if Kind='sub' then Head:='01011'
  else if Kind='mul' then Head:='10110'
  else raise Exception.Create('невідомий тестовий індекс');
  LNum:=ReadNumericPhysical(EncodeNumericDecimal(LDec,12),12);
  RNum:=ReadNumericPhysical(EncodeNumericDecimal(RDec,12),12);
  LBits:=LNum.ExactBits;RBits:=RNum.ExactBits;
  Need((Length(LBits)=12) and (Length(RBits)=12),'втрачено W12');
  Source:=Pack(['10',Head,LBits,RBits,'01']);
  Save(String(Tag)+'.sens',Source);
  Save(String(Tag)+'.expected.sens',EncodeNumericDecimal(Wanted,Width));
  Ledger.Add(String(Tag)+#9+String(Kind)+#9+String(LDec)+#9+
             String(RDec)+#9+String(Wanted)+#9+IntToStr(Width));
  Inc(Positives);
end;

var Z,O,W24:RawByteString;
begin
  Need(ParamCount=1,'потрібна приватна тека фізичних свідків');
  Dir:=ParamStr(1);
  Need(ForceDirectories(Dir),'не створено теку фізичних свідків');
  Ledger:=TStringList.Create;
  try
    Positives:=0;
    CasePhysical('01','add','31','42','73',12);
    CasePhysical('02','add','-2048','2047','-1',12);
    CasePhysical('03','add','-100','20','-80',12);
    CasePhysical('04','add','2047','-2048','-1',12);
    CasePhysical('05','sub','1','-2048','2049',24);
    CasePhysical('06','sub','-2048','1','-2049',24);
    CasePhysical('07','sub','7','-7','14',12);
    CasePhysical('08','sub','2047','-2048','4095',24);
    CasePhysical('09','mul','12','12','144',12);
    CasePhysical('10','mul','-2048','-1','2048',24);
    CasePhysical('11','mul','-12','7','-84',12);
    CasePhysical('12','mul','0','-2048','0',12);
    Z:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
    O:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
    W24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
    Save('wrong-arity.sens',Pack(['10','01010',Z,'01']));
    Save('wrong-domain.sens',Pack(['10','01010',Z,W24,'01']));
    Save('wrong-head.sens',Pack(['10','01000',Z,O,'01']));
    Save('two-roots.sens',Pack(['10','01011',Z,O,'01','0']));
    Save('unclosed.sens',Pack(['10','10110',Z,O]));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','01010',Z,O,'01']));
    Need(Positives=12,'неповний позитивний набір');
    Ledger.SaveToFile(Dir+'/cases.tsv');
    WriteLn(UA('Д5-СПІЛЬНИЙ-СВІДКИ-ГАРАЗД physical=12 negatives=8'));
  finally
    Ledger.Free;
  end;
end.