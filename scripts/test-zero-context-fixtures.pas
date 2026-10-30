{ G6.190 — 16 фізичних D5:01000(D12) canonical SENS свідків.
  Decimal — лише test-input для D12 encoder, не мовна семантика.
  Всі очікувані відповіді — точний D1 packed T5M, а не host bool. }
program test_zero_context_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Directory:String;Manifest:TStringList;Count:SizeInt;

{ Ім'я — borrowed host path; Data — owned packed T5M bytes.
  FPC TFileStream release even after WriteBuffer exception.
  1) Чому у фізичному файлі немає UTF-8 проєкції?
  2) Хто закриває fd за відмови?
  3) Де записані точні leading zeros? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Directory+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

{ Words borrowed bit arrays; Result exact physical T5M.
  1) Чому D2 framing — два exact words?
  2) Чому сама 12-бітова ширина не дає D12 закон?
  3) Хто визначає canonical padding? }
function Pack(const Values:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Values));
  for I:=0 to High(Values) do W[I]:=Values[I];
  Result:=EncodeT5M(W);
end;

function ReadD24Dummy:RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
  Result:=N.ExactBits;
end;

function Bits12(const Decimal:String):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  if (N.DomainWidth<>12) or (Length(N.ExactBits)<>12) then
    raise Exception.Create('не підтверджений signed D12');
  Result:=N.ExactBits;
end;

{ Zero is only test expectation, never a Pascal SENS evaluator.
  Machine TEST/SETE produces real D1 physical answer when executed.
  1) Чому тест не замінює pinned SENS REPL oracle?
  2) Чому -2048 є допустимим D12?
  3) Чому reference result має ширину 1? }
procedure Valid(const LabelText,Decimal:String;Zero:Boolean);
var B:RawByteString;
begin
  B:=Bits12(Decimal);
  Save(LabelText+'.sens',Pack(['10','01000',B,'01']));
  if Zero then Save(LabelText+'.expected.sens',Pack(['1']))
  else Save(LabelText+'.expected.sens',Pack(['0']));
  Manifest.Add(LabelText+#9+Decimal);
  Inc(Count);
end;
var Z:RawByteString;
begin
  try
    if ParamCount<>1 then raise Exception.Create('потрібен каталог свідків');
    Directory:=ParamStr(1);
    if not ForceDirectories(Directory) then raise Exception.Create('каталог недоступний');
    Manifest:=TStringList.Create;
    try
      Count:=0;
      Valid('01','0',True); Valid('02','1',False);
      Valid('03','-1',False); Valid('04','2',False);
      Valid('05','-2',False); Valid('06','7',False);
      Valid('07','-7',False); Valid('08','42',False);
      Valid('09','-42',False); Valid('10','1024',False);
      Valid('11','-1024',False); Valid('12','2047',False);
      Valid('13','-2048',False); Valid('14','511',False);
      Valid('15','-511',False); Valid('16','1234',False);
      if Count<>16 then raise Exception.Create('потрібні 16 різних D12');
      Z:=Bits12('0');
      Save('bad-head.sens',Pack(['10','01001',Z,'01']));
      Save('bad-arity.sens',Pack(['10','01000',Z,Z,'01']));
      Save('bad-d1.sens',Pack(['10','01000','1','01']));
      Save('bad-d24.sens',Pack(['10','01000',
        ReadD24Dummy,'01']));
      Save('bad-open.sens',Pack(['10','01000',Z]));
      Save('bad-two-roots.sens',Pack(['10','01000',Z,'01','1']));
      Save('bad-t5m.sens',#$FF);
      Save('bad-empty.sens','');
      Manifest.SaveToFile(Directory+'/cases.tsv');
      WriteLn('ZERO-CONTEXT-FIXTURES-OK count=',Count,' negatives=8');
    finally Manifest.Free end;
  except on E:Exception do begin
    WriteLn(StdErr,'ZERO-CONTEXT-FIXTURES-FAIL ',E.Message);
    Halt(1)
  end end;
end.
