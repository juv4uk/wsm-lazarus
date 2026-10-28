program test_binarylocbind;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.domain, wsm.bind, wsm.binarybind, wsm.binarylocbind;
var T: TDomainSet; Words: TExactWords; Items: TLocatedBinaryWords;
    Physical: RawByteString; I: SizeInt; Rejected: Boolean;
function ExactWords(const S: array of RawByteString): TExactWords;
var J: SizeInt;
begin
  SetLength(Result, Length(S));
  for J:=0 to High(S) do Result[J] := S[J];
end;
procedure Check(B: Boolean; const Why: String);
begin
  if not B then begin WriteLn(StdErr, 'ДВІЙКОВА-АДРЕСА-ПОМИЛКА: ',Why); Halt(1); end;
end;
begin
  LoadPinnedDomains('external/sens',T);
  Words := ExactWords(['10','111','00','1','000','01']);
  Physical := EncodeT5M(Words);
  BindLocatedT5M(Physical,T,Items);
  Check(Length(Items)=3,'три атоми D2');
  Check(SameKey(Items[0].Word.Key,ExactKey('111')) and
    (Items[0].Word.WordIndex=2) and (Items[0].Word.RootIndex=0) and
    (Items[0].Word.Ukrainian='сполучити'), 'D3:111 — первинна координата');
  Check((Items[0].Physical.TritStart=3) and
    (Items[0].Physical.TritEnd=6) and
    (Items[0].Physical.ByteStart=0) and
    (Items[0].Physical.ByteEnd=2), 'D3:111 перетинає фізичні байти');
  Check(SameKey(Items[1].Word.Key,ExactKey('1')) and
    (Items[1].Word.WordIndex=4) and
    (Items[1].Physical.TritStart=10) and
    (Items[1].Physical.TritEnd=11), 'D1:1 на власній адресі');
  Check(SameKey(Items[2].Word.Key,ExactKey('000')) and
    (Items[2].Word.IsEmpty) and
    (Items[2].Word.WordIndex=5) and
    (Items[2].Physical.TritStart=12) and
    (Items[2].Physical.TritEnd=15), 'D3:000 порожня структура');
  Check(not SameKey(Items[2].Word.Key,ExactKey('0')), 'D3:000 не є D1:0');
  Check((Items[1].Physical.ByteStart=2) and
    (Items[2].Physical.ByteStart=2), 'різні слова в одному фізичному байті');

  Words := ExactWords(['0','1']);
  Physical := EncodeT5M(Words);
  BindLocatedT5M(Physical,T,Items);
  Check(Length(Physical)=1,'два доменні слова в одному T5M байті');
  Check((Length(Items)=2) and
    (Items[0].Word.RootIndex=0) and (Items[1].Word.RootIndex=1) and
    SameKey(Items[0].Word.Key,ExactKey('0')) and
    SameKey(Items[1].Word.Key,ExactKey('1')), 'два фізичні корені D1');
  Check((Items[0].Physical.ByteStart=0) and
    (Items[1].Physical.ByteStart=0) and
    (Items[0].Physical.TritStart=0) and
    (Items[0].Physical.TritEnd=1) and
    (Items[1].Physical.TritStart=2) and
    (Items[1].Physical.TritEnd=3), 'точні спільні байти і окремі трити');

  Words := ExactWords(['10','1','11','0','01']);
  BindLocatedT5M(EncodeT5M(Words),T,Items);
  Check((Length(Items)=2) and
    (Items[0].Word.WordIndex=2) and
    (Items[1].Word.WordIndex=4) and
    SameKey(Items[0].Word.Key,ExactKey('1')) and
    SameKey(Items[1].Word.Key,ExactKey('0')), 'крапкова пара');

  Words := ExactWords(['000000001']);
  BindLocatedT5M(EncodeT5M(Words),T,Items);
  Check((Length(Items)=1) and
    (Items[0].Word.Key.Width=9) and
    SameKey(Items[0].Word.Key,ExactKey('000000001')) and
    (Items[0].Physical.TritEnd-Items[0].Physical.TritStart=9),
    'збережено провідні нулі і ширину D9');

  Rejected:=False;
  try BindLocatedT5M(#243,T,Items);
  except on E:ET5MError do Rejected:=True; end;
  Check(Rejected,'зіпсований T5M байт прийнято');
  Rejected:=False;
  try BindLocatedT5M('',T,Items);
  except on E:ET5MError do Rejected:=True; end;
  Check(Rejected,'порожній фізичний файл прийнято');
  Words := ExactWords(['10','1']);
  Rejected:=False;
  try BindLocatedT5M(EncodeT5M(Words),T,Items);
  except on E:ED2PhysicalError do begin
    Rejected:=True;
    Check(E.Span.IsEOF and (E.Span.WordIndex=3) and
      (E.Span.ByteStart=Length(EncodeT5M(Words))),
      'відсутня фізична адреса помилки EOF');
  end; end;
  Check(Rejected,'незакриту D2 структуру прийнято');

  Words:=ExactWords(['0000000000']);
  Rejected:=False;
  try BindLocatedT5M(EncodeT5M(Words),T,Items);
  except on E:ED2PhysicalError do begin
    Rejected:=True;
    Check(E.Span.WordIndex=1,'невірна адреса недопущеної ширини');
  end; end;
  Check(Rejected,'W10 помилково допущено до reader W1/W3–W9');

  SetLength(T[1],0);
  Words:=ExactWords(['1']);
  Rejected:=False;
  try BindLocatedT5M(EncodeT5M(Words),T,Items);
  except on E:EBinaryBindError do Rejected:=True; end;
  Check(Rejected,'неповні pinned таблиці прийнято');

  WriteLn('ДВІЙКОВІ-АДРЕСИ-ГАРАЗД: ',
    'байти=точні трити=точні домени=точні ',
    'D3:000<>D1:0 викличність=не-доведено');
end.
