{ G6.74 — справжній pinned ExactIR -> x86-64 для двох цитованих W7.
  Мовний авторитет: тільки pinned SENS Contract 12; D7 — дані.
  Перший прохід T5M/D2/binder -> VerifyExactIRStructure, потім
  БЕЗ повторного reader/evaluator machine XOR/OR/TEST/SETE/MOVZX.
  Жодного хостового EQ за назвою, D12, Core1 або нового закону. }
unit wsm.ird7eq;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type
  EIRD7EqError=class(Exception);
  { Owned managed W7 bytes from verified exact IR; physical word indices
    are provenance metadata only. This record is NOT a SENS value. }
  TLoweredD7Eq=record
    LeftBits,RightBits:RawByteString;
    HeadWord,LeftWord,RightWord:SizeInt;
  end;
procedure LowerPinnedQuotedD7Eq(const Physical,AuthorityRoot:RawByteString;
  out Lowered:TLoweredD7Eq);
function BuildPinnedQuotedD7EqIRELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
implementation
uses wsm.bind,wsm.domain,wsm.exactir,wsm.exactirguard,
  wsm.t5m,wsm.elfgeometry;
const HeaderBytes=120;MaxMachineBytes=256;

procedure Require(B:Boolean;const Why:String);
begin
  if not B then raise EIRD7EqError.Create(Why);
end;

{ Вхідні Physical/AuthorityRoot — borrowed canonical packed T5M bytes і шлях.
  Tables/IR/Stats локальні, managed FPC values, живуть до кінця процедури.
  Вихідний Lowered заповнюється АТОМАРНО лише після повного guard.
  Це pinned семантичний допуск через exact D3:101 + дві D3:001 цитати,
  не локальна таблиця законів. Сам D7 не може бути викличною головою.
  Контроль: чому два W7 не D12? Чому перевіряємо два окремих QUOTE?
  Чому не віримо довжині UTF-8 імені? Який lifetime IR?
  Чому звичайний List із двох W7 не є автоматично викликом EQ? }
procedure LowerPinnedQuotedD7Eq(const Physical,AuthorityRoot:RawByteString;
  out Lowered:TLoweredD7Eq);
var Tables:TDomainSet;IR:TExactIR;Stats:TExactIRGuardStats;
    Temp:TLoweredD7Eq;I:SizeInt;
begin
  Lowered.LeftBits:='';Lowered.RightBits:='';
  Lowered.HeadWord:=0;Lowered.LeftWord:=0;Lowered.RightWord:=0;
  Temp.LeftBits:='';Temp.RightBits:='';
  Temp.HeadWord:=0;Temp.LeftWord:=0;Temp.RightWord:=0;
  Require((Length(Physical)>0) and (Length(Physical)<=65536),
    'Фізичне джерело перевищило host-ліміт або порожнє');
  LoadPinnedDomains(AuthorityRoot,Tables);
  BuildExactIR(Physical,Tables,IR);
  VerifyExactIRStructure(IR,Stats);
  Require((Length(IR.Roots)=1) and (IR.Roots[0]=0) and
    (Length(IR.Nodes)=8) and (IR.BoundLeaves=5),
    'Потрібна одна точна D3:101 з двома цитованими D7');
  Require((IR.Nodes[0].Kind=ikList) and
    (IR.Nodes[0].ParentIndex=-1) and
    (IR.Nodes[0].SubtreeEndExclusive=8) and
    (IR.Nodes[1].Kind=ikIdentity) and IR.Nodes[1].HasKey and
    SameKey(IR.Nodes[1].Key,ExactKey('101')) and
    (IR.Nodes[1].ParentIndex=0) and
    (IR.Nodes[1].ChildIndex=0) and
    (IR.Nodes[1].SubtreeEndExclusive=2),
    'Фізична голова не є точною D3:101');
  for I:=0 to 1 do begin
    { Два піддерева рівно [2,5) і [5,8) у preorder:
      Quote list, D3:001 head, D7 argument. }
    Require((IR.Nodes[2+3*I].Kind=ikList) and
      (IR.Nodes[2+3*I].ParentIndex=0) and
      (IR.Nodes[2+3*I].ChildIndex=I+1) and
      (IR.Nodes[2+3*I].SubtreeEndExclusive=5+3*I),
      'Відсутня окрема фізична цитата');
    Require((IR.Nodes[3+3*I].Kind=ikIdentity) and
      IR.Nodes[3+3*I].HasKey and
      SameKey(IR.Nodes[3+3*I].Key,ExactKey('001')) and
      (IR.Nodes[3+3*I].ParentIndex=2+3*I) and
      (IR.Nodes[3+3*I].ChildIndex=0) and
      (IR.Nodes[3+3*I].SubtreeEndExclusive=4+3*I),
      'Аргумент має бути ратифікованою D3:001 цитатою');
    Require((IR.Nodes[4+3*I].Kind=ikIdentity) and
      IR.Nodes[4+3*I].HasKey and
      (IR.Nodes[4+3*I].Key.Width=7) and
      (IR.Nodes[4+3*I].ParentIndex=2+3*I) and
      (IR.Nodes[4+3*I].ChildIndex=1) and
      (IR.Nodes[4+3*I].SubtreeEndExclusive=5+3*I),
      'Цитований аргумент має бути точним D7 атомом');
  end;
  Temp.LeftBits:=KeyBits(IR.Nodes[4].Key);
  Temp.RightBits:=KeyBits(IR.Nodes[7].Key);
  Require((Length(Temp.LeftBits)=7) and (Length(Temp.RightBits)=7),
    'Точний D7 розрядний рисунок втрачено');
  for I:=1 to 7 do
    Require((Temp.LeftBits[I] in ['0','1']) and
      (Temp.RightBits[I] in ['0','1']),
      'Не двійкові біти в D7-даних');
  Temp.HeadWord:=IR.Nodes[1].WordIndex;
  Temp.LeftWord:=IR.Nodes[4].WordIndex;
  Temp.RightWord:=IR.Nodes[7].WordIndex;
  Lowered:=Temp;
