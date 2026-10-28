program test_wideir;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.d2source,wsm.physloc,
  wsm.domain,wsm.bind,wsm.wideir;
var
  Tables:TDomainSet;
  Words:TExactWords;
  R:TWideIR;
  I,J,Count24:SizeInt;
  Rejected:Boolean;
  Physical:RawByteString;
  Stream:TFileStream;

procedure Demand(B:Boolean;const Why:String);
begin
  if not B then begin WriteLn(StdErr,'ШИРОКЕ-IR-ПОМИЛКА: ',Why); Halt(1); end;
end;
function MakeWords(const A:array of RawByteString):TExactWords;
var K:SizeInt;
begin
  SetLength(Result,Length(A));
  for K:=0 to High(A) do Result[K]:=A[K];
end;
function BitsOf(Width:SizeInt;Last:AnsiChar):RawByteString;
begin
  SetLength(Result,Width);
  if Width>0 then FillChar(Result[1],Width,Ord('0'));
  if Width>0 then Result[Width]:=Last;
end;
procedure Reject(const P:RawByteString;const Why:String);
begin
  SetLength(R.Nodes,1);SetLength(R.Roots,1);
  R.PhysicalLeaves:=5;R.OpaqueLeaves:=3;
  Rejected:=False;
  try BuildWideIR(P,Tables,R);
  except on E:Exception do
    Rejected:=(E is ET5MError) or (E is ED2SourceError) or
      (E is EWideIRError) or (E is EPhysicalLocationError);
  end;
  Demand(Rejected,Why+' прийнято');
  Demand((Length(R.Nodes)=0) and (Length(R.Roots)=0) and
    (R.PhysicalLeaves=0) and (R.OpaqueLeaves=0),
    Why+' залишила часткові вузли');
end;

