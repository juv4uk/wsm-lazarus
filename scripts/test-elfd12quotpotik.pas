{ G6.161 — фізичні два runtime D12 та D5:10111 pinned якір.
  Цілочисельні тестові значення — свідки, не Pascal мовний закон.
  Кожен позитив перевірятиме незалежний pinned SENS CLI. }
program test_elfd12quotpotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Dir:String;Valid,Rejected:TStringList;Positive,Negative:SizeInt;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('Д5-ЧАСТКА-СВІДОК: '+Why) end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;
function Word12(V:LongInt):RawByteString;
var T:TExplicitNumeric;
begin
  Result:=EncodeNumericDecimal(IntToStr(V),12);
  T:=ReadNumericPhysical(Result,12);
  Need((Length(Result)=3) and (T.DomainWidth=12) and
       (Length(T.ExactBits)=12),'число поза фізичним D12');
end;
function Bits12(V:LongInt):RawByteString;
var T:TExplicitNumeric;
begin T:=ReadNumericPhysical(Word12(V),12);Result:=T.ExactBits end;
function Pack(const Values:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Values));
  for I:=0 to High(Values) do W[I]:=Values[I];
  Result:=EncodeT5M(W);
end;
function Form(A,B:LongInt):RawByteString;
begin
  Result:=Pack(['10','10111',Bits12(A),Bits12(B),'01']);
end;

{ A/B/Expected — лише test expectations, реально обчислює CPU,
  oracle отримає незалежну canonical форму фізичного .sens.
  Frame: owned 6 byte T5M = W12+W12, НЕ D2 програмна форма.
  1) Чому дві трійки байтів не означають суцільний .sens?
  2) Чому дробове ділення відхиляється в обраному профілі?
  3) Чому в D12 знак — частина рівно 12 бітів?
  4) Хто доводить семантичний результат: FPC чи SENS REPL? }
procedure CaseOf(const LabelText:String;A,B,Expected:LongInt);
var Frame,ProgramBytes,OutputBytes:RawByteString;
begin
  Need((B<>0) and (A mod B=0) and (A div B=Expected),
       'позитивний свідок не є точною цілочисельною часткою');
  Frame:=Word12(A)+Word12(B);
  ProgramBytes:=Form(A,B);
  OutputBytes:=Word12(Expected);
  Save(LabelText+'.frame',Frame);
  Save(LabelText+'.sens',ProgramBytes);
  Save(LabelText+'.expected.sens',OutputBytes);
  Valid.Add(LabelText+#9+IntToStr(A)+#9+IntToStr(B)+#9+
    IntToStr(Expected));
  Inc(Positive);
end;
procedure RejectOf(const LabelText:String;A,B:LongInt);
begin
  Save(LabelText+'.frame',Word12(A)+Word12(B));
  Save(LabelText+'.sens',Form(A,B));
  Rejected.Add(LabelText+#9+IntToStr(A)+#9+IntToStr(B));
  Inc(Negative);
end;
procedure BadFrame(const LabelText:String;const Data:RawByteString);
begin Save(LabelText+'.frame',Data) end;
var Frame:RawByteString;W:TExactWords;
begin
  try
    Need(ParamCount=1,'потрібен каталог доказів');
    Dir:=ParamStr(1);
    Need(ForceDirectories(Dir),'каталог недоступний');
    Valid:=TStringList.Create;Rejected:=TStringList.Create;
    try
      Positive:=0;Negative:=0;
      Save('anchor.sens',Form(7,7));
      CaseOf('01',0,1,0);
      CaseOf('02',0,-1,0);
      CaseOf('03',1,1,1);
      CaseOf('04',-1,-1,1);
      CaseOf('05',2,1,2);
      CaseOf('06',-2,-1,2);
      CaseOf('07',7,7,1);
      CaseOf('08',-7,7,-1);
      CaseOf('09',7,-7,-1);
      CaseOf('10',-7,-7,1);
      CaseOf('11',14,7,2);
      CaseOf('12',-14,7,-2);
      CaseOf('13',14,-7,-2);
      CaseOf('14',-14,-7,2);
      CaseOf('15',21,3,7);
      CaseOf('16',35,-5,-7);
      CaseOf('17',-35,-5,7);
      CaseOf('18',512,2,256);
      CaseOf('19',-512,2,-256);
      CaseOf('20',2046,2,1023);
      CaseOf('21',-2048,2,-1024);
      CaseOf('22',2047,1,2047);
      CaseOf('23',-2048,1,-2048);
      CaseOf('24',2000,-4,-500);
      CaseOf('25',42,6,7);
      Need(Positive=25,'потрібні рівно 25 позитивних пар');
      Valid.SaveToFile(Dir+'/cases.tsv');
      RejectOf('divide-zero',7,0);
      RejectOf('zero-zero',0,0);
      RejectOf('fraction',7,3);
      RejectOf('negative-fraction',-7,3);
      RejectOf('negative-divisor',7,-3);
      RejectOf('fraction-large',2047,2);
      RejectOf('promotion',-2048,-1);
      Need(Negative=7,'потрібні рівно 7 числових відмов');
      Rejected.SaveToFile(Dir+'/numeric-reject.tsv');
      Frame:=Word12(7)+Word12(-7);
      BadFrame('empty','');
      BadFrame('short1',Copy(Frame,1,1));
      BadFrame('short5',Copy(Frame,1,5));
      BadFrame('extra',Frame+#0);
      BadFrame('newline',Frame+#10);
      BadFrame('invalid243',#$FF+Copy(Frame,2,5));
      BadFrame('badfirst',#$02+Copy(Frame,2,5));
      BadFrame('badsecond',Copy(Frame,1,3)+#$02+Copy(Frame,5,2));
      BadFrame('badlast',Copy(Frame,1,5)+#0);
      BadFrame('projection',RawByteString(
        UTF8Encode(UnicodeString('(частка 7 -7)')))+#10);
      SetLength(W,1);W[0]:='1';
      BadFrame('d1',EncodeT5M(W)+EncodeT5M(W));
      WriteLn('D5-ЧАСТКА-ДИНАМІЧНІ-СВІДКИ positive=25 numeric-reject=7 frame-reject=11');
    finally Valid.Free;Rejected.Free end;
  except on E:Exception do begin
    WriteLn(StdErr,'Д5-ЧАСТКА-СВІДКИ-ВІДМОВА: ',E.Message);
    Halt(1)
  end end;
end.
