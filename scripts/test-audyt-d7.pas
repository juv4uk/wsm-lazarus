{ G2.30: не змінюємо pinned SENS, лише тимчасово підмінюємо
  FPC-managed каталог після успішного завантаження, потім відновлюємо. }
program test_audyt_d7;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.proektsii, wsm.d7audit;

var
  Catalog:TProektsiiCatalog;
  Good,Again,RejectedReport:TD7AuditReport;
  OriginalText:RawByteString;
  OriginalBits:QWord;
  RejectCount:SizeInt;

procedure Check(Condition:Boolean;const Why:String);
begin
  if not Condition then raise Exception.Create('Д7-АУДИТ-ТЕСТ-ПОМИЛКА: '+Why);
end;

procedure MustReject(const Name:String);
var Failed:Boolean;C:SizeInt;
begin
  FillChar(RejectedReport,SizeOf(RejectedReport),$5A);
  Failed:=False;
  try
    AuditPinnedD7(Catalog,RejectedReport);
  except
    on E:ED7AuditError do Failed:=True;
  end;
  Check(Failed,'не відхилено: '+Name);
  Check((RejectedReport.Coordinates=0) and
    (RejectedReport.Printable=0) and (RejectedReport.Controls=0),
    'оприлюднено неповний звіт: '+Name);
  for C:=0 to 5 do
    Check((RejectedReport.Present[C]=0) and
      (RejectedReport.CrossDomainNames[C]=0),
      'збережено часткову статистику: '+Name);
  Inc(RejectCount);
end;

begin
  if ParamCount<>1 then begin
    WriteLn(ErrOutput,'Потрібен каталог pinned SENS');Halt(64);
  end;
  LoadPinnedProjections(ParamStr(1),Catalog);
  AuditPinnedD7(Catalog,Good);
  Check((Good.Coordinates=128) and (Good.Printable=95) and
    (Good.Controls=33),'канон D7: 128/95/33');
  Check((Good.Present[4]=0) and (Good.CrossDomainNames[4]=0),
    'LISP не є проєкцією D7');
  Check((Good.Present[0]=95) and (Good.Present[1]=95) and
    (Good.Present[2]=95) and (Good.Present[3]=95) and
    (Good.Present[5]=95),'п’ять D7 текстових площин');
  AuditPinnedD7(Catalog,Again);
  Check(CompareMem(@Good,@Again,SizeOf(Good)),
    'недетермінований результат на тих самих двійкових ключах');

  OriginalText:=Catalog[7][33].Surface[0];
  Catalog[7][33].Surface[0]:=Catalog[7][32].Surface[0];
  try MustReject('дубль двох W7 у проєкції ук');
  finally Catalog[7][33].Surface[0]:=OriginalText end;

  OriginalText:=Catalog[7][22].Surface[1];
  Catalog[7][22].Surface[1]:='вигадано';
  try MustReject('D7 SYN не може бути друкованим');
  finally Catalog[7][22].Surface[1]:=OriginalText end;

  OriginalText:=Catalog[7][34].Surface[4];
  Catalog[7][34].Surface[4]:='QUOTE';
  try MustReject('D7 LISP не стає викличною формою');
  finally Catalog[7][34].Surface[4]:=OriginalText end;

  OriginalText:=Catalog[7][35].Surface[2];
  Catalog[7][35].Surface[2]:='';
  try MustReject('відсутня san-проєкція друкованого W7');
  finally Catalog[7][35].Surface[2]:=OriginalText end;

  OriginalBits:=Catalog[7][32].Key.Bits;
  Catalog[7][32].Key.Bits:=33;
  try MustReject('підміна двійкового слова координати');
  finally Catalog[7][32].Key.Bits:=OriginalBits end;

  OriginalBits:=Catalog[10][0].Key.Bits;
  Catalog[10][0].Key.Bits:=1;
  try MustReject('підміна координати іншого домену');
  finally Catalog[10][0].Key.Bits:=OriginalBits end;

  AuditPinnedD7(Catalog,Again);
  Check(CompareMem(@Good,@Again,SizeOf(Good)),
    'каталог не відновився після всіх негативів');
  Check(RejectCount=6,'неповний набір негативних перевірок');
  WriteLn('Д7-АУДИТ-МЕХАНІКА-ГАРАЗД 128/95/33 шість-проєкцій=так',
    ' негативних=',RejectCount,' підміна-ключа=відхилено',
    ' пізній-звіт=порожній');
end.
