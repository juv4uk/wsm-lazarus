{ G6.162 — source-backed pinned Core1 multiply stream fixture generator.
  T5M input/ELF bytes are owned RawByteString values; output directory
  is borrowed. Core1 execution is cross-checked against the D12+ plane.
  1) Why must the function body be read from core1.sens?
  2) How does one ELF accept different runtime operands?
  3) Why can D12 products need D24 output?
  4) What is the difference between Core1 execution and the REPL oracle?
  5) Who owns the emitted T5M result and the output streams? }
program test_core1mulpotikfixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.lowerpinnedcore1mul,wsm.t5m,wsm.numericplane,
  wsm.numericmul;
var Dir:String;Manifest:TStringList;Count:SizeInt;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('CORE1-МНОЖЕННЯ-ФІКСТУРА: '+Why) end;

procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(IncludeTrailingPathDelimiter(Dir)+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;

procedure ReportUTF8(const Message:UnicodeString);
var Bytes:RawByteString;S:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  S:=THandleStream.Create(TextRec(Output).Handle);
  try S.WriteBuffer(Bytes[1],Length(Bytes)) finally S.Free end;
end;

function Atom(Value:LongInt):RawByteString;
var N:TExplicitNumeric;
begin
  Result:=EncodeNumericDecimal(IntToStr(Value),12);
  N:=ReadNumericPhysical(Result,12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12) and
       (Length(Result)=3),'втрачені домен/ширина/байти D12');
end;

procedure CaseOf(const LabelText:String;A,B:LongInt);
var Left,Right,Frame,Expected,NumericResult,Form:RawByteString;
    Product:Int64;Width:SizeInt;N:TExplicitNumeric;Lisp:UnicodeString;
begin
  Left:=Atom(A);Right:=Atom(B);
  Frame:=Left+Right;
  Expected:=PinnedCore1MulCall('.',Left,Right);
  NumericResult:=MultiplyNumericPhysical(Left,Right,12);
  Need(Expected=NumericResult,'Core1 call і numeric plane розійшлись');
  Product:=Int64(A)*Int64(B);
  if (Product>=-2048) and (Product<=2047) then Width:=12 else Width:=24;
  N:=ReadNumericPhysical(Expected,Width);
  Need(N.DomainWidth=Width,'результат не зберіг точну ширину');
  Lisp:=UnicodeString('(помножити '+IntToStr(A)+' '+IntToStr(B)+')'+#10);
  Form:=RawByteString(UTF8Encode(Lisp));
  Save(LabelText+'.frame',Frame);
  Save(LabelText+'.expected.sens',Expected);
  Save(LabelText+'.oracle.lisp',Form);
  Save(LabelText+'.oracle.expected',RawByteString(IntToStr(Product))+#10);
  Manifest.Add(LabelText+#9+IntToStr(A)+#9+IntToStr(B)+#9+
    IntToStr(Product)+#9+IntToStr(Width));
  Inc(Count);
end;

var AnchorL,AnchorR:RawByteString;
begin
  Need((ParamCount=1) and ForceDirectories(ParamStr(1)),
    'потрібен створений каталог свідків');
  Dir:=ParamStr(1);Manifest:=TStringList.Create;
  try
    Count:=0;
    AnchorL:=Atom(7);AnchorR:=Atom(3);
    Save('anchor-left.sens',AnchorL);Save('anchor-right.sens',AnchorR);
    CaseOf('zero',0,-2048);CaseOf('unit',1,1);
    CaseOf('positive',47,43);CaseOf('negative',-47,43);
    CaseOf('negative-both',-47,-43);CaseOf('d12-edge',2047,1);
    CaseOf('promote-positive',48,43);CaseOf('promote-negative',-48,43);
    CaseOf('promote-min',-2048,-1);CaseOf('promote-max',2047,2047);
    CaseOf('wide-product',-2048,-2048);CaseOf('mixed-wide',-128,64);
    CaseOf('small-negative',-1,1);CaseOf('boundary-negative',-2048,1);
    CaseOf('promote-mid',100,50);CaseOf('promote-mid-negative',-100,50);
    Need(Count=16,'неповний набір runtime-входів');
    Save('bad-d24.sens',EncodeNumericDecimal('2048',24));
    Save('bad-pair.sens',AnchorL+AnchorR);
    Save('bad-t5m.sens',#$FF);
    Save('fake.lisp',RawByteString(UTF8Encode(UnicodeString('(помножити 7 3)'))));
    Save('empty.sens','');
    Manifest.SaveToFile(IncludeTrailingPathDelimiter(Dir)+'cases.tsv');
    ReportUTF8('CORE1-МНОЖЕННЯ-ФІЗИЧНІ-СВІДКИ-ГОТОВО: cases=16');
  finally Manifest.Free end;
end.
