{ G6.174 — D5:01001 «число?» над exact D1:0/D1:1 тепер дає D1:0.
  G6.158 — нативна спеціалізація pinned D12/D24 атома дає D1:1.
  Повна двійкова форма → pinned WideIR, без іменного dispatch.
  Статично допущений числовий домен дає D1:1, D1 — D1:0; у ELF працює
  справжній Linux syscall write, вивід — канонічний T5M, не ASCII.
  Це НЕ загальний numberp для довільних значень і НЕ REPL. }
unit wsm.irwidenumberp;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EIRWideNumberError=class(Exception);
function BuildIRWideNumberELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.domain,wsm.bind,wsm.wideir,wsm.wideirguard,
     wsm.numericplane,wsm.elfgeometry;
const
  HeaderBytes=120;
  { Машинний ET_DYN: write(1, &T5M_D1_1, 1), exit(0);
    якщо write не повернув 1 — exit(1). Код незалежний від Pascal RTL. }
  MachineCode=
    #$B8#$01#0#0#0+
    #$BF#$01#0#0#0+
    #$48#$8D#$35#$26#0#0#0+
    #$BA#$01#0#0#0+
    #$0F#$05+
    #$48#$83#$F8#$01+
    #$0F#$85#$09#0#0#0+
    #$B8#$3C#0#0#0+
    #$31#$FF+#$0F#$05+
    #$B8#$3C#0#0#0+
    #$BF#$01#0#0#0+
    #$0F#$05;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise EIRWideNumberError.Create(Why) end;

{ Image: owned managed byte array, D1 фізичний байт створено
  чинним EncodeT5M, не машинною константою або ASCII '1'.
  Host ELF заголовок і RIP/rel32 — лише ABI, не SENS-координати.
  1) Чому код розміщується рівно після 120 байтів?
  2) Чому запис мусить бути рівно одного байта?
  3) Чому не дозволена часткова відповідь при помилці?
  4) Чому ELF PT_LOAD не визначає мовних законів?
  5) Коли звільняється managed Result? }
function MakeMachineAnswer(const AnswerBits:RawByteString):RawByteString;
var W:TExactWords;D1:RawByteString;G:TELFGeometry;I:SizeInt;
  procedure Put(At:SizeInt;Value:QWord;Width:SizeInt);
  var K:SizeInt;
  begin
    Need((At>=0) and (Width>=1) and (Width<=8) and
      (At<=Length(Result)-Width),'пошкоджено межі ELF64');
    for K:=0 to Width-1 do begin
      Result[At+K+1]:=AnsiChar(Byte(Value and $FF));
      Value:=Value shr 8;
    end;
  end;
begin
  Need((AnswerBits='0') or (AnswerBits='1'),
       'потрібна точна двійкова відповідь D1');
  SetLength(W,1);W[0]:=AnswerBits;
  D1:=EncodeT5M(W);
  Need((Length(D1)=1) and (Length(MachineCode)=55),
       'порушено перевірений фізичний/машинний формат');
  SetLength(Result,HeaderBytes+Length(MachineCode)+1);
  FillChar(Result[1],Length(Result),0);
  Put(0,$464C457F,4);
  Put(4,2,1);Put(5,1,1);Put(6,1,1);
  Put(16,3,2);Put(18,62,2);Put(20,1,4);
  Put(24,HeaderBytes,8);Put(32,64,8);
  Put(52,64,2);Put(54,56,2);Put(56,1,2);
  Put(64,1,4);Put(68,5,4);
  Put(80,0,8);Put(88,0,8);
  Put(96,Length(Result),8);Put(104,Length(Result),8);Put(112,$1000,8);
  for I:=1 to Length(MachineCode) do Result[HeaderBytes+I]:=MachineCode[I];
  Result[Length(Result)]:=D1[1];
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=HeaderBytes) and
       (G.FileBytes=Length(Result)),'некоректний нативний PIE ELF64');
end;

