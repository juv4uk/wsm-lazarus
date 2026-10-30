{ G6.67 — перевірений ExactIR → реальна машинна вибірка третього D1.
  Мовна ідентичність тільки pinned D5:10011, D4:1110, D1:0/1.
  Корені .sens фізичні. Історичний caddr — донор ідеї, не закон. }
unit wsm.ird5third;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRThirdError=class(Exception);
function BuildPinnedIRThirdELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,
     wsm.exactirguard,wsm.elfgeometry,wsm.elfwriteguard,wsm.x64code,wsm.x64stack;

const HeaderBytes=120;
procedure Need(Good:Boolean;const Why:UnicodeString);
begin
  if not Good then raise EIRThirdError.Create(RawByteString(UTF8Encode(Why)));
end;

{ Запозичений IR — тільки pinned ключі, індекси та фізичні адреси.
  Він не містить SENS значень часу виконання або текстових імен.
  Питання: чому D5:10011 не D4:1001? Чому D3:000 не D1:0?
  Чому форму треба перевірити перед машинним lowering? }
function D1Value(const IR:TExactIR; N,Parent,Child:SizeInt):Byte;
var Node:TExactIRNode; Bits:RawByteString;
begin
  Node:=IR.Nodes[N];
  Need((Node.Kind=ikIdentity) and Node.HasKey and
       (Node.ParentIndex=Parent) and (Node.ChildIndex=Child) and
       (Node.SubtreeEndExclusive=N+1) and
       (Node.Key.Width=1),'Операнд має бути точним D1');
  Bits:=KeyBits(Node.Key);
  if Bits='0' then Result:=0
  else if Bits='1' then Result:=1
  else raise EIRThirdError.Create('Недопустимий точний біт D1');
end;

function BuildPinnedIRThirdELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet; IR:TExactIR; Stats:TExactIRGuardStats;
    Words:TExactWords; Values:array[0..2] of Byte;
    Zero,One,Machine:RawByteString; Delta:Byte;
    Geometry:TELFGeometry; Code:TX64Code; I,Total:SizeInt;
  procedure PutLE(At:SizeInt;Value:QWord;Width:SizeInt);
  var J:SizeInt;
  begin
    Need((At>=0) and (Width>=1) and (Width<=8) and
         (At<=Length(Result)-Width),'Порушена геометрія ELF64');
    for J:=0 to Width-1 do begin
      Result[At+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;
begin
  Result:='';
  try
    Need((Length(Physical)>0) and (Length(Physical)<=65536),
      'Фізична програма поза межею');
    DecodeT5M(Physical,Words);
    Need(EncodeT5M(Words)=Physical,'Не канонічний packed T5M');
    LoadPinnedDomains(AuthorityRoot,Tables);
    BuildExactIR(Physical,Tables,IR);
    VerifyExactIRStructure(IR,Stats);
    Need((Length(IR.Roots)=1) and (IR.Roots[0]=0) and
         (Length(IR.Nodes)=7) and (IR.BoundLeaves=5),
         'Потрібна одна D5:10011(D4:1110 D1 D1 D1)');
    Need((IR.Nodes[0].Kind=ikList) and
         (IR.Nodes[0].ParentIndex=-1) and
         (IR.Nodes[0].SubtreeEndExclusive=7) and
         (IR.Nodes[1].Kind=ikIdentity) and IR.Nodes[1].HasKey and
         (IR.Nodes[1].ParentIndex=0) and (IR.Nodes[1].ChildIndex=0) and
         (IR.Nodes[1].Key.Width=5) and
         (KeyBits(IR.Nodes[1].Key)='10011') and
         (IR.Nodes[2].Kind=ikList) and
         (IR.Nodes[2].ParentIndex=0) and (IR.Nodes[2].ChildIndex=1) and
         (IR.Nodes[2].SubtreeEndExclusive=7) and
         (IR.Nodes[3].Kind=ikIdentity) and IR.Nodes[3].HasKey and
         (IR.Nodes[3].ParentIndex=2) and (IR.Nodes[3].ChildIndex=0) and
         (IR.Nodes[3].Key.Width=4) and
         (KeyBits(IR.Nodes[3].Key)='1110'),
         'Порушено ратифіковані D5/D4 точні координати');
    for I:=0 to 2 do Values[I]:=D1Value(IR,I+4,2,I+1);
    SetLength(Words,1);
    Words[0]:='0';Zero:=EncodeT5M(Words);
    Words[0]:='1';One:=EncodeT5M(Words);
    Need((Length(Zero)=1) and (Length(One)=1) and
         (Ord(Zero[1])<=127) and (Ord(One[1])>Ord(Zero[1])) and
         (Ord(One[1])-Ord(Zero[1])<=127),
         'Непідтримане точне кодування D1 через T5M');
    Delta:=Ord(One[1])-Ord(Zero[1]);
    { Три власні QWord-комірки живуть тільки у процесі ELF.
      x86-64 MOV [rsi+16] обирає ТРЕТЮ комірку при запуску, а
      IMUL/ADD кодують D1 за поточним T5M codec. Жодної готової
      семантичної відповіді в ELF немає.
      Питання: де фактично живуть три елементи? Хто формує T5M?
      Чому дані не інтерпретуються як D12? Як завершено lifetime? }
    { G6: кадр і STORE через перевірений x64stack (вирівняння, fail-closed). }
    X64Reset(Code);
    X64MovImm32(Code,xrAX,Values[0]);
    X64MovImm32(Code,xrCX,Values[1]);
    X64MovImm32(Code,xrDX,Values[2]);
    X64StackSubtract(Code,32);
    X64StackStore(Code,xrAX,0);
    X64StackStore(Code,xrCX,8);
    X64StackStore(Code,xrDX,16);
    X64LeaRSIRsp(Code);
    X64LoadRDXRSI(Code,16);
    X64ImulEDX8(Code,Delta);
    X64AddEDX8(Code,Byte(Zero[1]));
    X64StoreRspDL(Code);
    X64MovImm32(Code,xrAX,1);
    X64MovImm32(Code,xrDI,1);
    X64MovRSIRsp(Code);
    X64MovImm32(Code,xrDX,1);
    X64Syscall(Code);
    X64MovImm32(Code,xrAX,60);
    X64XorEDI(Code);
    X64Syscall(Code);
    Machine:=X64Image(Code);
    Need((Length(Machine)>60) and (Length(Machine)<256),
      'Вихідний машинний код поза host-межами');
    Total:=HeaderBytes+Length(Machine);
    SetLength(Result,Total);
    FillChar(Result[1],Total,0);
    PutLE(0,$464C457F,4);
    PutLE(4,2,1);PutLE(5,1,1);PutLE(6,1,1);
    PutLE(16,3,2);PutLE(18,62,2);PutLE(20,1,4);
    PutLE(24,HeaderBytes,8);PutLE(32,64,8);
    PutLE(52,64,2);PutLE(54,56,2);PutLE(56,1,2);
    PutLE(64,1,4);PutLE(68,5,4);
    PutLE(80,0,8);PutLE(88,0,8);
    PutLE(96,Total,8);PutLE(104,Total,8);PutLE(112,$1000,8);
    for I:=1 to Length(Machine) do Result[HeaderBytes+I]:=Machine[I];
    VerifySENSELF64(Result,Geometry);
    Need((Geometry.Kind=3) and (Geometry.FileBytes=Total),
      'ELF64 PIE не пройшов незалежну геометрію');
    { G6.234: обов'язковий повний Linux write, а не лише sys_write. }
    Result:=RequireCompleteNativeWrite(Result);
    VerifySENSELF64(Result,Geometry);
    Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Result)) and
         (Length(Result)=Total+11),
         'ELF64 з контрольованим Linux write має неправильну геометрію');
  except
    on E:EIRThirdError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRThirdError.Create('Нативний D5:10011 відхилено: '+E.Message);
    end;
  end;
end;
end.
