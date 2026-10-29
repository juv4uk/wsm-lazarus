{ G6.138 — два pinned D6 профілі через спільний WideIR.
  Генератор створює лише фізичні T5M input/expected та TSV.
  Machine ELF генерує чинний compiler; test oracle є зовнішній SENS.
  1) Чому у fixture порівняння host не є semantic oracle?
  2) Чому width=12 за крайнього -2048?
  3) Хто звільняє TFileStream/TStringList?
  4) Чому дві окремі D6 координати мають той самий D12 output? }
program test_irwidefront_minmax;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
const
  AValues:array[0..11] of LongInt=
    (-2048,2047,-2048,2047,0,-1,0,-17,17,12,-120,1024);
  BValues:array[0..11] of LongInt=
    (2047,-2048,-2048,2047,0,0,-1,17,-17,48,-110,1023);
var Folder:String;Cases:TStringList;
    I,Kind,OutputValue,Count:SizeInt;
    A,B:TExplicitNumeric;LabelText,Head:RawByteString;

function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;J:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for J:=0 to High(Tokens) do Words[J]:=Tokens[J];
  Result:=EncodeT5M(Words);
end;

procedure Save(const Name:String;const Content:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try
    if Length(Content)>0 then F.WriteBuffer(Content[1],Length(Content));
  finally F.Free end;
end;

begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not ForceDirectories(Folder) then Halt(2);
  Cases:=TStringList.Create;
  try
    Count:=0;
    for Kind:=0 to 1 do
      for I:=0 to High(AValues) do begin
        A:=ReadNumericPhysical(EncodeNumericDecimal(IntToStr(AValues[I]),12),12);
        B:=ReadNumericPhysical(EncodeNumericDecimal(IntToStr(BValues[I]),12),12);
        if Kind=0 then begin
          Head:='110101';
          if AValues[I]<BValues[I] then OutputValue:=AValues[I]
          else OutputValue:=BValues[I];
        end else begin
          Head:='110111';
          if AValues[I]>BValues[I] then OutputValue:=AValues[I]
          else OutputValue:=BValues[I];
        end;
        LabelText:=Format('%.2d',[Count+1]);
        Save(String(LabelText)+'.sens',
             Pack(['10',Head,A.ExactBits,B.ExactBits,'01']));
        Save(String(LabelText)+'.expected.sens',
             EncodeNumericDecimal(IntToStr(OutputValue),12));
        Save(String(LabelText)+'.a.sens',
             EncodeNumericDecimal(IntToStr(AValues[I]),12));
        Save(String(LabelText)+'.b.sens',
             EncodeNumericDecimal(IntToStr(BValues[I]),12));
        Cases.Add(String(LabelText)+#9+IntToStr(Kind)+#9+
          IntToStr(AValues[I])+#9+IntToStr(BValues[I])+#9+
          IntToStr(OutputValue));
        Inc(Count);
      end;
    Cases.SaveToFile(Folder+'/cases.tsv');
    A:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12);
    B:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
    Save('bad-d24-left.sens',Pack(['10','110101',B.ExactBits,A.ExactBits,'01']));
    Save('bad-d24-right.sens',Pack(['10','110111',A.ExactBits,B.ExactBits,'01']));
    Save('bad-d1.sens',Pack(['10','110101','1',A.ExactBits,'01']));
    Save('bad-d3.sens',Pack(['10','110111','000',A.ExactBits,'01']));
    Save('bad-d7.sens',Pack(['10','110101','0010110',A.ExactBits,'01']));
    Save('bad-arity-one.sens',Pack(['10','110101',A.ExactBits,'01']));
    Save('bad-arity-three.sens',Pack(['10','110111',A.ExactBits,A.ExactBits,A.ExactBits,'01']));
    Save('bad-nested.sens',Pack(['10','110101',A.ExactBits,'10',A.ExactBits,'01','01']));
    Save('bad-two-roots.sens',Pack(['10','110111',A.ExactBits,A.ExactBits,'01','0']));
    Save('bad-head.sens',Pack(['10','110110',A.ExactBits,A.ExactBits,'01']));
    Save('bad-truncated.sens',Pack(['10','110101',A.ExactBits,A.ExactBits]));
    Save('bad-root.sens',Pack([A.ExactBits]));
    Save('bad-t5m.sens',#$FF);
    Save('bad-empty.sens','');
    Save('fake.lisp',Pack(['10','110101',A.ExactBits,A.ExactBits,'01']));
    if Count<>24 then Halt(3);
    WriteLn('D6-MINMAX-FIXTURES positive=',Count,' negative=14');
  finally Cases.Free end;
end.
