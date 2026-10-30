{ G6.171 — 12 перевірюваних викличних D4 хибне?(D5 нуль? D12).
  Жодного обчислювача SENS у генераторі: expected біт — тестова
  гіпотеза, звіряється незалежним pinned SENS REPL. }
program test_irwidenenul;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Folder:String; Manifest:TStringList; Positive:SizeInt;

procedure WritePhysical(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

{ Borrowed exact words → owned managed canonical packed T5M.
  1) Чому W2 структурні 10/01 не є SENS числом?
  2) Чому W12 leading zeros залишаються в байтах?
  3) Чому .lisp не може бути канонічним свідком? }
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;

{ Позитивний свідок: тільки ратифіковані D4:0100, D5:01000;
  Numeric — FPC-owned descriptor explicit D12, не семантичний oracle.
  1) Хто доводить signed 12-bit межу?
  2) Хто незалежно доведе очікуваний D1 біт?
  3) Чому D24 не слід мовчки звужувати? }
procedure CaseForm(const LabelText,Decimal,Wanted:RawByteString);
var Numeric:TExplicitNumeric; Answer:TExactWords;
begin
  Numeric:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  WritePhysical(String(LabelText)+'.sens',
    Pack(['10','0100','10','01000',Numeric.ExactBits,'01','01']));
  SetLength(Answer,1); Answer[0]:=Wanted;
  WritePhysical(String(LabelText)+'.expected.sens',EncodeT5M(Answer));
  Manifest.Add(String(LabelText)+#9+String(Decimal)+#9+String(Wanted));
  Inc(Positive);
end;

var Zero,Wide:TExplicitNumeric;
begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not ForceDirectories(Folder) then Halt(2);
  Manifest:=TStringList.Create;
  try
    Positive:=0;
    CaseForm('01','0','0');
    CaseForm('02','-2048','1');
    CaseForm('03','2047','1');
    CaseForm('04','-2047','1');
    CaseForm('05','-1024','1');
    CaseForm('06','-1','1');
    CaseForm('07','1','1');
    CaseForm('08','2','1');
    CaseForm('09','3','1');
    CaseForm('10','100','1');
    CaseForm('11','-100','1');
    CaseForm('12','1024','1');
    Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12);
    Wide:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
    WritePhysical('bad-d4.sens',
      Pack(['10','0101','10','01000',Zero.ExactBits,'01','01']));
    WritePhysical('bad-d5.sens',
      Pack(['10','0100','10','01001',Zero.ExactBits,'01','01']));
    WritePhysical('bad-d24.sens',
      Pack(['10','0100','10','01000',Wide.ExactBits,'01','01']));
    WritePhysical('bad-d1.sens',
      Pack(['10','0100','10','01000','1','01','01']));
    WritePhysical('bad-d7.sens',
      Pack(['10','0100','10','01000','0010110','01','01']));
    WritePhysical('bad-arity.sens',
      Pack(['10','0100','10','01000',Zero.ExactBits,Zero.ExactBits,'01','01']));
    WritePhysical('bad-missing.sens',
      Pack(['10','0100','10','01000','01','01']));
    WritePhysical('bad-nested.sens',
      Pack(['10','0100','10','01000','10','01000',Zero.ExactBits,'01','01','01']));
    WritePhysical('bad-two-roots.sens',
      Pack(['10','0100','10','01000',Zero.ExactBits,'01','01',
            '10','0100','10','01000',Zero.ExactBits,'01','01']));
    WritePhysical('bad-d6.sens',
      Pack(['10','0100','10','010100',Zero.ExactBits,'01','01']));
    WritePhysical('bad-corrupt.sens',#$FF);
    WritePhysical('bad-empty.sens','');
    Manifest.SaveToFile(Folder+'/cases.tsv');
    Writeln('НЕНУЛЬ-СВІДКИ-ГОТОВО positive=',Positive,' negatives=12');
  finally Manifest.Free end;
end.
