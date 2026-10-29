program test_wideirguard;
{$mode objfpc}{$H+}{$codepage utf8}
uses {$ifdef unix}cwstring,{$endif}
  SysUtils,Classes,wsm.t5m,wsm.d2source,wsm.physloc,
  wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard;
var
  Tables:TDomainSet;
  Base,Mutated,Other:TWideIR;
  Stats:TWideIRGuardStats;
  Words:TExactWords;
  F:TFileStream;
  Physical:RawByteString;
  I,RejectedCount,Count24:SizeInt;

procedure Demand(Condition:Boolean;const Why:String);
begin
  if not Condition then begin
    WriteLn(StdErr,'ШИРОКИЙ-СТОРОЖ-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;

function MakeWords(const Items:array of RawByteString):TExactWords;
var J:SizeInt;
begin
  SetLength(Result,Length(Items));
  for J:=0 to High(Items) do Result[J]:=Items[J];
end;

function WideBits(Width:SizeInt):RawByteString;
begin
  SetLength(Result,Width);
  FillChar(Result[1],Width,Ord('0'));
  Result[Width]:='1';
end;

procedure MustReject(const Broken:TWideIR;const Why:String);
var Got:Boolean; S:TWideIRGuardStats;
begin
  FillChar(S,SizeOf(S),$7F);
  Got:=False;
  try VerifyWideIRStructure(Broken,S);
  except on E:EWideIRGuardError do Got:=True; end;
  Demand(Got,Why+' не відхилено');
  Demand((S.Nodes=0) and (S.Roots=0) and
    (S.PhysicalLeaves=0) and (S.OpaqueLeaves=0) and
    (S.MaxDepth=0),Why+' частково оприлюднило статистику');
  Inc(RejectedCount);
end;

procedure MutateAndReject(VariantNo:SizeInt);
begin
  Mutated:=Base;
  Mutated.Nodes:=Copy(Base.Nodes,0,Length(Base.Nodes));
  Mutated.Roots:=Copy(Base.Roots,0,Length(Base.Roots));
  case VariantNo of
    0: Mutated.Nodes[2].Bits[8]:='2';
    1: Mutated.Nodes[2].HasPinnedKey:=True;
    2: Mutated.Nodes[1].NarrowKey:=ExactKey('0');
    3: Mutated.Nodes[3].Kind:=wkAtom;
    4: Inc(Mutated.Nodes[3].Physical.ByteEnd);
    5: Inc(Mutated.Nodes[2].Physical.TritStart);
    6: Mutated.Nodes[1].ChildIndex:=5;
    7: begin Mutated.Nodes[2].ParentIndex:=1;
             Mutated.Nodes[2].Depth:=2; end;
    8: Mutated.Nodes[0].RootIndex:=5;
    9: Mutated.Nodes[0].OwnWord:=False;
   10: Inc(Mutated.PhysicalLeaves);
   11: Inc(Mutated.OpaqueLeaves);
   12: Mutated.Roots[0]:=2;
   13: Mutated.Nodes[1].Physical.WordIndex:=0;
   14: Mutated.Nodes[3].Width:=2;
   15: Mutated.Nodes[2].NarrowKey.Width:=1;
  end;
  MustReject(Mutated,'мутація '+IntToStr(VariantNo));
end;

{ Копії вузлів/коренів належать Mutated; Bits лишається керованим
  точним рядком FPC. Чужий позитивний Other не змінюється мутаціями. }
procedure CopyOther;
begin
  Mutated:=Other;
  Mutated.Nodes:=Copy(Other.Nodes,0,Length(Other.Nodes));
  Mutated.Roots:=Copy(Other.Roots,0,Length(Other.Roots));
end;

procedure MoveSpan(var Node:TWideIRNode; StartTrit:SizeInt);
var Width:SizeInt;
begin
  Width:=Node.Physical.TritEnd-Node.Physical.TritStart;
  Node.Physical.TritStart:=StartTrit;
  Node.Physical.TritEnd:=StartTrit+Width;
  Node.Physical.ByteStart:=StartTrit div 5;
  Node.Physical.ByteEnd:=(Node.Physical.TritEnd-1) div 5+1;
end;

procedure CheckPhysicalOrder;
var Before,Width,J:SizeInt;
    Saved:TWideIRNode;
begin
  Before:=RejectedCount;
  Words:=MakeWords([WideBits(192),WideBits(192)]);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Roots=2) and (Stats.OpaqueLeaves=2),
    'два фізично різні W192 корені');
  CopyOther;
  MoveSpan(Mutated.Nodes[1],Mutated.Nodes[0].Physical.TritStart);
  MustReject(Mutated,'два W192 корені зайняли ті самі трити');
  CopyOther;
  MoveSpan(Mutated.Nodes[1],Mutated.Nodes[0].Physical.TritEnd-1);
  MustReject(Mutated,'W192 корені перекрили один трит');
  CopyOther;
  MoveSpan(Mutated.Nodes[0],Other.Nodes[1].Physical.TritStart);
  MoveSpan(Mutated.Nodes[1],Other.Nodes[0].Physical.TritStart);
  MustReject(Mutated,'зворотний тритовий порядок W192 коренів');
  CopyOther;
  Mutated.Nodes[0].WordIndex:=2;
  Mutated.Nodes[0].Physical.WordIndex:=2;
  Mutated.Nodes[1].WordIndex:=1;
  Mutated.Nodes[1].Physical.WordIndex:=1;
  MustReject(Mutated,'зворотний WordIndex при зростанні тритів');

  Words:=MakeWords(['10','1',WideBits(12),'000','01']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  CopyOther;
  MoveSpan(Mutated.Nodes[2],Mutated.Nodes[1].Physical.TritStart);
  MustReject(Mutated,'широке слово перекрило вузький листок');
  CopyOther;
  Saved:=Mutated.Nodes[1];
  Mutated.Nodes[1]:=Mutated.Nodes[3];
  Mutated.Nodes[3]:=Saved;
  Mutated.Nodes[1].ChildIndex:=0;
  Mutated.Nodes[3].ChildIndex:=2;
  MustReject(Mutated,'переставлені фізичні слова зі збереженим preorder');
  CopyOther;
  MoveSpan(Mutated.Nodes[0],1000);
  MustReject(Mutated,'D2 OPEN звичайного списку після його листків');

  Words:=MakeWords(['10','1','11',WideBits(24),'01',
    '00','10','0','11',WideBits(192),'01']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Roots=2) and (Stats.Nodes=6),
    'дві незалежні фізичні пари з D2:00 між ними');
  CopyOther;
  Mutated.Nodes[3].WordIndex:=Mutated.Nodes[0].WordIndex;
  Mutated.Nodes[3].Physical:=Mutated.Nodes[0].Physical;
  MustReject(Mutated,'дві фізичні пари повторили одну опору OPEN');
  CopyOther;
  MoveSpan(Mutated.Nodes[0],1000);
  MustReject(Mutated,'опора першої пари фізично після її листків');

  Words:=MakeWords(['10','10','1','11',WideBits(24),'01','11',
    '10','0',WideBits(192),'11','000','01','01']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Nodes=9) and (Stats.PhysicalLeaves=5) and
    (Stats.OpaqueLeaves=2) and (Other.Nodes[1].Kind=wkPair) and
    (Other.Nodes[4].Kind=wkPair) and (Other.Nodes[6].Kind=wkPair) and
    (Other.Nodes[4].WordIndex<>Other.Nodes[0].WordIndex) and
    (Other.Nodes[6].WordIndex=Other.Nodes[4].WordIndex),
    'вкладені фізичні пари та спільна права похідна опора');
  CopyOther;
  Mutated.Nodes[1].WordIndex:=Mutated.Nodes[0].WordIndex;
  Mutated.Nodes[1].Physical:=Mutated.Nodes[0].Physical;
  MustReject(Mutated,'ліва пара привласнила опору батька');
  CopyOther;
  MoveSpan(Mutated.Nodes[6],Mutated.Nodes[6].Physical.TritStart+1);
  MustReject(Mutated,'спільне слово опори з різними тритами');
  CopyOther;
  Mutated.Nodes[6].WordIndex:=Mutated.Nodes[5].WordIndex;
  Mutated.Nodes[6].Physical.WordIndex:=Mutated.Nodes[5].WordIndex;
  MustReject(Mutated,'похідна пара привласнила WordIndex листка');
  CopyOther;
  MoveSpan(Mutated.Nodes[4],Mutated.Nodes[3].Physical.TritStart);
  MustReject(Mutated,'нова фізична опора перекрила попередній листок');
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Nodes=9) and (Stats.OpaqueLeaves=2),
    'позитивний оригінал і відновлення після мутацій');

  { Позитиви перевіряють точні spans, а не неперетин БАЙТІВ.
    Пропуски D2:00 не зобов'язують IR до суміжних WordIndex. }
  Words:=MakeWords(['0','1']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Other.Nodes[0].Physical.ByteStart=0) and
    (Other.Nodes[1].Physical.ByteStart=0) and
    (Other.Nodes[0].Physical.TritEnd<=Other.Nodes[1].Physical.TritStart),
    'окремі D1 трити у спільному байті');
  Words:=MakeWords(['00','10','00','1','00',WideBits(192),'00','01','00']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Other.Nodes[0].WordIndex=2) and
    (Other.Nodes[1].WordIndex=4) and (Other.Nodes[2].WordIndex=6),
    'фізичні пропуски до і всередині форми');
  for Width:=10 to 192 do begin
    Words:=MakeWords(['10',WideBits(Width),'11','000','01']);
    BuildWideIR(EncodeT5M(Words),Tables,Other);
    VerifyWideIRStructure(Other,Stats);
    Demand((Stats.OpaqueLeaves=1) and (Other.Nodes[1].Width=Width) and
      (Other.Nodes[1].Bits=WideBits(Width)),
      'кожна точна ширина W10..W192 як непрозорий payload');
    for J:=0 to High(Other.Nodes) do
      Demand(Other.Nodes[J].Physical.TritEnd>
        Other.Nodes[J].Physical.TritStart,'непорожній точний span');
  end;
  Demand(RejectedCount-Before=13,'тринадцять міжвузлових негативів');
  WriteLn('ШИРОКИЙ-ПОРЯДОК-ГАРАЗД: ',
    'W10-W192=183 негативних=',RejectedCount-Before+1,
    ' спільний-байт=так похідні-пари=так відновлення=так');
