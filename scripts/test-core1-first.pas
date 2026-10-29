{ Core1.2: живе замикання з ПЕРШОГО pinned core1.sens.
  Жодного локального закону «друге» або назви-до-opcode dispatch. }
program TestCore1First;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core1first, wsm.t5m;

var Runtime:TCore1FirstRuntime; Name:RawByteString;
    Passed:SizeInt;

procedure Check(Condition:Boolean;const Why:String);
begin
  Inc(Passed);
  if not Condition then raise Exception.Create(Why);
end;

{ Розміщення: словесні координати D7 копіюються з фізичного DEFINE.
  Це host-тестовий побудовник, не український reader і не interpreter. }
function MakeCall(const NameBits:RawByteString;
  const Elements:TExactWords):RawByteString;
var Words:TExactWords; I,P,Count:SizeInt;
begin
  Count:=Length(NameBits) div 7;
  if (Count=0) or (Count*7<>Length(NameBits)) then
    raise Exception.Create('недопустима довжина D7');
  SetLength(Words,Count+Length(Elements)*2+9);
  P:=0;
  Words[P]:='10';Inc(P); { виклик }
  Words[P]:='10';Inc(P); { D7 ім'я }
  for I:=0 to Count-1 do begin
    Words[P]:=Copy(NameBits,I*7+1,7);Inc(P);
  end;
  Words[P]:='01';Inc(P);
  Words[P]:='10';Inc(P); { D4:1110 список }
  Words[P]:='1110';Inc(P);
  for I:=0 to High(Elements) do begin
    Words[P]:=Elements[I];Inc(P);
  end;
  Words[P]:='01';Inc(P); { аргумент }
  Words[P]:='01';Inc(P); { виклик }
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
    'фізичне замикання повернуло неправильне точне слово');
  Check(Runtime.ExecutePhysicalCall(Physical)=EncodeT5M(Got),
    'два послідовні виклики змінили фізичні байти');
end;

{ FPC Text stdout codepage залежить від хоста. Запис UTF-8 байтів
  без text transcoding, а CI підтверджує кириличний результат. }
procedure ShowSuccess;
var S:RawByteString; Stream:THandleStream;
begin
  S:=RawByteString(UTF8Encode(UnicodeString(
    'CORE1-ПЕРШЕ-ЗАМИКАННЯ-ГАРАЗД перевірок=')))+
    RawByteString(IntToStr(Passed))+
    RawByteString(UTF8Encode(UnicodeString(
      ' фізичний=так D4:1001=через-існуючий-evaluator GC=не-інтегровано')))+#10;
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
  Runtime:=TCore1FirstRuntime.Create(ParamStr(1),ParamStr(2));
  try
    Name:=Runtime.FirstIdentifier;
    Check((Length(Name)>=7) and ((Length(Name) mod 7)=0),
      'немає збереженого exact D7 замикання');
    Elements:=nil;
    SetLength(Elements,3);
    Elements[0]:='1';Elements[1]:='0';Elements[2]:='1';
    AnswerIs(Elements,'0');
    Elements[0]:='0';Elements[1]:='1';Elements[2]:='0';
    AnswerIs(Elements,'1');
    Elements[0]:='1';Elements[1]:='000000000000000000000001';
    Elements[2]:='0';AnswerIs(Elements,Elements[1]); { opaque W24 }
    Fake:=Name;
    if Fake[1]='0' then Fake[1]:='1' else Fake[1]:='0';
    Reject(MakeCall(Fake,Elements),'незнайоме exact D7 ім’я');
    SetLength(Elements,1);Elements[0]:='1';
    Reject(MakeCall(Name,Elements),'список із одним елементом');
    Reject(AnsiChar(243),'зіпсований T5M');
    Reject('','порожній T5M');
    Reject(MakeCall(Name,Elements)+#0,'пошкоджений кінець T5M');
    SetLength(Elements,3);
    Elements[0]:='0';Elements[1]:='1';Elements[2]:='0';
    AnswerIs(Elements,'1');
    ShowSuccess;
  finally Runtime.Free end;
end.
