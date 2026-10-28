program test_domain;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain;
var
  F:TFileStream;
  S, Base10, Damaged, Surface:RawByteString;
  Rows:TDomainTable;
  K:TDomainKey; Row:TDomainRow;
  W, P, Q, Last, Checks:Integer;
  Rejected:Boolean;
procedure Require(Ok:Boolean; const MessageText:String);
begin if not Ok then begin WriteLn(StdErr,'DOMAIN-FAIL ',MessageText); Halt(1); end; end;
{ Пошук лише по байтах pinned проєкції; без нормалізації UTF-8. }
function LastPos(const Needle,Haystack:RawByteString):Integer;
var I:Integer;
begin
  Result:=0;
  for I:=Length(Haystack)-Length(Needle)+1 downto 1 do
    if Copy(Haystack,I,Length(Needle))=Needle then Exit(I);
end;

procedure RejectTable(const Source:RawByteString; Width:Byte;
  const Explanation:String);
var Failed:Boolean;
begin
  { Фізично спершу завантажуємо повну таблицю, щоб довести очищення
    і старого snapshot, і частково прочитаних нових координат. }
  LoadDomainTable(Base10,10,Rows);
  Require(Length(Rows)=1024,'неповний вихідний D10 свідок');
  Failed:=False;
  try LoadDomainTable(Source,Width,Rows);
  except on E:EDomainError do Failed:=True end;
  Require(Failed,Explanation+' не відхилено');
  Require(Length(Rows)=0,Explanation+' залишило частковий/старий домен');
  Inc(Checks);
end;

begin
  for W:=1 to 3 do begin
  F:=TFileStream.Create('external/sens/lib/domains/d'+IntToStr(W)+'.lisp',fmOpenRead);
  try SetLength(S,F.Size); if F.Size>0 then F.ReadBuffer(S[1],F.Size);
  finally F.Free; end;
  LoadDomainTable(S,W,Rows);
  Require(Length(Rows)=(1 shl W),'domain table is incomplete');
  end;
  LoadDomainTable(S,3,Rows);
  Require(Length(Rows)=8,'D3 must have eight exact coordinates');
  Require(UkrainianKey(Rows,'як-є',K),'missing Ukrainian quote surface');
  Require(SameKey(K,ExactKey('001')),'quote coordinate mismatch');
  Require(DomainRowByKey(Rows,ExactKey('001'),Row),'domain key not found');
  Require(Row.Ukrainian='як-є','reverse lookup wrong surface');
  Require(not DomainRowByKey(Rows,ExactKey('0001'),Row),'wrong-width lookup matched');
  Require(UkrainianKey(Rows,'за-умовою',K),'missing Ukrainian cond surface');
  Require(SameKey(K,ExactKey('110')),'cond coordinate mismatch');
  Require(not UkrainianKey(Rows,'quote',K),'English is not Ukrainian surface');
  Require(not SameKey(ExactKey('01'),ExactKey('001')),'width identity collapsed');
  Require(KeyBits(ExactKey('000'))='000','zero key loses width');
  Rejected:=False;
  try K:=ExactKey('00X'); except on E:EDomainError do Rejected:=True; end;
  Require(Rejected,'nonbinary coordinate accepted');
  Rejected:=False;
  try K:=ExactKey(''); except on E:EDomainError do Rejected:=True; end;
  Require(Rejected,'empty coordinate accepted');
  Rejected:=False;
  try LoadDomainTable('(000 (ук немає))',3,Rows); except on E:EDomainError do Rejected:=True; end;
  Require(Rejected,'incomplete table accepted');
  Require(not SameKey(ExactKey('0'),ExactKey('00')),'D1/D2 key collision');
  Require(not SameKey(ExactKey('00'),ExactKey('000')),'D2/D3 key collision');
  { G2.21: справжня pinned D10, а не 1024 синтетичних opcode.
    Екземпляри Mutant живуть лише в тесті; канонічний файл незмінний. }
  F:=TFileStream.Create('external/sens/lib/domains/d10.lisp',fmOpenRead);
  try
    SetLength(Base10,SizeInt(F.Size));
    Require(Length(Base10)>0,'порожній pinned D10');
    F.ReadBuffer(Base10[1],Length(Base10));
  finally F.Free end;
  Checks:=0;
  LoadDomainTable(Base10,10,Rows);
  Require(Length(Rows)=1024,'D10 має рівно 1024 exact координати');
  Require(SameKey(Rows[0].Key,ExactKey('0000000000')),
    'D10 втратив перші провідні нулі');
  Require(SameKey(Rows[1023].Key,ExactKey('1111111111')),
    'D10 втратив останню координату');
  for W:=0 to 1023 do
    Require(Rows[W].Key.Bits=W,'D10 зіпсовано порядок');
  P:=LastPos('(1111111111 ',Base10);
  Require(P>0,'відсутній останній рядок pinned D10');

  Damaged:=Copy(Base10,1,P-1)+'(1111111110 '+
    Copy(Base10,P+Length('(1111111111 '),MaxInt);
  RejectTable(Damaged,10,'пізній дубльований D10 ключ');

  { Повторна назва «ук» останнього ключа дорівнює реальному першому;
    інші пізні 1023 записи мали пройти до помилки. }
  Q:=Pos('(ук ',Base10);
  Require(Q>0,'немає початкової ук назви');
  Q:=Q+Length('(ук ');
  Last:=Q;
  while (Last<=Length(Base10)) and (Base10[Last]<>')') do Inc(Last);
  Surface:=Copy(Base10,Q,Last-Q);
  Require((Surface<>'') and (Surface<>'('),'невідповідна перша ук назва');
  Q:=LastPos('(ук ',Base10);
  Require(Q>P,'немає останньої ук назви');
  Last:=Q+Length('(ук ');
  while (Last<=Length(Base10)) and (Base10[Last]<>')') do Inc(Last);
  Require(Last<=Length(Base10),'незакрите останнє ук');
  Damaged:=Copy(Base10,1,Q+Length('(ук ')-1)+Surface+
    Copy(Base10,Last,MaxInt);
  RejectTable(Damaged,10,'пізня неоднозначна українська ук назва');

  Damaged:=Copy(Base10,1,P-1)+'(111111111X '+
    Copy(Base10,P+Length('(1111111111 '),MaxInt);
  RejectTable(Damaged,10,'пізнє не-двійкове слово');
  Damaged:=Copy(Base10,1,P-1);
  RejectTable(Damaged,10,'пізня неповна таблиця');
  Damaged:=Base10+#10+'(0000000000 (ук додаткова))'+#10;
  RejectTable(Damaged,10,'перевищено 1024 рядки');
  RejectTable('',10,'порожнє джерело');
  RejectTable(Base10,11,'заборонено ширину D11 у host loader');

  { Для неправильного порядку достатньо обміняти дві перші різні
    канонічні адреси: кожна існує рівно один раз у pinned D10. }
  Damaged:=StringReplace(Base10,'(0000000000 ','(0000000001 ',
    [rfReplaceAll]);
  RejectTable(Damaged,10,'рання дубльована адреса після swap');

  LoadDomainTable(Base10,10,Rows);
  Require((Length(Rows)=1024) and
    SameKey(Rows[1023].Key,ExactKey('1111111111')),
    'відновлення повного pinned D10 після відмов');
  WriteLn('ДОМЕННА-ТАБЛИЦЯ-АТОМАРНА D10=1024 негативних=',Checks,
    ' partial=0 перевірено=pinned-ук exact-width=так');
  WriteLn('DOMAIN-OK D1-D3 exact-width uk=verified');
end.