{ Physical: borrowed canonical T5M source; AuthorityRoot: pinned gitlink.
  IR, Tables, Numeric і Words — локальна керована FPC пам'ять.
  Одне джерело законів pinned D5:01001: перевіряється точний W5.
  W12/W24 НЕ отримує числового статусу за самою шириною: лише
  явний ReadNumericPhysical після допущеного профілю D5.
  D1:0 і D1:1 приймаємо тільки як pinned W1, а НЕ як число.
  Result: новий owned ELF64 ET_DYN з exact D1:0 або D1:1 T5M stdout.
  1) Чому форма D5:01000 тут повинна відхилятися?
  2) Чому D7 текст не бере участі в ідентичності?
  3) Чому numeric D1 не може бути числом?
  4) Який негатив перевіряє невідому викличність?
  5) Який зовнішній oracle підтверджує спеціалізацію? }
function BuildIRWideNumberELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var Tables:TDomainSet;IR:TWideIR;Stats:TWideIRGuardStats;
    Decoded,AtomWords:TExactWords;Atom:RawByteString;
    Numeric:TExplicitNumeric;Head,Value:TWideIRNode;
begin
  Result:='';
  Need((Length(Physical)>0) and (Length(Physical)<=65536),
       'неприпустима довжина канонічної програми T5M');
  DecodeT5M(Physical,Decoded);
  Need(EncodeT5M(Decoded)=Physical,'фізичне T5M не канонічне');
  LoadPinnedDomains(String(AuthorityRoot),Tables);
  BuildWideIR(Physical,Tables,IR);
  VerifyWideIRStructure(IR,Stats);
  Need((Stats.Nodes=3) and (Stats.Roots=1) and
       (Stats.PhysicalLeaves=2) and (Stats.OpaqueLeaves in [0,1]) and
       (Length(IR.Nodes)=3) and (Length(IR.Roots)=1) and
       (IR.Roots[0]=0),'потрібна одна плоска D5 форма з числовим атомом');
  Need((IR.Nodes[0].Kind=wkList) and
       (IR.Nodes[0].RootIndex=0) and (IR.Nodes[0].ParentIndex=-1) and
       (IR.Nodes[0].ChildIndex=0) and (IR.Nodes[0].Depth=0),
       'корінь не є точним D2 списком');
  Head:=IR.Nodes[1];
  Need((Head.Kind=wkAtom) and Head.OwnWord and Head.HasPinnedKey and
       (Head.Width=5) and (Head.Bits='01001') and
       SameKey(Head.NarrowKey,ExactKey('01001')) and
       (Head.ParentIndex=0) and (Head.RootIndex=0) and
       (Head.ChildIndex=0) and (Head.Depth=1),
       'непідтверджена ратифікована D5:01001 голова');
  Value:=IR.Nodes[2];
  Need((Value.Kind=wkAtom) and Value.OwnWord and
       (Length(Value.Bits)=Value.Width) and
       (Value.ParentIndex=0) and (Value.RootIndex=0) and
       (Value.ChildIndex=1) and (Value.Depth=1),
       'підтриманий тільки один фізичний атом');
  if Value.Width=1 then begin
    { Exact W1 прив'язано до D1 за pinned контрактом, не за назвою.
      D1:0 та D1:1 — обидва НЕ числа. Це не host truthiness. }
    Need((Value.HasPinnedKey) and ((Value.Bits='0') or (Value.Bits='1')) and
         SameKey(Value.NarrowKey,ExactKey(Value.Bits)) and
         (Stats.OpaqueLeaves=0),
         'непідтверджений фізичний предикат D1');
    Result:=MakeMachineAnswer('0');
  end else begin
    Need((Value.Width in [12,24]) and (not Value.HasPinnedKey) and
         (Stats.OpaqueLeaves=1),
         'підтримані тільки pinned D1 та opaque D12/D24');
    SetLength(AtomWords,1);
    AtomWords[0]:=Value.Bits;
    Atom:=EncodeT5M(AtomWords);
    Numeric:=ReadNumericPhysical(Atom,Value.Width);
    Need((Numeric.DomainWidth=Value.Width) and
         (Numeric.ExactBits=Value.Bits),
         'втрачено точні біти/домен числового аргументу');
    Result:=MakeMachineAnswer('1');
  end;
end;
end.
