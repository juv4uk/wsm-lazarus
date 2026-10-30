{ G6.181 — лише механізм pinned source-backed Core1 «частка» → справжній ELF.
  Ні одного бібліотечного тіла SENS тут не визначено. Фізичний двійковий
  Core1 (T5M) і ратифіковані D4/D5/D7/D12+ залишаються єдиним авторитетом. }
unit wsm.core1chastkaadaptive;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ECore1ChastkaAdaptive=class(Exception);
function BuildPinnedCore1AdaptiveQuotELF(const RepoRoot:String):RawByteString;
implementation
uses Classes,wsm.t5m,wsm.d2source,wsm.core1selektor,
     wsm.numericplane,wsm.irwidequot,wsm.irwidefront,
     wsm.elfd12quotadaptive,wsm.elfgeometry;
const MaxCore1Bytes=4*1024*1024;

procedure Need(OK:Boolean;const Reason:String);
begin
  if not OK then raise ECore1ChastkaAdaptive.Create(Reason);
end;

{ Node borrowed from TD2Document; result owned exact D7 bits, not UTF-8.
  No lexical projection becomes an opcode or a semantic dispatch.
  Questions: what is the lifetime of Node? Why preserve leading zeros?
  Why is Width=7 not enough without the bits? }
function D7Name(const Node:TD2Node):RawByteString;
var I:SizeInt; C:TD2Node;
begin
  Need((Node<>nil) and (Node.Kind=dkList) and
       (Length(Node.Children)>0) and (Length(Node.Children)<=256),
       'відсутня точна послідовність D7');
  Result:='';
  for I:=0 to High(Node.Children) do begin
    C:=Node.Children[I];
    Need((C<>nil) and (C.Kind=dkIdentity) and
         (C.Width=7) and (Length(C.Bits)=7),
         'пошкоджено фізичний D7-гліф');
    Result:=Result+C.Bits;
  end;
end;

{ Read-only borrowed root path to pinned physical 96 Core1 definitions.
  Stream/Document/Runtime are owned here and freed in finally. NameBits
  is owned binary exact D7 sequence. Reject reordered or alien parameters.
  Questions: why compare D5 head inside original AST? Why exactly 96?
  How can a second matching DEFINE become dangerous? Why ask Selektor? }
function PinnedQuotientName(const RepoRoot:String):RawByteString;
var Path:String;Stream:TFileStream;Physical:RawByteString;
    Words:TExactWords;Doc:TD2Document;Root,Lambda,Params,Body:TD2Node;
    I,Matches,Ordinal:SizeInt;LeftName,RightName:RawByteString;
    Selector:TCore1Selektor;
