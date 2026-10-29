{ G6.89 — одна вкладена фізична форма D5:11011(D5:01010,D12).
  pinned Contract12/D5 — закон; FPC лише WideIR admission/ELF-механізм.
  Не додає новий SENS resident, власний evaluator чи textual dispatch. }
unit wsm.irwideaddgreater;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideAddGreaterError=class(Exception);
function BuildIRWideAddGreaterELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.numericadd,wsm.elfd12add,
     wsm.elfd12greater,wsm.elfgeometry;

const HeaderBytes=120; MoveBytes=5; AddBytes=5;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRWideAddGreaterError.Create(Why) end;

{ Запозичений вузол має лише фізичні Bits/Width/Span. Отримання
  D12-контексту можливе тільки через точну батьківську викличну D5
  координату і чинний ReadNumericPhysical; W12 сам по собі opaque.
  Result — owned packed T5M одного точного W12 без текстового мосту.
  1) Чому Width=12 не визначає закон?
  2) Хто гарантує точність провідних нулів?
  3) Чому фізична адреса leaf не є його локальним T5M byte offset?
  4) Чому D24 буде відхилено? }
function D12Atom(const Node:TWideIRNode;Parent,Child,Depth:SizeInt):RawByteString;
var Words:TExactWords;N:TExplicitNumeric;
begin
  Need((Node.Kind=wkAtom) and Node.OwnWord and
    (Node.Width=12) and (Length(Node.Bits)=12) and
    (not Node.HasPinnedKey) and (Node.ParentIndex=Parent) and
    (Node.ChildIndex=Child) and (Node.RootIndex=0) and
    (Node.Depth=Depth),'потрібен exact opaque D12 аргумент');
  SetLength(Words,1);Words[0]:=Node.Bits;
  Result:=EncodeT5M(Words);
  N:=ReadNumericPhysical(Result,12);
  Need((N.DomainWidth=12) and (N.ExactBits=Node.Bits),
    'фізичне числове допущення не підтвердило D12');
end;

{ Кожен запис у результаті належить owned RawByteString — ELF host,
  не слово SENS. Структурний guard проводиться ПЕРЕД компіляцією.
  Величини Offset/Value — лише ELF64 little-endian p_filesz/p_memsz.
  1) Чому 96/104 належать ELF, а не доменній драбині?
  2) Чому нова довжина змінюється на п'ять байтів?
  3) Чому LEA RIP-relative не потребує іншого displacement?
  4) Яка перевірка забороняє писати за межі Result? }
procedure PutLE64(var Image:RawByteString;Offset:SizeInt;Value:QWord);
var I:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(Image)-8),
       'машинне поле ELF поза межами');
  for I:=0 to 7 do begin
    Image[Offset+I+1]:=AnsiChar(Byte(Value and $FF));
    Value:=Value shr 8;
  end;
end;

{ ProgramPhysical — borrowed один canonical packed D2/T5M binary file.
  AuthorityRoot — borrowed pinned SENS domain tables.
  Result — owned ET_DYN executable, allocated як managed byte string.
  Строго: (D5:11011 (D5:01010 W12 W12) W12), 7 preorder вузлів.
  Спершу pinned WideIR + перевірка батьків/синів і exact ключів.
  Далі D12 admission, AddNumericPhysical з явним W12→D24 fail-closed.
  Машинний MOV+ADD із вже перевіреного ADD ELF заміняє перший MOV
  уже перевіреного CMP/SETG ELF: під час виконання EAX справді
  обчислює суму, ECX — третій аргумент, SETG дає D1 T5M.
  Pascal НЕ обчислює D1 predicate і не вкладає готовий вихід.
  1) Які вузли не мають HasPinnedKey, і чому?
  2) Чому проміжний D24 не звужуємо?
  3) Чому machine-time CMP важливий для енергобенчмарку?
  4) Що перевіряє byte-prefix guard?
  5) Чому це не компілятор довільних Core1 програм? }
