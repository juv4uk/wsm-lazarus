{ G6.115: сім профілів WideIR; вхід — фізичний packed T5M.
  12 тестових коренів беруться з перевіреного test-irwidesub.
  Вхід і Result — керовані RawByteString, кожен виклик володіє виходом.
  1) Чому W12 без D5 лишається непрозорим?
  2) Чому байти ELF двох шляхів мають збігатися?
  3) Чому D24 не можна замінити D12?
  4) Що стається з Result при відмові?
  5) Кому належать TFileStream та масиви TExactWords? }
program TestIRWideFrontSub;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.irwidefront,
     wsm.irwidesub,wsm.elfgeometry;
var Dir:String;I,Good,Bad,Widened:SizeInt;
    Zero,One,MaxD12,MinD12,D24:RawByteString;
    G:TELFGeometry;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('СІМ-ПРОФІЛІВ-ПРОВАЛ: '+Why) end;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=65536),'некоректна довжина свідка');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;J:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for J:=0 to High(Tokens) do Words[J]:=Tokens[J];
  Result:=EncodeT5M(Words);
end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;
{ Відмова — жодного ELF; D1 false не дорівнює відмові.
  Candidate — локальний managed buffer, не публікується до success.
  1) Чому слід відхиляти noncanonical source перед машинним кодом?
  2) Чому fail-closed не є дозволом на незнайомі SENS голови?
  3) Хто звільняє Candidate при винятку? }
procedure Refuse(const LabelText:String;const Bytes:RawByteString);
var Candidate:RawByteString;Rejected:Boolean;
begin
  Candidate:='';Rejected:=False;
  try Candidate:=BuildVerifiedWideELF(Bytes,'external/sens')
  except on E:Exception do Rejected:=True end;
  Need(Rejected and (Candidate=''),'не відхилено '+LabelText);
  Inc(Bad);
end;
procedure Prove(const LabelText:String);
var SourceBytes,CommonImage,SpecialImage,Expected:RawByteString;
begin
  SourceBytes:=ReadPhysical(Dir+'/'+LabelText+'.sens');
  Expected:=ReadPhysical(Dir+'/'+LabelText+'.expected.sens');
  CommonImage:=BuildVerifiedWideELF(SourceBytes,'external/sens');
  SpecialImage:=BuildIRWideSubELF(SourceBytes,'external/sens');
  Need((Length(CommonImage)>120) and (CommonImage=SpecialImage),
    'спільний фронт змінив машинний ELF '+LabelText);
  VerifySENSELF64(CommonImage,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(CommonImage)),'ELF64 PIE геометрія');
  if Length(Expected)=5 then Inc(Widened)
  else Need(Length(Expected)=3,'порушено D12/D24 ширину');
  Inc(Good);
end;
begin
  Need(ParamCount=1,'потрібна тека фізичних свідків');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'відсутня тека');
  Good:=0;Bad:=0;Widened:=0;
  for I:=1 to 12 do Prove(Format('%.2d',[I]));
  Need((Good=12) and (Widened=4),'12 фізичних програм / 4 D24');
  Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
  One:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
  MaxD12:=ReadNumericPhysical(EncodeNumericDecimal('2047',12),12).ExactBits;
  MinD12:=ReadNumericPhysical(EncodeNumericDecimal('-2048',12),12).ExactBits;
  D24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;

  { Інші вже підтримані ADD/MUL перевіряє попередній regression.
    D5:01001 — ратифікована координата, але без machine profile. }
  Refuse('D5 без machine profile',Pack(['10','01001',Zero,One,'01']));
  Refuse('D6 без machine profile',Pack(['10','010101',Zero,One,'01']));
  Refuse('голова D7',Pack(['10','0010110',Zero,One,'01']));
  Refuse('перший D1',Pack(['10','01011','1',One,'01']));
  Refuse('другий D24',Pack(['10','01011',Zero,D24,'01']));
  Refuse('бракує аргумента',Pack(['10','01011',Zero,'01']));
  Refuse('зайвий аргумент',Pack(['10','01011',Zero,One,One,'01']));
  Refuse('вкладений аргумент',Pack(['10','01011','10',One,'01',Zero,'01']));
  Refuse('зайвий корінь',Pack(['10','01011',Zero,One,'01','0']));
  Refuse('крапкова пара',Pack(['10','01011','11',Zero,One,'01']));
  Refuse('не закрита D2',Pack(['10','01011',Zero,One]));
  Refuse('голий W12',Pack([One]));
  Refuse('пошкоджений T5M',#$FF);
  Refuse('порожнє джерело','');
  Refuse('D3 порожнеча',Pack(['10','01011','000',One,'01']));
  Refuse('зайве закриття',Pack(['10','01011',Zero,One,'01','01']));
  Refuse('порожня форма',Pack(['10','01']));
  Refuse('два корені',Pack(['10','01011',Zero,One,'01','1']));
  Need(Bad=18,'кількість відмов');
  Save('front-unsupported.sens',Pack(['10','01001',MaxD12,MinD12,'01']));
  WriteLn('SEVEN-WIDEIR-SUB-OK positive=12 D24=4 negative=18 images=identical');
end.
