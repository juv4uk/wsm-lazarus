{ G6.65 — перше суворо перевірене AOT-згортання сталої D3:111.
  Єдине джерело результату — чинний pinned фізичний виконавець SENS.
  Вже існуючий ExactIR підтверджує домен/слово/фізичне походження.
  Це НЕ машинний CONS: компілятор один раз обчислює сталу і створює
  справжній x86-64 ET_DYN ELF, що виводить її точні packed T5M байти. }
unit wsm.irconstcons;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRConstConsError = class(Exception);
function BuildPinnedConstConsELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,
     wsm.exactirguard,wsm.binaryexec,wsm.elfgeometry;

const HeaderBytes=120;
      MaxPhysicalSource=65536;
      MaxAnswerBytes=4096;
      WriterBytes=33;

procedure Require(Good:Boolean;const Why:UnicodeString);
begin
  if not Good then
    raise EIRConstConsError.Create(RawByteString(UTF8Encode(Why)));
end;

{ Фізичний ExactIR позичений; кожний вузол контролює parent, child,
  subtree і exact Dn key. Власних таблиць чи текстового dispatch немає.
  Не підтримані аргументи не згортаються, навіть якщо runtime їх знає.
  Питання: чому D1:0 і D3:000 різні?
  Чому один біт не можна автоматично вважати числом D12?
  Чому голови порівнюються тільки exact-key?
  Чому Shape guard має передувати запуску evaluator? }
procedure AdmitLiteralCons(const IR:TExactIR);
var A,B:TExactIRNode;
begin
  Require((Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Length(IR.Nodes)=4) and (IR.BoundLeaves=3),
    'Потрібна одна точна D3:111 форма із двома атомами');
  Require((IR.Nodes[0].Kind=ikList) and
    (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].SubtreeEndExclusive=4),
    'Неприпустимий фізичний D2 корінь');
  Require((IR.Nodes[1].Kind=ikIdentity) and IR.Nodes[1].HasKey and
    (IR.Nodes[1].ParentIndex=0) and
    (IR.Nodes[1].ChildIndex=0) and
    (IR.Nodes[1].SubtreeEndExclusive=2) and
    SameKey(IR.Nodes[1].Key,ExactKey('111')),
    'Голова не є pinned D3:111');
  A:=IR.Nodes[2];B:=IR.Nodes[3];
  Require((A.Kind=ikIdentity) and A.HasKey and
    (A.ParentIndex=0) and (A.ChildIndex=1) and
    (A.SubtreeEndExclusive=3) and
    (A.Key.Width=1) and
    ((KeyBits(A.Key)='0') or (KeyBits(A.Key)='1')),
    'Лівий сталий операнд мусить бути точним D1');
  Require((B.Kind in [ikIdentity,ikEmpty]) and B.HasKey and
    (B.ParentIndex=0) and (B.ChildIndex=2) and
    (B.SubtreeEndExclusive=4) and
    (((B.Kind=ikIdentity) and (B.Key.Width=1) and
      ((KeyBits(B.Key)='0') or (KeyBits(B.Key)='1'))) or
     ((B.Kind=ikEmpty) and (B.Key.Width=3) and
      (KeyBits(B.Key)='000'))),
    'Правий сталий операнд: лише D1 або фізичний D3:000');
end;

{ Answer — owned canonical packed T5M, результат уже допущеного
  evaluator. Машинний код НЕ містить інтерпретатора, алокацій, D7
  spelling чи арифметики D12+. Код пише Answer через Linux write/exit.
  RIP displacement формується з точного розміру Machine, не з адреси
  поточного FPC процесу. ELF64 ET_DYN потім перевіряє готовий guard.
  Питання: чому це AOT constant folding, а не runtime CONS?
  Чому не можна без перевірки вбудувати произвольні байти Answer?
  Хто володіє Answer та Image?
  Чому ET_DYN не визначає семантичну ідентичність SENS? }
