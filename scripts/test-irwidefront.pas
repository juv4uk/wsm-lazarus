{ G6.97 — 16 повних канонічних фізичних D2/T5M SENS програм.
  Тестовий генератор не є мовним evaluator: незалежний pinned SENS CLI
  перевіряє ВСІ 16 випадків із реальними machine ELF stdout. }
program test_irwidefront;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Dir:String;M:TStringList;Count:Integer;Zero,D24:TExplicitNumeric;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

{ Tokens — borrowed exact bitwords including D2 '10' and '01'.
  Result owned packed T5M. Never serialize source to human ASCII Lisp.
  1) Чому D2 «10» і «01» не є числовими літералами?
  2) Як зберегти leading zeros 12-бітного D12?
  3) Хто звільняє dynamic TExactWords?
  4) Чому Width лише part exact domain identity? }
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;

{ Host fixture Kind — тільки тестовий індекс чотирьох ВЖЕ доведених
  компіляторних профілів, не semantic Lisp dispatch. Exact head у source
  визначається pinned D5/D6 таблицями; independent oracle перевіряє
  кожну фактичну відповідь.
  1) Чому fixture expected не є семантичним oracle?
  2) Чому 2048 треба кодувати в D24?
  3) Що визначає вихід D1, а що — D12/D24? }
procedure CasePhysical(const LabelText,Kind,Left,Right,Expected:RawByteString;
                       OutputWidth:SizeInt);
var A,B:TExplicitNumeric;P:RawByteString;W:TExactWords;
begin
  A:=ReadNumericPhysical(EncodeNumericDecimal(Left,12),12);
  Save(String(LabelText)+'.a1.sens',EncodeNumericDecimal(Left,12));
  if (Kind='zero') or (Kind='abs') then begin
    if Kind='zero' then P:=Pack(['10','01000',A.ExactBits,'01'])
    else P:=Pack(['10','010011',A.ExactBits,'01']);
  end else begin
    B:=ReadNumericPhysical(EncodeNumericDecimal(Right,12),12);
    Save(String(LabelText)+'.a2.sens',EncodeNumericDecimal(Right,12));
    if Kind='less' then P:=Pack(['10','11010',A.ExactBits,B.ExactBits,'01'])
    else if Kind='greater' then P:=Pack(['10','11011',A.ExactBits,B.ExactBits,'01'])
    else Halt(71);
  end;
  Save(String(LabelText)+'.sens',P);
  if OutputWidth=1 then begin
    SetLength(W,1); W[0]:=Expected;
    Save(String(LabelText)+'.expected.sens',EncodeT5M(W));
  end else
    Save(String(LabelText)+'.expected.sens',
      EncodeNumericDecimal(Expected,OutputWidth));
  M.Add(String(LabelText)+#9+String(Kind)+#9+
    String(Left)+#9+String(Right)+#9+
    String(Expected)+#9+IntToStr(OutputWidth));
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Dir:=ParamStr(1);
  if not ForceDirectories(Dir) then Halt(2);
  M:=TStringList.Create;
  try
    Count:=0;
    CasePhysical('01','zero','0','-','1',1);
    CasePhysical('02','zero','-1','-','0',1);
    CasePhysical('03','zero','2047','-','0',1);
    CasePhysical('04','zero','-2048','-','0',1);
    CasePhysical('05','less','-2048','-2047','1',1);
    CasePhysical('06','less','7','-12','0',1);
    CasePhysical('07','less','0','0','0',1);
    CasePhysical('08','less','2047','-2048','0',1);
    CasePhysical('09','greater','2047','-2048','1',1);
    CasePhysical('10','greater','-2048','2047','0',1);
    CasePhysical('11','greater','7','7','0',1);
    CasePhysical('12','greater','-1','-2','1',1);
    CasePhysical('13','abs','0','-','0',12);
    CasePhysical('14','abs','-17','-','17',12);
    CasePhysical('15','abs','-2048','-','2048',24);
    CasePhysical('16','abs','2047','-','2047',12);
    Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12);
    D24:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
    Save('other-d5.sens',Pack(['10','01010',Zero.ExactBits,Zero.ExactBits,'01']));
    Save('other-d6.sens',Pack(['10','010010',Zero.ExactBits,'01']));
    Save('other-d7.sens',Pack(['10','0010110',Zero.ExactBits,'01']));
    Save('bad-zero-arity.sens',Pack(['10','01000',Zero.ExactBits,Zero.ExactBits,'01']));
    Save('bad-zero-empty.sens',Pack(['10','01000','01']));
    Save('bad-zero-d1.sens',Pack(['10','01000','1','01']));
    Save('bad-zero-d7.sens',Pack(['10','01000','0010110','01']));
    Save('bad-less-arity.sens',Pack(['10','11010',Zero.ExactBits,'01']));
    Save('bad-less-d24.sens',Pack(['10','11010',Zero.ExactBits,D24.ExactBits,'01']));
    Save('bad-less-d1.sens',Pack(['10','11010','0',Zero.ExactBits,'01']));
    Save('bad-greater-arity.sens',Pack(['10','11011',Zero.ExactBits,'01']));
    Save('bad-greater-nested.sens',Pack(['10','11011',Zero.ExactBits,'10',Zero.ExactBits,'01','01']));
    Save('bad-abs-arity.sens',Pack(['10','010011',Zero.ExactBits,Zero.ExactBits,'01']));
    Save('bad-abs-d24.sens',Pack(['10','010011',D24.ExactBits,'01']));
    Save('bad-abs-d3.sens',Pack(['10','010011','000','01']));
    Save('two-roots.sens',Pack(['10','01000',Zero.ExactBits,'01','0']));
    Save('dotted.sens',Pack(['10','010011','11',Zero.ExactBits,'01']));
    Save('unclosed.sens',Pack(['10','010011',Zero.ExactBits]));
    Save('root-atom.sens',Pack([Zero.ExactBits]));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','010011',Zero.ExactBits,'01']));
    M.SaveToFile(Dir+'/cases.tsv');
    if Count<>16 then Halt(2);
    WriteLn('G6.97-WIDE-FRONT-FIXTURES-OK cases=16');
  finally M.Free end;
end.
