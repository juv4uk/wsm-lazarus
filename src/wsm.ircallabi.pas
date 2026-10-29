{ G6.69 — точний pinned D3:101(D1,D1) → x86-64 CALL/RET → T5M.
  Історичний juv4uk/mccarthy-eval — архітектурний донор ABI,
  не семантичний авторитет. Вхід тільки canonical binary .sens.
  Це вузький механізм машинного виклику, НЕ загальний APPLY/REPL. }
unit wsm.ircallabi;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRCallABIError=class(Exception);
function BuildPinnedD1EqCallELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.exactir,wsm.exactirguard,
     wsm.elfgeometry;

const HeaderBytes=120; MaxSourceBytes=65536; MaxMachineBytes=128;

procedure Require(Condition:Boolean;const Why:String);
begin
  if not Condition then raise EIRCallABIError.Create(Why);
end;

function GetD1(const Node:TExactIRNode;Position:SizeInt):Byte;
var Bits:RawByteString;
begin
  Require((Node.Kind=ikIdentity) and Node.HasKey and
          (Node.ParentIndex=0) and (Node.ChildIndex=Position) and
          (Node.SubtreeEndExclusive=Position+2) and
          (Node.Key.Width=1),
    'Потрібен точний зв’язаний атом D1 у заданій позиції');
  Bits:=KeyBits(Node.Key);
  if Bits='0' then Exit(0);
  if Bits='1' then Exit(1);
  raise EIRCallABIError.Create('Невідоме ратифіковане D1 слово');
end;

{ Borrowed IR після BuildExactIR; жодних lookup за "укр", англійськими
  назвами чи host-тегами. Результат — два машинні immediate D1-біти,
  але тільки після повного pinned фізичного admission.
  Питання: чому шість ратифікованих проєкцій не впливають на dispatch?
  Чому D12 не заміняє D1 при рівності numeric payload?
  Що доводить точний порядок/батьківство IR?
  Які перевірки виконуються до емісії першого байта ELF? }
procedure LowerD1Eq(const IR:TExactIR;out LeftBit,RightBit:Byte);
begin
  LeftBit:=0;RightBit:=0;
  Require((Length(IR.Roots)=1) and (IR.Roots[0]=0) and
          (Length(IR.Nodes)=4) and (IR.BoundLeaves=3),
    'Потрібна одна фізична чотиривузлова D3 рівність');
  Require((IR.Nodes[0].Kind=ikList) and
          (IR.Nodes[0].ParentIndex=-1) and
          (IR.Nodes[0].SubtreeEndExclusive=4),
    'Невірна структура одного D2 виклику');
  Require((IR.Nodes[1].Kind=ikIdentity) and IR.Nodes[1].HasKey and
          (IR.Nodes[1].ParentIndex=0) and
          (IR.Nodes[1].ChildIndex=0) and
          (IR.Nodes[1].SubtreeEndExclusive=2) and
          SameKey(IR.Nodes[1].Key,ExactKey('101')),
    'Голова не є ратифікованою D3:101');
  LeftBit:=GetD1(IR.Nodes[2],1);
  RightBit:=GetD1(IR.Nodes[3],2);
end;

{ Машинний підпрограмний ABI: args у EDI/ESI, result EAX, CALL rel32
  на окремий функціональний блок, CMP/SETE/MOVZX, RET. Фізична
  адреса коду обчислюється тільки з довжин власного ELF, не з host
  покажчиків. RSP вирівняно до 16 перед CALL (callee отримує %16=8).
  Код НЕ обчислює відповідь у Pascal: вона виникає після CALL у CPU.
  Zero/One — pinned codec, не вбудований ASCII або SENS textual law.
  Питання: чому EDI/ESI не є функціональними іменами SENS?
  Чому call rel32 придатний і до ET_DYN/ASLR?
  Як CALL/RET впливають на вирівнювання стека?
  Чому два immediate не означають результат constant-folding?
  Хто володіє RawByteString Machine/Result? }
function EmitD1Call(const LeftBit,RightBit:Byte):RawByteString;
var Zero,One,Machine:RawByteString; Words:TExactWords;
    Diff,CallAt,FunctionAt,Total,I:SizeInt; Delta:Byte;
    Geometry:TELFGeometry;
  procedure PutLE(Offset:SizeInt;Value:QWord;Width:SizeInt);
  var J:SizeInt;
  begin
    Require((Offset>=0) and (Width>=1) and (Width<=8) and
            (Offset<=Length(Result)-Width),
      'Машинне поле ELF64 за фізичною межею');
    for J:=0 to Width-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;
