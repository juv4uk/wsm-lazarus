{ G1.20: пряме пакування фізичних T5M без великих тимчасових тритів.
  Перевірка тільки exact bit width/byte; semantic law pinned juv4uk/sens. }
program test_t5m_direct;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m;

var Checks: SizeInt;

procedure Check(Condition: Boolean; const Why: String);
begin
  Inc(Checks);
  if not Condition then begin
    WriteLn(StdErr,'T5M-ПРЯМИЙ-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;

{ Незалежна маленька математична перевірка: "2".join(words), padding
  до 5 і base-3 fold, як pinned sens_t5_t5m_codec.py.
  Лише тестова модель — production не створює масив тритів. }
function ReferenceBytes(const Words: TExactWords): RawByteString;
var Trits: RawByteString; I,J,K,V,P:SizeInt;
begin
  Trits:='';
  for I:=0 to High(Words) do begin
    if I<>0 then Trits:=Trits+'2';
    Trits:=Trits+Words[I];
  end;
  while Length(Trits) mod 5 <> 0 do Trits:=Trits+'2';
  SetLength(Result,Length(Trits) div 5);
  P:=1;
  for I:=0 to Length(Result)-1 do begin
    V:=0;
    for K:=1 to 5 do
      V:=V*3+Ord(Trits[I*5+K])-Ord('0');
    Result[P]:=AnsiChar(V);
    Inc(P);
  end;
end;

procedure Compare(const Words: array of RawByteString; const Why:String);
var W,D:TExactWords; I:SizeInt; B:RawByteString;
begin
  SetLength(W,Length(Words));
  for I:=0 to High(Words) do W[I]:=Words[I];
  B:=EncodeT5M(W);
  Check(B=ReferenceBytes(W),Why+' має інші фізичні T5M байти');
  DecodeT5M(B,D);
  Check(Length(D)=Length(W),Why+' змінило кількість точних слів');
  for I:=0 to High(W) do
    Check(W[I]=D[I],Why+' втратило провідні нулі чи межі');
  Check(EncodeT5M(D)=B,Why+' зламало зворотні фізичні байти');
end;

procedure Reject(const W:TExactWords;const Why:String);
var Raised:Boolean; Bad:RawByteString;
begin
  Raised:=False;
  try Bad:=EncodeT5M(W);
  except on E:ET5MError do Raised:=True end;
  Check(Raised,Why+' не відхилено');
end;

var
  W,D:TExactWords;
  B:RawByteString;
  I,J,N,P,BigBits,PhysicalBytes:SizeInt;
  First,Last:RawByteString;
begin
  Checks:=0;
  Compare(['0'],'один D1:0');
  Compare(['1'],'один D1:1');
  Compare(['000'],'D3:000 не D1:0');
  Compare(['00','01','10','11'],'фізичні слова D2');
  Compare(['11111','1','00000','0'],'межа байта й ширини');
  Compare(['010101010','1','11111111111'],'перехід через два байти');

  { Усі п'ять можливих фаз закінчення і межі між тритами. }
  for N:=1 to 25 do begin
    SetLength(W,2);
    W[0]:=StringOfChar('0',N);
    W[1]:=StringOfChar('1',N mod 7+1);
    Compare(W,'фаза '+IntToStr(N));
  end;
  { Два точних слова будь-якої 4-бітної маски. }
  for I:=0 to 15 do
    for J:=0 to 15 do begin
      SetLength(W,2); SetLength(W[0],4); SetLength(W[1],4);
      for P:=0 to 3 do begin
        W[0][P+1]:=AnsiChar(Ord('0')+((I shr P) and 1));
        W[1][P+1]:=AnsiChar(Ord('0')+((J shr P) and 1));
      end;
      Compare(W,'маска '+IntToStr(I)+'/'+IntToStr(J));
    end;

  { Багато реальних точних T5M boundaries; не трактувати як D1 закон. }
  SetLength(W,65536);
  for I:=0 to High(W) do
    if (I and 1)=0 then W[I]:='0' else W[I]:='1';
  B:=EncodeT5M(W);
  Check(Length(B)=26215,'65536 коротких слів: точний обсяг T5M');
  DecodeT5M(B,D);
  Check(Length(D)=65536,'65536 слів після decode');
  Check((D[0]='0') and (D[65535]='1') and (D[32768]='0'),
    'втрата першого/середнього/останнього exact слова');
  Check(EncodeT5M(D)=B,'множинні короткі слова не reversible');
  SetLength(W,0);SetLength(D,0);B:='';

  { 4 MiB фізична квота: 5*4MiB бітів як ОДНЕ exact word.
    Це host-квота фізичного кодувальника, а НЕ семантична D20971520. }
  BigBits:=MAX_T5M_FILE_BYTES*5;
  SetLength(W,1);
  W[0]:=StringOfChar('0',BigBits);
  W[0][1]:='1';W[0][BigBits]:='1';
  First:=Copy(W[0],1,16);
  Last:=Copy(W[0],BigBits-15,16);
  B:=EncodeT5M(W);
  PhysicalBytes:=Length(B);
  Check(PhysicalBytes=MAX_T5M_FILE_BYTES,'4 MiB max фізичного T5M');
  DecodeT5M(B,D);
  Check((Length(D)=1) and (Length(D[0])=BigBits),
    'велике фізичне exact слово втратило ширину');
  Check((Copy(D[0],1,16)=First) and
    (Copy(D[0],BigBits-15,16)=Last),
    'втрата провідних/завершальних фізичних бітів');
  Check(EncodeT5M(D)=B,'4 MiB фізичний byte-roundtrip');
  Check(Copy(W[0],1,16)=First,'вхідне const слово змінилося');
  W[0]:=W[0]+'0';
  Reject(W,'перевищення фізичного розміру');
  W[0]:='10X';
  Reject(W,'недвійковий exact word');
  W[0]:='';
  Reject(W,'порожній exact word');
  SetLength(W,0);
  Reject(W,'порожній потік');
  SetLength(W,2);W[0]:='0';W[1]:='1X';
  Reject(W,'пізня недвійкова координата');
  Check(PhysicalBytes=4*1024*1024,'фізична максимальна квота');
  WriteLn('T5M-ПРЯМИЙ-ГАРАЗД еталон=base3 ',
    'малих-слів=65536 фізичний-ліміт=',PhysicalBytes,
    ' negative=5 перевірок=',Checks,
    ' закони=pinned-only');
end.
