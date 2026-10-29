{ G3.45: саме pinned Core1.first + чинний TGCClosureBridge + wsm.gc.
  Ні CLI-echo, ні нових D4 законів або D1-числових перетворень. }
program test_core1_gcresult;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.core1gcresult, wsm.t5m, wsm.core1first;

var
  Runtime:TCore1GCResult;
  Native:TCore1FirstRuntime;
  Name:RawByteString;
  Tests,I:SizeInt;
  Before:RawByteString;

procedure Check(Condition:Boolean;const Why:String);
begin
  Inc(Tests);
  if not Condition then raise Exception.Create(Why);
end;

function MakeCall(const Identifier:RawByteString;
  const Values:array of RawByteString):RawByteString;
var Words:TExactWords;I,K,P:SizeInt;
begin
  K:=Length(Identifier) div 7;
  if (K=0) or (7*K<>Length(Identifier)) then
    raise Exception.Create('фізичний D7 ключ не кратний ширині');
  SetLength(Words,2+K+1+2+Length(Values)+2);
  P:=0;
  Words[P]:='10';Inc(P);Words[P]:='10';Inc(P);
  for I:=0 to K-1 do begin
    Words[P]:=Copy(Identifier,I*7+1,7);Inc(P);
  end;
  Words[P]:='01';Inc(P);
  Words[P]:='10';Inc(P);Words[P]:='1110';Inc(P);
  for I:=0 to High(Values) do begin Words[P]:=Values[I];Inc(P) end;
  Words[P]:='01';Inc(P);Words[P]:='01';Inc(P);
  SetLength(Words,P);
  Result:=EncodeT5M(Words);
end;

function Atom(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=Bits;
  Result:=EncodeT5M(W);
end;

procedure CheckSuccess(const Call,Expected:RawByteString);
var Response:RawByteString;
begin
  Response:=Runtime.ExecutePhysical(Call);
  Check(Response=Atom(Expected),'помилка фізичного виходу Core1');
  Check(Runtime.CurrentPhysical=Response,'GC загубив живу відповідь');
  Check(Runtime.RootCount=1,'захоплений root не єдиний');
  Check(Runtime.LiveCount=2,'після sweep не два об’єкти (кадр+атом)');
  Check(Runtime.Collect=0,'GC звільнив захоплений фізичний атом');
end;

procedure RejectPreserves(const Call:RawByteString;const Why:String);
var Failed:Boolean;Count:SizeInt;
begin
  Before:=Runtime.CurrentPhysical;
  Count:=Runtime.LiveCount;
  Failed:=False;
  try Runtime.ExecutePhysical(Call);
  except on E:Exception do Failed:=True end;
  Check(Failed,Why+': виклик не відхилено');
  Check(Runtime.CurrentPhysical=Before,Why+': втрачено попередню відповідь');
  Check(Runtime.LiveCount=Count,Why+': змінився reachability GC');
  Check(Runtime.Collect=0,Why+': GC звільнив живу відповідь');
end;

procedure Show;
var Line:RawByteString; Stream:THandleStream;
begin
  Line:=RawByteString(UTF8Encode(UnicodeString(
    'CORE1-GC-РЕЗУЛЬТАТ-ГАРАЗД перевірок=')))+
    RawByteString(IntToStr(Tests))+
    RawByteString(UTF8Encode(UnicodeString(
    ' викликів=256 GC=wsm.gc корінь=захоплений stale=не-доступний')))+#10;
  Stream:=THandleStream.Create(TextRec(Output).Handle);
  try Stream.WriteBuffer(Line[1],Length(Line));
  finally Stream.Free end;
end;

var Fake:RawByteString;
begin
  Tests:=0;
  if ParamCount<>2 then Halt(64);
  Runtime:=nil;Native:=nil;
  try
    Native:=TCore1FirstRuntime.Create(ParamStr(1),ParamStr(2));
    Name:=Native.FirstIdentifier;
    Runtime:=TCore1GCResult.Create(ParamStr(1),ParamStr(2));
    Check(Runtime.LiveCount=0,'GC не стартує порожнім');
    Check(Runtime.RootCount=0,'зайвий початковий корінь');
    CheckSuccess(MakeCall(Name,['1','0','1']),'0');
    CheckSuccess(MakeCall(Name,['0','1','0']),'1');
    CheckSuccess(MakeCall(Name,['1',
      '000000000000000000000001','0']),'000000000000000000000001');
    Fake:=Name;
    if Fake[1]='0' then Fake[1]:='1' else Fake[1]:='0';
    RejectPreserves(MakeCall(Fake,['1','0','1']),
      'невідома D7 ідентичність');
    RejectPreserves(MakeCall(Name,['1']),'один аргумент у списку');
    RejectPreserves(AnsiChar(243),'пошкоджений T5M');
    RejectPreserves('','порожній T5M');
    RejectPreserves(MakeCall(Name,['1','0','1'])+#0,
      'зіпсований T5M суфікс');
    for I:=1 to 256 do begin
      if Odd(I) then
        CheckSuccess(MakeCall(Name,['1','0','1']),'0')
      else
        CheckSuccess(MakeCall(Name,['0','1','0']),'1');
    end;
    Check(Runtime.HeapSlots<=4,'GC не перевикористовує комірки');
    Check(Runtime.MetadataTokens=259,
      'неочікувана кількість host ticket після 259 викликів');
    Runtime.ReleaseCurrent;
    Check(Runtime.LiveCount=0,'останній результат не звільнено');
    Check(Runtime.RootCount=0,'GC залишив корінь після Release');
    Check(Runtime.Collect=0,'повторний sweep неідемпотентний');
    Check(Runtime.HeapSlots<=4,'heap виріс після повного збирання');
    try Runtime.CurrentPhysical; raise Exception.Create('stale результат доступний');
    except on E:ECore1GCResultError do Inc(Tests) end;
    CheckSuccess(MakeCall(Name,['0','1','0']),'1');
    Runtime.ReleaseCurrent;
    Check(Runtime.LiveCount=0,'GC після відновлення не порожній');
    Show;
  finally Runtime.Free;Native.Free end;
end.
