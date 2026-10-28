program test_wideirguard;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.d2source,wsm.physloc,
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