end;

{ Вхід: перевірені owned W7 строки, MSB-first, не Unicode і не числа.
  Машина отримує по 7 пар imm8, рівність ОБЧИСЛЮЄ x86-64 під час запуску;
  Result — owned ELF64 ET_DYN як RawByteString, heap тимчасовий FPC.
  Фізичний stdout D1:0/1 — canonical EncodeT5M, не ASCII.
  Питання: чому XOR/OR працюють над 7 бітами, не символами?
  Чому не можна hard-code D1 T5M byte? Де machine TEST/SETE?
  Чому ET_DYN — host ABI, не домен? Який розмір RX PT_LOAD? }
function EmitLoweredD7EqELF(const Op:TLoweredD7Eq):RawByteString;
var
  Words:TExactWords;
  ZeroBytes,OneBytes,Machine:RawByteString;
  Delta:Byte;I,J,Total:SizeInt;
  procedure Add(B:Byte);
  begin
    Require(Length(Machine)<MaxMachineBytes,'Квота машинного коду D7');
    Machine:=Machine+AnsiChar(B);
  end;
  procedure Put(Offset:SizeInt;Value:QWord;Count:SizeInt);
  var K:SizeInt;
  begin
    Require((Offset>=0) and (Count>=1) and (Count<=8) and
      (Offset<=Length(Result)-Count),'ELF64 поле вийшло за межі');
    for K:=0 to Count-1 do begin
      Result[Offset+K+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;
begin
  Result:='';
  Require((Length(Op.LeftBits)=7) and (Length(Op.RightBits)=7),
    'Брак семи точних бітів D7');
  for J:=1 to 7 do
    Require((Op.LeftBits[J] in ['0','1']) and
      (Op.RightBits[J] in ['0','1']),'Не двійковий D7');
  SetLength(Words,1);
  Words[0]:='0';ZeroBytes:=EncodeT5M(Words);
  Words[0]:='1';OneBytes:=EncodeT5M(Words);
  Require((Length(ZeroBytes)=1) and (Length(OneBytes)=1) and
    (Ord(OneBytes[1])>Ord(ZeroBytes[1])) and
    (Ord(OneBytes[1])-Ord(ZeroBytes[1])<=127),
    'Порушено канонічний фізичний D1 транспорт');
  Delta:=Ord(OneBytes[1])-Ord(ZeroBytes[1]);
  Machine:='';
  Add($31);Add($C0); { xor eax,eax }
  for I:=1 to 7 do begin
    Add($B1);Add(Ord(Op.LeftBits[I])-Ord('0'));
    Add($80);Add($F1);Add(Ord(Op.RightBits[I])-Ord('0'));
    Add($08);Add($C8);
  end;
  Add($84);Add($C0); { test al,al }
  Add($0F);Add($94);Add($C0); { sete }
  Add($0F);Add($B6);Add($C0); { movzx }
  Add($6B);Add($C0);Add(Delta);
  Add($83);Add($C0);Add(Byte(ZeroBytes[1]));
  Add($48);Add($83);Add($EC);Add($08);
  Add($88);Add($04);Add($24);
  Add($B8);Add(1);Add(0);Add(0);Add(0);
  Add($BF);Add(1);Add(0);Add(0);Add(0);
  Add($48);Add($89);Add($E6);
  Add($BA);Add(1);Add(0);Add(0);Add(0);
  Add($0F);Add($05);
  Add($B8);Add($3C);Add(0);Add(0);Add(0);
  Add($31);Add($FF);Add($0F);Add($05);
  Total:=HeaderBytes+Length(Machine);
  SetLength(Result,Total);
  FillChar(Result[1],Total,0);
  Put(0,$464C457F,4);Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,QWord(Total),8);Put(104,QWord(Total),8);
  Put(112,$1000,8);
  for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
end;

{ Нижні рівні є окремими host механізмами. На помилці ані ELF, ані
  Lowered не виносяться частково; жодного evaluator під час emission. }
function BuildPinnedQuotedD7EqIRELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
var Op:TLoweredD7Eq;Geometry:TELFGeometry;
begin
  Result:='';
  try
    LowerPinnedQuotedD7Eq(Physical,AuthorityRoot,Op);
    Result:=EmitLoweredD7EqELF(Op);
    VerifySENSELF64(Result,Geometry);
    Require((Geometry.Kind=3) and
      (Geometry.FileBytes=Length(Result)) and
      (Geometry.MachineBytes>0),
      'Машинний ELF64 D7 має неприпустиму геометрію');
  except
    on E:EIRD7EqError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRD7EqError.Create('Прямий фізичний D7 IR відхилено: '+
        E.Message);
    end;
  end;
end;
end.