function EmitLiteral(const Answer:RawByteString):RawByteString;
var Machine:RawByteString;
    Geometry:TELFGeometry;
    Total,DataStart,I:SizeInt;
  procedure PutLE(Offset:SizeInt;Value:QWord;Width:SizeInt);
  var J:SizeInt;
  begin
    Require((Offset>=0) and (Width>=1) and (Width<=8) and
      (Offset<=Length(Result)-Width),
      'Неприпустима позиція поля ELF64');
    for J:=0 to Width-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;
begin
  Result:='';
  Require((Length(Answer)>0) and (Length(Answer)<=MaxAnswerBytes),
    'Сталий фізичний результат поза host-лімітом');
  Machine:=
    #$B8#$01#0#0#0 + #$BF#$01#0#0#0 +
    #$48#$8D#$35#0#0#0#0 + #$BA#0#0#0#0 +
    #$0F#$05 + #$B8#$3C#0#0#0 + #$31#$FF + #$0F#$05;
  Require(Length(Machine)=WriterBytes,'Змінено код перевіреного ELF writer');
  DataStart:=HeaderBytes+WriterBytes;
  Total:=DataStart+Length(Answer);
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  PutLE(0,$464C457F,4);
  PutLE(4,2,1); PutLE(5,1,1); PutLE(6,1,1);
  PutLE(16,3,2); PutLE(18,62,2); PutLE(20,1,4);
  PutLE(24,HeaderBytes,8); PutLE(32,64,8);
  PutLE(52,64,2); PutLE(54,56,2); PutLE(56,1,2);
  PutLE(64,1,4); PutLE(68,5,4);
  PutLE(80,0,8); PutLE(88,0,8);
  PutLE(96,Total,8); PutLE(104,Total,8); PutLE(112,$1000,8);
  for I:=1 to WriterBytes do Result[HeaderBytes+I]:=Machine[I];
  PutLE(HeaderBytes+13,DataStart-(HeaderBytes+17),4);
  PutLE(HeaderBytes+18,Length(Answer),4);
  for I:=1 to Length(Answer) do Result[DataStart+I]:=Answer[I];
  VerifySENSELF64(Result,Geometry);
  Require((Geometry.Kind=3) and (Geometry.FileBytes=Total),
    'Сталий нативний ELF не пройшов геометрію');
end;

{ Обидва фінальні сліди від незалежних механізмів: один pinned
  фізичний D2/binder/IR для admission; другий той же чинний SENS
  evaluator для ДІЙСНОГО результату. Відповідь byte-exact T5M.
  Ніякого згортання довільних викликів, рекурсій чи ефектів.
  Питання: чому незнайома голова не може використовувати цю оптимізацію?
  Чим runtime-виклик відрізняється від текстового projection lookup?
  Чому після збоїв не залишається часткового ELF?
  Чому це не верифікація продуктивності/джоулів? }
function BuildPinnedConstConsELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
var Tables:TDomainSet; IR:TExactIR; Stats:TExactIRGuardStats;
    Executor:TBinaryExecutor; Answer:RawByteString; Words:TExactWords;
begin
  Result:=''; Executor:=nil;
  try
    try
      Require((Length(Physical)>=1) and (Length(Physical)<=MaxPhysicalSource),
      'Джерело поза межею фізичного T5M');
    LoadPinnedDomains(AuthorityRoot,Tables);
    BuildExactIR(Physical,Tables,IR);
    VerifyExactIRStructure(IR,Stats);
    AdmitLiteralCons(IR);
    Executor:=TBinaryExecutor.Create(AuthorityRoot);
    Answer:=Executor.ExecutePhysicalT5M(Physical);
    Require((Length(Answer)>=1) and (Length(Answer)<=MaxAnswerBytes),
      'Неприпустимий фізичний результат pinned runtime');
    DecodeT5M(Answer,Words);
    Require((Length(Words)>0) and (EncodeT5M(Words)=Answer),
      'Runtime повернув неканонічний T5M');
    Result:=EmitLiteral(Answer);
  except
    on E:EIRConstConsError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRConstConsError.Create(
        'Перевірене згортання D3:111 відхилено: '+E.Message);
    end;
    end;
  finally Executor.Free end;
end;
end.
