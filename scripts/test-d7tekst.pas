{ G1.22 — exact D7 v2 клавіатурна проєкція, не SENS opcode. }
program test_d7tekst;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.d7tekst,wsm.t5m;
var Alphabet,Broken:TD7Alphabet;
    Text,Physical,Recovered:RawByteString;
    Words:TExactWords;
    Positives,Rejected,I:SizeInt;

procedure Check(Condition:Boolean;const Why:String);
begin if not Condition then raise Exception.Create('Д7-ТЕКСТ-ТЕСТ-ПОМИЛКА: '+Why) end;

function WordsOf(const A:array of RawByteString):TExactWords;
var J:SizeInt;
begin SetLength(Result,Length(A));for J:=0 to High(A) do Result[J]:=A[J] end;

procedure Positive(const S:RawByteString);
var Bytes:RawByteString;W:TExactWords;
begin
  Bytes:=UkrainianD7ToPhysical(S,Alphabet);
  DecodeT5M(Bytes,W);
  Check(Length(W)>0,'порожній фізичний D7');
  Check(EncodeT5M(W)=Bytes,'неканонічний T5M');
  Check(PhysicalD7ToUkrainian(Bytes,Alphabet)=S,'точний український текст');
  Inc(Positives);
end;

procedure NegativeText(const S:RawByteString;const Why:String);
var RejectedHere:Boolean;Bytes:RawByteString;
begin
  RejectedHere:=False;Bytes:='';
  try Bytes:=UkrainianD7ToPhysical(S,Alphabet)
  except on E:ED7TextError do RejectedHere:=True end;
  Check(RejectedHere and (Bytes=''),Why);
  Inc(Rejected);
end;

procedure NegativePhysical(const S:RawByteString;const Why:String);
var RejectedHere:Boolean;Bytes:RawByteString;
begin
  RejectedHere:=False;Bytes:='';
  try Bytes:=PhysicalD7ToUkrainian(S,Alphabet)
  except on E:Exception do RejectedHere:=True end;
  Check(RejectedHere and (Bytes=''),Why);
  Inc(Rejected);
end;

begin
  Positives:=0;Rejected:=0;
  LoadPinnedD7('external/sens',Alphabet);
  Check((Alphabet[0]='') and (Alphabet[22]='') and
    (Alphabet[127]=''),'керувальні координати D7 збережено');
  Check((Alphabet[32]=' ') and (Alphabet[40]='(') and
    (Alphabet[41]=')') and (Alphabet[34]='"') and
    (Alphabet[92]='ґ') and (Alphabet[124]='Ґ'),
    'точна pinned D7 таблиця, лапки, дужки, українські glyph');
  Text:='';
  for I:=0 to High(Alphabet) do if Alphabet[I]<>'' then begin
    Positive(Alphabet[I]);
    Text:=Text+Alphabet[I];
  end;
  Check(Positives=95,'95 друкованих D7 координат');
  Positive(Text);Positive('Привіт, світ! (Д7) ₴');
  Positive('() . ; "" '+#$5C+' ґҐїЇ'); { парні дужки — саме D7 текст }
  Positive('0012'); { це текстові D7-цифри, НЕ числовий D12 атом }
  SetLength(Words,1);Words[0]:='0101000';
  Physical:=EncodeT5M(Words);
  Check(PhysicalD7ToUkrainian(Physical,Alphabet)='(',
    'W7 0101000 є символом тексту, не D2 OPEN');
  Inc(Positives);
  NegativeText('','порожній текст');
  NegativeText(#10,'LF не в pinned D7 text');
  NegativeText('A','латинська A не українська А');
  NegativeText(#$C0#$AF,'UTF-8 overlong');
  NegativeText(#$ED#$A0#$80,'UTF-8 surrogate');
  NegativeText(#$F4#$90#$80#$80,'UTF-8 поза Unicode');
  NegativeText(#$D0,'неповний UTF-8');
  NegativeText('е'+#$CC#$81,'немає складеного довільного glyph');
  NegativeText(StringOfChar('а',MaxD7TextBytes+1),'завеликий D7');
  NegativePhysical('','порожній physical');
  NegativePhysical(#$F3,'недопустимий T5M байт');
  NegativePhysical(EncodeT5M(WordsOf(['1'])),'W1 не D7');
  NegativePhysical(EncodeT5M(WordsOf(['101'])),'W3 не D7');
  NegativePhysical(EncodeT5M(WordsOf(['000000000000'])),'W12 не D7');
  NegativePhysical(EncodeT5M(WordsOf(['0000000'])),'D7 control NUL');
  NegativePhysical(EncodeT5M(WordsOf(['0010110'])),'D7 SYN');
  NegativePhysical(EncodeT5M(WordsOf(['1111111'])),'D7 control DEL');
  NegativePhysical(EncodeT5M(WordsOf(['0101000','1'])),'mixed D7/D1');
  Broken:=Alphabet;
  Broken[33]:=Broken[34];
  Check(Broken[33]<>Alphabet[33],'мутант пошкодив pinned glyph');
  Physical:='';
  try Physical:=UkrainianD7ToPhysical('(',Broken)
  except on E:ED7TextError do Inc(Rejected) end;
  Check(Physical='','колізія glyph не має створювати фізичний результат');
  Check((Positives=100) and (Rejected=20),'лічильники D7 test cases');
  WriteLn('Д7-ТЕКСТ-ГАРАЗД друкованих=95 позитивні=',Positives,
    ' негативні=',Rejected,
    ' T5M=канонічний D2-дужки=тільки-дані D12+=не-числа');
end.
