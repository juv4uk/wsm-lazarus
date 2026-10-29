{ G6.89 — фізичні T5M свідки вкладеної D5 форми, а не нові закони.
  Очікуваний D1 даний тестовою матрицею; незалежний pinned SENS REPL
  перевіряє кожен позитив, а не FPC-диспетчер чи host-компаратор. }
program test_irwideaddgreater_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Folder:String;Passed:Integer;P,Q,R,Wide:RawByteString;
    W:TExactWords;

function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;

procedure Save(const Name:String;const Value:RawByteString);
var St:TFileStream;
begin
  St:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Value)>0 then St.WriteBuffer(Value[1],Length(Value));
  finally St.Free end;
end;

{ Borrowed десятковий fixture label — лише тестовий вхід хоста;
  EncodeNumericDecimal повертає canonical T5M конкретного D12.
  Далі цифри зберігаємо як точні RawByteString з DecodeT5M.
  Це НЕ runtime парсер десяткових програм SENS.
  1) Чому зберігаємо всі 12 біт?
  2) Чому розрізняємо signed -2048 і D24?
  3) Хто є незалежним оракулом?
  4) Чому ці числа не використовуються у frontend-коді? }
function D12(const Decimal:RawByteString):RawByteString;
var Packed:RawByteString;N:TExplicitNumeric;
begin
  Packed:=EncodeNumericDecimal(Decimal,12);
  N:=ReadNumericPhysical(Packed,12);
  Result:=N.ExactBits;
end;

{ Два D2 OPEN та CLOSE позначають саме вкладену форму.
  Result — owned physical T5M; семантика не виводиться з проєкцій.
  1) Чому D5:01010 стоїть перед двома numeric D12?
  2) Чому вкладений D2 CLOSE обов'язковий?
  3) Чому W12 не означає резидент без контексту?
  4) Чому очікування D1 треба перевірити ще upstream REPL? }
function Nested(const A,B,C:RawByteString):RawByteString;
begin
  Result:=EncodeT5M(Words(['10','11011','10','01010',A,B,'01',C,'01']));
end;

procedure CaseOf(const LabelText,A,B,C,Expected:RawByteString);
var N:RawByteString;
begin
  if (Expected<>'0') and (Expected<>'1') then Halt(2);
  N:=Nested(D12(A),D12(B),D12(C));
  Save(String(LabelText)+'-program.sens',N);
  Save(String(LabelText)+'-expected.sens',EncodeT5M(Words([Expected])));
  WriteLn(LabelText,#9,A,#9,B,#9,C,#9,Expected);
  Inc(Passed);
end;

begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not ForceDirectories(Folder) then Halt(2);
  Passed:=0;
  CaseOf('01','1','2','2','1');
  CaseOf('02','2','1','3','0');
  CaseOf('03','-3','2','-2','1');
  CaseOf('04','-3','2','0','0');
  CaseOf('05','0','0','0','0');
  CaseOf('06','2047','0','2046','1');
  CaseOf('07','-2048','0','-2047','0');
  CaseOf('08','-2048','1','-2048','1');
  CaseOf('09','2046','1','2047','0');
  CaseOf('10','-1000','-1000','-2048','1');
  CaseOf('11','-1000','-1000','-1999','0');
  CaseOf('12','1023','1024','2046','1');
  CaseOf('13','1023','1024','2047','0');
  CaseOf('14','-1024','1024','-1','1');
  if Passed<>14 then Halt(2);
  P:=D12('1');Q:=D12('2');R:=D12('3');
  Save('bad-root.sens',EncodeT5M(Words(
    ['10','11010','10','01010',P,Q,'01',R,'01'])));
  Save('bad-inner.sens',EncodeT5M(Words(
    ['10','11011','10','01011',P,Q,'01',R,'01'])));
  Save('bad-d7.sens',EncodeT5M(Words(
    ['10','11011','10','01010','0010110',Q,'01',R,'01'])));
  DecodeT5M(EncodeNumericDecimal('1',24),W);Wide:=W[0];
  Save('bad-d24.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,Q,'01',Wide,'01'])));
  Save('bad-w13.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,'0000000000001','01',R,'01'])));
  Save('bad-inner-missing.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,'01',R,'01'])));
  Save('bad-inner-extra.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,Q,R,'01',R,'01'])));
  Save('bad-roots.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,Q,'01',R,'01','0'])));
  Save('bad-flat.sens',EncodeT5M(Words(
    ['10','11011',P,Q,R,'01'])));
  Save('bad-outer-extra.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,Q,'01',R,R,'01'])));
  Save('bad-outer-missing.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,Q,'01','01'])));
  Save('bad-dotted.sens',EncodeT5M(Words(
    ['10','11011','10','01010',P,Q,'01','11',R,'01'])));
  Save('bad-corrupt.sens',#$FF);
  Save('bad-padding.sens',#$F2);
  Save('bad-empty.sens','');
  Save('bad-projection.lisp',Nested(P,Q,R));
  Save('bad-overflow-positive.sens',Nested(D12('2047'),D12('1'),D12('0')));
  Save('bad-overflow-negative.sens',Nested(D12('-2048'),D12('-1'),D12('0')));
  WriteLn(StdErr,'ВКЛАДЕНИЙ-Д5-СВІДКИ-ГОТОВО: 14 позитивів; 18 негативів');
end.
