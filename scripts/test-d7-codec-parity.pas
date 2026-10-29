{ G1.25 — міжкодековий D7 v2 parity без нового Unicode→SENS кодека.
  ОБИДВА механізми зчитують тільки pinned lib/domains/d7.lisp.
  Відмінність Unicode codepoint ≠ відмінність exact W7 identity. }
program test_d7_codec_parity;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.d7tekst,wsm.d7text,wsm.t5m,wsm.physloc;
var
  Alphabet:TD7Alphabet;
  Map:TD7Map;
  Counts,Negatives,I,J,NextI,N:SizeInt;
  P1,P2,Uk,Data,TextBack:RawByteString;
  W:TExactWords;
  Span:TPhysicalWordSpans;

procedure Must(C:Boolean;const Reason:String);
begin
  Inc(Counts);
  if not C then raise Exception.Create('Д7-ПАРИТЕТ-ПОМИЛКА: '+Reason);
end;

function SinglePhysicalWord(const Bits:RawByteString):RawByteString;
var A:TExactWords;
begin
  SetLength(A,1);A[0]:=Bits;
  Result:=EncodeT5M(A);
end;

function ExpectedBits(Code:SizeInt):RawByteString;
var K:SizeInt;
begin
  { Чисто перевірка 7-бітної адреси рядка: НЕ таблиця Unicode, не D7 law. }
  SetLength(Result,7);
  for K:=1 to 7 do begin
    if (Code and (1 shl (7-K)))<>0 then Result[K]:='1'
    else Result[K]:='0';
  end;
end;

procedure RejectText(const Candidate:RawByteString;const Why:String);
var Flag:Boolean;Output:RawByteString;
begin
  Flag:=False;Output:='';
  try
    Output:=EncodeD7Text(Candidate,Map,dsUk);
  except on E:Exception do Flag:=True end;
  Must(Flag and (Output=''),Why+': D7 v2 мусить відхилити до результату');
  Flag:=False;Output:='';
  try
    Output:=UkrainianD7ToPhysical(Candidate,Alphabet);
  except on E:Exception do Flag:=True end;
  Must(Flag and (Output=''),Why+': старий D7 мусить відхилити без bytes');
  Inc(Negatives);
end;

procedure RejectPhysical(const Candidate:RawByteString;const Why:String);
var Flag:Boolean;Output:RawByteString;
begin
  Flag:=False;Output:='';
  try
    Output:=DecodeD7Text(Candidate,Map,dsUk);
  except on E:Exception do Flag:=True end;
  Must(Flag and (Output=''),Why+': D7 v2 прийняв заборонений payload');
  Flag:=False;Output:='';
  try
    Output:=PhysicalD7ToUkrainian(Candidate,Alphabet);
  except on E:Exception do Flag:=True end;
  Must(Flag and (Output=''),Why+': старий D7 прийняв заборонений payload');
  Inc(Negatives);
end;

