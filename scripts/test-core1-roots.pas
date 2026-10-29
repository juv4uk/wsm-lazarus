{ Core1.2 — перевірка реального wsm.gc + лексичного wsm.envframe.
  Усі Int64 payload — непрозорі host-свідки, не числа/істина SENS. }
program test_core1_roots;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.domain, wsm.envframe, wsm.gc, wsm.core1roots;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('CORE1-КОРЕНІ-ПРОВАЛ: '+Why);
end;

{ stdout — host-байти UTF-8, без Ansi codepage-конверсії FPC.
  Повідомлення — лише доказ тесту, не програмна проєкція .lisp. }
procedure ReportUTF8(const MessageText:UnicodeString);
var Bytes:RawByteString; Sink:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(MessageText))+#10;
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Bytes[1],Length(Bytes))
  finally Sink.Free end;
end;

var
  H,Other:TGCHeap;
  C:TCore1RootedClosure;
  Entry,Value,Orphan,Foreign,CallValue,Nested1,Nested2,OldValue,Reused:TGCHandle;
  Token,Outer,Inner:TGCFrameToken;
  Key,OtherKey:TDomainKey;
  I,Freed:SizeInt;
  Failed:Boolean;
begin
  H:=TGCHeap.Create;
  Other:=TGCHeap.Create;
  C:=nil;
  try
    Key:=ExactKey('0101100');
    OtherKey:=ExactKey('0101101');
    Entry:=H.Allocate(101);
    Value:=H.Allocate(202);
    Orphan:=H.Allocate(303);
    Foreign:=Other.Allocate(404);
    C:=TCore1RootedClosure.Create(H,Entry);
    C.CaptureExact(Key,Value);
    { Цикл reachability: вищий рівень замикання -> value -> closure.
      Єдиний mark/sweep у wsm.gc зобов'язаний обійти цикл. }
    H.Link(Value,C.ClosureHandle);
    Check(H.Collect=1,'не зібрано незалежний сирітський об’єкт');
    Check(not H.IsAlive(Orphan),'сирота лишилася живою');
    Check(H.IsAlive(Entry) and H.IsAlive(Value),'rooted entry/value зникли');
    Check(SameHandle(C.ResolveExact(Key),Value),'лексичний exact ключ не збігся');
    Check(H.ValueOf(C.ResolveExact(Key))=202,'захоплений payload не зберігся');
    Check(H.LiveCount=3,'неочікувана кількість reachable клітинок');

    Failed:=False;
    try C.CaptureExact(Key,Entry);
    except on E:ECore1RootsError do Failed:=True end;
    Check(Failed,'дубль exact лексичного ключа допущено');
    Failed:=False;
    try C.CaptureExact(OtherKey,Foreign);
    except on E:ECore1RootsError do Failed:=True end;
    Check(Failed,'чужий heap handle допущено до capture');
    Failed:=False;
    try C.ResolveExact(OtherKey);
    except on E:EFrameError do Failed:=True end;
    Check(Failed,'неіснуючий exact лексичний ключ знайдено');

    { Реальна LIFO область коренів wsm.gc для вкладених викликів. }
    Nested1:=H.Allocate(501);
    Outer:=C.BeginCall(Nested1);
    Nested2:=H.Allocate(502);
    Inner:=C.BeginCall(Nested2);
    Check(H.Collect=0,'живі вкладені аргументи зібрані');
    Failed:=False;
    try C.EndCall(Outer);
    except on E:EGCError do Failed:=True end;
    Check(Failed,'заборонене порушення порядку областей LIFO');
    C.EndCall(Inner);
    C.EndCall(Outer);
    Check(H.Collect=2,'не зібрано два відпущені виклики');
    Check(not H.IsAlive(Nested1) and not H.IsAlive(Nested2),
      'застарілі викличні хендли не відхилено');

    { 256 реальних bounded scope/Collect, без прихованого retention. }
    for I:=1 to 256 do begin
      CallValue:=H.Allocate(I);
      Token:=C.BeginCall(CallValue);
      try
        Check(H.Collect=0,'аргумент активного виклику зібрано');
        Check(H.IsAlive(CallValue),'активний аргумент став stale');
        Check(H.IsAlive(C.ResolveExact(Key)),
          'захоплене значення зникло під час виклику');
      finally
        C.EndCall(Token);
      end;
      Check(H.Collect=1,'тимчасове значення не звільнено після виклику');
      Check(not H.IsAlive(CallValue),'тимчасовий хендл не став stale');
    end;

    CallValue:=H.Allocate(600);
    Token:=C.BeginCall(CallValue);
    try
      Failed:=False;
      try
        raise Exception.Create('змодельована відмова виконавця Core1');
      except on E:Exception do Failed:=True end;
      Check(Failed,'помилка не була зафіксована');
      Failed:=False;
      try C.Release; except on E:ECore1RootsError do Failed:=True end;
      Check(Failed,'замикання звільнено всередині активного виклику');
    finally
      C.EndCall(Token);
    end;
    Check(H.Collect=1,'після помилки аргумент не звільнений');
    OldValue:=Value;
    C.Release;
    Freed:=H.Collect;
    Check(Freed=3,'не зібрано цикл замикання + entry + captured');
    Check(H.LiveCount=0,'GC-купа не повернулася в нуль');
    Failed:=False;
    try C.ResolveExact(Key);
    except on E:ECore1RootsError do Failed:=True end;
    Check(Failed,'звільнене замикання ще розв’язує ключ');

    Reused:=H.Allocate(707);
    Check(not SameHandle(OldValue,Reused),
      'slot може повторюватись, але GC покоління відрізняється');
    Failed:=False;
    try H.ValueOf(OldValue);
    except on E:EGCError do Failed:=True end;
    Check(Failed,'застарілий захоплений хендл повторно ожив');
    Check(H.Collect=1,'повторно використана вільна комірка не зібрана');
    Check(H.LiveCount=0,'фінальна купа не порожня');

    ReportUTF8(UnicodeString('CORE1-GC-КОРЕНІ-ГАРАЗД цикли=так звільнено=')+
      UnicodeString(IntToStr(Freed))+
      UnicodeString(' вкладені=LIFO виклики=256 unwind=так stale=відхилено')+
      UnicodeString(' чужий-heap=відхилено середовище=exact-D7 семантика=ні'));
  finally
    C.Free;
    Other.Free;
    H.Free;
  end;
end.
