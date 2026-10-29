{ G1.22 — pinned D7 v2: кожна з 95 друкованих координат W7 у «ук/укр»
  має рівно один UTF-8 символ. Точні біти — першоджерело, не кодпойнт. }
program test_d7text;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.d7text,wsm.t5m;
var Map:TD7Map; Source,Physical,Encoded,TextData,Decoded:RawByteString;
    F:TFileStream; Root:String; Positives,Negatives,I,J:SizeInt;
    W:TExactWords;

procedure Check(C:Boolean;const Why:String);
begin if not C then raise Exception.Create('Д7-ТЕСТ-ПОМИЛКА: '+Why) end;

function Words(const Items:array of RawByteString):TExactWords;
var K:SizeInt;
begin
  SetLength(Result,Length(Items));
  for K:=0 to High(Items) do Result[K]:=Items[K];
end;

function OneWord(N:SizeInt):RawByteString;
var K:SizeInt; S:RawByteString;
begin
  SetLength(S,7);
  for K:=1 to 7 do
    if (N and (1 shl (7-K)))<>0 then S[K]:='1'
    else S[K]:='0';
  Result:=EncodeT5M(Words([S]));
end;

procedure NegativeText(const Input:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try EncodeD7Text(Input,Map,dsUkr);
  except on E:Exception do Rejected:=True end;
  Check(Rejected,Why);Inc(Negatives);
end;

procedure NegativePhysical(const Input:RawByteString;const Why:String);
var Rejected:Boolean;
begin
  Rejected:=False;
  try DecodeD7Text(Input,Map,dsUkr);
  except on E:Exception do Rejected:=True end;
  Check(Rejected,Why);Inc(Negatives);
end;

procedure NegativeSource(const Input:RawByteString;const Why:String);
var Temp:TD7Map; Rejected:Boolean;
begin
  Rejected:=False;
  try ParseD7Map(Input,Temp);
  except on E:Exception do Rejected:=True end;
  Check(Rejected,Why);Inc(Negatives);
end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Вкажіть корінь з pinned external/sens');Halt(64)
  end;
  Root:=ParamStr(1);
  LoadPinnedD7Map(Root,Map);
  F:=TFileStream.Create(Root+'/external/sens/lib/domains/d7.lisp',
    fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Source,SizeInt(F.Size));
    F.ReadBuffer(Source[1],Length(Source));
  finally F.Free end;
  Positives:=0;Negatives:=0;
  for I:=32 to 126 do begin
    Physical:=OneWord(I);
    for J:=0 to 1 do begin
      if J=0 then begin
        Decoded:=DecodeD7Text(Physical,Map,dsUk);
        Encoded:=EncodeD7Text(Decoded,Map,dsUk);
      end else begin
        Decoded:=DecodeD7Text(Physical,Map,dsUkr);
        Encoded:=EncodeD7Text(Decoded,Map,dsUkr);
      end;
      Check((Encoded=Physical) and (Decoded<>''),'ін’єкція W7 координати '+IntToStr(I));
      Inc(Positives);
    end;
  end;
  TextData:=RawByteString(UTF8Encode(
    UnicodeString('Це 0() №Їґ «')));
  { « відсутній на 95-клавішній поверхні: не підмінюємо схожим знаком. }
  NegativeText(TextData,'непідтверджена літера « не може мати D7 координату');
  TextData:=RawByteString(UTF8Encode(
    UnicodeString('Це 0() №Їґ')));
  Physical:=EncodeD7Text(TextData,Map,dsUkr);
  Check(DecodeD7Text(Physical,Map,dsUkr)=TextData,
    'буквальні дужки, цифри, українські літери збереглися як дані D7');
  DecodeT5M(Physical,W);
  Check((Length(W)>4) and (W[2]='0100000') and
    (W[3]='0110000') and (W[4]='0101000') and
    (W[5]='0101001'),'D7 пробіл/0/дужки: не D2 і не D12+');
  Inc(Positives);
  NegativeText('','порожній host-текст');
  NegativeText('i','латинська i не українська і');
  NegativeText(#0,'NUL заборонений');
  NegativeText(#$C0#$AF,'неканонічний UTF8');
  NegativeText(#$F0#$9F#$98#$80,'emoji поза клавіатурою D7');
  NegativePhysical(OneWord(22),'SYN 0010110 є керувальним');
  NegativePhysical(OneWord(127),'DEL 1111111 є керувальним');
  NegativePhysical(EncodeT5M(Words(['0'])),'W1 не W7');
  NegativePhysical(EncodeT5M(Words(['000000000000'])),'D12 не W7');
  NegativePhysical(EncodeT5M(Words(['0110000','0'])),'змішана W7/W1');
  NegativePhysical(#$F3,'T5M байт 243 не канонічний');
  NegativeSource(StringReplace(Source,'(0100001 (ук "!")',
    '(0100010 (ук "!")',[]),'змінено координату D7');
  NegativeSource(StringReplace(Source,'(0100001 (ук "!")',
    '(0100001 (ук " ")',[]),'дубль «ук» без допуску');
  NegativeSource(StringReplace(Source,'(0100001 (ук "!")',
    '(0100001 (ук "!") (LISP 0)',[]),'зайвий вузол у рядку');
  Check((Positives=191) and (Negatives=15),'лічильники проєкцій і відмов');
  WriteLn('Д7-В2-ГАРАЗД W7=128 друковані=95 поверхні=ук/укр ',
    'позитивні=',Positives,' негативні=',Negatives,
    ' колізій=0 D1/D2/D12=без-змішування');
end.