end;

begin
  RejectedCount:=0;
  Demand(ParamCount=1,'потрібний справжній pinned .sens свідок');
  LoadPinnedDomains('external/sens',Tables);
  Words:=MakeWords(['10','1',WideBits(24),'000','01']);
  BuildWideIR(EncodeT5M(Words),Tables,Base);
  VerifyWideIRStructure(Base,Stats);
  Demand((Stats.Nodes=4) and (Stats.Roots=1) and
    (Stats.PhysicalLeaves=3) and (Stats.OpaqueLeaves=1) and
    (Stats.MaxDepth=1),'позитивне дерево D1/D3/W24');
  for I:=0 to 15 do MutateAndReject(I);

  { Окремі коректні spans не доводять фізичну відмінність слів.
    Копіюємо Nodes явно: керовані масиви FPC не мають copy-on-write. }
  Words:=MakeWords([WideBits(192),WideBits(192)]);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Mutated:=Other;
  Mutated.Nodes:=Copy(Other.Nodes,0,Length(Other.Nodes));
  Mutated.Nodes[1].WordIndex:=Mutated.Nodes[0].WordIndex;
  Mutated.Nodes[1].Physical.WordIndex:=Mutated.Nodes[0].WordIndex;
  MustReject(Mutated,'два W192 корені з одним фізичним WordIndex');
  CheckPhysicalOrder;

  Words:=MakeWords(['10','10','1','01','10','1','01','01']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Nodes=5) and (Stats.MaxDepth=2),'вкладене дерево');
  Mutated:=Other;
  Mutated.Nodes:=Copy(Other.Nodes,0,Length(Other.Nodes));
  Mutated.Nodes[4].ParentIndex:=1;
  Mutated.Nodes[4].ChildIndex:=1;
  MustReject(Mutated,'повернення у закрите піддерево');

  Words:=MakeWords(['10',WideBits(12),WideBits(24),
     WideBits(48),WideBits(96),WideBits(192),WideBits(13),'01']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Nodes=7) and (Stats.OpaqueLeaves=6),
    'широкі фізичні слова без семантичного допуску');
  Words:=MakeWords(['10','1','11',WideBits(24),'01']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Nodes=3) and (Other.Nodes[0].Kind=wkPair),
    'похідна фізична пара');
  Words:=MakeWords(['0','1']);
  BuildWideIR(EncodeT5M(Words),Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Demand((Stats.Nodes=2) and (Stats.Roots=2),
    'два фізичні корені в одному T5M байті');

  F:=TFileStream.Create(ParamStr(1),fmOpenRead);
  try
    Demand((F.Size>0) and (F.Size<=MAX_T5M_FILE_BYTES),
      'неприпустимий розмір pinned файлу');
    SetLength(Physical,SizeInt(F.Size));
    F.ReadBuffer(Physical[1],Length(Physical));
  finally F.Free; end;
  BuildWideIR(Physical,Tables,Other);
  VerifyWideIRStructure(Other,Stats);
  Count24:=0;
  for I:=0 to High(Other.Nodes) do
    if (Other.Nodes[I].Kind=wkAtom) and
       (Other.Nodes[I].Width=24) then begin
      Demand(not Other.Nodes[I].HasPinnedKey,
        'ширина свідка не є числовим законом');
      Inc(Count24);
    end;
  Demand(Count24=2,'немає двох pinned W24');
  WriteLn('ШИРОКИЙ-СТОРОЖ-ГАРАЗД: FPC=реальний ',
    'мутацій=',RejectedCount,' D12-D192=opaque ',
    'D2=preorder pinned-W24=',Count24,' GUI=перед-допуском');
end.
