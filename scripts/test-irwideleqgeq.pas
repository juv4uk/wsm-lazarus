{ G6.156 — фізичні D6 межі, signed D12, D1 T5M.
  Генератор свідків НЕ є SENS evaluator. Значення очікувань
  додатково перевіряє незалежний pinned SENS REPL. }
program test_irwideleqgeq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Folder:String;Manifest:TStringList;Positive:SizeInt;

procedure WritePhysical(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

{ Tokens — borrowed exact words включно з D2. Result — owned T5M.
  1) Чому обрамлення списку має W2, не W7?
  2) Чому останній T5M байт є transport, не opcode?
  3) Хто звільняє динамічний масив? }
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;

{ ОЧІКУВАНИЙ біт — лише тестовий oracle candidate. Семантичну
  відповідь перевірить окремий pinned CLI у повній укр проєкції.
  Жодних Pascal if A<=B: жодної власної SENS математичної семантики.
  1) Що доводить машина, а що незалежний oracle?
  2) Чому signed межі -2048 і 2047 критичні?
  3) Чому не можна підмінити D12 D24? }
procedure CaseForm(const LabelText,Head,L,R,Wanted:RawByteString);
var Left,Right:TExplicitNumeric;Answer:TExactWords;
begin
  Left:=ReadNumericPhysical(EncodeNumericDecimal(L,12),12);
  Right:=ReadNumericPhysical(EncodeNumericDecimal(R,12),12);
  WritePhysical(String(LabelText)+'.sens',
    Pack(['10',Head,Left.ExactBits,Right.ExactBits,'01']));
  SetLength(Answer,1);Answer[0]:=Wanted;
  WritePhysical(String(LabelText)+'.expected.sens',EncodeT5M(Answer));
  Manifest.Add(String(LabelText)+#9+String(Head)+#9+
               String(L)+#9+String(R)+#9+String(Wanted));
  Inc(Positive);
end;

var Z:TExplicitNumeric;Large:TExplicitNumeric;
begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not ForceDirectories(Folder) then Halt(2);
  Manifest:=TStringList.Create;
  try
    Positive:=0;
    CaseForm('01','110100','-2048','-2048','1');
    CaseForm('02','110100','-2048','2047','1');
    CaseForm('03','110100','2047','-2048','0');
    CaseForm('04','110100','2047','2047','1');
    CaseForm('05','110100','-1','0','1');
    CaseForm('06','110100','0','-1','0');
    CaseForm('07','110100','1','2','1');
    CaseForm('08','110100','2','1','0');
    CaseForm('09','110110','-2048','-2048','1');
    CaseForm('10','110110','-2048','2047','0');
    CaseForm('11','110110','2047','-2048','1');
    CaseForm('12','110110','2047','2047','1');
    CaseForm('13','110110','-1','0','0');
    CaseForm('14','110110','0','-1','1');
    CaseForm('15','110110','1','2','0');
    CaseForm('16','110110','2','1','1');
    Z:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12);
    Large:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
    WritePhysical('bad-head.sens',
      Pack(['10','110101',Z.ExactBits,Z.ExactBits,'01']));
    WritePhysical('bad-arity.sens',Pack(['10','110100',Z.ExactBits,'01']));
    WritePhysical('bad-d24.sens',
      Pack(['10','110110',Z.ExactBits,Large.ExactBits,'01']));
    WritePhysical('bad-d1.sens',
      Pack(['10','110110',Z.ExactBits,'1','01']));
    WritePhysical('bad-d7.sens',
      Pack(['10','110100','0010110',Z.ExactBits,'01']));
    WritePhysical('bad-two-roots.sens',
      Pack(['10','110100',Z.ExactBits,Z.ExactBits,'01',
            '10','110110',Z.ExactBits,Z.ExactBits,'01']));
    WritePhysical('bad-nested.sens',
      Pack(['10','110100','10','110110',Z.ExactBits,Z.ExactBits,
            '01',Z.ExactBits,'01']));
    WritePhysical('bad-corrupt.sens',#$FF);
    WritePhysical('bad-empty.sens','');
    Manifest.SaveToFile(Folder+'/cases.tsv');
    Writeln('D6-МЕЖІ-СВІДКИ-ГАРАЗД positive=',Positive,' negatives=9');
  finally Manifest.Free end;
end.
