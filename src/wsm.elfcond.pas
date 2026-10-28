{ G6.20 — фізичний SENS D3:110 -> справжній Linux x86-64 ELF64.
  До 32 гілок: D1 test або вкладений D3:101 двох точних D1.
  Рівність обчислюють машинні CMP/SETE, не Pascal host bool.
  Закон — pinned SENS Contract 12 K12.3; ELF не є мовним .sens. }
unit wsm.elfcond;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfCondError=class(Exception);
function BuildCondELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.d2source,wsm.binarybind,wsm.bind,wsm.domain,wsm.binaryexec;
const
  ELFBase:QWord=$400000;
  ELFCodeOffset=64+56;
  MaxClauses=32; { ресурсний ліміт emitter, не ратифікація SENS }
  MaxMachineBytes=4096;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

function BuildCondELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Doc:TD2Document;
  Bound:TBinaryWords;
  Tables:TDomainSet;
  Engine:TBinaryExecutor;
  Exact:TExactWords;
  Machine,Answer:RawByteString;
  I,J,Total,Count,At:SizeInt;
  Tests:array of record
    Kind,LeftBit,RightBit:Byte; { 0 = D1; 1 = pinned D3:101 }
  end;
  ExpressionBits:array of Byte;
  Clause,Head:TD2Node;

  procedure Fail(const Why:UnicodeString);
  begin raise EElfCondError.Create(UA(Why)); end;

  procedure Add(B:Byte);
  begin
    if Length(Machine)>=MaxMachineBytes then
      Fail('Перевищено допустимий машинний код умовної форми');
    Machine:=Machine+AnsiChar(B);
  end;

  procedure Put(Offset:SizeInt; V:QWord; Width:SizeInt);
  var K:SizeInt;
  begin
    if (Offset<0) or (Width<1) or (Width>8) or
       (Offset>Length(Result)-Width) then
      Fail('Порушено межі ELF64');
    for K:=0 to Width-1 do begin
      Result[Offset+K+1]:=AnsiChar(Byte(V and $FF));
      V:=V shr 8;
    end;
  end;

  function ExactD1(N:TD2Node; Index:SizeInt):Byte;
  var Bits:RawByteString;
  begin
    if (N=nil) or (N.Kind<>dkIdentity) or (N.Width<>1) or
       (Length(N.Bits)<>1) or (Index<0) or (Index>=Length(Bound)) then
      Fail('Гілка D3:110: допустимий лише точний атом D1');
    Bits:=KeyBits(Bound[Index].Key);
    if (Bound[Index].RootIndex<>0) or
       (Bound[Index].WordIndex<>N.WordIndex) or
       (Bound[Index].Key.Width<>1) or Bound[Index].IsEmpty or
       (Bits<>N.Bits) then
      Fail('Порушено pinned ідентичність D1');
    if Bits='0' then Result:=0
    else if Bits='1' then Result:=1
    else Fail('Невідомий точний біт D1');
  end;

  { Кожний машинний шлях виводить точне представлення результату.
    Це host-транспорт stdout, не бінарне кодування .sens. }
  procedure EmitWrite(const Value:RawByteString);
  var K:SizeInt;
  begin
    if (Value<>'0'+#10) and (Value<>'1'+#10) and
       (Value<>'()'+#10) then Fail('Недопустимий результат D3:110');
    Add($48);Add($83);Add($EC);Add($08); { sub rsp,8 }
    for K:=1 to Length(Value) do begin
      if K=1 then begin
        Add($C6);Add($04);Add($24);Add(Ord(Value[K]));
      end else begin
        Add($C6);Add($44);Add($24);Add(K-1);Add(Ord(Value[K]));
      end;
    end;
    Add($B8);Add(1);Add(0);Add(0);Add(0); { SYS_write }
    Add($BF);Add(1);Add(0);Add(0);Add(0); { stdout }
    Add($48);Add($89);Add($E6);         { rsi=rsp }
    Add($BA);Add(Length(Value));Add(0);Add(0);Add(0);
    Add($0F);Add($05);                  { syscall }
    Add($B8);Add($3C);Add(0);Add(0);Add(0); { SYS_exit }
    Add($31);Add($FF);Add($0F);Add($05);
  end;

  procedure EmitClause(TestKind,LeftBit,RightBit,ValueBit:Byte);
  var JumpOffset,StartCode:SizeInt;
  begin
    Add($B8);Add(LeftBit);Add(0);Add(0);Add(0); { mov eax, D1 }
    if TestKind=1 then begin
      Add($B9);Add(RightBit);Add(0);Add(0);Add(0); { mov ecx, D1 }
      Add($39);Add($C8);                       { cmp eax, ecx }
      Add($0F);Add($94);Add($C0);             { sete al }
      Add($0F);Add($B6);Add($C0);             { movzx eax, al }
    end else if TestKind<>0 then
      Fail('Неприпустимий тип машинного предиката');
    Add($83);Add($F8);Add(1);                  { cmp eax, D1:1 }
    Add($75);JumpOffset:=Length(Machine)+1;
    Add(0);                                    { jne next clause }
    StartCode:=Length(Machine);
    EmitWrite(AnsiChar(Ord('0')+ValueBit)+#10);
    if Length(Machine)-StartCode>127 then
      Fail('Завелика умовна машинна гілка');
    Machine[JumpOffset]:=AnsiChar(Length(Machine)-StartCode);
  end;

begin
  Result:='';Doc:=nil;Engine:=nil;Machine:='';
  try
    try
      DecodeT5M(Physical,Exact);
      if EncodeT5M(Exact)<>Physical then
        Fail('Фізичний T5M неканонічний');
      Doc:=ParseD2Words(Exact);
      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      if (Length(Doc.Roots)<>1) or (Doc.Roots[0]=nil) or
         (Doc.Roots[0].Kind<>dkList) then
        Fail('Потрібна одна фізична форма D3:110');
      Count:=Length(Doc.Roots[0].Children)-1;
      if (Count<0) or (Count>MaxClauses) or (Length(Bound)<1) then
        Fail('Цей backend підтримує не більше 32 двопольових гілок D3:110');
      Head:=Doc.Roots[0].Children[0];
      if (Head=nil) or (Head.Kind<>dkIdentity) or
         (Head.Width<>3) or (Head.Bits<>'110') or
         (Bound[0].RootIndex<>0) or Bound[0].IsEmpty or
         (Bound[0].WordIndex<>Head.WordIndex) or
         (Bound[0].Key.Width<>3) or
         (KeyBits(Bound[0].Key)<>'110') then
        Fail('Відсутня точна pinned голова D3:110');
      { Pinned binder має preorder лише за фізичними листками.
        Для вкладеного EQ курсор зростає на голову й два D1 слова;
        неприйнятий або зайвий фізичний листок — відмова. }
      SetLength(Tests,Count);
      SetLength(ExpressionBits,Count);
      At:=1;
      for I:=0 to Count-1 do begin
        Clause:=Doc.Roots[0].Children[I+1];
        if (Clause=nil) or (Clause.Kind<>dkList) or
           (Length(Clause.Children)<>2) then
          Fail('Гілка D3:110 має рівно два поля');
        if (Clause.Children[0]<>nil) and
           (Clause.Children[0].Kind=dkList) then begin
          { D3:101 — лише pinned машинна голова з двома D1.
            Жодна текстова українська назва не бере участі. }
          if Length(Clause.Children[0].Children)<>3 then
            Fail('Вкладена тотожність D3:101 має два операнди');
          Head:=Clause.Children[0].Children[0];
          if (Head=nil) or (Head.Kind<>dkIdentity) or
             (Head.Width<>3) or (Head.Bits<>'101') or
             (At>=Length(Bound)) then
            Fail('Вкладена перевірка має бути D3:101');
          if (Bound[At].RootIndex<>0) or Bound[At].IsEmpty or
             (Bound[At].WordIndex<>Head.WordIndex) or
             (Bound[At].Key.Width<>3) or
             (KeyBits(Bound[At].Key)<>'101') then
            Fail('Вкладена голова D3:101 не збігається з pinned');
          Inc(At);
          Tests[I].Kind:=1;
          Tests[I].LeftBit:=ExactD1(Clause.Children[0].Children[1],At);
          Inc(At);
          Tests[I].RightBit:=ExactD1(Clause.Children[0].Children[2],At);
          Inc(At);
        end else begin
          Tests[I].Kind:=0;
          Tests[I].LeftBit:=ExactD1(Clause.Children[0],At);
          Inc(At);
        end;
        ExpressionBits[I]:=ExactD1(Clause.Children[1],At);
        Inc(At);
      end;
      if At<>Length(Bound) then
        Fail('Зайві або втрачені слова pinned preorder');
      { Перевірка чинним вузьким executor — не окремий oracle SENS. }
      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Answer:=Engine.ExecutePhysical(Physical);
      if (Answer<>'0') and (Answer<>'1') and (Answer<>'()') then
        Fail('Виконавець D3 не підтвердив форму результату');
      { Рішення приймається справжнім машинним CMP/JNE, а не
        копіюванням Answer як готової відповіді у ELF. }
      for I:=0 to Count-1 do
        EmitClause(Tests[I].Kind,Tests[I].LeftBit,Tests[I].RightBit,
          ExpressionBits[I]);
      EmitWrite('()'+#10); { вичерпання: точне структурне D3:000 }
      Total:=ELFCodeOffset+Length(Machine);
      SetLength(Result,Total);
      for J:=1 to Total do Result[J]:=#0;
      Put(0,$464C457F,4);
      Put(4,2,1);Put(5,1,1);Put(6,1,1);
      Put(16,2,2);Put(18,62,2);Put(20,1,4);
      Put(24,ELFBase+ELFCodeOffset,8);Put(32,64,8);
      Put(52,64,2);Put(54,56,2);Put(56,1,2);
      Put(64,1,4);Put(68,5,4);
      Put(80,ELFBase,8);Put(88,ELFBase,8);
      Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
      for J:=1 to Length(Machine) do Result[ELFCodeOffset+J]:=Machine[J];
    except
      on E:EElfCondError do raise;
      on E:Exception do raise EElfCondError.Create(
        UA('Машинну форму D3:110 відхилено: ')+E.Message);
    end;
  finally
    Engine.Free;
    Doc.Free;
  end;
end;
end.
