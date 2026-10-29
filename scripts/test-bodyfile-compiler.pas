{ G6.148 — незалежні фізичні файли для справжнього FILE→AOT CLI.
  Тестовий генератор використовує pinned D7 лише для отримання exact W7
  та D12+ числовий механізм для packed W24; жодних Pascal Core1 правил.
  Managed масиви/рядки живуть до кінця процедури; файл є власним. }
program test_bodyfile_compiler;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.d7text,wsm.numericplane;
var Map:TD7Map; Folder:String;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create(Why) end;
{ Файлові packed байти власні, не Unicode; потік звільняється у finally.
  Питання: чому D7 не є семантичним dispatch? Хто закриває потік?
  Чому точний W24 не можна замінити W12? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
function One(const W:RawByteString):TExactWords;
begin SetLength(Result,1);Result[0]:=W end;
function Join(const Chunks:array of TExactWords):TExactWords;
var I,J,K:SizeInt;
begin
  SetLength(Result,0);
  for I:=0 to High(Chunks) do
    for J:=0 to High(Chunks[I]) do begin
      K:=Length(Result);SetLength(Result,K+1);Result[K]:=Chunks[I][J];
    end;
end;
function NameNode(const Name:RawByteString):TExactWords;
var Raw,Bits:RawByteString;W:TExactWords;I,N:SizeInt;
begin
  Raw:=EncodeD7Text(Name,Map,dsUk);
  DecodeT5M(Raw,W);
  Bits:='';for I:=0 to High(W) do Bits:=Bits+W[I];
  Need((Length(Bits)>0) and (Length(Bits) mod 7=0),'ім’я не pinned D7');
  N:=Length(Bits) div 7;SetLength(Result,N+2);
  Result[0]:='10';Result[N+1]:='01';
  for I:=0 to N-1 do Result[I+1]:=Copy(Bits,I*7+1,7);
end;
function Atom24(Value:Integer):TExactWords;
begin
  DecodeT5M(EncodeNumericDecimal(RawByteString(IntToStr(Value)),24),Result);
  Need(Length(Result)=1,'очікували один D24 атом');
end;
{ Вхід — точні слова/масиви; вихід — новий D2 список, а не Lisp текст.
  D5:01010 / 01011 / 11010 та D3:110 беруться з чинного pinned SENS.
  1) Чому D2:10/01 — окремі слова? 2) Чому гліфи — окремий D7 вузол?
  3) Чому числа не проходять через двійкову проєкцію host-числа?
  4) Чому тіло не є законним без подальшого admission компілятора? }
function Call(const Head:RawByteString;const A,B:TExactWords):TExactWords;
begin Result:=Join([One('10'),One(Head),A,B,One('01')]) end;
function Quote24(Value:Integer):TExactWords;
begin Result:=Join([One('10'),One('001'),Atom24(Value),One('01')]) end;
function Clause(const Test,Body:TExactWords):TExactWords;
begin Result:=Join([One('10'),Test,Body,One('01')]) end;
function CallName2(const Name,A,B:TExactWords):TExactWords;
begin Result:=Join([One('10'),Name,A,B,One('01')]) end;

procedure CaseOne(const Tag:String;V:Integer;const Body:TExactWords);
begin
  Save(Tag+'.body.sens',EncodeT5M(Body));
  Save(Tag+'.p1.sens',EncodeT5M(NameNode('величина')));
  Save(Tag+'.a1.sens',EncodeNumericDecimal(RawByteString(IntToStr(V)),24));
  WriteLn(Tag,#9,'1',#9,V,#9,0,#9,V,#9,'-');
end;
procedure CasePair(const Tag:String;A,B,Wanted:Integer;
  const Body:TExactWords;Mode:Char);
var OpText:String;
begin
  Save(Tag+'.body.sens',EncodeT5M(Body));
  Save(Tag+'.p1.sens',EncodeT5M(NameNode('величина')));
  Save(Tag+'.p2.sens',EncodeT5M(NameNode('додаток')));
  Save(Tag+'.self.sens',EncodeT5M(NameNode('сума-сенс')));
  Save(Tag+'.a1.sens',EncodeNumericDecimal(RawByteString(IntToStr(A)),24));
  Save(Tag+'.a2.sens',EncodeNumericDecimal(RawByteString(IntToStr(B)),24));
  OpText:='-';
  if Mode='A' then OpText:='додати'
  else if Mode='S' then OpText:='відняти';
  WriteLn(Tag,#9,Mode,#9,A,#9,B,#9,Wanted,#9,OpText);
end;
procedure Run;
var P1,P2,SelfName,AddBody,SubBody,RecurBody:TExactWords;
begin
  Need(ParamCount=2,'потрібні корінь pinned і каталог свідків');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(2));
  Need(ForceDirectories(Folder),'не створено каталог');
  LoadPinnedD7Map(ParamStr(1),Map);
  P1:=NameNode('величина');P2:=NameNode('додаток');
  SelfName:=NameNode('сума-сенс');
  AddBody:=Call('01010',P1,P2);
  SubBody:=Call('01011',P1,P2);
  RecurBody:=Join([One('10'),One('110'),
    Clause(Call('11010',P1,P2),Quote24(0)),
    Clause(One('1'),Call('01010',P1,
      CallName2(SelfName,Call('01011',P1,Quote24(1)),P2))),
    One('01')]);
  CaseOne('one17',17,P1);
  CaseOne('one255',255,P1);
  CasePair('add7',7,-3,4,AddBody,'A');
  CasePair('addneg',-100,55,-45,AddBody,'A');
  CasePair('sub7',7,-3,10,SubBody,'S');
  CasePair('subneg',-100,55,-155,SubBody,'S');
  CasePair('rec5',5,0,15,RecurBody,'R');
  CasePair('rec10',10,7,34,RecurBody,'R');
  CasePair('rec12',12,12,0,RecurBody,'R');
  Save('bad-name.sens',EncodeT5M(Atom24(5)));
  Save('bad-width.sens',EncodeNumericDecimal('1',12));
  Save('bad-body.sens',EncodeT5M(Call('100',P1,P2)));
  Save('bad-self.sens',EncodeT5M(NameNode('інше')));
  Save('bad-corrupt.sens',#$FF);
  WriteLn(StdErr,'BODY-FILE-FIXTURES-OK cases=9 negatives=5');
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'BODY-FILE-FIXTURES-FAIL: ',E.Message);Halt(1)
  end end;
end.
