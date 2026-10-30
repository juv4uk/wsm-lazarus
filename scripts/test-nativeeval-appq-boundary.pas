{ G3 / #803: механічна границя Appq→Pairlis, не oracle і не
  твердження про завершену підтримку замикань.
  Вхід — host TNativeCell, результат — індекс уже обчисленої клітинки.
  Питання: чи D1:1 дорівнює D3:001? Ні.
  Чому ncClosure не отримує нового ключа? Де живе ValueHandle?
  Чому неправильна форма цитати має завершитися відмовою? }
program test_nativeeval_appq_boundary;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.nativeeval,wsm.domain;
var Pair,Head:TNativeCell; Value:SizeInt; Count:SizeInt;
procedure Need(B:Boolean;const Reason:String);
begin
  Inc(Count);
  if not B then raise Exception.Create(Reason);
end;
procedure Reject(const Reason:String);
begin
  Value:=159;
  Need(not TryAppqActual(Pair,Head,Value),Reason);
  Need(Value=0,'відмова залишила застарілий індекс значення');
end;
begin
  Count:=0;
  Pair:=Default(TNativeCell);
  Head:=Default(TNativeCell);
  Pair.Kind:=ncPair; Pair.First:=9; Pair.Rest:=18;
  Head.Kind:=ncDomain; Head.Key:=ExactKey('001');
  Value:=0;
  Need(TryAppqActual(Pair,Head,Value),'точний D3:001 не прийнято');
  Need(Value=18,'Pairlis отримав wrapper замість уже обчисленого значення');
  Pair.Rest:=0; { D3:000 — порожній native handle, НЕ D1:0. }
  Need(TryAppqActual(Pair,Head,Value),'порожнє значення помилково відхилено');
  Need(Value=0,'порожня структура не збереглася як handle 0');
  Pair.Rest:=18;

  Head.Key:=ExactKey('1'); { однаковий числовий payload, інша ширина. }
  Reject('D1:1 підміняє D3:001');
  Head.Key:=ExactKey('000');
  Reject('D3:000 підміняє D3:001');
  Head.Key:=ExactKey('010');
  Reject('D3:010 підміняє D3:001');
  Head.Key:=ExactKey('001');
  Head.Kind:=ncName;
  Reject('ncName підміняє точний домен');
  Head.Kind:=ncClosure;
  Reject('ncClosure підміняє точний домен');
  Head.Kind:=ncDomain;
  Pair.Kind:=ncDomain;
  Reject('не-список підміняє цитату');
  Pair.Kind:=ncPair;
  Pair.Rest:=-1;
  Reject('недопустимий від’ємний handle');
  Pair.Rest:=18;
  Need(TryAppqActual(Pair,Head,Value),'свіжий коректний аргумент не прийнято');
  Need(Value=18,'неправильний handle після відмов');
  WriteLn('NATIVEEVAL-APPQ-BOUNDARY-PASS checks=',Count,
    ' exact=D3:001 empty=D3:000 negatives=7',
    ' Core1=NOT_VERIFIED oracle=NOT_RUN');
end.
