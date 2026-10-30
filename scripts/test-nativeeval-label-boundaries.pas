{ #867: фізичні межі LABEL. Жодної реалізації рекурсії в тесті.
  Оракул мовних законів: тільки pinned external/sens, не цей Pascal код.
  TBinaryExecutor повторно використовує T5M/D2/binder/nativeeval.
  Вхід: паковані T5M байти одного виразу; результат: або точний D1,
  або EBinaryExecutionError з індексом фізичного слова.
  Частково реалізований D5 LABEL не оголошується відсутнім або готовим. }
program test_nativeeval_label_boundaries;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.t5m, wsm.binaryexec;

var
  Engine: TBinaryExecutor;
  Checks: SizeInt;

procedure Demand(Condition:Boolean; const Description:String);
begin
  Inc(Checks);
  if not Condition then begin
    WriteLn(StdErr,'МІТКА-ФІЗИЧНИЙ-ПРОВАЛ: ',Description);
    Halt(1);
  end;
end;

function PackT5M(const Coordinates:array of RawByteString):RawByteString;
var
  Words:TExactWords;
  I:SizeInt;
begin
  SetLength(Words,Length(Coordinates));
  for I:=0 to High(Coordinates) do Words[I]:=Coordinates[I];
  Result:=EncodeT5M(Words);
end;

procedure ExpectReject(const Description:String;
  const Coordinates:array of RawByteString; AtWord:SizeInt;
  const Fragment:String);
var
  Rejected:Boolean;
  Actual:RawByteString;
begin
  Rejected:=False;
  try
    Actual:=Engine.ExecutePhysical(PackT5M(Coordinates));
  except
    on E:EBinaryExecutionError do begin
      Rejected:=True;
      Demand(E.WordIndex=AtWord,
        Description+': помилка на слові '+IntToStr(E.WordIndex)+
        ', очікувалося '+IntToStr(AtWord));
      Demand(Pos(Fragment,E.Message)>0,
        Description+': не та причина відмови: '+E.Message);
    end;
  end;
  Demand(Rejected,Description+': неприпустимий виклик виконано');
end;

procedure ExpectValue(const Description:String;
  const Coordinates:array of RawByteString; const Expected:RawByteString);
var
  Actual:RawByteString;
begin
  Actual:=Engine.ExecutePhysical(PackT5M(Coordinates));
  Demand(Actual=Expected,
    Description+': очікувано '+Expected+', отримано '+Actual);
end;

procedure ExpectBrokenT5M;
var
  Rejected:Boolean;
  Actual, Corrupt:RawByteString;
begin
  Corrupt:=#$F3; { недопустима фізична п'яткова байтова оболонка T5M }
  Rejected:=False;
  try
    Actual:=Engine.ExecutePhysical(Corrupt);
  except
    on E:EBinaryExecutionError do begin
      Rejected:=True;
      Demand(E.WordIndex=0,
        'зіпсований T5M не має вигаданої координати слова');
    end;
  end;
  Demand(Rejected,'зіпсований T5M допущено');
end;

var
  One, Answer:RawByteString;
begin
  Checks:=0;

  { Тут лише перевірка exact-width механізму. Ратифікованість LABEL
    окремо звіряє shell-gate безпосередньо з pinned таблицею D5. }
  Demand(KeyBits(ExactKey('00100'))='00100',
    'втрачено провідні нулі D5');
  Demand(not SameKey(ExactKey('00100'),ExactKey('0100')),
    'D4 не може підмінити D5 навіть із тими самими числовими бітами');
  Demand(not SameKey(ExactKey('00100'),ExactKey('000100')),
    'D6 не може підмінити D5');

  Engine:=TBinaryExecutor.Create('external/sens');
  try
    { Дозвіл на точну адресу НЕ робить неповну форму мітки допустимою.
      (D2-відкриття D5:00100 D1:1 D2-закриття). }
    ExpectReject('точна D5 мітка без тіла повинна відхилятися',
      ['10','00100','1','01'],1,'D5:00100');

    { Повна за довжиною мітка теж не допускає тіло, що не є замиканням.
      Д3/D5 закон не перевизначаємо: чинний native evaluator виконує
      контроль типу, а це механічний негатив фізичної форми.
      1) Чому імʼя D1:0 тут не означає логічну хибність?
      2) Чому адресу помилки має саме 4-те фізичне слово?
      3) Який механізм гарантує відсутність глобального побічного запису?
      4) Чому це не доводить виконання правильного рекурсивного LABEL? }
    ExpectReject('D5 мітка з тілом-не-замиканням',
      ['10','00100','0','1','01'],4,'тіло мусить дати замикання');

    { Інша п'ятибітова адреса, навіть близька, НЕ є міткою. }
    ExpectReject('чужі біти у D5',
      ['10','00101','1','01'],2,'unsupported D5 callable');

    { Те саме числове значення під іншими ширинами не стає D5. }
    ExpectReject('D4 інша ширина',
      ['10','0100','1','01'],2,'unsupported native callable domain');
    ExpectReject('D6 інша ширина',
      ['10','000100','1','01'],2,'unsupported native callable domain');
    { Ця ширина відхиляється фізичним D2 раніше за callable-dispatch.
      1) Чому це reader-guard, а не новий закон D10?
      2) Хто встановлює допустимі ширини?
      3) Чому native evaluator тут не викликається? }
    ExpectReject('D10 інша ширина на рівні D2',
      ['10','0000000100','1','01'],2,'unsupported exact source width');

    { Необмежена довільна голова так само не стає LABEL. }
    ExpectReject('D1 не може бути викличною головою',
      ['10','1','1','01'],2,'unsupported native callable domain');

    { Той самий виконавець після відмов мусить працювати.
      D3:010 (атом?) над D1:1 => точний D1:1. }
    ExpectValue('відновлення після семи відмов',
      ['10','010','1','01'],'1');
    ExpectBrokenT5M;
    ExpectValue('відновлення після зіпсованого T5M',
      ['10','010','1','01'],'1');

    One:=PackT5M(['1']);
    Answer:=Engine.ExecutePhysicalT5M(One);
    Demand(Answer=One,'фізична D1 відповідь не побайтова');
    WriteLn('МІТКА-ФІЗИЧНИЙ-ГАРАЗД checks=',Checks,
      ' адреса=D5:00100 неповна_форма=відхилена',
      ' тіло_не_замикання=відхилено рекурсія=НЕ_ПЕРЕВІРЕНА',
      ' T5M=так D2=так binder=pinned',
      ' wrong-width=fail-closed wrong-bits=fail-closed',
      ' no-stale=так oracle=NOT_VERIFIED');
  finally
    Engine.Free;
  end;
end.
