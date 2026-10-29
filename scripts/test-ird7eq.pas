{ G6.74: pinned ExactIR D7 equality vs existing compiler + real ELF.
  Source .sens is canonical T5M. No host D7 textual EQ dispatch. }
program test_ird7eq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.ird7eq,wsm.elfd7eq;
var Root,Dir:String;Passed,Rejected:SizeInt;

function Pack(const Parts:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Parts));
  for I:=0 to High(Parts) do W[I]:=Parts[I];
  Result:=EncodeT5M(W);
end;
procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('Прямий IR D7: '+Why);
end;
procedure Save(const Path:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(B)>0 then F.WriteBuffer(B[1],Length(B));
  finally F.Free end;
end;

{ Both bits borrowed MSB-first; no Unicode/codepage coercion.
  Each positive writes exact physical source, full ELF, result T5M,
  and independent oracle's human projection as separate TEST artifacts.
  Questions: Why byte-exact entire ELF vs only stdout? Why 7 XOR pairs?
  Why does the pinned oracle receive same .sens? What owns local Bytes? }
procedure Positive(const LabelText:String;
  const L,R,Expected:RawByteString);
var Physical,ELF,Reference,Answer:RawByteString;
    Lowered:TLoweredD7Eq;
begin
  Physical:=Pack(['10','101','10','001',L,'01',
    '10','001',R,'01','01']);
  LowerPinnedQuotedD7Eq(Physical,RawByteString(Root),Lowered);
  Need((Lowered.LeftBits=L) and (Lowered.RightBits=R),
    'Втрачено exact D7 у verified IR '+LabelText);
  ELF:=BuildPinnedQuotedD7EqIRELF(Physical,RawByteString(Root));
  Reference:=BuildQuotedD7EqELF(Physical,RawByteString(Root));
  Need(ELF=Reference,'Не byte-identical до чинного D7 ELF: '+LabelText);
  Need((Length(ELF)>160) and (Length(ELF)<400) and
    (Copy(ELF,1,4)=#$7F'ELF') and
    (Ord(ELF[17])=3) and (Ord(ELF[19])=62),
    'Неправильний AMD64 PIE/ELF64');
  Need(Pos(#$84#$C0#$0F#$94#$C0#$0F#$B6#$C0,ELF)>0,
    'Відсутнє машинне TEST/SETE/MOVZX');
  Need(BuildPinnedQuotedD7EqIRELF(Physical,RawByteString(Root))=ELF,
    'Недетермінований ELF64');
  Answer:=Pack([Expected]);
  Need(Length(Answer)=1,'D1 має бути рівно одним T5M байтом');
  Save(Dir+'/'+LabelText+'.sens',Physical);
  Save(Dir+'/'+LabelText+'.elf',ELF);
  Save(Dir+'/'+LabelText+'.expected.sens',Answer);
  Save(Dir+'/'+LabelText+'.expected.txt',Expected+#10);
  Inc(Passed);
end;

procedure RejectRaw(const Source:RawByteString;const Why:String);
var Image:RawByteString;Refused:Boolean;
begin
  Image:='';Refused:=False;
  try Image:=BuildPinnedQuotedD7EqIRELF(Source,RawByteString(Root));
  except on E:EIRD7EqError do Refused:=True end;
  Need(Refused and (Image=''),'Не відхилено: '+Why);
  Inc(Rejected);
end;
procedure Reject(const Parts:array of RawByteString;const Why:String);
begin RejectRaw(Pack(Parts),Why) end;
begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);Dir:=ParamStr(2);Passed:=0;Rejected:=0;
  Need(ForceDirectories(Dir),'Немає каталогу тестів');
  Positive('син-однакові','0010110','0010110','1');
  Positive('син-різні','0010110','0000000','0');
  Positive('старший-однакові','1111111','1111111','1');
  Positive('старший-різні','1111111','0010110','0');
  Positive('нулі-однакові','0000001','0000001','1');
  Positive('нулі-різні','0000001','0000010','0');
  Reject(['1'],'D1 без D3 голови');
  Reject(['10','0010110','1','01'],'D7 виклична голова');
  Reject(['10','101','0010110',
    '10','001','0010110','01','01'],'нецитований лівий W7');
  Reject(['10','101','10','001','0010110','01',
    '0010110','01'],'нецитований правий W7');
  Reject(['10','101','10','001','000000000000','01',
    '10','001','0010110','01','01'],'D12 під D7');
  Reject(['10','101','10','001','0010110','01',
    '1','01'],'D1 праворуч як D7');
  Reject(['10','101','10','001','0010110','01',
    '10','001','0010110','01','1','01'],'зайва арність');
  Reject(['10','101','10','001','0010110','01','01'],'нестача аргументу');
  Reject(['10','101','10','001','0010110','01',
    '10','001','0010110','01','01','1'],'другий корінь');
  Reject(['10','101','10','001','000','01',
    '10','001','0010110','01','01'],'порожня D3 не D7');
  RejectRaw(#$F3,'зіпсований T5M');
  RejectRaw('','порожнє фізичне джерело');
  Need((Passed=6) and (Rejected=12),'лічильник свідків');
  Positive('син-відновлено','0010110','0010110','1');
  Need((Passed=7) and (Rejected=12),'сценарій відновлення');
  WriteLn('IRD7EQ-OK positives=',Passed,' negatives=',Rejected,
    ' verified-IR=1 byte-identical=1');
end.