begin
  Result:='';
  Require((LeftBit<=1) and (RightBit<=1),'D1 ABI отримав не D1');
  SetLength(Words,1);
  Words[0]:='0';Zero:=EncodeT5M(Words);
  Words[0]:='1';One:=EncodeT5M(Words);
  Require((Length(Zero)=1) and (Length(One)=1) and
    (Byte(One[1])>Byte(Zero[1])) and
    (Byte(One[1])-Byte(Zero[1])<=127),
    'Не підтверджено канонічне кодування двох D1 результатів');
  Delta:=Byte(One[1])-Byte(Zero[1]);

  Machine:=#$BF+AnsiChar(LeftBit)+#0#0#0 + { mov edi,left }
           #$BE+AnsiChar(RightBit)+#0#0#0 + { mov esi,right }
           #$48#$83#$E4#$F0;             { and rsp,-16 }
  CallAt:=Length(Machine);
  Machine:=Machine+#$E8#0#0#0#0;         { call rel32: fixup нижче }
  Machine:=Machine+
    #$6B#$C0+AnsiChar(Delta)+        { imul eax,eax,T5M delta }
    #$83#$C0+Zero[1]+               { add eax,physical D1:0 }
    #$48#$83#$EC#$08+                { sub rsp,8 }
    #$88#$04#$24+                    { mov [rsp],al }
    #$B8#$01#0#0#0+                  { Linux write(1,rsp,1) }
    #$BF#$01#0#0#0+
    #$48#$89#$E6+
    #$BA#$01#0#0#0+
    #$0F#$05+
    #$B8#$3C#0#0#0+                  { Linux exit(0) }
    #$31#$FF+#$0F#$05;
  FunctionAt:=Length(Machine);
  Machine:=Machine+
    #$39#$F7+                        { cmp edi,esi }
    #$0F#$94#$C0+                    { sete al }
    #$0F#$B6#$C0+                    { movzx eax,al }
    #$C3;                            { ret }
  Diff:=FunctionAt-(CallAt+5);
  Require((Diff>=0) and (Diff<=High(LongInt)),
    'CALL виходить за межі rel32');
  for I:=0 to 3 do
    Machine[CallAt+2+I]:=AnsiChar(Byte((QWord(Diff) shr (I*8)) and $FF));
  Require((Length(Machine)>FunctionAt) and
          (Length(Machine)<=MaxMachineBytes),
    'Машинна програма перевищила host квоту');
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
  Require((Geometry.Kind=3) and (Geometry.FileBytes=Total) and
    (Geometry.MachineBytes=Length(Machine)),
    'Не допущено повний native ELF64 PIE');
end;

{ Фізичний source є borrowed; таблиці й IR — локальні FPC-managed.
  Відмови не публікують частковий машинний об'єкт. Підстановка іншого
  .sens повністю повторює pinned reader+binder перед викликом.
  Питання: чому тут немає розпізнавання голів за текстом?
  Чи можна розширити цей ABI до довільної LAMBDA без нової перевірки?
  Яка різниця між pinned оцінкою семантики та механікою CALL?
  Чому це не вимірювання джоулів? }
function BuildPinnedD1EqCallELF(const Physical,AuthorityRoot:RawByteString):
  RawByteString;
var Tables:TDomainSet; IR:TExactIR; Stats:TExactIRGuardStats;
    LeftBit,RightBit:Byte;
begin
  Result:='';
  try
    Require((Length(Physical)>=1) and (Length(Physical)<=MaxSourceBytes),
      'Фізичне джерело поза host квотою');
    LoadPinnedDomains(AuthorityRoot,Tables);
    BuildExactIR(Physical,Tables,IR);
    VerifyExactIRStructure(IR,Stats);
    LowerD1Eq(IR,LeftBit,RightBit);
    Result:=EmitD1Call(LeftBit,RightBit);
  except
    on E:EIRCallABIError do begin Result:='';raise end;
    on E:Exception do begin
      Result:='';
      raise EIRCallABIError.Create(
        'Не допущено нативний CALL/RET: '+E.Message);
    end;
  end;
end;
end.
