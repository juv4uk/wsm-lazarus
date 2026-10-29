{ Core1.5 — фізична D7→укр проєкція ВСІХ повних імен із pinned Core1.
  Це host-огляд, не інтерпретатор, викличність чи новий мовний закон.
  TCore1Index повертає exact W7 біти і структурні D4 DEFINE з .sens.
  wsm.d7text читає єдину ратифіковану pinned таблицю; копій немає. }
program senscore1imena;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.d7text, wsm.core1index;

type ECore1NamesError = class(Exception);

procedure Need(Condition:Boolean;const MessageText:String);
begin
  if not Condition then raise ECore1NamesError.Create(MessageText);
end;

{ Bits: позичені exact D7 біти імені (кожні 7 біт утворюють W7),
  Map: pinned D7 укр; Result: власний UTF-8 рядок людської проєкції.
  Керовані TExactWords/RawByteString звільняє FPC після виклику.
  1) Чому це D7-дані, а не callable? 2) Чому не можна читати по байтах?
  3) Чому зворотне кодування важливе? 4) Де джерело значень D7? }
function FullName(const Bits:RawByteString;const Map:TD7Map):RawByteString;
var Words:TExactWords; Packed:RawByteString; I,N:SizeInt;
begin
  Need((Bits<>'') and (Length(Bits) mod 7=0) and
       (Length(Bits)<=7*256),'неприпустима фізична довжина D7-імені');
  N:=Length(Bits) div 7;
  SetLength(Words,N);
  for I:=0 to N-1 do
    Words[I]:=Copy(Bits,I*7+1,7);
  Packed:=EncodeT5M(Words);
  Result:=DecodeD7Text(Packed,Map,dsUkr);
  Need(EncodeD7Text(Result,Map,dsUkr)=Packed,
       'D7 проєкція втратила точні фізичні слова');
  Need((Pos(#10,Result)=0) and (Pos(#13,Result)=0),
       'назва містить заборонене розділення рядка');
end;

{ Index: живе тільки в цій процедурі, зчитує pinned core1.sens;
  Map: pinned d7.lisp; Candidate — приватний bounded UTF-8 звіт.
  Жодного stdout до перевірки ВСІХ імен та їхнього round-trip.
  1) Чому лічильник не є SENS-числом? 2) Навіщо повний буфер?
  3) Чому .lisp не джерело фізичної ідентичності? 4) Де lifetime Index? }
function AllNames(const RepoRoot:String):RawByteString;
const MaxReportBytes=256*1024;
var Index:TCore1Index; Map:TD7Map; Candidate,NameText:RawByteString;
    I:SizeInt; Def:TCore1Definition;
begin
  Result:='';
  LoadPinnedD7Map(RepoRoot,Map);
  Index:=TCore1Index.Create(RepoRoot);
  try
    Need((Index.Count>0) and (Index.Count<=256),
         'неприпустима кількість фізичних визначень');
    Candidate:='';
    for I:=1 to Index.Count do begin
      Def:=Index.Definition(I);
      NameText:=FullName(Def.NameBits,Map);
      Need((Length(NameText)>0) and
           (Length(NameText)+1<=MaxReportBytes-Length(Candidate)),
           'перевищено бюджет звіту Core1');
      Candidate:=Candidate+NameText+#10;
    end;
    Result:=Candidate;
  finally
    Index.Free;
  end;
end;

{ Фізичний машинний потік не зачіпаємо; stdout тут — тільки укр-проєкція.
  Дані передано в один THandleStream після повної валідації.
  1) Чим stdout відрізняється від .sens? 2) Коли звільняється stream?
  3) Чому недопустимий корінь не лишає половину списку? }
procedure WriteReport(const Data:RawByteString);
var Sink:THandleStream;
begin
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(Data)>0 then Sink.WriteBuffer(Data[1],Length(Data));
  finally
    Sink.Free;
  end;
end;

begin
  try
    Need(ParamCount=1,'потрібен лише корінь репозиторію');
    WriteReport(AllNames(ParamStr(1)));
  except
    on E:Exception do begin
      WriteLn(StdErr,'CORE1-ІМЕНА-ВІДМОВА: ',E.Message);
      Halt(2);
    end;
  end;
end.
