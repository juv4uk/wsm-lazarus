{ G6.105 — один фізичний D2/T5M вираз із 1..4 ВКЛАДЕНИХ
  D6 «найменше»/«найбільше» → WideIR → справжній машинний ELF64 PIE.
  Жодного нового закону SENS: лише pinned D6 та доведені backend
  BuildD12MinELF/BuildD12MaxELF. Цей код не є general compiler. }
unit wsm.irmixedextrema;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRMixedExtrema=class(Exception);
function BuildIRMixedExtremaELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfd12min,wsm.elfd12max,wsm.elfgeometry;
const HeaderBytes=120; FirstInstructionBytes=15; MaxDepth=4;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise EIRMixedExtrema.Create(Why) end;

{ Node: borrowed фізичний W12 після перевіреного WideIR;
  повертає owned packed T5M D12, без неявної текстової проєкції.
  Локальний managed Words звільняється при завершенні функції.
  1) Чому W12 само по собі ще не числовий домен?
  2) Навіщо повторний ReadNumericPhysical?
  3) Де збережено провідні нулі? }
function AdmitD12(const Node:TWideIRNode;Parent,Child,Depth:SizeInt):RawByteString;
var W:TExactWords;N:TExplicitNumeric;
begin
  Need((Node.Kind=wkAtom) and Node.OwnWord and
    (Node.Width=12) and (Length(Node.Bits)=12) and
    (not Node.HasPinnedKey) and (Node.RootIndex=0) and
    (Node.ParentIndex=Parent) and (Node.ChildIndex=Child) and
    (Node.Depth=Depth),'потрібен точний фізичний D12 листок');
  SetLength(W,1);W[0]:=Node.Bits;
  Result:=EncodeT5M(W);
  N:=ReadNumericPhysical(Result,12);
  Need((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
    'числовий D12 admission змінив фізичну ідентичність');
end;

{ Локальна машинна imm32 у signed x86 профілі; не семантичне число
  SENS і не закон домену. Обмежений діапазон — exact signed D12.
  1) Чому розширення знака не змінює 12 молодших бітів?
  2) Хто перевірив домен до виклику?
  3) Чому host LongWord не є числовою адресою D12? }
function SignedImmediate12(const Bits:RawByteString):LongWord;
var Value,I:LongInt;
begin
  Need(Length(Bits)=12,'очікується exact W12');
  Value:=0;
  for I:=1 to 12 do begin
    Need(Bits[I] in ['0','1'],'невірний фізичний біт');
    Value:=Value*2+Ord(Bits[I])-Ord('0');
  end;
  if Bits[1]='1' then Value:=Value-4096;
  Result:=LongWord(Value);
end;

{ Zero-based ELF header offset, own managed Image bytes.
  Оновлюємо filesz+memsz після механічного splice до перевірки PIE.
  1) Чому два ELF розміри мають збігатися?
  2) Чому не можна змінювати offset коду довільно?
  3) Хто перевіряє геометрію після patch? }
procedure Put64(var Image:RawByteString;Off:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Off>=0) and (Off+8<=Length(Image)),'ELF header поза образом');
  for I:=0 to 7 do begin
    Image[Off+I+1]:=AnsiChar(Byte(Value and $FF));Value:=Value shr 8;
  end;
end;

{ Borrowed canonical Physical .sens і pinned AuthorityRoot; Result owned
  Linux x86-64 ELF64. Preorder WideIR: N list-head пар, два deepest
  D12 leaves, N-1 зовнішніх D12 справа; N=1..4. Всі фізичні листки
  допускаються незалежно. Кожен CMOV виконується ТІЛЬКИ в машині.
  Еталонний ELF min/max надає і заголовок, і canonical T5M writer.
  Додаємо перед writer тільки mov ecx/ cmp eax,ecx/ signed cmov;
  RIP writer+таблиця пересуваються ОДНИМ блоком, отже rel32 сталі.
  1) Чому дерево перевіряємо до emission?
  2) Як відділяються D6 голови від D12 чисел?
  3) Чому тут НЕ обчислюємо min/max у Pascal?
  4) Чому байти базового backend перевіряються до splice?
  5) Чому весь ELF перевіряється повторно? }
function BuildIRMixedExtremaELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Words:TExactWords;Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Geom:TELFGeometry;Row:TDomainRow;Key:TDomainKey;
    N,I,P,LeafIndex:SizeInt;Node:TWideIRNode;
    LeftAtom,RightAtom,Image,Extra:RawByteString;Value:LongWord;
    J:SizeInt;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=512),
    'порожній або надмірний двійковий документ');
  DecodeT5M(Physical,Words);
  Need(EncodeT5M(Words)=Physical,'пошкоджений або неканонічний T5M');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Roots=1) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0) and (Length(IR.Nodes)=Stats.Nodes) and
       (Stats.Nodes>=4) and (Stats.Nodes<=3*MaxDepth+1) and
       ((Stats.Nodes-1) mod 3=0),
       'потрібен один фізичний D2 корінь із 1..4 вкладень');
  N:=(Stats.Nodes-1) div 3;
  Need((Stats.PhysicalLeaves=2*N+1) and
       (Stats.OpaqueLeaves=N+1),
       'кількість physical/opaque листків не підтверджена');
  for I:=0 to N-1 do begin
    P:=2*I;
    Node:=IR.Nodes[P];
    Need((Node.Kind=wkList) and Node.OwnWord and
      (Node.RootIndex=0) and (Node.Depth=I) and
      (((I=0) and (Node.ParentIndex=-1) and (Node.ChildIndex=0)) or
       ((I>0) and (Node.ParentIndex=P-2) and (Node.ChildIndex=1))),
      'змінилися фізичні батьки вкладеної D2 структури');
    Node:=IR.Nodes[P+1];
    Need((Node.Kind=wkAtom) and Node.OwnWord and Node.HasPinnedKey and
      (Node.Width=6) and ((Node.Bits='110101') or (Node.Bits='110111')) and
      (Node.ParentIndex=P) and (Node.ChildIndex=0) and
      (Node.RootIndex=0) and (Node.Depth=I+1) and
      SameKey(Node.NarrowKey,ExactKey(Node.Bits)),
      'потрібна лише pinned D6 голова «найменше»/«найбільше»');
    Key:=ExactKey(Node.Bits);
    Need(DomainRowByKey(Tables[6],Key,Row) and SameKey(Row.Key,Key),
      'невідомий фізичний D6 ключ у pinned каталозі');
  end;

  LeftAtom:=AdmitD12(IR.Nodes[2*N],2*N-2,1,N);
  RightAtom:=AdmitD12(IR.Nodes[2*N+1],2*N-2,2,N);
  if IR.Nodes[2*N-1].Bits='110101' then
    Image:=BuildD12MinELF(LeftAtom,RightAtom)
  else
    Image:=BuildD12MaxELF(LeftAtom,RightAtom);
  VerifySENSELF64(Image,Geom);
  Need((Geom.Kind=3) and (Geom.Entry=HeaderBytes) and
    (Geom.FileBytes=Length(Image)) and
    (Copy(Image,HeaderBytes+1,1)=#$B8) and
    (Copy(Image,HeaderBytes+6,1)=#$B9) and
    (Copy(Image,HeaderBytes+11,2)=#$39#$C8) and
    (Copy(Image,HeaderBytes+16,5)=#$25#$FF#$0F#0#0),
    'вихідний машинний пролог signed CMP/CMOV не підтверджено');
  if IR.Nodes[2*N-1].Bits='110101' then
    Need(Copy(Image,HeaderBytes+13,3)=#$0F#$4F#$C1,
      'початкова машинна інструкція не є signed CMOVG')
  else
    Need(Copy(Image,HeaderBytes+13,3)=#$0F#$4C#$C1,
      'початкова машинна інструкція не є signed CMOVL');
  { Add outer right leaves from inner to outer, preserving x86 EAX result. }
  Extra:='';
  for I:=N-2 downto 0 do begin
    LeafIndex:=2*N+1+(N-1-I);
    RightAtom:=AdmitD12(IR.Nodes[LeafIndex],2*I,2,I+1);
    Value:=SignedImmediate12(IR.Nodes[LeafIndex].Bits);
    Extra:=Extra+#$B9;
    for J:=0 to 3 do begin
      Extra:=Extra+AnsiChar(Byte(Value and $FF));Value:=Value shr 8;
    end;
    Extra:=Extra+#$39#$C8;
    if IR.Nodes[2*I+1].Bits='110101' then
      Extra:=Extra+#$0F#$4F#$C1
    else
      Extra:=Extra+#$0F#$4C#$C1;
  end;
  Need(Length(Extra)=(N-1)*10,'втрачено x86 машинні кроки');
  Need(Length(Image)+Length(Extra)<1024*1024,'перевищено межу ELF');
  Result:=Copy(Image,1,HeaderBytes+FirstInstructionBytes)+Extra+
    Copy(Image,HeaderBytes+FirstInstructionBytes+1,
      Length(Image)-HeaderBytes-FirstInstructionBytes);
  Need(Length(Result)=Length(Image)+Length(Extra),
    'змінено машинну геометрію або таблиці T5M');
  Put64(Result,96,Length(Result));
  Put64(Result,104,Length(Result));
  VerifySENSELF64(Result,Geom);
  Need((Geom.Kind=3) and (Geom.Entry=HeaderBytes) and
        (Geom.FileBytes=Length(Result)),'складений ELF64 PIE не допущений');
end;
end.
