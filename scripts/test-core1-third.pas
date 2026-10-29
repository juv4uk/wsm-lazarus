{ Core1.3: живе замикання з ДРУГОГО pinned core1.sens (третій елемент).
  Жодного локального закону «третє» або назви-до-opcode dispatch. }
program TestCore1Third;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core1third, wsm.t5m;

var Runtime:TCore1ThirdRuntime; Name:RawByteString;
    Passed:SizeInt;

procedure Check(Condition:Boolean;const Why:String);
begin
  Inc(Passed);
  if not Condition then raise Exception.Create(Why);
end;

function MakeCall(const NameBits:RawByteString;
  const Elements:TExactWords):RawByteString;
var Words:TExactWords; I,P,Count:SizeInt;
begin
  Count:=Length(NameBits) div 7;
  if (Count=0) or (Count*7<>Length(NameBits)) then
    raise Exception.Create('недопустима довжина D7');
  SetLength(Words,Count+Length(Elements)*2+9);
  P:=0;
  Words[P]:='10';Inc(P);
  Words[P]:='10';Inc(P);
  for I:=0 to Count-1 do begin
    Words[P]:=Copy(NameBits,I*7+1,7);Inc(P);
  end;
  Words[P]:='01';Inc(P);
  Words[P]:='10';Inc(P);
  Words[P]:='1110';Inc(P);
  for I:=0 to High(Elements) do begin
    Words[P]:=Elements[I];Inc(P);
  end;
  Words[P]:='01';Inc(P);
  Words[P]:='01';Inc(P);
  SetLength(Words,P);
  Result:=EncodeT5M(Words);
end;

procedure AnswerIs(const Elements:TExactWords;const Expected:RawByteString);
var Got:TExactWords; Physical:RawByteString;
begin
  Physical:=MakeCall(Name,Elements);
  Got:=nil;
  DecodeT5M(Runtime.ExecutePhysicalCall(Physical),Got);
  Check((Length(Got)=1) and (Got[0]=Expected),
    'фізичне друге замикання повернуло неправильне точне слово');
  Check(Runtime.ExecutePhysicalCall(Physical)=EncodeT5M(Got),
    'два послідовні виклики змінили фізичні байти');
end;

procedure ShowSuccess;
var S:RawByteString; Stream:THandleStream;
begin
  S:=RawByteString(UTF8Encode(UnicodeString(
    'CORE1-ТРЕТЄ-ЗАМИКАННЯ-ГАРАЗД перевірок=')))+
    RawByteString(IntToStr(Passed))+
    RawByteString(UTF8Encode(UnicodeString(
      ' фізичний=так Roots[1]=через-існуючий-evaluator GC=не-інтегровано')))+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(S[1],Length(S));
  finally Stream.Free end;
end;

procedure Reject(const Physical:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try Runtime.ExecutePhysicalCall(Physical);
  except on E:Exception do Rejected:=True end;
  Check(Rejected,Why);
end;

var Elements:TExactWords; Fake:RawByteString;
begin
  Passed:=0;
  if ParamCount<>2 then Halt(64);
  Runtime:=TCore1ThirdRuntime.Create(ParamStr(1),ParamStr(2));
  try
    Name:=Runtime.SecondIdentifier;
    Check((Length(Name)>=7) and ((Length(Name) mod 7)=0),
      'немає збереженого exact D7 другого замикання');
    Elements:=nil;
    SetLength(Elements,3);
    Elements[0]:='1';Elements[1]:='0';Elements[2]:='1';
    AnswerIs(Elements,'1'); { третій елемент }
    Elements[0]:='0';Elements[1]:='1';Elements[2]:='0';
    AnswerIs(Elements,'0');
    Elements[0]:='1';Elements[1]:='0';
    Elements[2]:='000000000000000000000001';
    AnswerIs(Elements,Elements[2]); { opaque W24 як третій }
    Elements[2]:='000'; { D3 структурна порожнеча НЕ D1:0 }
    AnswerIs(Elements,'000');
    Elements[2]:='1010101'; { opaque D7 — дані, не виклик }
    AnswerIs(Elements,'1010101');
    SetLength(Elements,4);
    Elements[0]:='0';Elements[1]:='1';Elements[2]:='0';Elements[3]:='1';
    AnswerIs(Elements,'0'); { четвертий не повинен замінити третій }
    Fake:=Name;
    if Fake[1]='0' then Fake[1]:='1' else Fake[1]:='0';
    Reject(MakeCall(Fake,Elements),'незнайоме exact D7 ім’я');
    SetLength(Elements,2);Elements[0]:='1';Elements[1]:='0';
    Reject(MakeCall(Name,Elements),'список із двома елементами для третього');
    Reject(AnsiChar(243),'зіпсований T5M');
    Reject(MakeCall(Name,Elements)+AnsiChar(243),
      'пізній недопустимий T5M після правильного виклику');
    Reject('','порожній T5M');
    SetLength(Elements,3);
    Elements[0]:='0';Elements[1]:='1';Elements[2]:='0';
    AnswerIs(Elements,'0');
    ShowSuccess;
  finally Runtime.Free end;
end.
