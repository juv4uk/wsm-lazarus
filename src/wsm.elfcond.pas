{ G6.17 — фізичний SENS D3:110 -> справжній Linux x86-64 ELF64.
  Лише 0..2 гілки з точними D1 предикатами та результатами.
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
  MaxMachineBytes=256;
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
  TestBits,ExpressionBits:array[0..1] of Byte;
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

  procedure EmitClause(TestBit,ValueBit:Byte);
  var JumpOffset,StartCode:SizeInt;
  begin
    Add($B8);Add(TestBit);Add(0);Add(0);Add(0); { mov eax, D1 }
    Add($83);Add($F8);Add(1);                  { cmp eax, 1 }
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
      if (Count<0) or (Count>2) or (Length(Bound)<>1+2*Count) then
        Fail('Підтримано тільки 0–2 двопольові гілки D3:110');
      Head:=Doc.Roots[0].Children[0];
      if (Head=nil) or (Head.Kind<>dkIdentity) or
         (Head.Width<>3) or (Head.Bits<>'110') or
         (Bound[0].RootIndex<>0) or Bound[0].IsEmpty or
         (Bound[0].WordIndex<>Head.WordIndex) or
         (Bound[0].Key.Width<>3) or
         (KeyBits(Bound[0].Key)<>'110') then
        Fail('Відсутня точна pinned голова D3:110');
      for I:=0 to Count-1 do begin
        Clause:=Doc.Roots[0].Children[I+1];
        if (Clause=nil) or (Clause.Kind<>dkList) or
           (Length(Clause.Children)<>2) then
          Fail('Гілка D3:110 має рівно два поля');
        At:=1+2*I;
        TestBits[I]:=ExactD1(Clause.Children[0],At);
        ExpressionBits[I]:=ExactD1(Clause.Children[1],At+1);
      end;
      { Перевірка чинним вузьким executor — не окремий oracle SENS. }
      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Answer:=Engine.ExecutePhysical(Physical);
      if (Answer<>'0') and (Answer<>'1') and (Answer<>'()') then
        Fail('Виконавець D3 не підтвердив форму результату');
      { Рішення приймається справжнім машинним CMP/JNE, а не
        копіюванням Answer як готової відповіді у ELF. }
      for I:=0 to Count-1 do EmitClause(TestBits[I],ExpressionBits[I]);
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
