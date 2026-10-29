{ G5.66 — лише фізичні test fixtures для справжнього Core1 runtime.
  Тіло першого DEFINE отримано з pinned core1.sens у чинному модулі.
  Очікуваний результат береться викликом того самого одноформового API;
  незалежний SENS REPL перевіряється ОКРЕМИМ сценарієм у workflow. }
program test_core1_paket;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.core1first, wsm.core1index;

var Runtime:TCore1FirstRuntime; Index:TCore1Index; Name:RawByteString;
    All,Expected,OneCall,OneAnswer:TExactWords;
    I,J,Used:SizeInt;

function MakeCall(const Id:RawByteString;
  const Items:array of RawByteString; InvalidName:Boolean=False):TExactWords;
var K,N:SizeInt; Letter:RawByteString;
begin
  N:=Length(Id) div 7;
  if (N<1) or (N*7<>Length(Id)) then
    raise Exception.Create('немає точного D7 ідентифікатора');
  SetLength(Result,0);
  SetLength(Result,N+Length(Items)+7);
  K:=0;
  Result[K]:='10';Inc(K); { D2 call }
  Result[K]:='10';Inc(K); { D7 name }
  for I:=0 to N-1 do begin
    Letter:=Copy(Id,I*7+1,7);
    if InvalidName and (I=0) then begin
      if Letter[1]='0' then Letter[1]:='1'
      else Letter[1]:='0';
    end;
    Result[K]:=Letter;Inc(K);
  end;
  Result[K]:='01';Inc(K);
  Result[K]:='10';Inc(K); { D4 list argument }
  Result[K]:='1110';Inc(K);
  for I:=0 to High(Items) do begin Result[K]:=Items[I];Inc(K) end;
  Result[K]:='01';Inc(K);
  Result[K]:='01';Inc(K);
  SetLength(Result,K);
end;

procedure Save(const FileName:String;const Words:TExactWords);
var F:TFileStream; B:RawByteString;
begin
  B:=EncodeT5M(Words);
  F:=TFileStream.Create(FileName,fmCreate);
  try if Length(B)>0 then F.WriteBuffer(B[1],Length(B))
  finally F.Free end;
end;

procedure AppendWords(var Target:TExactWords;const Extra:TExactWords);
var Count,K:SizeInt;
begin
  Count:=Length(Target);
  if Length(Extra)>MaxInt-Count then
    raise Exception.Create('перевищено межу host-масиву');
  SetLength(Target,Count+Length(Extra));
  for K:=0 to High(Extra) do Target[Count+K]:=Extra[K];
end;

function CallForIndex(N:SizeInt; Bad:Boolean=False):TExactWords;
const W24:RawByteString='000000000000000000000001';
begin
  case N mod 4 of
    0: Result:=MakeCall(Name,['1','0','1'],Bad);
    1: Result:=MakeCall(Name,['0','1','0'],Bad);
    2: Result:=MakeCall(Name,['1',W24,'0'],Bad);
    else Result:=MakeCall(Name,['1010101','1','0'],Bad);
  end;
end;

procedure MakeSet(const Folder,LabelText:String; Count:SizeInt;
  BadLast:Boolean=False);
var Calls,Answers,UnitWords,AnswerWords:TExactWords;
    Reply:RawByteString; K:SizeInt;
begin
  Calls:=nil;Answers:=nil;
  for K:=0 to Count-1 do begin
    UnitWords:=CallForIndex(K,BadLast and (K=Count-1));
    AppendWords(Calls,UnitWords);
    if not BadLast then begin
      Reply:=Runtime.ExecutePhysicalCall(EncodeT5M(UnitWords));
      DecodeT5M(Reply,AnswerWords);
      if (Length(AnswerWords)<1) or (EncodeT5M(AnswerWords)<>Reply) then
        raise Exception.Create('single Core1 runtime повернув неканонічні байти');
      AppendWords(Answers,AnswerWords);
    end;
  end;
  Save(IncludeTrailingPathDelimiter(Folder)+LabelText+'.sens',Calls);
  if not BadLast then Save(IncludeTrailingPathDelimiter(Folder)+
    LabelText+'.expected.sens',Answers);
end;

begin
  if ParamCount<>3 then Halt(64);
  Runtime:=TCore1FirstRuntime.Create(ParamStr(1),ParamStr(2));
  try
    Name:=Runtime.FirstIdentifier;
    MakeSet(ParamStr(3),'one',1);
    MakeSet(ParamStr(3),'three',3);
    MakeSet(ParamStr(3),'sixtyfour',64);
    MakeSet(ParamStr(3),'sixtyfive',65);
    MakeSet(ParamStr(3),'late-bad',64,True);
    { Відоме pinned DEFINE #2 має справжній точний D7 ключ, але
      runtime поки не виконує його. Це не невідомий ідентифікатор.
      Індекс живе лише під час створення фізичного свідка. }
    Index:=TCore1Index.Create(ParamStr(2));
    try
      if Index.Count<2 then
        raise Exception.Create('pinned Core1 не має другого DEFINE');
      Save(IncludeTrailingPathDelimiter(ParamStr(3))+
        'known-blocked.sens',
        MakeCall(Index.Definition(2).NameBits,['1','0','1']));
    finally Index.Free end;
    { Недопустима глибока фізична структура: замінюємо останнє D2
      закриття на пару/крапку. Це не новий закон парсера. }
    OneCall:=CallForIndex(0);
    OneCall[High(OneCall)]:='11';
    Save(IncludeTrailingPathDelimiter(ParamStr(3))+'broken-d2.sens',OneCall);
    WriteLn('CORE1-PAKET-FIXTURES-OK 1/3/64/65 late=64 D1/W24');
  finally Runtime.Free end;
end.
