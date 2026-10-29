{ Нативні фізичні перевірки обмеженого двійкового допуску.
  Жодна українська чи англійська назва не маршрутизує семантику. }
program test_t5madmission;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.t5madmission;

procedure Check(Ok: Boolean; const Why: String);
begin
  if not Ok then begin
    WriteLn(StdErr,'ДОПУСК-Т5М-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;

function WordsOf(const A: array of RawByteString): TExactWords;
var I: SizeInt;
begin
  SetLength(Result,Length(A));
  for I:=0 to High(A) do Result[I]:=A[I];
end;

function FromPhysical(const Physical: RawByteString): TD2Document;
var S: TMemoryStream;
begin
  S:=TMemoryStream.Create;
  try
    if Length(Physical)>0 then S.WriteBuffer(Physical[1],Length(Physical));
    S.Position:=0;
    Result:=ReadCheckedD2Stream(S);
  finally S.Free; end;
end;

procedure SameNode(A,B: TD2Node);
var I: SizeInt;
begin
  Check((A<>nil) and (B<>nil),'вузол відсутній');
  Check((A.Kind=B.Kind) and (A.WordIndex=B.WordIndex) and
        (A.Width=B.Width) and (A.Bits=B.Bits),
        'втрата ширини, бітів або джерельного індексу');
  Check(Length(A.Children)=Length(B.Children),'кількість нащадків');
  for I:=0 to High(A.Children) do SameNode(A.Children[I],B.Children[I]);
end;

procedure CompareValid(const Input: array of RawByteString);
var A,B: TD2Document; Data: RawByteString; I:SizeInt;
begin
  Data:=EncodeT5M(WordsOf(Input));
  A:=ReadD2T5M(Data);
  B:=FromPhysical(Data);
  try
    Check(Length(A.Roots)=Length(B.Roots),'кількість коренів');
    for I:=0 to High(A.Roots) do SameNode(A.Roots[I],B.Roots[I]);
  finally A.Free; B.Free; end;
end;

procedure RejectPhysical(const Physical: RawByteString; const Why: String);
var D: TD2Document; Rejected: Boolean;
begin
  D:=nil;
  Rejected:=False;
  try
    D:=FromPhysical(Physical);
  except
    on E:ET5MAdmissionError do Rejected:=True;
    on E:ET5MError do Rejected:=True;
    on E:ED2SourceError do Rejected:=True;
  end;
  D.Free;
  Check(Rejected,Why+' прийнято');
end;

procedure RejectWords(const Words: array of RawByteString; const Why: String);
begin
  RejectPhysical(EncodeT5M(WordsOf(Words)),Why);
end;


{ G1.30: host-чита́ння навмисно повертає лише 1..5 байтів,
  хоча T5M слова та D2 дужки перетинають межі Read. Потік borrowed,
  не вимагається Seek і не передає жодного викличного закону. }
type
  TPartialReadStream = class(TMemoryStream)
  private
    FChunk: Longint;
    FReadCalls: SizeInt;
  public
    constructor Create(const Physical: RawByteString; ChunkSize: Longint);
    function Read(var Buffer; Count: Longint): Longint; override;
    property ReadCalls: SizeInt read FReadCalls;
  end;

constructor TPartialReadStream.Create(const Physical: RawByteString;
  ChunkSize: Longint);
begin
  inherited Create;
  if ChunkSize < 1 then raise Exception.Create('нульова фізична частина');
  FChunk := ChunkSize;
  FReadCalls := 0;
  if Length(Physical)>0 then WriteBuffer(Physical[1],Length(Physical));
  Position := 0;
end;

function TPartialReadStream.Read(var Buffer; Count: Longint): Longint;
begin
  if Count>FChunk then Count:=FChunk;
  Inc(FReadCalls);
  Result:=inherited Read(Buffer,Count);
end;

procedure CompareWideLocated(const Physical: RawByteString;
  ChunkSize: Longint; ExpectedWords: SizeInt);
var Stream: TPartialReadStream;
    D, Reference: TD2Document;
    Located, Direct: TPhysicalWordSpans;
    I: SizeInt;
begin
  Stream := TPartialReadStream.Create(Physical,ChunkSize);
  D:=nil; Reference:=nil;
  try
    Reference:=ReadD2WideWithPhysicalLocations(Physical,Direct);
    D:=ReadCheckedD2WideLocatedStream(Stream,Located);
    Check(Stream.ReadCalls > 1,'часткове читання не виконано');
    Check((Length(Located)=ExpectedWords) and
      (Length(Direct)=Length(Located)) and
      (Length(D.Roots)=Length(Reference.Roots)),
      'не збігаються wide D2 форми/слова');
    for I:=0 to High(Located) do
      Check((Located[I].WordIndex=Direct[I].WordIndex) and
        (Located[I].TritStart=Direct[I].TritStart) and
        (Located[I].TritEnd=Direct[I].TritEnd) and
        (Located[I].ByteStart=Direct[I].ByteStart) and
        (Located[I].ByteEnd=Direct[I].ByteEnd) and
        (Located[I].IsEOF=Direct[I].IsEOF),
        'втрата exact фізичної адреси при partial Read');
    for I:=0 to High(D.Roots) do
      Check((D.Roots[I].Width=Reference.Roots[I].Width) and
        (D.Roots[I].Bits=Reference.Roots[I].Bits) and
        (D.Roots[I].Kind=Reference.Roots[I].Kind) and
        (D.Roots[I].WordIndex=Reference.Roots[I].WordIndex),
        'потоковий D2 AST не тотожний чинному wide parser');
  finally
    D.Free; Reference.Free; Stream.Free;
  end;
end;

procedure RejectWideLocated(const Physical: RawByteString;
  ChunkSize: Longint; const Problem: String; ExpectEOF: Boolean);
var Stream:TPartialReadStream;
    D:TD2Document;
    Spans:TPhysicalWordSpans;
    Caught, FoundEOF:Boolean;
    First:TExactWords;
begin
  Stream:=TPartialReadStream.Create(Physical,ChunkSize);
  D:=nil;
  Caught:=False; FoundEOF:=False;
  { Посіяти попередні правильні адреси й довести fail-closed out. }
  DecodeT5MWithLocations(EncodeT5M(WordsOf(['0'])),First,Spans);
  Check(Length(Spans)=1,'початковий wide span порожній');
  try
    try D:=ReadCheckedD2WideLocatedStream(Stream,Spans);
    except
      on E:ET5MAdmissionError do Caught:=True;
      on E:ET5MError do Caught:=True;
      on E:ED2PhysicalError do begin
        Caught:=True;
        FoundEOF:=E.Span.IsEOF and
          (E.Span.ByteStart=Length(Physical));
      end;
    end;
    Check(Caught and (D=nil) and (Length(Spans)=0),
      Problem+': помилково прийнято або залишено попередні адреси');
    if ExpectEOF then Check(FoundEOF,
      Problem+': втрачено фізичну EOF-адресу');
  finally
    D.Free; Stream.Free;
  end;
end;

procedure CheckWideLocatedStream;
var Wide:TExactWords; Good,Corrupted:RawByteString;
    D:TD2Document;
    Spans:TPhysicalWordSpans;
    Chunk:SizeInt;
    Caught:Boolean;
begin
  Wide:=WordsOf(['10',RawByteString(StringOfChar('1',12)),
    '00',RawByteString(StringOfChar('0',24)),'01',
    RawByteString(StringOfChar('0',191)+'1')]);
  Good:=EncodeT5M(Wide);
  for Chunk:=1 to 5 do CompareWideLocated(Good,Chunk,6);
  CompareWideLocated(EncodeT5M(WordsOf(['0','1'])),1,2);

  { Фізичне D2 джерело: один список W12/W24 і opaque W192 корінь,
    з exact leading zeros. Жоден із Wn тут НЕ набуває домену Dn. }
  D:=nil;
  D:=ReadD2WideWithPhysicalLocations(Good,Spans);
  try
    Check((Length(D.Roots)=2) and
      (D.Roots[0].Kind=dkList) and
      (D.Roots[0].Children[0].Width=12) and
      (D.Roots[0].Children[1].Width=24) and
      (D.Roots[1].Width=192) and
      (D.Roots[1].Bits=Wide[5]) and
      (Spans[5].TritEnd>Spans[4].TritEnd),
      'втрачено широкий D2 список або W192 біти');
  finally D.Free end;

  RejectWideLocated(EncodeT5M(WordsOf(['10',
    RawByteString(StringOfChar('1',12))])),1,
    'пізня D2 EOF помилка',True);
  RejectWideLocated(EncodeT5M(WordsOf(['01'])),3,
    'передчасне D2 закриття',False);
  RejectWideLocated(EncodeT5M(WordsOf([
    RawByteString(StringOfChar('1',193))])),2,
    'W193 поза широкою фізичною квотою',False);
  Corrupted:=Good+#243;
  RejectWideLocated(Corrupted,1,'пізній заборонений байт T5M',False);
  RejectWideLocated(#242,1,'неправильне T5M заповнення',False);
  RejectWideLocated('',1,'порожній фізичний stream',False);

  DecodeT5MWithLocations(EncodeT5M(WordsOf(['0'])),Wide,Spans);
  D:=nil;Caught:=False;
  try D:=ReadCheckedD2WideLocatedStream(nil,Spans);
  except on E:ET5MAdmissionError do Caught:=True end;
  D.Free;
  Check(Caught and (Length(Spans)=0),'nil потік залишив адреси');

  { Після серії відмов читання іншого реального потоку працює знову. }
  CompareWideLocated(Good,1,6);
  WriteLn('ПОТІК-D2-АДРЕСИ-ГАРАЗД FPC=справжній ',
    'chunks=1/2/3/4/5 W12/W24/W192=opaque ',
    'T5M=канонічний trit-byte=точно EOF=адресовано ',
    'W193/bad-byte/padding/nil=відхилено out=атомарно');
end;

{ Типи/життя: Stream owned локально і Free у finally;
  D/Reference owned TD2Document, Free; Spans owned dynamic array;
  результат тесту — лише host істина, не D1.
  Питання: 1) Чому chunk 1 байт не зобов'язаний означати 1 слово?
  2) Чому W192 ще не D192? 3) Чому out Spans очищується до читання?
  4) Чому EOF byte span нульовий? 5) Який parser визначає D2? }