begin
  LoadPinnedDomains('external/sens',Tables);
  Words:=MakeWords(['10','111','00','0','000','01']);
  BuildWideIR(EncodeT5M(Words),Tables,R);
  Demand((Length(R.Nodes)=4) and (Length(R.Roots)=1) and
    (R.PhysicalLeaves=3) and (R.OpaqueLeaves=0),
    'вузька сумісність');
  Demand((R.Nodes[0].Kind=wkList) and (not R.Nodes[0].HasPinnedKey) and
    (R.Nodes[1].HasPinnedKey) and
    SameKey(R.Nodes[1].NarrowKey,ExactKey('111')) and
    (R.Nodes[2].Bits='0') and (R.Nodes[2].Width=1) and
    (R.Nodes[3].Kind=wkEmpty) and (R.Nodes[3].Bits='000'),
    'D1:0 не тотожний D3:000, D2 не є викликом');

  Words:=MakeWords(['10',BitsOf(12,'1'),BitsOf(24,'1'),
     BitsOf(48,'1'),BitsOf(96,'1'),BitsOf(192,'1'),
     BitsOf(13,'1'),'01']);
  Physical:=EncodeT5M(Words);
  BuildWideIR(Physical,Tables,R);
  Demand((Length(R.Nodes)=8) and (R.OpaqueLeaves=6) and
    (R.PhysicalLeaves=6) and (Length(R.Roots)=1),'D12+ вузли');
  for I:=1 to 6 do begin
    Demand((R.Nodes[I].WordIndex=I+1) and (R.Nodes[I].ParentIndex=0) and
      (R.Nodes[I].RootIndex=0) and (R.Nodes[I].Depth=1) and
      (R.Nodes[I].ChildIndex=I-1),'порядок дерева');
    Demand((not R.Nodes[I].HasPinnedKey) and (R.Nodes[I].Kind=wkAtom) and
      (R.Nodes[I].Width=Length(Words[I])) and (R.Nodes[I].Bits=Words[I]) and
      (R.Nodes[I].Physical.TritEnd-R.Nodes[I].Physical.TritStart=
        R.Nodes[I].Width),'opaque без числової семантики');
    if I>1 then
      Demand(R.Nodes[I].Physical.TritStart>
        R.Nodes[I-1].Physical.TritEnd,'фізичні роздільники');
  end;
  Demand((R.Nodes[6].Width=13) and not R.Nodes[6].HasPinnedKey,
    'W13 не має автоматичного D13 закону');
  Demand(R.Nodes[5].Width=192,'без обрізання D192 до host Int64');
  Demand(EncodeT5M(Words)=Physical,'побітовий фізичний round-trip');

  Words:=MakeWords(['10','1','11',BitsOf(24,'0'),'01']);
  BuildWideIR(EncodeT5M(Words),Tables,R);
  Demand((Length(R.Nodes)=3) and (R.Nodes[0].Kind=wkPair) and
    (not R.Nodes[0].OwnWord) and (R.Nodes[0].WordIndex=1) and
    (R.Nodes[1].HasPinnedKey) and (R.Nodes[2].Width=24) and
    (R.Nodes[2].ParentIndex=0) and
    (not R.Nodes[2].HasPinnedKey),
    'крапкова пара D2 без власного фізичного токена');

  Words:=MakeWords(['0','1']);
  Demand(Length(EncodeT5M(Words))=1,'два слова в байті');
  BuildWideIR(EncodeT5M(Words),Tables,R);
  Demand((Length(R.Roots)=2) and (R.Roots[0]=0) and
    (R.Roots[1]=1) and (R.Nodes[0].Physical.ByteStart=0) and
    (R.Nodes[1].Physical.ByteStart=0) and
    (R.Nodes[1].Physical.TritStart=2),'спільний фізичний байт');

  Reject(#243,'некоректний байт T5M');
  Reject(#242,'неприпустиме заповнення');
  Reject(EncodeT5M(MakeWords(['01'])),'закривання без початку');
  Reject(EncodeT5M(MakeWords(['10','1'])),'незакритий D2');
  Reject(EncodeT5M(MakeWords(['10','11','1','01'])),'крапка без голови');
  Reject(EncodeT5M(MakeWords([BitsOf(193,'1')])),
    'надмірна фізична ширина 193');
  SetLength(Tables[3],0);
  Reject(EncodeT5M(MakeWords(['1'])),'неповні pinned домени');
  LoadPinnedDomains('external/sens',Tables);

  { Бюджет IR окремий від фізичного reader. }
  SetLength(Words,MaxWideIRNodes+1);
  for I:=0 to High(Words) do Words[I]:='1';
  Reject(EncodeT5M(Words),'понад ліміт вузлів');

  { НЕ синтетика: pinned root SENS має два точні 24-бітні слова.
    Назва файлу "d12" не робить їх 12-бітними. }
  Demand(ParamCount=1,'обов’язковий реальний pinned свідок');
  Stream:=TFileStream.Create(ParamStr(1),fmOpenRead);
  try
    Demand((Stream.Size>0) and (Stream.Size<=MAX_T5M_FILE_BYTES),
      'розмір pinned свідка');
    SetLength(Physical,Stream.Size);
    Stream.ReadBuffer(Physical[1],Length(Physical));
  finally Stream.Free; end;
  BuildWideIR(Physical,Tables,R);
  Count24:=0;
  for J:=0 to High(R.Nodes) do
    if (R.Nodes[J].Kind=wkAtom) and (R.Nodes[J].Width=24) then begin
      Demand(not R.Nodes[J].HasPinnedKey,'заміна D24 на вузький закон');
      Demand((R.Nodes[J].Bits=BitsOf(24,'1')) or
        (R.Nodes[J].Bits=BitsOf(22,'0')+'11'),
        'числовий pinned свідок — фізичні біти без зміни');
      Inc(Count24);
    end;
  Demand(Count24=2,'потрібні два фізичні D24 зі справжнього SENS');
  WriteLn('ШИРОКЕ-IR-ГАРАЗД: D12,D24,D48,D96,D192=точні W13=opaque ',
    'джерело=pinned-сенс D24=2 відмови=атомарні закони=не-додані');
end.
