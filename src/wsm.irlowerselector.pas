{ G6.55 — пряме зниження перевіреного ExactIR селектора у ELF64.
  Мовні закони залишаються в pinned SENS; модуль перевіряє походження
  вузлів і формує x86-64 інструкції лише для фізичної D3:100/011 форми. }
unit wsm.irlowerselector;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.exactir;
type EIRLowerSelectorError=class(Exception);
function LowerVerifiedSelectorELF(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactirguard;

const HeaderBytes=120;

function UA(const S:UnicodeString):RawByteString;
begin
  Result:=RawByteString(UTF8Encode(S));
end;

procedure Require(Condition:Boolean;const Why:UnicodeString);
begin
  if not Condition then raise EIRLowerSelectorError.Create(UA(Why));
end;

function SameNode(const A,B:TExactIRNode):Boolean;
begin
  { ExactIR є фізичним походженням: порівнюємо поля явно, не record padding. }
  Result:=(A.Kind=B.Kind) and (A.RootIndex=B.RootIndex) and
    (A.ParentIndex=B.ParentIndex) and (A.ChildIndex=B.ChildIndex) and
    (A.Depth=B.Depth) and
    (A.SubtreeEndExclusive=B.SubtreeEndExclusive) and
    (A.WordIndex=B.WordIndex) and (A.HasKey=B.HasKey) and
    (A.Key.Width=B.Key.Width) and (A.Key.Bits=B.Key.Bits) and
    (A.Physical.WordIndex=B.Physical.WordIndex) and
    (A.Physical.TritStart=B.Physical.TritStart) and
    (A.Physical.TritEnd=B.Physical.TritEnd) and
    (A.Physical.ByteStart=B.Physical.ByteStart) and
    (A.Physical.ByteEnd=B.Physical.ByteEnd) and
    (A.Physical.IsEOF=B.Physical.IsEOF);
end;

procedure VerifyPhysicalIR(const Physical,AuthorityRoot:RawByteString;
  const Candidate:TExactIR;out Actual:TExactIR);
var
  Tables:TDomainSet;
  CandidateStats,ActualStats:TExactIRGuardStats;
  I:SizeInt;
begin
  SetLength(Actual.Nodes,0);SetLength(Actual.Roots,0);Actual.BoundLeaves:=0;
  Require((Length(Physical)>=1) and (Length(Physical)<=65536),
    'Фізичне джерело поза host-межею');
  VerifyExactIRStructure(Candidate,CandidateStats);
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildExactIR(Physical,Tables,Actual);
  VerifyExactIRStructure(Actual,ActualStats);
  Require((Length(Candidate.Roots)=Length(Actual.Roots)) and
    (Length(Candidate.Nodes)=Length(Actual.Nodes)) and
    (Candidate.BoundLeaves=Actual.BoundLeaves),
    'ExactIR не відповідає фізичному джерелу');
  Require((CandidateStats.Nodes=ActualStats.Nodes) and
    (CandidateStats.Roots=ActualStats.Roots) and
    (CandidateStats.BoundLeaves=ActualStats.BoundLeaves) and
    (CandidateStats.StructuralNodes=ActualStats.StructuralNodes) and
    (CandidateStats.MaxDepth=ActualStats.MaxDepth),
    'Статистика ExactIR не відповідає фізичному джерелу');
  for I:=0 to High(Actual.Roots) do
    Require(Candidate.Roots[I]=Actual.Roots[I],
      'Змінено індекс фізичного кореня');
  for I:=0 to High(Actual.Nodes) do
    Require(SameNode(Candidate.Nodes[I],Actual.Nodes[I]),
      'ExactIR вузол не відповідає фізичному слову №'+UnicodeString(IntToStr(I)));
end;

function LowerVerifiedSelectorELF(const Physical,AuthorityRoot:RawByteString;
  const CandidateIR:TExactIR):RawByteString;
var
  Actual:TExactIR;
  Selector,LeftBits,RightBits,Zero,One,Machine:RawByteString;
  Encoded:TExactWords;
  SelectorOffset,LeftValue,RightValue,Delta:Byte;
  Total,I:SizeInt;

  procedure PutLE(At:SizeInt;Value:QWord;Width:SizeInt);
  var J:SizeInt;
  begin
    Require((At>=0) and (Width>=1) and (Width<=8) and
      (At<=Length(Result)-Width),'Порушено межу ELF64');
    for J:=0 to Width-1 do begin
      Result[At+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;

begin
  Result:='';
  try
    VerifyPhysicalIR(Physical,AuthorityRoot,CandidateIR,Actual);
    Require((Length(Actual.Roots)=1) and (Actual.Roots[0]=0) and
      (Length(Actual.Nodes)=6) and (Actual.BoundLeaves=4),
      'Очікується одна форма D3-селектора над CONS і двома D1');
    Require((Actual.Nodes[0].Kind=ikList) and
      (Actual.Nodes[0].ParentIndex=-1) and
      (Actual.Nodes[1].Kind=ikIdentity) and Actual.Nodes[1].HasKey and
      (Actual.Nodes[1].ParentIndex=0) and (Actual.Nodes[1].ChildIndex=0) and
      (Actual.Nodes[2].Kind=ikList) and
      (Actual.Nodes[2].ParentIndex=0) and (Actual.Nodes[2].ChildIndex=1) and
      (Actual.Nodes[3].Kind=ikIdentity) and Actual.Nodes[3].HasKey and
      (Actual.Nodes[3].ParentIndex=2) and (Actual.Nodes[3].ChildIndex=0) and
      (Actual.Nodes[4].Kind=ikIdentity) and Actual.Nodes[4].HasKey and
      (Actual.Nodes[4].ParentIndex=2) and (Actual.Nodes[4].ChildIndex=1) and
      (Actual.Nodes[5].Kind=ikIdentity) and Actual.Nodes[5].HasKey and
      (Actual.Nodes[5].ParentIndex=2) and (Actual.Nodes[5].ChildIndex=2),
      'ExactIR не має точної форми selector(CONS D1 D1)');
    Require((Actual.Nodes[1].Key.Width=3) and
      (Actual.Nodes[3].Key.Width=3) and (KeyBits(Actual.Nodes[3].Key)='111'),
      'CONS потребує exact D3:111 координати');
    Selector:=KeyBits(Actual.Nodes[1].Key);
    if Selector='100' then SelectorOffset:=0
    else if Selector='011' then SelectorOffset:=8
    else raise EIRLowerSelectorError.Create('Підтримано лише точні D3:100/011');
    Require((Actual.Nodes[4].Key.Width=1) and
      (Actual.Nodes[5].Key.Width=1),'CONS допускає лише два exact D1 атоми');
    LeftBits:=KeyBits(Actual.Nodes[4].Key);
    RightBits:=KeyBits(Actual.Nodes[5].Key);
    if LeftBits='0' then LeftValue:=0
    else if LeftBits='1' then LeftValue:=1
    else raise EIRLowerSelectorError.Create('Лівий аргумент не є D1:0/1');
    if RightBits='0' then RightValue:=0
    else if RightBits='1' then RightValue:=1
    else raise EIRLowerSelectorError.Create('Правий аргумент не є D1:0/1');

    { Опорні байти беруться з чинного фізичного T5M codec.
      Машинний код зчитує вибрану комірку CONS і кодує D1 на запуску. }
    SetLength(Encoded,1);
    Encoded[0]:='0';Zero:=EncodeT5M(Encoded);
    Encoded[0]:='1';One:=EncodeT5M(Encoded);
    Require((Length(Zero)=1) and (Length(One)=1) and
      (Byte(Zero[1])<=127) and (Byte(One[1])>Byte(Zero[1])) and
      (Byte(One[1])-Byte(Zero[1])<=127),
      'Непідтриманий фізичний D1 T5M codec');
    Delta:=Byte(One[1])-Byte(Zero[1]);

    { Операнди D1 потрапляють у дві QWord комірки; інструкція MOV із
      offset 0/8 лишає саме фізичний вибір на виконання ELF. }
    Machine:=#$B8+AnsiChar(LeftValue)+#0#0#0+
      #$B9+AnsiChar(RightValue)+#0#0#0+
      #$48#$83#$EC#$10+#$48#$89#$04#$24+
      #$48#$89#$4C#$24#$08+#$48#$8D#$34#$24+
      #$48#$8B#$56+AnsiChar(SelectorOffset)+
      #$6B#$D2+AnsiChar(Delta)+#$83#$C2+Zero[1]+
      #$48#$83#$EC#$08+#$88#$14#$24+
      #$B8#$01#0#0#0+#$BF#$01#0#0#0+#$48#$89#$E6+
      #$BA#$01#0#0#0+#$0F#$05+
      #$B8#$3C#0#0#0+#$31#$FF#$0F#$05;
    Require(Length(Machine)=73,'Неочікувана довжина x86-64 коду');

    { ELF64 Linux ET_DYN: один read/execute PT_LOAD, без інтерпретатора
      чи relocation. Усі межі та заголовки — host-геометрія ELF. }
    Total:=HeaderBytes+Length(Machine);
    SetLength(Result,Total);
    FillChar(Result[1],Length(Result),0);
    Result[1]:=#$7F;Result[2]:='E';Result[3]:='L';Result[4]:='F';
    Result[5]:=#2;Result[6]:=#1;Result[7]:=#1;
    PutLE(16,3,2);PutLE(18,62,2);PutLE(20,1,4);
    PutLE(24,HeaderBytes,8);PutLE(32,64,8);
    PutLE(52,64,2);PutLE(54,56,2);PutLE(56,1,2);
    PutLE(64,1,4);PutLE(68,5,4);PutLE(80,0,8);
    PutLE(88,0,8);PutLE(96,QWord(Total),8);
    PutLE(104,QWord(Total),8);PutLE(112,$1000,8);
    for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
  except
    on E:EIRLowerSelectorError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRLowerSelectorError.Create(UA(
        UnicodeString('ExactIR селектора відхилено: ')+UnicodeString(E.Message)));
    end;
  end;
end;

{ Physical/AuthorityRoot — borrowed immutable byte strings; CandidateIR is
  borrowed managed ExactIR; Actual owns a locally rebuilt tree. Result owns
  the complete ELF64 bytes only after every guard and geometry check passes.
  Questions: 1) Why does provenance compare SubtreeEndExclusive?
  2) Why is D3:100/011 a static memory offset, not a Pascal-selected value?
  3) Which exact codec defines the T5M result bytes?
  4) Why can this narrow ET_DYN not claim complete compiler support? }
end.