var
  S: TMemoryStream;
  D: TD2Document;
  W: TExactWords;
  I: SizeInt;
begin
  CompareValid(['10','111','00','1','000','01']);
  CompareValid(['10','1','11','0','01']);
  CompareValid(['0','00','1']);
  CompareValid(['101010101']);
  CompareValid(['000000000']);
  D:=FromPhysical(EncodeT5M(WordsOf(['10','111','1','000','01'])));
  try
    Check(Length(D.Roots)=1,'одна форма');
    Check(D.Roots[0].Kind=dkList,'фізичний відкритий D2 список');
    Check(Length(D.Roots[0].Children)=3,'три елементи');
    Check((D.Roots[0].Children[0].Bits='111') and
      (D.Roots[0].Children[0].Width=3),'точна D3-координата');
    Check((D.Roots[0].Children[1].Bits='1') and
      (D.Roots[0].Children[1].Width=1),'точна D1-координата');
    Check(D.Roots[0].Children[2].Kind=dkEmpty,'D3:000 окремо від D1:0');
  finally D.Free; end;

  RejectPhysical('','порожній потік');
  RejectPhysical(#243,'заборонений байт 243');
  RejectPhysical(#255,'заборонений байт 255');
  RejectPhysical(#242,'лише заповнення');
  RejectPhysical(#162,'початковий роздільник');
  RejectPhysical(#72,'подвійний роздільник');
  RejectPhysical(#80#0,'внутрішнє повторне заповнення');
  RejectWords(['0000000000'],'слово W10 поза D2');
  RejectWords(['00000000000'],'слово W11 поза D2');
  RejectWords(['01'],'неприпустиме закриття D2');
  RejectWords(['10','1'],'незавершений D2 список');
  RejectWords(['10','11','1','01'],'крапка D2 без голови');

  { 100001 слів W1: фізичний T5M допустимий, але D2 бюджету недостатньо.
    Відхилити ДО матеріалізації сотні тисяч вузлів AST. }
  SetLength(W,MaxD2Words+1);
  for I:=0 to High(W) do W[I]:='1';
  RejectPhysical(EncodeT5M(W),'перевищено ліміт кількості слів');

  S:=TMemoryStream.Create;
  try
    D:=nil;
    try D:=ReadCheckedD2Stream(nil);
    except on E:ET5MAdmissionError do begin end; end;
    Check(D=nil,'відсутній потік прийнято');
  finally S.Free; end;

  CheckWideLocatedStream;
  WriteLn('ДВІЙКОВИЙ-ДОПУСК-ГАРАЗД: FPC=справжній T5M=чинний ',
    'D2=чинний W1–W9=строго слів=обмежено AST=без-часткового ',
    'українська=проєкція семантика=не-доведено');
end.
