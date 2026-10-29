{ G6.50. Побітовий негативний доказ лише приватного контейнера EIR1.
  Мовні координати визначає pinned SENS; цей тест не виводить законів,
  не трактує EIR1 як .sens і не доводить виконуваність компілятора. }
program test_eir1_pobitovo;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.d2source, wsm.physloc, wsm.domain,
  wsm.bind, wsm.binarybind, wsm.exactir, wsm.exactirguard,
  wsm.exactirwire;

var
  Tables: TDomainSet;
  Source, Encoded, Mutated, Another: RawByteString;
  SourceIndex, ByteIndex, BitIndex, PrefixLen: SizeInt;
  Positive, Negative, BitFlips: SizeInt;
  ExpectedIR, ReturnedIR: TExactIR;
  Stats: TExactIRGuardStats;

procedure Demand(Condition: Boolean; const Why: String);
begin
  if not Condition then begin
    WriteLn(StdErr, 'EIR1-ПОБІТОВО-ПРОВАЛ: ', Why);
    Halt(1);
  end;
end;

function Pack(const Parts: array of RawByteString): RawByteString;
var
  Words: TExactWords;
  I: SizeInt;
begin
  SetLength(Words, Length(Parts));
  for I := 0 to High(Parts) do Words[I] := Parts[I];
  Result := EncodeT5M(Words);
end;

procedure RejectAltered(const Physical, Changed: RawByteString;
  const Reason: String);
var
  Failed: Boolean;
  Candidate: TExactIR;
begin
  { Навмисно забруднюємо вихід, щоб довести fail-closed скидання. }
  SetLength(Candidate.Nodes, 1);
  SetLength(Candidate.Roots, 1);
  Candidate.BoundLeaves := 9;
  Failed := False;
  try
    DecodePinnedExactIR(Physical, Tables, Changed, Candidate);
  except
    on E: EExactIRWireError do Failed := True;
  end;
  Demand(Failed, Reason + ': змінений EIR1 було прийнято');
  Demand((Length(Candidate.Nodes)=0) and
    (Length(Candidate.Roots)=0) and (Candidate.BoundLeaves=0),
    Reason + ': після відмови залишено частковий IR');
  Inc(Negative);
end;

procedure CheckOriginal(const Physical, Blob: RawByteString);
var
  CheckIR: TExactIR;
  CheckStats: TExactIRGuardStats;
  I: SizeInt;
begin
  Demand(Copy(Blob,1,4)='EIR1', 'відсутній приватний заголовок');
  Demand(Blob = EncodePinnedExactIR(Physical,Tables),
    'нерівні байти двох незалежних кодувань');
  BuildExactIR(Physical,Tables,ExpectedIR);
  DecodePinnedExactIR(Physical,Tables,Blob,CheckIR);
  VerifyExactIRStructure(CheckIR,CheckStats);
  Demand((CheckStats.Nodes=Length(ExpectedIR.Nodes)) and
    (CheckStats.Roots=Length(ExpectedIR.Roots)) and
    (CheckStats.BoundLeaves=ExpectedIR.BoundLeaves),
    'декодоване дерево не пройшло структуру');
  for I := 0 to High(ExpectedIR.Nodes) do
    Demand(CheckIR.Nodes[I].SubtreeEndExclusive=
      ExpectedIR.Nodes[I].SubtreeEndExclusive,
      'розбіжність піввідкритої межі піддерева');
  Inc(Positive);
end;

begin
  LoadPinnedDomains('external/sens',Tables);
  Positive:=0;
  Negative:=0;
  BitFlips:=0;

  for SourceIndex:=0 to 5 do begin
    case SourceIndex of
      0: Source:=Pack(['0','1']); { два корені в одному T5M байті }
      1: Source:=Pack(['10','111','00','0','000','01']);
      2: Source:=Pack(['10','1','0','11','000','01']); { вкладена D2 пара }
      3: Source:=Pack(['000000001']); { точні провідні нулі D9 }
      4: Source:=Pack(['0010110']); { D7 SYN тільки дані }
      5: Source:=Pack(['10','111','10','001','1','01','000','01','0']);
    end;
    Encoded:=EncodePinnedExactIR(Source,Tables);
    CheckOriginal(Source,Encoded);

    { Один змінений біт у КОЖНОМУ байті, навіть у високих байтах
      індексів, прапорців та provenance, не може бути легальним. }
    for ByteIndex:=1 to Length(Encoded) do
      for BitIndex:=0 to 7 do begin
        Mutated:=Encoded;
        Mutated[ByteIndex]:=AnsiChar(Ord(Mutated[ByteIndex]) xor
          (1 shl BitIndex));
        RejectAltered(Source,Mutated,
          'зразок='+IntToStr(SourceIndex)+
          ' байт='+IntToStr(ByteIndex-1)+
          ' біт='+IntToStr(BitIndex));
        Inc(BitFlips);
      end;

    { Жоден префікс і жоден зайвий байт не є повним EIR1. }
    for PrefixLen:=0 to Length(Encoded)-1 do
      RejectAltered(Source,Copy(Encoded,1,PrefixLen),
        'обрізання='+IntToStr(PrefixLen));
    RejectAltered(Source,Encoded+#0,'додано нульовий байт');
    RejectAltered(Source,Encoded+#255,'додано чужий байт');

    { Після всіх відмов повторне використання API мусить працювати. }
    CheckOriginal(Source,Encoded);
  end;

  { Однакова геометрія D2/кількість вузлів НЕ дає дозволу
    переносити приватний EIR1 на інший фізичний .sens. }
  Source:=Pack(['0','1']);
  Another:=Pack(['1','0']);
  Demand(Source<>Another,'змішано фізичні канони');
  Encoded:=EncodePinnedExactIR(Source,Tables);
  RejectAltered(Another,Encoded,'контейнер з іншої фізичної програми');
  CheckOriginal(Source,Encoded);

  Demand(BitFlips>6000,'неповний обхід кожного біта');
  WriteLn('EIR1-ПОБІТОВО-ГАРАЗД зразків=6 позитивних=',Positive,
    ' змінених-бітів=',BitFlips,' відхилень=',Negative,
    ' частковий-IR=ні');
  WriteLn('EIR1-ПОБІТОВО-МЕЖІ EIR1=приватний .sens=канонічний',
    ' SENS-REPL=не-викликано виконуваність=не-доведена');
end.
