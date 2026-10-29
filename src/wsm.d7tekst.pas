{ G1.22 — механічна українська текстова проєкція точних D7 W7.
  ТІЛЬКИ pinned lib/domains/d7.lisp є власником клавіатурної карти;
  тут немає локального кодування, D2-парсера, opcode чи мовного закону.
  Текстові '(' і ')' є ДАНИМИ, не D2 рамкою. }
unit wsm.d7tekst;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
const MaxD7TextBytes=65536;
      MaxD7Characters=8192;
type
  ED7TextError=class(Exception);
  TD7Alphabet=array[0..127] of RawByteString;

procedure LoadPinnedD7(const AuthorityRoot:RawByteString;
  out Alphabet:TD7Alphabet);
function UkrainianD7ToPhysical(const Ukrainian:RawByteString;
  const Alphabet:TD7Alphabet):RawByteString;
function PhysicalD7ToUkrainian(const Physical:RawByteString;
  const Alphabet:TD7Alphabet):RawByteString;
implementation
uses Classes,wsm.t5m;

procedure Require(Condition:Boolean;const Why:String);
begin
  if not Condition then raise ED7TextError.Create(Why);
end;

{ Один строгий UTF-8 Unicode scalar, без replacement/normalization.
  At є 1-based позицією байта; NextAt — наступний байт. }
function ScalarAt(const S:RawByteString;At:SizeInt;
  out NextAt:SizeInt):RawByteString;
var B,B2,B3,B4,N:SizeInt;
  function Continuation(P:SizeInt):SizeInt;
  begin
    Require((P<=Length(S)) and (Byte(S[P]) in [$80..$BF]),
      'Некоректне продовження UTF-8');
    Result:=Byte(S[P]);
  end;
begin
  Require((At>=1) and (At<=Length(S)),'UTF-8 scalar поза межами');
  B:=Byte(S[At]);
  if B<128 then N:=1
  else if (B>=$C2) and (B<=$DF) then N:=2
  else if (B>=$E0) and (B<=$EF) then N:=3
  else if (B>=$F0) and (B<=$F4) then N:=4
  else begin
    raise ED7TextError.Create('Недопустимий UTF-8 leading byte');
    N:=0;
  end;
  Require(N<=Length(S)-At+1,'Незавершений UTF-8 scalar');
  if N>=2 then B2:=Continuation(At+1) else B2:=0;
  if N>=3 then B3:=Continuation(At+2) else B3:=0;
  if N>=4 then B4:=Continuation(At+3) else B4:=0;
  if N=3 then Require(
    ((B<>$E0) or (B2>=$A0)) and
    ((B<>$ED) or (B2<$A0)), 'UTF-8 overlong або surrogate');
  if N=4 then Require(
    ((B<>$F0) or (B2>=$90)) and
    ((B<>$F4) or (B2<$90)), 'UTF-8 overlong або поза Unicode');
  { B3/B4 уже строго перевірені, ці змінні не мають мовного значення. }
  if (B3<0) or (B4<0) then raise ED7TextError.Create('UTF-8');
  NextAt:=At+N;
  Result:=Copy(S,At,N);
end;

procedure ValidateAlphabet(const Alphabet:TD7Alphabet);
var I,J,NextAt,Visible:SizeInt;
begin
  Visible:=0;
  for I:=0 to High(Alphabet) do
    if Alphabet[I]<>'' then begin
      NextAt:=0;
      ScalarAt(Alphabet[I],1,NextAt);
      Require(NextAt=Length(Alphabet[I])+1,
        'D7 проєкція не є єдиним UTF-8 символом');
      for J:=0 to I-1 do
        Require(Alphabet[J]<>Alphabet[I],
          'Колізія pinned D7 українських клавіатурних символів');
      Inc(Visible);
    end;
  Require(Visible=95,
    'Потрібні рівно 95 чинних друкованих координат pinned D7 v2');
end;

{ Одна quoted surface враховує лапки, escape і D7 дужки як ДАНІ.
  Поточний загальний доменний reader шукає першу ')' і для D7
  quoted ')' втрачає інформацію; не використовуємо його для тексту. }
