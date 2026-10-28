{ G6.5: жодної семантичної перевірки мовних функцій.
  Тестує фізичний EIR1 ↔ source-exact IR, включно з ворожими байтами. }
program test_exactir_wire;
{$mode objfpc}{$H+}
uses SysUtils, wsm.t5m, wsm.physloc, wsm.d2source, wsm.domain,
  wsm.bind, wsm.binarybind, wsm.exactir, wsm.exactirwire;

var
  Tables: TDomainSet;
  ProgramIR: TExactIR;
  Words: TExactWords;
  Physical, Encoded, Damaged, Altered: RawByteString;
  I, J, Runs, Negatives: SizeInt;

procedure Check(Condition: Boolean; const MessageText: String);
begin
  if not Condition then begin
    WriteLn(StdErr, 'ТОЧНЕ-EIR1-ТЕСТ-ПОМИЛКА: ', MessageText);
    Halt(1);
  end;
end;

function Pack(const Parts: array of RawByteString): RawByteString;
var
  W: TExactWords;
  K: SizeInt;
begin
  SetLength(W, Length(Parts));
  for K := 0 to High(Parts) do W[K] := Parts[K];
  Result := EncodeT5M(W);
end;

function ChangeByte(const Data: RawByteString;
  Position: SizeInt; BitMask: Byte): RawByteString;
begin
  Check((Position > 0) and (Position <= Length(Data)),
    'поза тестовим контейнером');
  Result := Data;
  Result[Position] := AnsiChar(Ord(Data[Position]) xor BitMask);
end;

procedure CheckReject(const Source, Blob, Name: RawByteString);
var
  Rejected: Boolean;
begin
  SetLength(ProgramIR.Nodes, 1);
  SetLength(ProgramIR.Roots, 1);
  ProgramIR.BoundLeaves := 7;
  Rejected := False;
  try
    DecodePinnedExactIR(Source, Tables, Blob, ProgramIR);
  except
    on E: EExactIRWireError do Rejected := True;
    on E: EExactIRError do Rejected := True;
    on E: ET5MError do Rejected := True;
    on E: ED2PhysicalError do Rejected := True;
    on E: EBinaryBindError do Rejected := True;
    on E: EPhysicalLocationError do Rejected := True;
  end;
  Check(Rejected, String(Name) + ': підроблені дані прийнято');
  Check((Length(ProgramIR.Nodes)=0) and (Length(ProgramIR.Roots)=0) and
    (ProgramIR.BoundLeaves=0),
    String(Name) + ': після відмови опубліковано частковий IR');
  Inc(Negatives);
end;

procedure CheckRoundTrip(const Source: RawByteString);
var
  Blob, Duplicate: RawByteString;
  IR: TExactIR;
begin
  Blob := EncodePinnedExactIR(Source, Tables);
  Duplicate := EncodePinnedExactIR(Source, Tables);
  Check((Length(Blob) > 0) and (Blob = Duplicate),
    'недетерміновані байти приватного IR');
  DecodePinnedExactIR(Source, Tables, Blob, IR);
  Check((Length(IR.Nodes) > 0) and (Length(IR.Roots) > 0),
    'втрачено фізичне дерево');
  Check(Blob = EncodePinnedExactIR(Source, Tables),
    'порушено повторне byte-exact кодування');
  Inc(Runs);
end;

