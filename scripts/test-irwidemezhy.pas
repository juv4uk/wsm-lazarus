{ G6.144 — побудова цілісних D2 фізичних D6:110100/110110 свідків
  із раніше ратифікованих signed D12 пар G6.78.
  Не задає SENS законів; результати перевіряє незалежний REPL.
  Об'єкти TFileStream і managed TExactWords живуть лише в generator.
  1) Чому D2 framing обов'язковий?
  2) Чому атому потрібна точна ширина, навіть при числі нуль?
  3) Чому генератор не є SENS evaluator?
  4) Чому D24 негативний випадок має відхилятись?
  5) Хто звільняє тимчасові файли в CI? }
program test_irwidemezhy;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Folder:String;I,Count:SizeInt;L,R,Wide:TExplicitNumeric;
    LBits,RBits:RawByteString;

procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Path,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

function Pack(const A:array of RawByteString):RawByteString;
var W:TExactWords;J:SizeInt;
begin
  SetLength(W,Length(A));
  for J:=0 to High(A) do W[J]:=A[J];
  Result:=EncodeT5M(W);
end;

{ Name — реальний existing canonical D12 physical filename;
  Result = original exact W12 word after roundtrip and numeric admission.
  1) Чому не використовуємо текст decimal з.tsv як canonical input?
  2) Чому ReadNumericPhysical після DecodeT5M?
  3) Хто володіє двійковим Input?
  4) Чим W12 відрізняється від D12 result domain? }
function ReadOne(const Name:String):RawByteString;
var S:TFileStream;B:RawByteString;W:TExactWords;N:TExplicitNumeric;
begin
  S:=TFileStream.Create(Folder+'/'+Name,fmOpenRead or fmShareDenyWrite);
  try
    if S.Size<>3 then raise Exception.Create('очікувався packed W12');
    SetLength(B,SizeInt(S.Size));
    S.ReadBuffer(B[1],Length(B));
  finally S.Free end;
  DecodeT5M(B,W);
  if (Length(W)<>1) or (Length(W[0])<>12) or (EncodeT5M(W)<>B) then
    raise Exception.Create('не канонічний signed W12');
  N:=ReadNumericPhysical(B,12);
  if (N.DomainWidth<>12) or (N.ExactBits<>W[0]) then
    raise Exception.Create('numeric admission не збігся');
  Result:=W[0];
end;

procedure Invalid(const Name:String;const Tokens:array of RawByteString);
begin Save(Name+'.sens',Pack(Tokens)) end;

var LabelText,OneBits,WideBits:RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not DirectoryExists(Folder) then Halt(2);
  Count:=0;
  for I:=1 to 12 do begin
    LabelText:=Format('%.2d',[I]);
    LBits:=ReadOne(String(LabelText)+'-l.sens');
    RBits:=ReadOne(String(LabelText)+'-r.sens');
    Save(String(LabelText)+'-110100.sens',Pack([
      '10','110100',LBits,RBits,'01']));
    Save(String(LabelText)+'-110110.sens',Pack([
      '10','110110',LBits,RBits,'01']));
    Inc(Count,2);
  end;
  OneBits:=ReadOne('06-l.sens');
  Wide:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24);
  WideBits:=Wide.ExactBits;
  Invalid('wrong-d5',['10','11010',OneBits,OneBits,'01']);
  Invalid('wrong-d6',['10','110101',OneBits,OneBits,'01']);
  Invalid('wrong-d7',['10','0010110',OneBits,OneBits,'01']);
  Invalid('d1',['10','110100','1',OneBits,'01']);
  Invalid('d24',['10','110100',WideBits,OneBits,'01']);
  Invalid('d24-right',['10','110110',OneBits,WideBits,'01']);
  Invalid('missing',['10','110100',OneBits,'01']);
  Invalid('extra',['10','110100',OneBits,OneBits,OneBits,'01']);
  Invalid('nested',['10','110100','10',OneBits,'01',OneBits,'01']);
  Invalid('two-roots',['10','110100',OneBits,OneBits,'01','0']);
  Invalid('dotted',['10','110100','11',OneBits,OneBits,'01']);
  Invalid('root-atom',[OneBits]);
  Invalid('unclosed',['10','110110',OneBits,OneBits]);
  Invalid('close-only',['01']);
  Invalid('wrong-signature',['10','110101',OneBits,'01']);
  Save('malformed.sens',#$FF);
  Save('empty.sens','');
  Save('fake.lisp',Pack(['10','110100',OneBits,OneBits,'01']));
  if Count<>24 then Halt(3);
  WriteLn('D6-MEZHY-FIXTURES-OK: 24 фізичні форми, 18 негативів');
end.
