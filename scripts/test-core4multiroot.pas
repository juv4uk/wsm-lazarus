{ G4.34: фізичні свідки змішаних однослівних і складених коренів.
  D7 береться виключно з першого pinned Core4 DEFINE, D24 непрозорий. }
program test_core4multiroot;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes{$IFDEF UNIX}, cwstring{$ENDIF},
  wsm.core4runtime, wsm.core4multiroot,
  wsm.t5m, wsm.d2source;

const Zero24='000000000000000000000000';
var Runtime:TCore4Runtime; Name:RawByteString;
    Input,Expected,Large,LargeExpected,Mixed,MixedExpected,Late,Bad,Single1,Single2,Single3:TExactWords;
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

{ SelectCore4Result працює ТІЛЬКИ із вже виконаними фізичними
  відповідями; жоден виклик helper не є evaluator або D12 арифметикою. }
procedure CheckSelection(const All:TExactWords; Index:SizeInt;
  const Want:TExactWords;const Why:String);
var Reply:RawByteString; Words:TExactWords; Doc:TD2Document;
begin
  Reply:=SelectCore4Result(EncodeT5M(All),Index);
  Need(Reply=EncodeT5M(Want),Why+': втрачено exact T5M слова');
  DecodeT5M(Reply,Words);
  Need(Length(Words)=Length(Want),Why+': число слів');
  Doc:=ParseD2WordsWide(Words);
  try Need(Length(Doc.Roots)=1,Why+': результат не один D2-корінь')
  finally Doc.Free end;
end;

procedure ExpectSelectionFailure(const Physical:RawByteString;
  Index:SizeInt;const Why,MustContain:String);
var Failed:Boolean;MessageText:String;
begin
  Failed:=False;MessageText:='';
  try
    SelectCore4Result(Physical,Index);
  except
    on E:Exception do begin Failed:=True;MessageText:=E.Message end;
  end;
  Need(Failed,Why+': вибір помилково вдався');
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
    { Три незалежно складені очікувані фізичні відповіді. }
    Single1:=nil;Single2:=nil;Single3:=nil;
    Add(Single1,'1');
    Add(Single2,'10');Add(Single2,'1');
    Add(Single2,Zero24);Add(Single2,'01');
    Add(Single3,Zero24);
    CheckSelection(Expected,1,Single1,'перший виконаний D1:1');
    CheckSelection(Expected,2,Single2,'другий повний D2-список');
    CheckSelection(Expected,3,Single3,'третій opaque W24');
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'single-1.sens',EncodeT5M(Single1));
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'single-2.sens',EncodeT5M(Single2));
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'single-3.sens',EncodeT5M(Single3));
    ExpectSelectionFailure(EncodeT5M(Expected),0,'індекс 0','1..64');
    ExpectSelectionFailure(EncodeT5M(Expected),4,'відсутній корінь 4','відсутній');
    ExpectSelectionFailure(EncodeT5M(Expected),65,'індекс 65','1..64');
    ExpectSelectionFailure(#255,2,'пошкоджений T5M','T5M');
    ExpectSelectionFailure('',1,'порожня відповідь','T5M');
    Bad:=nil;Add(Bad,'01');
    ExpectSelectionFailure(EncodeT5M(Bad),1,'непарна D2 рамка','unexpected D2 close 01');
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

    Single1:=nil;Add(Single1,'0');
    CheckSelection(LargeExpected,1,Single1,'перший з 64');
    CheckSelection(LargeExpected,64,Single2,'останній із 64 — складений');
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'large.sens',EncodeT5M(Large));
    WritePhysical(IncludeTrailingPathDelimiter(ParamStr(2))+'single-64-first.sens',EncodeT5M(Single1));

    { 64 справжні pinned Core4 корені, кожен другий повертає
      складений D2 результат із точним непрозорим W24.
      Результат має 160 слів: кілька розширень геометричної місткості. }
    Mixed:=nil;MixedExpected:=nil;
    for I:=1 to 32 do begin
      AddList(Mixed);
      Add(MixedExpected,'10');
      Add(MixedExpected,'1');
      Add(MixedExpected,Zero24);
      Add(MixedExpected,'01');
      AddIdentityCall(Mixed,Name,'0');
      Add(MixedExpected,'0');
    end;
    CheckResult(Mixed,MixedExpected,64,
      '64 змішані виконані Core4 корені й 160 exact слів');

    { Fail-closed на останньому з 64 коренів: видані до цього 63
      відповіді не є частковим успіхом. Те саме середовище придатне. }
    Late:=nil;
    for I:=1 to 63 do AddIdentityCall(Late,Name,'1');
    AddLateInvalid(Late);
    ExpectFailure(EncodeT5M(Late),'пізній корінь 64','форма=64');

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
    WriteLn('CORE4-КОРЕНІ-ТЕСТ-ГАРАЗД форми=1/3/64 складені=так змішані-слова=160 негативні=6 вибір=1/2/3/64 відмови-вибору=6');
  finally Runtime.Free end;
end.
