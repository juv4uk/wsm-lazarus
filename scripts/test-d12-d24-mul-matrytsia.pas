{ G6.157 — 100 exact canonical D12×D12 signed witnesses for existing WideIR ELF.
  This is an independent TEST fixture generator, not a SENS semantic implementation.
  Inputs: one borrowed directory path; outputs: owned packed T5M files and TSV.
  Numeric values are test data; identity stays exact (domain,width,bits,law).
  Memory: local managed RawByteString/TExactWords/Strings, TFileStream closed on exit.
  1) Чому числовий D12 допускається тільки в контексті pinned D5?
  2) Чому expected T5M обчислюємо окремо від machine ELF?
  3) Чому 47 випадків мають D24, а решта 53 — D12?
  4) Хто володіє байтами .sens після Save?
  5) Чому потрібен незалежний SENS REPL, якщо є механічний еталон? }
program test_d12_d24_mul_matrytsia;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericmul;
const
  Vals:array[0..9] of ShortString=
    ('-2048','-2047','-1024','-31','-1','0','1','31','1024','2047');
var
  Dir,Name,LeftDec,RightDec,Wanted: String;
  Manifest:TStringList;
  I,J,K,Width,Narrow,Wide:SizeInt;
  Product:Int64;
  LeftPhysical,RightPhysical,Expected,Actual:RawByteString;
  LeftNumeric,RightNumeric,Answer:TExplicitNumeric;
  LeftBits,RightBits,WideBits:RawByteString;
procedure Require(Condition:Boolean;const Detail:String);
begin if not Condition then raise Exception.Create('МАТРИЦЯ-МНОЖЕННЯ-ВІДМОВА: '+Detail) end;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;X:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for X:=0 to High(Tokens) do W[X]:=Tokens[X];
  Result:=EncodeT5M(W);
end;
begin
  Require(ParamCount=1,'потрібен каталог свідків');
  Dir:=ParamStr(1);
  Require(DirectoryExists(Dir),'каталог не існує');
  Manifest:=TStringList.Create;
  try
    Narrow:=0;Wide:=0;
    for I:=Low(Vals) to High(Vals) do
      for J:=Low(Vals) to High(Vals) do begin
        Name:='m'+IntToStr(I)+'-'+IntToStr(J);
        LeftDec:=String(Vals[I]);RightDec:=String(Vals[J]);
        Product:=StrToInt64(LeftDec)*StrToInt64(RightDec);
        Wanted:=IntToStr(Product);
        if (Product < -2048) or (Product > 2047) then begin
          Width:=24;Inc(Wide)
        end else begin Width:=12;Inc(Narrow) end;
        LeftPhysical:=EncodeNumericDecimal(RawByteString(LeftDec),12);
        RightPhysical:=EncodeNumericDecimal(RawByteString(RightDec),12);
        LeftNumeric:=ReadNumericPhysical(LeftPhysical,12);
        RightNumeric:=ReadNumericPhysical(RightPhysical,12);
        Require((LeftNumeric.DomainWidth=12) and (RightNumeric.DomainWidth=12),
          'втрачена числова ширина операнда '+Name);
        LeftBits:=LeftNumeric.ExactBits;RightBits:=RightNumeric.ExactBits;
        Expected:=EncodeNumericDecimal(RawByteString(Wanted),Width);
        Actual:=MultiplyNumericPhysical(LeftPhysical,RightPhysical,12);
        Require(Actual=Expected,'розходження pinned механізму й незалежної математики '+Name);
        Answer:=ReadNumericPhysical(Actual,Width);
        Require(Answer.DomainWidth=Width,'помилкова фізична ширина результату '+Name);
        Save(Name+'.sens',Pack(['10','10110',LeftBits,RightBits,'01']));
        Save(Name+'.expected.sens',Expected);
        Manifest.Add(Name+#9+LeftDec+#9+RightDec+#9+Wanted+#9+IntToStr(Width));
      end;
    Require((Manifest.Count=100) and (Wide=47) and (Narrow=53),
      'матриця не повна або межа просування D12/D24 неправильна');
    LeftBits:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
    RightBits:=ReadNumericPhysical(EncodeNumericDecimal('2',12),12).ExactBits;
    WideBits:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
    Save('bad-head.sens',Pack(['10','11111',LeftBits,RightBits,'01']));
    Save('bad-width.sens',Pack(['10','10110',WideBits,RightBits,'01']));
    Save('missing.sens',Pack(['10','10110',LeftBits,'01']));
    Save('extra.sens',Pack(['10','10110',LeftBits,RightBits,LeftBits,'01']));
    Save('nested.sens',Pack(['10','10110','10',LeftBits,'01',RightBits,'01']));
    Save('two-roots.sens',Pack(['10','10110',LeftBits,RightBits,'01','0']));
    Save('unclosed.sens',Pack(['10','10110',LeftBits,RightBits]));
    Save('bad-t5m.sens',#$FF);
    Save('empty.sens','');
    Save('fake.lisp',Pack(['10','10110',LeftBits,RightBits,'01']));
    Manifest.SaveToFile(Dir+'/cases.tsv');
    WriteLn('Д12-МАТРИЦЯ-СВІДКИ-ГОТОВО: cases=100 d12=',Narrow,' d24=',Wide,' negatives=10');
  finally Manifest.Free end;
end.
