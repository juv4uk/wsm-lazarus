{ G6.193 — 16 РІЗНИХ канонічних фізичних D2/T5M D5:01010(D12,D12).
  Десяткові фікстури лише для тесту, не новий SENS закон.
  Справжній числовий admission робить чинний wsm.numericplane. }
program test_add_context_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Folder:String;Manifest:TStringList;Count:SizeInt;

{ Точні запозичені слова → керовані bytes T5M, не .lisp.
  1) Чому дужки D2 — окремі біти?
  2) Чому фізичний padding T5M не є числовими бітами?
  3) Хто володіє тимчасовими FPC масивами? }
function Pack(const V:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(V));
  for I:=0 to High(V) do W[I]:=V[I];
  Result:=EncodeT5M(W);
end;

{ Запозичений filename, власний тимчасовий stream; Bytes — managed.
  1) Чому WriteBuffer не змінює T5M?
  2) Як закрити descriptor за помилки?
  3) Чому .sens не є UTF-8? }
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

function Bits12(const Decimal:String):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  if (N.DomainWidth<>12) or (Length(N.ExactBits)<>12) then
    raise Exception.Create('операнд не пройшов D12 admission');
  Result:=N.ExactBits;
end;

function Bits24(const Decimal:String):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,24),24);
  Result:=N.ExactBits;
end;

{ Очікувана сума — фізичний тестовий oracle fixture, а НЕ
  результат Pascal evaluator. Порівнюємо з реально запущеним ELF
  і, окремо, з pinned SENS REPL у PR-only CI.
  1) Хто генерує машинний ADD?
  2) Чому результат D12 має рівно 12 точних бітів?
  3) Чому крайовий D24 overflow відхиляється backend? }
procedure Valid(const LabelText,A,B,Expected:String);
begin
  Save(LabelText+'.sens',Pack(['10','01010',Bits12(A),Bits12(B),'01']));
  Save(LabelText+'.expected.sens',EncodeNumericDecimal(Expected,12));
  Manifest.Add(LabelText+#9+A+#9+B+#9+Expected);
  Inc(Count);
end;
var Zero,One,MinusOne:RawByteString;
begin
  try
    if ParamCount<>1 then raise Exception.Create('потрібен каталог свідків');
    Folder:=ParamStr(1);
    if not ForceDirectories(Folder) then raise Exception.Create('каталог недоступний');
    Manifest:=TStringList.Create;
    try
      Count:=0;
      Valid('01','0','0','0');
      Valid('02','31','42','73');
      Valid('03','-12','7','-5');
      Valid('04','-1024','-1024','-2048');
      Valid('05','-2048','2047','-1');
      Valid('06','1023','1','1024');
      Valid('07','2047','-2048','-1');
      Valid('08','2046','1','2047');
      Valid('09','-2047','-1','-2048');
      Valid('10','1','1','2');
      Valid('11','2047','-2047','0');
      Valid('12','-1500','500','-1000');
      Valid('13','1234','-432','802');
      Valid('14','-777','77','-700');
      Valid('15','80','-9','71');
      Valid('16','-13','-11','-24');
      if Count<>16 then raise Exception.Create('очікувалося 16 програм');
      Zero:=Bits12('0'); One:=Bits12('1'); MinusOne:=Bits12('-1');
      Save('bad-head.sens',Pack(['10','01011',Zero,One,'01']));
      Save('bad-arity.sens',Pack(['10','01010',Zero,'01']));
      Save('bad-d1.sens',Pack(['10','01010','1',One,'01']));
      Save('bad-d24.sens',Pack(['10','01010',Zero,Bits24('1'),'01']));
      Save('bad-extra.sens',Pack(['10','01010',Zero,One,One,'01']));
      Save('bad-unclosed.sens',Pack(['10','01010',Zero,One]));
      Save('bad-multiroot.sens',Pack(['10','01010',Zero,One,'01','1']));
      Save('bad-t5m.sens',#$FF);
      Save('bad-overflow.sens',Pack(['10','01010',Bits12('2047'),One,'01']));
      Save('bad-negative-overflow.sens',
        Pack(['10','01010',Bits12('-2048'),MinusOne,'01']));
      Save('bad-empty.sens','');
      Manifest.SaveToFile(Folder+'/cases.tsv');
      WriteLn('D5-ADD-CONTEXT-FIXTURES-OK good=16 bad=11');
    finally Manifest.Free end;
  except on E:Exception do begin
    WriteLn(StdErr,'D5-ADD-CONTEXT-FIXTURES-FAIL ',E.Message);
    Halt(1)
  end end;
end.
