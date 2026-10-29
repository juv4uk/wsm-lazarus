{ G2.24: pinned реальні 1024 D10 координати + UTF-8 byte-exact колізії.
  Індекс NameSlots — механічний одноразовий допуск, НЕ реєстр законів SENS.
  Тут навмисно немає {$codepage utf8}: тест конкатенує лише сирі UTF-8
  байти RawByteString і не має перетворювати їх у UnicodeString. }
program test_domain_fast;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain;

var Checks: SizeInt;

procedure Check(Ok:Boolean;const Why:String);
begin
  Inc(Checks);
  if not Ok then begin
    WriteLn(StdErr,'ДОМЕН-ШВИДКИЙ-ПОМИЛКА ',Why);
    Halt(1);
  end;
end;

function LastPos(const Needle, Haystack:RawByteString):SizeInt;
var I:SizeInt;
begin
  Result:=0;
  for I:=Length(Haystack)-Length(Needle)+1 downto 1 do
    if Copy(Haystack,I,Length(Needle))=Needle then Exit(I);
end;

{ G2.40: синтетичні байтові колізії залишаються повністю тестовими,
  проте джерело має той самий структурний формат, що й pinned D1.
  Намір: перевіряти колізію UTF-8, а не обхід зовнішньої таблиці. }
function FixtureD1(const Name0, Name1:RawByteString):RawByteString;
  function Line(const Bits, Name:RawByteString):RawByteString;
  begin
    Result:='  ('+Bits+' (ук '+Name+') (укр ()) (san ()) '+
      '(en ()) (LISP ()) (sym ()))'+#10;
  end;
begin
  Result:='(domain-table-1'+#10+
    Line('0',Name0)+Line('1',Name1)+')';
end;

procedure MustReject(const Source:RawByteString; Width:Byte;
  const LabelText:String;const Healthy:RawByteString);
var R:TDomainTable;Failed:Boolean;
begin
  LoadDomainTable(Healthy,10,R);
  Check(Length(R)=1024,'недоступний попередній справжній D10');
  Failed:=False;
  try LoadDomainTable(Source,Width,R);
  except on E:EDomainError do Failed:=True end;
  Check(Failed,LabelText+' не відхилено');
  Check(Length(R)=0,LabelText+' опублікував часткові чи застарілі рядки');
  LoadDomainTable(Healthy,10,R);
  Check(Length(R)=1024,LabelText+' зламав наступний pinned допуск');
end;

var
  D10, Mutant, S, A, B, C, Name:RawByteString;
  R:TDomainTable;K:TDomainKey;Row:TDomainRow;
  F:TFileStream;
  I,J,P,Q,E:SizeInt;
begin
  Checks:=0;
  F:=TFileStream.Create('external/sens/lib/domains/d10.lisp',fmOpenRead);
  try
    SetLength(D10,F.Size);
    Check(Length(D10)>0,'порожній pinned D10');
    F.ReadBuffer(D10[1],Length(D10));
  finally F.Free end;

  for I:=1 to 32 do begin
    LoadDomainTable(D10,10,R);
    Check(Length(R)=1024,'неповна pinned D10 таблиця');
    for J:=0 to 1023 do begin
      Check(R[J].Key.Width=10,'втрата фізичної ширини');
      Check(R[J].Key.Bits=J,'втрата точного порядку двійкових слів');
    end;
    Check(KeyBits(R[0].Key)='0000000000','втрата провідних нулів D10');
    Check(KeyBits(R[1023].Key)='1111111111','втрата останнього D10 слова');
    Check(DomainRowByKey(R,ExactKey('1111111111'),Row),
      'не вдається відновити D10:1111111111');
    Check(Row.Ukrainian=R[1023].Ukrainian,
      'хеш-індекс помилково змінив pinned проєкцію');
  end;

  { Спеціально створені фізично різні УКРАЇНСЬКІ bytes:
    а=D0B0, д=D0B4, А=D090. При modulus 4 всі мають
    однаковий bucket, але жодна не є байтовим дублем. }
  A:=#$D0#$B0; B:=#$D0#$B4; C:=#$D0#$90;
  S:=FixtureD1(A,B);
  LoadDomainTable(S,1,R);
  Check(Length(R)=2,'зіпсовано маленьку D1 таблицю');
  Check(UkrainianKey(R,A,K) and SameKey(K,ExactKey('0')),
    'колізія а/д злила першу українську назву');
  Check(UkrainianKey(R,B,K) and SameKey(K,ExactKey('1')),
    'колізія а/д злила другу українську назву');

  S:=FixtureD1(A,C);
  LoadDomainTable(S,1,R);
  Check(UkrainianKey(R,A,K) and SameKey(K,ExactKey('0')),
    'Unicode регістр злив різні байти');
  Check(UkrainianKey(R,C,K) and SameKey(K,ExactKey('1')),
    'регістр українських назв утратив ширину чи координату');

  S:=FixtureD1('()','()');
  LoadDomainTable(S,1,R);
  Check((Length(R)=2) and (R[0].Ukrainian='') and
    (R[1].Ukrainian=''),
    'явне () має лишатися порожньою поверхнею, не дублікатом');

  { Відновлення після помилки не допускає часткового D10. }
  P:=LastPos('(1111111111 ',D10);
  Check(P>0,'пізню D10 координату не знайдено');
  Mutant:=Copy(D10,1,P-1)+'(1111111110 '+
    Copy(D10,P+Length('(1111111111 '),MaxInt);
  MustReject(Mutant,10,'повтор точного D10 біта',D10);

  Q:=Pos('(ук ',D10)+Length('(ук ');
  E:=Q;
  while (E<=Length(D10)) and (D10[E]<>')') do Inc(E);
  Name:=Copy(D10,Q,E-Q);
  Check((Name<>'') and (Name<>'('),'немає першої pinned ук назви');
  Q:=LastPos('(ук ',D10);
  Check(Q>P,'немає останньої pinned ук назви');
  E:=Q+Length('(ук ');
  while (E<=Length(D10)) and (D10[E]<>')') do Inc(E);
  Mutant:=Copy(D10,1,Q+Length('(ук ')-1)+Name+
    Copy(D10,E,MaxInt);
  MustReject(Mutant,10,'пізній повтор української назви',D10);

  Mutant:=Copy(D10,1,P-1)+'(111111111X '+
    Copy(D10,P+Length('(1111111111 '),MaxInt);
  MustReject(Mutant,10,'пізнє недвійкове слово',D10);
  MustReject(Copy(D10,1,P-1),10,'неповний D10',D10);
  MustReject(D10+#10+'(0000000000 (ук зайве))'+#10,10,
    'перевищення 1024 координат',D10);
  MustReject(D10,11,'неприпустима ширина host таблиці',D10);
  MustReject('',10,'порожній документ',D10);

  S:=FixtureD1(A,A);
  MustReject(S,1,'повтор короткого українського імені',D10);
  S:='(domain-table-1'+#10+
     '  (1 (ук '+A+') (укр ()) (san ()) (en ()) (LISP ()) (sym ()))'+#10+
     '  (0 (ук '+B+') (укр ()) (san ()) (en ()) (LISP ()) (sym ()))'+#10+
     ')';
  MustReject(S,1,'переставлені фізичні координати D1',D10);

  WriteLn('ДОМЕН-ШВИДКИЙ-ГАРАЗД pinned-D10=1024 повторів=32 ',
    'byte-exact-колізій=3 негативних=9 перевірок=',Checks,
    ' часткових-таблиць=0 законів=нових-немає');
end.
