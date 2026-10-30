{ G1.59 — невірний останній фізичний span не повинен породжувати
  довірену EOF-адресу. Жодного нового T5M-декодера або закону SENS. }
program test_physloc_eof_guard;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.physloc;

procedure Perevir(Uslova: Boolean; const Prychyna: String);
begin
  if not Uslova then begin
    WriteLn(StdErr, 'PHYSLOC-EOF-FAIL: ',Prychyna);
    Halt(1);
  end;
end;

procedure PerevirEOF(const Physical: RawByteString;
  const Spans: TPhysicalWordSpans);
var EOFSpan: TPhysicalWordSpan;
begin
  EOFSpan:=LocatePhysicalWord(Physical,Spans,Length(Spans)+1);
  Perevir(EOFSpan.IsEOF and
    (EOFSpan.WordIndex=Length(Spans)+1) and
    (EOFSpan.TritStart=Spans[High(Spans)].TritEnd) and
    (EOFSpan.TritEnd=EOFSpan.TritStart) and
    (EOFSpan.ByteStart=Length(Physical)) and
    (EOFSpan.ByteEnd=Length(Physical)),
    'порушено фізичну адресу справного EOF');
end;

procedure PerevirPohodzhenniia(const Physical: RawByteString;
  const Trusted: TPhysicalWordSpans; Mutation: Integer);
var Bad:TPhysicalWordSpans;
    Rejected:Boolean;
    I:SizeInt;
    EOFSpan:TPhysicalWordSpan;
begin
  { Copy створює власний динамічний масив записів. Trusted не мутує. }
  Bad:=Copy(Trusted,0,Length(Trusted));
  I:=High(Bad);
  case Mutation of
    0: Bad[I].TritStart:=-1;
    1: Bad[I].TritEnd:=Length(Physical)*5+1;
    2: Bad[I].ByteEnd:=0;
    3: Bad[I].WordIndex:=Length(Bad)+2;
    4: Bad[I].IsEOF:=True;
  else raise Exception.Create('невідомий варіант фізичного пошкодження');
  end;
  Rejected:=False;
  try
    EOFSpan:=LocatePhysicalWord(Physical,Bad,Length(Bad)+1);
  except
    on E:EPhysicalLocationError do Rejected:=True;
  end;
  Perevir(Rejected,'пошкоджений останній span став довіреним EOF: '+
    IntToStr(Mutation));
  { Навіть після відмови оригінальна карта та адреса лишаються дійсними. }
  PerevirEOF(Physical,Trusted);
end;

var Words,Decoded:TExactWords;
    Physical:RawByteString;
    Spans:TPhysicalWordSpans;
    I:Integer;
begin
  SetLength(Words,3);
  Words[0]:='10';
  Words[1]:=RawByteString(StringOfChar('0',192));
  Words[2]:='01';
  Physical:=EncodeT5M(Words);
  DecodeT5MWithLocations(Physical,Decoded,Spans);
  Perevir((Length(Decoded)=3) and (Length(Spans)=3) and
    (Decoded[1]=Words[1]) and
    (EncodeT5M(Decoded)=Physical),
    'втрата точного фізичного W192 та T5M round-trip');
  PerevirEOF(Physical,Spans);
  for I:=0 to 4 do
    PerevirPohodzhenniia(Physical,Spans,I);
  WriteLn('VERIFIED-PHYSLOC-EOF-PASS FPC=checked wide=192 negative=5 recovery=5 energy=NOT-MEASURED');
end.

{ Типи/ресурси: Physical — owned canonical T5M-байти, Words/Decoded та
  Spans/Bad — локальні керовані Pascal-масиви; TD2/доменні закони
  не обчислюються. Вихід — host-код 0 і стабільний маркер доказу.
  1) Чому W192 не означає викличний D192?
  2) Як визначаються 0-based TritEnd та EOF-байт?
  3) Чому copy потрібна для тесту негативів?
  4) Що саме перевіряється без повторного T5M decoder?
  5) Чому успішна адреса EOF не доводить семантику SENS? }