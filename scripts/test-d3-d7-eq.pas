{ G3.29: виконане D3:101 над фізичними D1 та цитованими D7.
  Вхід і очікувана фізична відповідь — рівно T5M, без текстового mint.
  Окремий shell порівнює ці ж вхідні байти з незалежним pinned SENS.
  Ні D12+ чисел, ні власного реєстру законів, ні англійського dispatch. }
program test_d3_d7_eq;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.binaryexec, wsm.t5m;
var Executor:TBinaryExecutor; Checks:SizeInt;

procedure Check(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create('ТОЧНИЙ-Д7-ПРОВАЛ: '+Why);
end;

{ Type: raw exact T5M words, result: packed canonical .sens.
  Source array is borrowed until EncodeT5M returns an owned byte string.
  Питання: чи є текстом повернені байти? Хто задає 7-бітну ширину?
  Де відрізняється D1:1 від D7:0000001? }
function Pack(const Parts:array of RawByteString):RawByteString;
var W:TExactWords; I:SizeInt;
begin
  SetLength(W,Length(Parts));
  for I:=0 to High(Parts) do W[I]:=Parts[I];
  Result:=EncodeT5M(W);
end;

procedure Save(const FileName:String; const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(FileName,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free; end;
end;

{ Один незалежний фізичний свідок для pinned SENS binary REPL.
  Два обчислені операнди зберігаються в raw T5M, результат ncDomain
  ніколи не інтерпретується як Unicode-проєкція. Файли тесту живуть у
  тимчасовій директорії workflow; власник — shell після завершення.
  Питання: чому порівнюємо і відповідь T5M? Хто володіє результатом?
  Як доводиться, що oracle отримав саме цей Source? }
procedure Expect(const LabelText:RawByteString;
  const Data:array of RawByteString; const Expected:RawByteString);
var InBytes,Actual,Physical,ExpectedPhysical:RawByteString;
begin
  InBytes:=Pack(Data);
  Actual:=Executor.ExecutePhysical(InBytes);
  Physical:=Executor.ExecutePhysicalT5M(InBytes);
  ExpectedPhysical:=Pack([Expected]);
  Check(Actual=Expected,'текстове відображення D1: '+String(LabelText));
  Check(Physical=ExpectedPhysical,'канонічна фізична D1 відповідь: '+String(LabelText));
  Save('build/m0.2/d3-d7-eq-'+String(LabelText)+'.sens',InBytes);
  Save('build/m0.2/d3-d7-eq-'+String(LabelText)+'.answer.sens',Physical);
  Save('build/m0.2/d3-d7-eq-'+String(LabelText)+'.expected',Expected+#10);
end;

procedure Reject(const Data:array of RawByteString;
  WordAt:SizeInt; const Why:String);
var Input:RawByteString; Rejected:Boolean;
begin
  Input:=Pack(Data);
  Rejected:=False;
  try
    Executor.ExecutePhysicalT5M(Input);
  except on E:EBinaryExecutionError do begin
    Rejected:=True;
    if WordAt>=0 then Check(E.WordIndex=WordAt,
      Why+': хибна фізична 1-based адреса '+IntToStr(E.WordIndex));
  end; end;
  Check(Rejected,Why+': небезпечний фізичний вхід допущено');
end;

var Rejected:Boolean;
begin
  Checks:=0;
  Executor:=TBinaryExecutor.Create('external/sens');
  try
    { Лівий і правий D7:0010110 = pinned SYN як ДАНІ.
      Голова D3:101 — точний двійковий код, не ім'я «тотожне?». }
    Expect('syn-tak',
      ['10','101','10','001','0010110','01',
                  '10','001','0010110','01','01'],'1');
    Expect('syn-ni',
      ['10','101','10','001','0010110','01',
                  '10','001','0000000','01','01'],'0');
    Expect('d7-high-tak',
      ['10','101','10','001','1111111','01',
                  '10','001','1111111','01','01'],'1');
    Expect('d7-high-ni',
      ['10','101','10','001','1111111','01',
                  '10','001','0010110','01','01'],'0');
    { Однакове числове 1 НЕ робить D1:1 тотожним D7:0000001. }
    Expect('d1-d7-ni',
      ['10','101','1',
                  '10','001','0000001','01','01'],'0');
    Expect('d7-d1-ni',
      ['10','101','10','001','0000001','01',
                  '1','01'],'0');
    { Чотири раніше чинні D1/D1 відповіді — незмінні. }
    Expect('d1-tak',
      ['10','101','1','1','01'],'1');
    Expect('d1-ni',
      ['10','101','1','0','01'],'0');

    { Залишаються типові відмови, не host-boolean або текстовий alias. }
    Reject(['10','101','0010110','10','001','0010110','01','01'],
      3,'D7 поза цитатою');
    Reject(['10','101','10','001','0010110','01','0010110','01'],
      7,'нецитований правий D7');
    Reject(['10','101','000','10','001','0010110','01','01'],
      3,'порожній D3:000 не є атомом');
    Reject(['10','101','10','001','10','1','000','01','01',
                    '10','001','0010110','01','01'],
      3,'список не є атомом EQ');
    Reject(['10','0010110','1','01'],2,'D7 не стає викличною головою');
    Reject(['10','101','10','001','000000000','01',
                    '10','001','000000000','01','01'],
      3,'невідкритий D9 поза підтвердженим піднабором');
    Reject(['10','101','10','001','000000000000','01',
                    '10','001','0010110','01','01'],
      -1,'D12+ не стає числом або D7');

    Rejected:=False;
    try Executor.ExecutePhysicalT5M(#243);
    except on E:EBinaryExecutionError do begin
      Rejected:=True;
      Check(E.WordIndex=0,'пошкоджений байт T5M не має позиції слова');
    end; end;
    Check(Rejected,'пошкоджений T5M прийнято');
    { Після кожної відмови той самий evaluator має відновитися. }
    Check(Executor.ExecutePhysical(
      Pack(['10','101','10','001','0010110','01',
                   '10','001','0010110','01','01']))='1',
      'повторне виконання після негативів');
  finally Executor.Free end;
  WriteLn('D3-Д7-ТОТОЖНІСТЬ-ГАРАЗД перевірок=',Checks,
    ' фізичних-свідків=8 точні-D1-D7=так негативи=так');
end.
