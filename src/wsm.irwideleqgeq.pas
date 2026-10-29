{ G6.156 — виклична композиція D4:0100 із D5:11010/11011 → x86-64 SETLE/SETGE.
  НЕ обчислюємо предикат у Pascal: тільки exact WideIR admission та
  перевірене механічне переписування одного CMP/SETcc чинного емітера.
  Мовний авторитет — pinned Contract 12.0, d4.lisp та d5.lisp.
  D6:110100/110110 є каталоговими і НЕ стають викличними. }
unit wsm.irwideleqgeq;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideBoundsError=class(Exception);
function BuildIRWideBoundsELF(
  const PhysicalProgram,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,wsm.t5m,
     wsm.numericplane,wsm.elfd12less,wsm.elfd12greater,wsm.elfgeometry;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRWideBoundsError.Create(Why) end;

{ Вузол IR: запозичений exact opaque W12; повертаємо managed фізичний
  T5M D12 атом після окремого числового admission, без host десяткової
  конверсії та без виведення ідентичності з ширини.
  1) Чому opaque W12 сам не підтверджує закон?
  2) Чому потрібен ReadNumericPhysical?
  3) Хто звільняє W та Result? }
function D12Atom(const N:TWideIRNode;ExpectedChild:SizeInt):RawByteString;
var W:TExactWords;V:TExplicitNumeric;
begin
  Need((N.Kind=wkAtom) and N.OwnWord and (N.Width=12) and
       (Length(N.Bits)=12) and (not N.HasPinnedKey) and
       (N.NarrowKey.Width=0) and (N.ParentIndex=2) and
       (N.RootIndex=0) and (N.ChildIndex=ExpectedChild) and
       (N.Depth=2),'потрібен exact opaque D12 аргумент');
  SetLength(W,1);W[0]:=N.Bits;
  Result:=EncodeT5M(W);
  V:=ReadNumericPhysical(Result,12);
  Need((V.DomainWidth=12) and (V.ExactBits=N.Bits),
       'числовий D12 допуск не збігся з фізичним словом');
end;

{ Result — owned ELF64 ET_DYN; Image маніпулюємо тільки у відомому
  opcode SETcc після розбору єдиної ратифікованої композиції:
  (D4 ХИБНЕ? (D5 БІЛЬШЕ? A B)) → CMP/SETLE,
  (D4 ХИБНЕ? (D5 МЕНШЕ? A B)) → CMP/SETGE. x86-64 signed ordering (SF/OF/ZF), а не
  Pascal Boolean. Patch не рухає RIP-relative посилань чи геометрію ELF.
  1) Чому SETLE=$9E, SETGE=$9D, а не беззнакові SETBE/SETAE?
  2) Чому необхідна перевірка усіх сусідніх байтів?
  3) Чому D6:110100 не стає викличною головою?
  4) Хто обчислює кінцевий біт D1?
  5) Чому перевірка ELF — ще не independent SENS oracle? }
function BuildIRWideBoundsELF(
  const PhysicalProgram,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;Row:TDomainRow;K:TDomainKey;
    L,R,Image:RawByteString;G:TELFGeometry;IsLE:Boolean;
begin
  Result:='';
  Need((Length(PhysicalProgram)>0) and (Length(PhysicalProgram)<=65536),
       'порожнє або завелике фізичне джерело');
  DecodeT5M(PhysicalProgram,Words);
  Need(EncodeT5M(Words)=PhysicalProgram,'не канонічний packed T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(PhysicalProgram,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Roots=1) and (Stats.Nodes=6) and
       (Stats.PhysicalLeaves=4) and (Stats.OpaqueLeaves=2) and
       (Length(IR.Roots)=1) and (IR.Roots[0]=0) and
       (Length(IR.Nodes)=6),'потрібна одна вкладена D4(D5(D12,D12)) форма');
  Need((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].RootIndex=0) and
       (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
       'неправильна D2 рамка');
  Need((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       IR.Nodes[1].HasPinnedKey and (IR.Nodes[1].Width=4) and
       (IR.Nodes[1].Bits='0100') and
       (IR.Nodes[1].ParentIndex=0) and
       (IR.Nodes[1].RootIndex=0) and
       (IR.Nodes[1].ChildIndex=0) and (IR.Nodes[1].Depth=1) and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('0100')),
       'потрібна виклична pinned D4:0100 хибне?');
  K:=ExactKey('0100');
  Need(DomainRowByKey(Tables[4],K,Row) and SameKey(Row.Key,K),
       'немає точної координати в pinned D4');
  Need((IR.Nodes[2].Kind=wkList) and IR.Nodes[2].OwnWord and
       (IR.Nodes[2].ParentIndex=0) and (IR.Nodes[2].RootIndex=0) and
       (IR.Nodes[2].ChildIndex=1) and (IR.Nodes[2].Depth=1),
       'потрібен один вкладений список D5');
  Need((IR.Nodes[3].Kind=wkAtom) and IR.Nodes[3].OwnWord and
       IR.Nodes[3].HasPinnedKey and (IR.Nodes[3].Width=5) and
       ((IR.Nodes[3].Bits='11010') or (IR.Nodes[3].Bits='11011')) and
       (IR.Nodes[3].ParentIndex=2) and
       (IR.Nodes[3].RootIndex=0) and
       (IR.Nodes[3].ChildIndex=0) and (IR.Nodes[3].Depth=2) and
       SameKey(IR.Nodes[3].NarrowKey,ExactKey(IR.Nodes[3].Bits)),
       'вкладена голова повинна бути викличною D5 менше?/більше?');
  K:=ExactKey(IR.Nodes[3].Bits);
  Need(DomainRowByKey(Tables[5],K,Row) and SameKey(Row.Key,K),
       'немає точної координати в pinned D5');
  L:=D12Atom(IR.Nodes[4],1);
  R:=D12Atom(IR.Nodes[5],2);
  IsLE:=IR.Nodes[3].Bits='11011';
  if IsLE then begin
    Image:=BuildD12GreaterELF(L,R); { signed SETG → SETLE }
    VerifySENSELF64(Image,G);
    Need((G.Kind=3) and (G.Entry=120) and (Length(Image)>140) and
         (Image[121]=#$B8) and (Image[126]=#$B9) and
         (Image[131]=#$39) and (Image[132]=#$C8) and
         (Image[133]=#$0F) and (Image[134]=#$9F) and
         (Image[135]=#$C0) and (Image[136]=#$0F) and
         (Image[137]=#$B6) and (Image[138]=#$C0),
         'машинний CMP/SETG пролог змінився; відмова');
    Image[134]:=#$9E; { SETLE — signed less or equal }
  end else begin
    Image:=BuildD12LessELF(L,R); { signed SETL → SETGE }
    VerifySENSELF64(Image,G);
    Need((G.Kind=3) and (G.Entry=120) and (Length(Image)>140) and
         (Image[121]=#$B8) and (Image[126]=#$3D) and
         (Image[131]=#$0F) and (Image[132]=#$9C) and
         (Image[133]=#$C0) and (Image[134]=#$0F) and
         (Image[135]=#$B6) and (Image[136]=#$C0),
         'машинний CMP/SETL пролог змінився; відмова');
    Image[132]:=#$9D; { SETGE — signed greater or equal }
  end;
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Image)) and
       (G.MachineBytes=Length(Image)-120),
       'перетворений машинний ELF64 не пройшов перевірку');
  Result:=Image;
end;
end.
