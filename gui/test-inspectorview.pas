{ Механічні тести фізичного подання, не семантичний oracle. }
program test_inspectorview;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.physloc, wsm.domain, wsm.bind,
  wsm.inspectorview;

var T: TDomainSet; W: TExactWords; R: TVisualWords;
    B: RawByteString; Fail: Boolean; I: Integer;
procedure Check(X: Boolean; const Why: String);
begin
  if not X then begin WriteLn(StdErr, 'ІНСПЕКТОР-ПОМИЛКА: ', Why); Halt(1); end;
end;
begin
  LoadPinnedDomains('external/sens', T);
  SetLength(W,6);
  W[0]:='10'; W[1]:='111'; W[2]:='00'; W[3]:='1';
  W[4]:='000'; W[5]:='01';
  B:=EncodeT5M(W);
  BuildVisualWords(B,T,R);
  Check(Length(R)=6,'кількість фізичних слів');
  for I:=0 to 5 do begin
    Check(R[I].Index=I+1,'порядковий номер');
    Check(R[I].Bits=W[I],'фізичні біти без нормалізації');
    Check(R[I].Key.Width=Length(W[I]),'точна ширина домену');
    Check(KeyBits(R[I].Key)=W[I],'точна ідентичність з початковими нулями');
    Check(R[I].Position.WordIndex=I+1,'позиційний індекс');
    Check(R[I].Position.ByteEnd<=Length(B),'фізична межа байтів');
  end;
  Check((R[0].Key.Width=2) and (R[0].Bits='10'),'D2 структурний');
  Check((R[1].Key.Width=3) and (R[1].Bits='111') and
    (R[1].Ukrainian='сполучити'),'ук лише із pinned D3');
  Check((R[3].Key.Width=1) and (R[3].Bits='1') and
    (R[3].Ukrainian='так'),'D1:1 не host boolean');
  Check((R[4].Key.Width=3) and (R[4].Bits='000'),'D3 порожня структура');
  Check(not SameKey(R[4].Key, ExactKey('0')),'D3:000 відмінне від D1:0');
  Check(R[0].Position.ByteStart=R[1].Position.ByteStart,
    'різні слова можуть займати спільний фізичний байт');

  Fail:=False;
  try BuildVisualWords(#243,T,R);
  except on E:ET5MError do Fail:=True; end;
  Check(Fail,'пошкоджений фізичний байт має відхилятися');
  Check(Length(R)=0,'помилковий вхід не повернув старі рядки');

  BuildVisualWords(B,T,R);
  SetLength(T[3],0);
  Fail:=False;
  try BuildVisualWords(B,T,R);
  except on E:EVisualInspect do Fail:=True; end;
  Check(Fail,'відсутня pinned таблиця має бути помилкою');
  Check(Length(R)=0,'немає часткового візуального результату');

  LoadPinnedDomains('external/sens',T);
  SetLength(W,1); W[0]:='1010101010'; { дослідний D10 }
  Fail:=False;
  try BuildVisualWords(EncodeT5M(W),T,R);
  except on E:EVisualInspect do Fail:=True; end;
  Check(Fail,'не можна мовчки ратифікувати D10');
  Check(Length(R)=0,'D10 залишив частковий результат');

  WriteLn('ІНСПЕКТОР-ПЕРЕВІРЕНО: фізичний-T5M=так координати=точні ',
    'байти=точні українська=pinned негативні=пройдено семантика=не-перевірялась');
end.
