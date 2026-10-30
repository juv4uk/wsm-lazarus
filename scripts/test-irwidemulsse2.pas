{ G6.242 — реальні фізичні D5 множення у SIMD ELF64.
  Базовий генератор test-irwidemul робить 12 canonical .sens свідків,
  4 D24 результати. Цей тест НЕ інтерпретує SENS: він порівнює
  незалежно допущені IMUL та новий PMULUDQ codegen.
  Borrowed файли/байти T5M, власні managed ELF; TFileStream закрито.
  1) Чому D24 результат може займати п'ять T5M байтів?
  2) Чому незмінність машинного хвоста важлива для доказу?
  3) Чому вигадане D7 ім'я не допускається?
  4) Навіщо перевіряти atomic failure і повторення?
  5) Де в зовнішньому сценарії відбувається реальне виконання ELF? }
program test_irwidemulsse2;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.irwidemul,wsm.irwidemulsse2,wsm.elfgeometry;
const HeaderBytes=120;OldPrefixBytes=11;NewPrefixBytes=30;
var DirectoryName:String;I,Good,D12Count,D24Count,Bad:SizeInt;
    Name,Source,Original,Optimized,Expected:RawByteString;
    Geometry:TELFGeometry;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('SIMD-МНОЖЕННЯ-ПРОВАЛ: '+Why);
end;
function ReadData(const Filename:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(DirectoryName+'/'+Filename,
      fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<65536),'невірна довжина свідка '+Filename);
    SetLength(Result,F.Size);
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure Save(const Filename:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(DirectoryName+'/'+Filename,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;J:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for J:=0 to High(Tokens) do W[J]:=Tokens[J];
  Result:=EncodeT5M(W);
end;
procedure Refuse(const Why:String;const Physical:RawByteString);
var Candidate:RawByteString;Rejected:Boolean;
begin
  Candidate:='';Rejected:=False;
  try Candidate:=BuildIRWideMulSSE2ELF(Physical,'external/sens')
  except on E:Exception do Rejected:=E.Message<>'' end;
  Need(Rejected and (Candidate=''),'неатомарна відмова: '+Why);
  Inc(Bad);
end;
var Zero,One,L24:RawByteString;
begin
  Need((ParamCount=1) and DirectoryExists(ParamStr(1)),
       'потрібна існуюча тека фізичних свідків');
  DirectoryName:=ParamStr(1);
  Good:=0;D12Count:=0;D24Count:=0;Bad:=0;
  for I:=1 to 12 do begin
    Name:=RawByteString(Format('%.2d',[I]));
    Source:=ReadData(String(Name)+'.sens');
    Expected:=ReadData(String(Name)+'.expected.sens');
    Original:=ReadData(String(Name)+'.reference.elf');
    Need(Original=BuildIRWideMulELF(Source,'external/sens'),
         'IMUL-профіль не збігається з source-backed baseline '+String(Name));
    Optimized:=BuildIRWideMulSSE2ELF(Source,'external/sens');
    Need(Optimized=BuildIRWideMulSSE2ELF(Source,'external/sens'),
         'PMULUDQ не є відтворюваним '+String(Name));
    VerifySENSELF64(Optimized,Geometry);
    Need((Geometry.Kind=3) and (Geometry.Entry=120) and
         (Geometry.FileBytes=Length(Optimized)) and
         (Length(Optimized)=Length(Original)+19),
         'ELF64 SIMD geometry '+String(Name));
    Need(Copy(Optimized,1,96)=Copy(Original,1,96),
         'змінено host ELF header до size fields');
    Need(Copy(Optimized,113,8)=Copy(Original,113,8),
         'змінено host ELF header після size fields');
    Need(Copy(Optimized,HeaderBytes+NewPrefixBytes+1,
              Length(Optimized)-HeaderBytes-NewPrefixBytes)=
         Copy(Original,HeaderBytes+OldPrefixBytes+1,
              Length(Original)-HeaderBytes-OldPrefixBytes),
         'змінено фізичний T5M writer або RIP-relative LUT');
    Need(Copy(Optimized,HeaderBytes+21,5)=#$66#$45#$0F#$F4#$C1,
         'немає x86-64 PMULUDQ xmm8,xmm9');
    Need((Length(Expected)=3) or (Length(Expected)=5),
         'пошкоджена довжина D12/D24 T5M');
    if Length(Expected)=3 then Inc(D12Count) else Inc(D24Count);
    Save(String(Name)+'.pmuludq.elf',Optimized);
    Inc(Good);
  end;
  Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
  One:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
  L24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
  Refuse('порожній фізичний T5M','');
  Refuse('пошкоджений T5M',#$FF);
  Refuse('чужа D5 голова',Pack(['10','01010',Zero,One,'01']));
  Refuse('D24 другий операнд',Pack(['10','10110',Zero,L24,'01']));
  Refuse('відсутнє D2 закриття',Pack(['10','10110',Zero,One]));
  Need((Good=12) and (D12Count=8) and (D24Count=4) and (Bad=5),
       'неповне покриття D12/D24/негативів');
  WriteLn('SIMD-МНОЖЕННЯ-ГАРАЗД physical=',Good,
          ' D12=',D12Count,' D24=',D24Count,
          ' negatives=',Bad,' tail=identical');
end.