begin
  Result:='';
  Need((RepoRoot<>'') and (Length(RepoRoot)<4096),
    'відсутній корінь pinned SENS');
  Path:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
    'external/sens/lib/core1.sens';
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Stream.Size>0) and (Stream.Size<=MaxCore1Bytes),
      'фізичний Core1 порожній або надто великий');
    SetLength(Physical,SizeInt(Stream.Size));
    Stream.ReadBuffer(Physical[1],Length(Physical));
  finally Stream.Free end;
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,'фізичний Core1 T5M неканонічний');
  Doc:=ParseD2WordsWide(Words);
  try
    Need(Length(Doc.Roots)=96,'змінився pinned Core1 census');
    Matches:=0;
    for I:=0 to High(Doc.Roots) do begin
      Root:=Doc.Roots[I];
      if (Root=nil) or (Root.Kind<>dkList) or
         (Length(Root.Children)<>3) then Continue;
      if (Root.Children[0]=nil) or
         (Root.Children[0].Kind<>dkIdentity) or
         (Root.Children[0].Width<>4) or
         (Root.Children[0].Bits<>'0011') then Continue;
      Lambda:=Root.Children[2];
      if (Lambda=nil) or (Lambda.Kind<>dkList) or
         (Length(Lambda.Children)<>3) then Continue;
      if (Lambda.Children[0]=nil) or
         (Lambda.Children[0].Kind<>dkIdentity) or
         (Lambda.Children[0].Width<>4) or
         (Lambda.Children[0].Bits<>'0010') then Continue;
      Params:=Lambda.Children[1];Body:=Lambda.Children[2];
      if (Params=nil) or (Params.Kind<>dkList) or
         (Length(Params.Children)<>2) or
         (Body=nil) or (Body.Kind<>dkList) or
         (Length(Body.Children)<>3) then Continue;
      if (Body.Children[0]=nil) or
         (Body.Children[0].Kind<>dkIdentity) or
         (Body.Children[0].Width<>5) or
         (Body.Children[0].Bits<>'10111') then Continue;
      LeftName:=D7Name(Params.Children[0]);
      RightName:=D7Name(Params.Children[1]);
      Need(LeftName<>RightName,'імена двох D7-параметрів збігаються');
      Need((D7Name(Body.Children[1])=LeftName) and
           (D7Name(Body.Children[2])=RightName),
        'оригінальне тіло Core1 змінило порядок параметрів');
      Need((Body.WordIndex>=1) and
           (Body.EndWordIndexExclusive<=Length(Words)+1) and
           (Body.EndWordIndexExclusive>Body.WordIndex) and
           (Words[Body.WordIndex-1]='10') and
           (Words[Body.EndWordIndexExclusive-2]='01'),
        'пошкоджено фізичну D2 рамку Core1 тіла');
      Inc(Matches);
      Need(Matches=1,'декілька однакових D5:10111 Core1 DEFINE');
      Result:=D7Name(Root.Children[1]);
    end;
    Need(Matches=1,'немає одного фізичного Core1 D5:10111 DEFINE');
  finally Doc.Free end;
  Selector:=TCore1Selektor.Create(RepoRoot);
  try
    Ordinal:=Selector.FindAdmitted(Result);
    Need((Ordinal>=0) and (Selector.AdmittedParamCount(Ordinal)=2) and
         (Selector.AdmittedName(Ordinal)=Result),
         'чинний Core1 runtime не допускає фізичне DEFINE');
  finally Selector.Free end;
end;

{ Binary-only source-backed proof: verify original DEFINE/LAMBDA/D7 order
  before building the same pinned D5 quotient WideIR which existing code
  already lowers to x86-64. Runtime numeric inputs are NOT compile-time 6/3.
  Result owned managed RawByteString ELF64; no new registers/GC bindings.
  Questions: why use a nonzero static anchor? Why require byte equality?
  Which backend performs IDIV? Which width can stdout have? }
function BuildPinnedCore1AdaptiveQuotELF(const RepoRoot:String):RawByteString;
var Name,Left,Right,Anchor,Authority,StaticProof,WideProof:RawByteString;
    N:TExplicitNumeric;W:TExactWords;G:TELFGeometry;
begin
  Result:='';
  Name:=PinnedQuotientName(RepoRoot);
  Need((Length(Name)>0) and (Length(Name) mod 7=0),
       'немає точного D7 Core1 ключа');
  Left:=EncodeNumericDecimal('3',12);
  Right:=EncodeNumericDecimal('3',12);
  N:=ReadNumericPhysical(Left,12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12),
       'порушено D12 лівого аргументу');
  SetLength(W,5);
  W[0]:='10';W[1]:='10111';W[2]:=N.ExactBits;
  N:=ReadNumericPhysical(Right,12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12),
       'порушено D12 правого аргументу');
  W[3]:=N.ExactBits;W[4]:='01';
  Anchor:=EncodeT5M(W);
  Authority:=RawByteString(IncludeTrailingPathDelimiter(
    ExpandFileName(RepoRoot))+'external/sens');
  { Статичний донор приймає лише рівні ненульові D12; 3/3 є
    механічним доказом джерела, а не обмеженням runtime stdin. }
  StaticProof:=BuildIRWideQuotELF(Anchor,Authority);
  WideProof:=BuildVerifiedWideELF(Anchor,Authority);
  Need(StaticProof=WideProof,
       'порушено byte-exact D5 Core1/WideIR походження');
  VerifySENSELF64(StaticProof,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(StaticProof)),
       'первинний pinned D5 не породив ELF64 PIE');
  Result:=BuildAdaptiveD12QuotStreamELF(Anchor,Authority);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Result)) and (G.MachineBytes>0),
       'адаптивний Core1 quotient не є виконуваним ELF64 PIE');
end;
end.