function ReadSurface(const Line:RawByteString):RawByteString;
const UK_MARKER=#$28#$D1#$83#$D0#$BA#$20; { байти "(ук " }
var At,Start:SizeInt;C:AnsiChar;Closed:Boolean;
begin
  At:=Pos(UK_MARKER,Line);
  Require(At>0,'Немає pinned поля «ук»');
  Inc(At,Length(UK_MARKER));
  Require(At<=Length(Line),'Порожнє поле D7 «ук»');
  if (Line[At]='(') then begin
    Require(Copy(Line,At,3)='())','Некоректне порожнє D7 «ук»');
    Exit('');
  end;
  Result:='';
  if Line[At]='"' then begin
    Inc(At);Closed:=False;
    while At<=Length(Line) do begin
      C:=Line[At];
      if C='"' then begin Inc(At);Closed:=True;Break;end;
      if C='\' then begin
        Inc(At);
        Require(At<=Length(Line),'Обірваний escape D7 «ук»');
        C:=Line[At];
        Require((C='"') or (C='\'),'Неприпустимий escape D7 «ук»');
      end;
      Result:=Result+C;
      Inc(At);
    end;
    Require(Closed and (At<=Length(Line)) and (Line[At]=')'),
      'Незавершені лапки pinned D7 «ук»');
  end else begin
    Start:=At;
    while (At<=Length(Line)) and (Line[At]<>')') do Inc(At);
    Require(At<=Length(Line),'Незавершений D7 «ук»');
    Result:=Copy(Line,Start,At-Start);
  end;
  Require(Result<>'','Порожнє непозначене поле D7');
end;

procedure LoadPinnedD7(const AuthorityRoot:RawByteString;
  out Alphabet:TD7Alphabet);
var Candidate:TD7Alphabet;
    Source,Path,Line,Bits,Glyph:RawByteString;
    F:TFileStream;
    P,E,Row,I,Value:SizeInt;
begin
  for I:=0 to 127 do Alphabet[I]:='';
  Path:=IncludeTrailingPathDelimiter(String(AuthorityRoot))+
    'lib/domains/d7.lisp';
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Require((F.Size>0) and (F.Size<=1024*1024),
      'Pinned D7 файл порожній або надмірний');
    SetLength(Source,SizeInt(F.Size));
    F.ReadBuffer(Source[1],Length(Source));
  finally F.Free end;
  for I:=0 to 127 do Candidate[I]:='';
  P:=1;Row:=0;
  while P<=Length(Source) do begin
    E:=P;
    while (E<=Length(Source)) and (Source[E]<>#10) do Inc(E);
    Line:=Trim(Copy(Source,P,E-P));
    P:=E+1;
    if (Length(Line)<2) or (Line[1]<>'(') or
       not (Line[2] in ['0','1']) then Continue;
    Require((Length(Line)>=11) and (Line[9]=' '),
      'Некоректний рядок pinned D7');
    Bits:=Copy(Line,2,7);
    Require(Length(Bits)=7,'Втрачено точну ширину D7');
    Value:=0;
    for I:=1 to 7 do begin
      Require(Bits[I] in ['0','1'],'Заборонений трит у D7 слові');
      Value:=(Value shl 1)+Ord(Bits[I])-Ord('0');
    end;
    Require((Row<128) and (Value=Row),
      'Пропущена, переставлена або дубльована координата D7');
    Require(Pos('(LISP ())',Line)>0,
      'Pinned D7 текст не має створювати callable Lisp голову');
    Glyph:=ReadSurface(Line);
    Candidate[Row]:=Glyph;
    Inc(Row);
  end;
  Require(Row=128,'Pinned D7 повинен мати рівно 128 точних слів');
  ValidateAlphabet(Candidate);
  Alphabet:=Candidate; { атомарна публікація лише після всієї таблиці }
end;

function PhysicalD7ToUkrainian(const Physical:RawByteString;
  const Alphabet:TD7Alphabet):RawByteString;
var Words:TExactWords;I,J,Value:SizeInt;
begin
  Result:='';
  ValidateAlphabet(Alphabet);
  Require((Length(Physical)>0) and
    (Length(Physical)<=MaxD7TextBytes),
    'Порожній або завеликий фізичний D7');
  DecodeT5M(Physical,Words);
  Require(Length(Words)<=MaxD7Characters,'Забагато фізичних D7 символів');
  Require(EncodeT5M(Words)=Physical,'Неканонічний фізичний T5M');
  for I:=0 to High(Words) do begin
    Require(Length(Words[I])=7,'Текст D7 вимагає лише W7 слова');
    Value:=0;
    for J:=1 to 7 do begin
      Require(Words[I][J] in ['0','1'],'Неточні D7 біти');
      Value:=(Value shl 1)+Ord(Words[I][J])-Ord('0');
    end;
    Require(Alphabet[Value]<>'',
      'Керувальна або недрукована D7 координата не має ук-проєкції');
    Require(Length(Alphabet[Value])<=MaxD7TextBytes-Length(Result),
      'D7 текст перевищує межу UTF-8');
    Result:=Result+Alphabet[Value];
  end;
end;

function UkrainianD7ToPhysical(const Ukrainian:RawByteString;
  const Alphabet:TD7Alphabet):RawByteString;
var Words:TExactWords; Count,At,NextAt,I:SizeInt;
    Glyph:RawByteString;Found:Boolean;
begin
  Result:='';
  ValidateAlphabet(Alphabet);
  Require((Length(Ukrainian)>0) and
    (Length(Ukrainian)<=MaxD7TextBytes),
    'Порожня або завелика українська D7-проєкція');
  SetLength(Words,MaxD7Characters);
  Count:=0;At:=1;
  while At<=Length(Ukrainian) do begin
    Require(Count<MaxD7Characters,'Перевищено кількість D7 символів');
    Glyph:=ScalarAt(Ukrainian,At,NextAt);
    Found:=False;
    for I:=0 to High(Alphabet) do
      if (Alphabet[I]<>'') and (Alphabet[I]=Glyph) then begin
        Words[Count]:='';
        SetLength(Words[Count],7);
        for var J:=1 to 7 do
          if (I and (1 shl (7-J)))<>0 then Words[Count][J]:='1'
          else Words[Count][J]:='0';
        Found:=True;Break;
      end;
    Require(Found,
      'Відсутня точна pinned D7 українська клавіатурна проєкція');
    Inc(Count);
    At:=NextAt;
  end;
  SetLength(Words,Count);
  Result:=EncodeT5M(Words);
  Require(PhysicalD7ToUkrainian(Result,Alphabet)=Ukrainian,
    'D7↔T5M порушив точний UTF-8 round-trip');
end;

{ Тип: TD7Alphabet містить 128 рядків pinned «ук», не opcode.
  Source — тимчасовий host UTF-8 file buffer <=1 MiB.
  Вхід/вихід проєкції — RawByteString; фізичний вихід — packed T5M bytes.
  Temporary Words і UTF-8 рядки керуються FPC reference counting.
  Питання: 1) Чому ')' D7 не закриває D2? 2) Навіщо точна W7 ширина?
  3) Чому контрольний D7 без «ук» відхиляється? 4) Де єдина мовна влада? }
end.