begin
  LoadPinnedDomains('external/sens', Tables);

  Physical := Pack(['10','111','00','0','000','01']);
  Encoded := EncodePinnedExactIR(Physical, Tables);
  Check(Length(Encoded)=16+4+4*46, 'точний розмір фіксованого EIR1');
  Check(Copy(Encoded,1,4)='EIR1', 'неправильне magic контейнера');
  DecodePinnedExactIR(Physical, Tables, Encoded, ProgramIR);
  Check((Length(ProgramIR.Nodes)=4) and
    (Length(ProgramIR.Roots)=1) and
    (ProgramIR.BoundLeaves=3), 'кореневі координати');
  Check((ProgramIR.Nodes[0].Kind=ikList) and
    (not ProgramIR.Nodes[0].HasKey) and
    (ProgramIR.Nodes[2].Kind=ikIdentity) and
    (ProgramIR.Nodes[3].Kind=ikEmpty) and
    SameKey(ProgramIR.Nodes[2].Key, ExactKey('0')) and
    SameKey(ProgramIR.Nodes[3].Key, ExactKey('000')),
    'відмінні точні D1:0 та D3:000');
  Check((ProgramIR.Nodes[3].Physical.TritStart=12) and
    (ProgramIR.Nodes[3].Physical.TritEnd=15),
    'збереження фізичних тритів');
  CheckRoundTrip(Physical);

  Altered := Pack(['0','1']);
  Check(Length(Altered)=1, 'два фізичні корені в одному байті');
  CheckRoundTrip(Altered);
  DecodePinnedExactIR(Altered, Tables,
    EncodePinnedExactIR(Altered, Tables), ProgramIR);
  Check((ProgramIR.Roots[0]=0) and (ProgramIR.Roots[1]=1) and
    (ProgramIR.Nodes[0].Physical.ByteStart=0) and
    (ProgramIR.Nodes[1].Physical.ByteStart=0) and
    (ProgramIR.Nodes[1].Physical.TritStart=2),
    'спільний байт та відмінні трит-адреси');

  CheckRoundTrip(Pack(['10','1','0','11','000','01']));
  CheckRoundTrip(Pack(['000000001']));
  CheckRoundTrip(Pack(['111']));

  { Усі числові поля першого вузла і прапорці: кожне
    підроблене поле має бути відхилене проти source-of-truth. }
  Negatives := 0;
  CheckReject(Physical, ChangeByte(Encoded,1,1), 'magic');
  CheckReject(Physical, ChangeByte(Encoded,5,1), 'кількість вузлів');
  CheckReject(Physical, ChangeByte(Encoded,9,1), 'кількість коренів');
  CheckReject(Physical, ChangeByte(Encoded,13,1), 'звязаних слів');
  CheckReject(Physical, ChangeByte(Encoded,17,1), 'індекс кореня');
  CheckReject(Physical, ChangeByte(Encoded,21,1), 'вид вузла');
  CheckReject(Physical, ChangeByte(Encoded,22,1), 'коренева адреса');
  CheckReject(Physical, ChangeByte(Encoded,26,1), 'батьківський індекс');
  CheckReject(Physical, ChangeByte(Encoded,30,1), 'порядок нащадка');
  CheckReject(Physical, ChangeByte(Encoded,34,1), 'глибина');
  CheckReject(Physical, ChangeByte(Encoded,38,1), 'номер слова');
  CheckReject(Physical, ChangeByte(Encoded,42,1), 'фізичний номер слова');
  CheckReject(Physical, ChangeByte(Encoded,46,1), 'початок трита');
  CheckReject(Physical, ChangeByte(Encoded,50,1), 'кінець трита');
  CheckReject(Physical, ChangeByte(Encoded,54,1), 'початок байта');
  CheckReject(Physical, ChangeByte(Encoded,58,1), 'кінець байта');
  CheckReject(Physical, ChangeByte(Encoded,62,1), 'підроблений EOF');
  CheckReject(Physical, ChangeByte(Encoded,63,1), 'підроблена викличність ключа');
  CheckReject(Physical, ChangeByte(Encoded,64,1), 'підроблена ширина ключа');
  CheckReject(Physical, ChangeByte(Encoded,65,1), 'підроблені біти ключа');
  { Доменні біти реального листка, не лише структурного вузла. }
  CheckReject(Physical, ChangeByte(Encoded,111,1), 'біти D3 листка');
  CheckReject(Physical, Copy(Encoded,1,Length(Encoded)-1), 'обрізаний файл');
  CheckReject(Physical, Encoded + #0, 'хвостовий байт');
  CheckReject(Pack(['10','111','00','1','000','01']), Encoded,
    'інший фізичний канон');
  CheckReject(#243, Encoded, 'пошкоджений канонічний T5M');

  SetLength(Tables[1], 0);
  CheckReject(Physical, Encoded, 'відсутній pinned домен');
  LoadPinnedDomains('external/sens', Tables);

  Runs := 5;
  for I := 1 to 64 do begin
    SetLength(Words, I+2);
    Words[0] := '10';
    for J := 1 to I do
      if (J mod 2)=0 then Words[J]:='0' else Words[J]:='1';
    Words[I+1] := '01';
    CheckRoundTrip(EncodeT5M(Words));
  end;
  WriteLn('ТОЧНЕ-EIR1-ГАРАЗД раундів=', Runs,
    ' негативних=', Negatives,
    ' точний-домен=так трит-байт=так підробки=відхилено');
  WriteLn('ТОЧНЕ-EIR1-МЕЖІ формат=приватний ',
    'семантична-викличність=не-перевірена codegen=ні Core4=не-виконується');
end.