function BuildIRWideAddGreaterELF(const ProgramPhysical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Words:TExactWords;AtomA,AtomB,AtomC,Sum,AddImage,GreaterImage:RawByteString;
    Number:TExplicitNumeric;
    AddGeometry,GreaterGeometry,FinalGeometry:TELFGeometry;
begin
  Result:='';
  Need((Length(ProgramPhysical)>0) and (Length(ProgramPhysical)<=65536),
       'фізична програма порожня або поза бюджетом');
  DecodeT5M(ProgramPhysical,Words);
  Need(EncodeT5M(Words)=ProgramPhysical,
       'фізичні байти T5M не є канонічними');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildWideIR(ProgramPhysical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Nodes=7) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=5) and (Stats.OpaqueLeaves=3) and
       (Length(IR.Nodes)=7) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0),'потрібна одна вкладена D5 форма, два D5 та три D12');
  Need((IR.Nodes[0].Kind=wkList) and IR.Nodes[0].OwnWord and
       (IR.Nodes[0].ParentIndex=-1) and (IR.Nodes[0].Depth=0) and
       (IR.Nodes[0].ChildIndex=0),'пошкоджено головний D2 корінь');
  Need((IR.Nodes[1].Kind=wkAtom) and IR.Nodes[1].OwnWord and
       IR.Nodes[1].HasPinnedKey and
       SameKey(IR.Nodes[1].NarrowKey,ExactKey('11011')) and
       (IR.Nodes[1].ParentIndex=0) and (IR.Nodes[1].ChildIndex=0) and
       (IR.Nodes[1].Depth=1),'потрібна exact D5:11011 «більше?»');
  Need((IR.Nodes[2].Kind=wkList) and IR.Nodes[2].OwnWord and
       (IR.Nodes[2].ParentIndex=0) and (IR.Nodes[2].ChildIndex=1) and
       (IR.Nodes[2].Depth=1),'потрібен фізичний внутрішній D2 список');
  Need((IR.Nodes[3].Kind=wkAtom) and IR.Nodes[3].OwnWord and
       IR.Nodes[3].HasPinnedKey and
       SameKey(IR.Nodes[3].NarrowKey,ExactKey('01010')) and
       (IR.Nodes[3].ParentIndex=2) and (IR.Nodes[3].ChildIndex=0) and
       (IR.Nodes[3].Depth=2),'потрібна exact D5:01010 «додати»');
  AtomA:=D12Atom(IR.Nodes[4],2,1,2);
  AtomB:=D12Atom(IR.Nodes[5],2,2,2);
  AtomC:=D12Atom(IR.Nodes[6],0,2,1);
  Sum:=AddNumericPhysical(AtomA,AtomB,12);
  try
    Number:=ReadNumericPhysical(Sum,12);
  except on E:ENumericPlaneError do
    raise EIRWideAddGreaterError.Create(
      'проміжна сума потребує D24, цей ELF профіль D12: '+E.Message);
  end;
  Need((Number.DomainWidth=12) and (Length(Number.ExactBits)=12),
       'проміжна сума не є точним D12');

  AddImage:=BuildD12AddELF(AtomA,AtomB);
  GreaterImage:=BuildD12GreaterELF(Sum,AtomC);
  VerifySENSELF64(AddImage,AddGeometry);
  VerifySENSELF64(GreaterImage,GreaterGeometry);
  Need((AddGeometry.Kind=3) and (GreaterGeometry.Kind=3) and
       (AddGeometry.Entry=HeaderBytes) and (GreaterGeometry.Entry=HeaderBytes),
       'машинні складники не є перевіреними ELF64 PIE');
  Need((Length(AddImage)>=HeaderBytes+MoveBytes+AddBytes) and
       (Length(GreaterImage)>=HeaderBytes+MoveBytes+12) and
       (AddImage[HeaderBytes+1]=#$B8) and
       (AddImage[HeaderBytes+6]=#$05) and
       (GreaterImage[HeaderBytes+1]=#$B8) and
       (GreaterImage[HeaderBytes+6]=#$B9) and
       (GreaterImage[HeaderBytes+11]=#$39) and
       (GreaterImage[HeaderBytes+12]=#$C8) and
       (GreaterImage[HeaderBytes+13]=#$0F) and
       (GreaterImage[HeaderBytes+14]=#$9F),
       'префікс перевірених машинних emitter-ів змінився');
  Need(Length(GreaterImage)<1024*1024-AddBytes,
       'поза допустимою квотою ELF64');
  Result:=Copy(GreaterImage,1,HeaderBytes)+
    Copy(AddImage,HeaderBytes+1,MoveBytes+AddBytes)+
    Copy(GreaterImage,HeaderBytes+MoveBytes+1,
         Length(GreaterImage)-HeaderBytes-MoveBytes);
  Need(Length(Result)=Length(GreaterImage)+AddBytes,
       'втрачено байти складеного машинного коду');
  PutLE64(Result,96,Length(Result));
  PutLE64(Result,104,Length(Result));
  VerifySENSELF64(Result,FinalGeometry);
  Need((FinalGeometry.Kind=3) and
       (FinalGeometry.Entry=HeaderBytes) and
       (FinalGeometry.FileBytes=Length(Result)),
       'складений ELF64 не пройшов кінцевий guard');
end;
end.