begin
  Counts:=0;Negatives:=0;
  LoadPinnedD7('external/sens',Alphabet);
  LoadPinnedD7Map('.',Map);
  for I:=0 to 127 do begin
    Must(Map[I].Uk=Alphabet[I],
      'помилка повної pinned D7 таблиці, координата '+IntToStr(I));
    if (I<32) or (I=127) then begin
      Must(Alphabet[I]='',
        'керувальна D7 координата має бути без проєкції '+IntToStr(I));
      Continue;
    end;
    Must((Map[I].Uk<>'') and (Map[I].Ukr<>''),
      'надрукований W7 не має двох українських проєкцій');
    P1:=EncodeD7Text(Map[I].Uk,Map,dsUk);
    P2:=UkrainianD7ToPhysical(Alphabet[I],Alphabet);
    Must(P1=P2,'два існуючих кодеки мають різні фізичні байти');
    Must(P1=SinglePhysicalWord(ExpectedBits(I)),
      'втрачено leading 0 або точну ширину W7');
    Must(DecodeD7Text(P1,Map,dsUk)=Map[I].Uk,
      'чинний D7 v2 неправильно повернув ук');
    Must(PhysicalD7ToUkrainian(P1,Alphabet)=Map[I].Uk,
      'перший D7 кодек неправильно повернув ук');
    Must(DecodeD7Text(P1,Map,dsUkr)=Map[I].Ukr,
      'друга pinned українська проєкція втрачена');
    Must(EncodeD7Text(Map[I].Ukr,Map,dsUkr)=P1,
      'укр повернула інше фізичне W7');
  end;

  { Максимальний СПІЛЬНИЙ обсяг 4096: реальні packed T5M байти,
    4096 W7 = 32767 значущих тритів із 4095 роздільниками. }
  Uk:='';Data:='';
  for I:=0 to 4095 do begin
    N:=32+(I mod 95);
    Uk:=Uk+Map[N].Uk;
    Data:=Data+Map[N].Ukr;
  end;
  P1:=UkrainianD7ToPhysical(Uk,Alphabet);
  P2:=EncodeD7Text(Uk,Map,dsUk);
  Must(P1=P2,'змішана довга українська послідовність не byte-exact');
  Must(EncodeD7Text(Data,Map,dsUkr)=P1,
    'укр при 4096 символах змінила фізичні біти');
  Must(DecodeD7Text(P1,Map,dsUkr)=Data,
    'укр decode довгої фізичної послідовності');
  Must(PhysicalD7ToUkrainian(P1,Alphabet)=Uk,
    'ук decode старого D7');
  DecodeT5MWithLocations(P1,W,Span);
  Must((Length(W)=4096) and (Length(Span)=4096),
    'не збережено всіх точних фізичних W7');
  for I:=0 to 4095 do begin
    NextI:=I*8;
    Must(W[I]=ExpectedBits(32+(I mod 95)),
      'невірна D7:bits координата у позиції '+IntToStr(I+1));
    Must((Span[I].WordIndex=I+1) and (Span[I].TritStart=NextI) and
      (Span[I].TritEnd=NextI+7) and (Span[I].ByteStart=NextI div 5) and
      (Span[I].ByteEnd=(NextI+11) div 5) and (not Span[I].IsEOF),
      'хибний half-open трит/байт інтервал W7 '+IntToStr(I+1));
  end;
  Must((Span[0].ByteStart=0) and (Span[0].ByteEnd=2) and
    (Span[1].ByteStart=1) and (Span[1].ByteEnd=3),
    'суміжні D7 слова мають право ділити фізичний байт');
  Must(EncodeT5M(W)=P1,'не збережено канонічний T5M');

  TextBack:='Це 0() №Їґ';
  P2:=EncodeD7Text(TextBack,Map,dsUkr);
  Must((DecodeD7Text(P2,Map,dsUkr)=TextBack) and
       (Length(P2)>0),'0 і дужки є D7 даними, не D1/D2/D12+');

  RejectText('i','латинська i не українська і');
  RejectText(#$C0#$AF,'неканонічний UTF-8');
  RejectText(#0,'NUL не printable D7');
  RejectText(#$F0#$9F#$98#$80,'emoji поза D7 таблицею');
  RejectText('','порожні текстові дані D7');
  RejectPhysical(SinglePhysicalWord('0010110'),'W7 SYN заборонений');
  RejectPhysical(SinglePhysicalWord('1111111'),'W7 DEL заборонений');
  RejectPhysical(SinglePhysicalWord('0'),'W1 не W7');
  RejectPhysical(SinglePhysicalWord('000000000000'),'D12+ не W7');
  RejectPhysical(#243,'неканонічний фізичний байт T5M');
  SetLength(W,2);W[0]:='0110000';W[1]:='0';
  RejectPhysical(EncodeT5M(W),'змішаний W7/W1');

  WriteLn('Д7-ДВА-КОДЕКИ-ГАРАЗД мапа=128 друкованих=95',
    ' фізична-згода=95/95 довгий-текст=4096',
    ' трити-байти=точні позитивних=',Counts,
    ' негативних=',Negatives,
    ' колізій=0 W1/D2/D12=НЕ-Д7');
end.
