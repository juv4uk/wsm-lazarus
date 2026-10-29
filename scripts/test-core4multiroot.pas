{ G4.34: фізичні свідки змішаних однослівних і складених коренів.
  D7 береться виключно з першого pinned Core4 DEFINE, D24 непрозорий. }
program test_core4multiroot;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes{$IFDEF UNIX}, cwstring{$ENDIF},
  wsm.core4runtime, wsm.core4multiroot,
  wsm.t5m, wsm.d2source;

const Zero24='000000000000000000000000';
var Runtime:TCore4Runtime; Name:RawByteString;
    Input,Expected,Large,LargeExpected,Late,Bad:TExactWords;
    Physical,Reply:RawByteString; Parsed:TD2Document;
    I:SizeInt;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('провал: '+Why);
end;

procedure Add(var W:TExactWords;const Bits:RawByteString);
var N:SizeInt;
begin
  N:=Length(W);SetLength(W,N+1);W[N]:=Bits;
end;

procedure AddD7(var W:TExactWords;const Id:RawByteString);
var J:SizeInt;
begin
  Need((Length(Id)>0) and ((Length(Id) mod 7)=0),
    'ім’я має бути точною D7-послідовністю');
  Add(W,'10');
  for J:=0 to (Length(Id) div 7)-1 do Add(W,Copy(Id,J*7+1,7));
  Add(W,'01');
end;

procedure AddIdentityCall(var W:TExactWords;
  const Id,Arg:RawByteString);
begin
  Add(W,'10');AddD7(W,Id);Add(W,Arg);Add(W,'01');
end;

procedure AddList(var W:TExactWords);
begin
  { Підтверджений у pinned Contract 12 фізичний D4:1110. }
  Add(W,'10');Add(W,'1110');Add(W,'1');Add(W,Zero24);
  Add(W,'01');
end;

procedure AddLateInvalid(var W:TExactWords);
begin
  { D4:0011 не є самостійним викличним D7-замиканням. }
  Add(W,'10');Add(W,'0011');Add(W,'1');Add(W,'01');
end;

procedure WritePhysical(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  Need(Length(Data)>0,'порожній тестовий файл');
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

procedure CheckResult(const Src:TExactWords;const Want:TExactWords;
  ExpectedRoots:SizeInt;const Why:String);
var Got:TExactWords; P:TD2Document; J:SizeInt;
    Encoded:RawByteString;
begin
  Encoded:=ExecuteCore4Roots(Runtime,EncodeT5M(Src));
  Need(Encoded=EncodeT5M(Want),Why+': фізичні T5M байти');
  DecodeT5M(Encoded,Got);
  Need(Length(Got)=Length(Want),Why+': число точних слів');
  for J:=0 to High(Got) do Need(Got[J]=Want[J],Why+': exact слово '+IntToStr(J+1));
  P:=ParseD2WordsWide(Got);
  try Need(Length(P.Roots)=ExpectedRoots,Why+': кількість D2 коренів')
  finally P.Free end;
end;

procedure ExpectFailure(const Src:RawByteString;const Why:String;
  const MustContain:String='');
var Failed:Boolean; MessageText:String;
begin
  Failed:=False;MessageText:='';
  try
    ExecuteCore4Roots(Runtime,Src);
  except
    on E:Exception do begin Failed:=True;MessageText:=E.Message end;
  end;
  Need(Failed,Why+': помилку не піднято');
  if MustContain<>'' then
    Need(Pos(MustContain,MessageText)>0,Why+': '+MessageText);
end;

begin
  if ParamCount<>2 then begin
    WriteLn(StdErr,'виклик: test_core4multiroot КОРІНЬ ТИМЧАСОВИЙ-КАТАЛОГ');
    Halt(64);
  end;
  Runtime:=TCore4Runtime.Create(ParamStr(1));
  try
    Name:=Runtime.FirstDefinitionIdentifier;
    Need(Runtime.BindingCount=3,'перші три pinned Core4 визначення');
    Input:=nil;Expected:=nil;
    AddIdentityCall(Input,Name,'1');Add(Expected,'1');
    AddList(Input);
    Add(Expected,'10');Add(Expected,'1');Add(Expected,Zero24);
    Add(Expected,'01');
    AddD7(Input,Runtime.BindingIdentifier(1));
    Add(Expected,Zero24);
    CheckResult(Input,Expected,3,'атом + фізичний D2 список + D24 глобал');
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'good.sens',EncodeT5M(Input));
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'expected.sens',EncodeT5M(Expected));

    { 64 окремі реальні Core4 форми, остання дає складений результат. }
    Large:=nil;LargeExpected:=nil;
    for I:=1 to 63 do begin
      AddIdentityCall(Large,Name,'0');Add(LargeExpected,'0');
    end;
    AddList(Large);
    Add(LargeExpected,'10');Add(LargeExpected,'1');
    Add(LargeExpected,Zero24);Add(LargeExpected,'01');
    CheckResult(Large,LargeExpected,64,'64 корені й останній список');

    { Пізня помилка НЕ повертає навіть перші два готові результати. }
    Late:=nil;
    AddIdentityCall(Late,Name,'1');AddList(Late);AddLateInvalid(Late);
    ExpectFailure(EncodeT5M(Late),'пізній невикличний D4','форма=3');
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'late.sens',EncodeT5M(Late));

    Bad:=nil;
    for I:=1 to 65 do AddIdentityCall(Bad,Name,'1');
    ExpectFailure(EncodeT5M(Bad),'65 замість 64','1..64');
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'too-many.sens',EncodeT5M(Bad));
    ExpectFailure(#255,'неканонічний T5M');
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'broken.sens',#255);
    ExpectFailure('','порожній T5M');
    Bad:=nil;Add(Bad,'01');
    ExpectFailure(EncodeT5M(Bad),'зайве D2-закриття','вхід D2');
    Bad:=nil;AddIdentityCall(Bad,Name,'0');
    Expected:=nil;Add(Expected,'0');
    CheckResult(Bad,Expected,1,'одна форма залишилася сумісною');
    WriteLn('CORE4-КОРЕНІ-ТЕСТ-ГАРАЗД форми=1/3/64 складені=так негативні=5');
  finally Runtime.Free end;
end.
