{ G6.156 — тестові ФІЗИЧНІ fixtures двох взаємно-рекурсивних тіл.
  D7 кодується ЛИШЕ з pinned таблиці. D3/D5 — точні слова тесту,
  які перевіряються чинним lowering. Це не нова семантика SENS.
  1) Чому імена з pinned карти, а не власний кодувальник?
  2) Чому результат D24, а не D1?
  3) Чому позитиви й негативи фізичні, а не текстові? }
program test_parfile_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.d7text;
var Map:TD7Map;OutputDir:String;

function One(const Word:RawByteString):TExactWords;
begin SetLength(Result,1);Result[0]:=Word end;

function Join(const Parts:array of TExactWords):TExactWords;
var I,J,N:SizeInt;
begin
  SetLength(Result,0);N:=0;
  for I:=0 to High(Parts) do
    for J:=0 to High(Parts[I]) do begin
      SetLength(Result,N+1);
      Result[N]:=Parts[I][J];Inc(N);
    end;
end;

function NameBits(const Text:RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  DecodeT5M(EncodeD7Text(Text,Map,dsUk),Words);
  Result:='';
  for I:=0 to High(Words) do Result:=Result+Words[I];
end;

function NameNode(const Bits:RawByteString):TExactWords;
var I,P:SizeInt;
begin
  SetLength(Result,Length(Bits) div 7+2);
  Result[0]:='10';P:=1;I:=1;
  while I+6<=Length(Bits) do begin
    Result[P]:=Copy(Bits,I,7);Inc(P);Inc(I,7);
  end;
  Result[P]:='01';
end;

function D24(Value:LongWord):RawByteString;
var I:Integer;
begin
  SetLength(Result,24);
  for I:=1 to 24 do
    if (Value and (LongWord(1) shl (24-I)))<>0 then Result[I]:='1'
    else Result[I]:='0';
end;

function QuoteAtom(const Word:RawByteString):TExactWords;
begin Result:=Join([One('10'),One('001'),One(Word),One('01')]) end;

function Clause(const Pred,Body:TExactWords):TExactWords;
begin Result:=Join([One('10'),Pred,Body,One('01')]) end;

function Call1(const Name,Arg:TExactWords):TExactWords;
begin Result:=Join([One('10'),Name,Arg,One('01')]) end;

procedure SavePhysical(const Name:String;const Words:TExactWords);
var F:TFileStream;Data:RawByteString;
begin
  Data:=EncodeT5M(Words);
  F:=TFileStream.Create(OutputDir+'/'+Name,fmCreate);
  try F.WriteBuffer(Data[1],Length(Data));finally F.Free end;
end;

procedure SaveRaw(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(OutputDir+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

var
  ParamRef,BodyA,BodyB:TExactWords;
  Values:array[0..6] of LongWord=(0,1,2,5,8,11,16);
  I:SizeInt;V:LongWord;Expected:LongWord;
begin
  if ParamCount<>2 then Halt(2);
  OutputDir:=ParamStr(2);
  LoadPinnedD7Map(ParamStr(1),Map);
  ParamRef:=NameNode(NameBits('величина'));
  BodyA:=Join([One('10'),One('110'),
    Clause(Join([One('10'),One('11010'),ParamRef,
      QuoteAtom(D24(1)),One('01')]),QuoteAtom(D24(1))),
    Clause(One('1'),Call1(NameNode(NameBits('непарне')),
      Join([One('10'),One('01011'),ParamRef,
        QuoteAtom(D24(1)),One('01')]))),
    One('01')]);
  BodyB:=Join([One('10'),One('110'),
    Clause(Join([One('10'),One('11010'),ParamRef,
      QuoteAtom(D24(1)),One('01')]),QuoteAtom(D24(0))),
    Clause(One('1'),Call1(NameNode(NameBits('парне')),
      Join([One('10'),One('01011'),ParamRef,
        QuoteAtom(D24(1)),One('01')]))),
    One('01')]);
  SavePhysical('тіло-а.sens',BodyA);
  SavePhysical('імя-а.sens',NameNode(NameBits('парне')));
  SavePhysical('тіло-б.sens',BodyB);
  SavePhysical('імя-б.sens',NameNode(NameBits('непарне')));
  SavePhysical('параметр.sens',ParamRef);
  for I:=0 to High(Values) do begin
    V:=Values[I];
    if (V and 1)=0 then Expected:=1 else Expected:=0;
    SavePhysical('arg-'+IntToStr(V)+'.sens',One(D24(V)));
    SavePhysical('expected-'+IntToStr(V)+'.sens',One(D24(Expected)));
    Writeln(V,#9,Expected);
  end;
  SavePhysical('bad-width.sens',One('000000000001'));
  SavePhysical('bad-name.sens',Join([One('10'),One('1'),One('01')]));
  SavePhysical('bad-body.sens',One('1111'));
  SaveRaw('bad-t5m.sens',#$FF);
  SaveRaw('empty.sens','');
  SaveRaw('bad-append.sens',EncodeT5M(BodyA)+#0);
end.
