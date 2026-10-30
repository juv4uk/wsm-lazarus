{ G6.9 — замкнена D3:010(ATOM) як справжні інструкції x86-64.
  Першоджерело — pinned SENS Contract 12 та фізичний T5M/D2/binder.
  Дозволено тільки спостереження «атом чи пара»: для D3:111(CONS)
  будується тимчасовий TAG пари, НЕ heap-комірка або повний CONS.
  Лише runtime x86 CMP/SETNE створює результат ATOM, не FPC output. }
unit wsm.elfatom;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfAtomError=class(Exception);
function BuildAtomELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
{ Host-only перевірений publish wrapper. Не змінює raw D3 донор для
  BuildAtomT5MELF і його exact OldSuffix; CLI працює лише через wrapper. }
function BuildCheckedAtomELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.d2source,wsm.t5m,wsm.binarybind,wsm.bind,
     wsm.domain,wsm.binaryexec,wsm.elfwriteguard;

const
  ELFBase:QWord=$400000;
  CodeOffset=64+56;
  MaxMachineBytes=2048;
  MaxAtomDepth=32;
  MaxAtomLeaves=128;
  PairArenaBytes=2048; { 128 * 16, host-ресурс, не SENS-закон }

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

function BuildAtomELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Doc:TD2Document;
  Bound:TBinaryWords;
  Tables:TDomainSet;
  Engine:TBinaryExecutor;
  Machine,Answer:RawByteString;
  LeafCount,NodeCount:SizeInt;

  procedure Fail(const Why:UnicodeString);
  begin raise EElfAtomError.Create(UA(Why)); end;

  procedure Add(B:Byte);
  begin
    if Length(Machine)>=MaxMachineBytes then
      Fail('Перевищено машинний ліміт коду');
    Machine:=Machine+AnsiChar(B);
  end;

  procedure MovTag(T:Byte);
  begin
    Add($B8);Add(T);Add(0);Add(0);Add(0); { mov eax, tag }
  end;

  procedure KeyedLeaf(N:TD2Node);
  var K:TDomainKey;
  begin
    if (N=nil) or (LeafCount>=Length(Bound)) then
      Fail('Немає зв’язаного фізичного слова');
    K:=Bound[LeafCount].Key;
    if (Bound[LeafCount].WordIndex<>N.WordIndex) or
       (Bound[LeafCount].RootIndex<>0) or
       (K.Width<>N.Width) or (KeyBits(K)<>N.Bits) or
       (Bound[LeafCount].IsEmpty<>(N.Kind=dkEmpty)) then
      Fail('Фізичний вузол не збігся з pinned exact-domain binder');
    Inc(LeafCount);
  end;

  procedure EmitExpr(N:TD2Node;Depth:SizeInt);
  var Opcode:RawByteString;
  begin
    if N=nil then Fail('Відсутній вузол D2');
    Inc(NodeCount);
    if (Depth>MaxAtomDepth) or (NodeCount>MaxAtomLeaves) then
      Fail('Перевищено межу вкладеності чи кількості форм');
    case N.Kind of
      dkIdentity:begin
        KeyedLeaf(N);
        if N.Width<>1 then Fail('Непідтримана двійкова ширина значення');
        if N.Bits='0' then MovTag(1)
        else if N.Bits='1' then MovTag(2)
        else Fail('Непідтверджений D1 літерал');
      end;
      dkEmpty:begin
        KeyedLeaf(N);
        if (N.Width<>3) or (N.Bits<>'000') then
          Fail('Тільки pinned D3:000 є структурною порожнечею');
        MovTag(0); { структурний порожній список, не D1:0 }
      end;
      dkList:begin
        if Length(N.Children)=0 then begin
          MovTag(0); { порожній D2-список, НЕ D1:0 або D3:000 }
          Exit;
        end;
        if (N.Children[0]=nil) or
           (N.Children[0].Kind<>dkIdentity) then
          Fail('Непідтримана обчислювана голова D3');
        KeyedLeaf(N.Children[0]);
        if N.Children[0].Width<>3 then
          Fail('Потрібна точна D3 голова');
        Opcode:=N.Children[0].Bits;
        if Opcode='010' then begin
          if Length(N.Children)<>2 then Fail('Неправильна арність D3:010');
          EmitExpr(N.Children[1],Depth+1);
          { Під час запуску: eax=0 NIL, 1/2 D1, pointer|3 пара.
            Рівно два молодші біти позначають тільки внутрішній
            машинний тип; AND/CMP/SETNE обчислює результат ATOM.
            Не виводимо закон SENS із pointer-tag. }
          Add($83);Add($E0);Add($03); { and eax,3 }
          Add($83);Add($F8);Add($03);
          Add($0F);Add($95);Add($C0);
          Add($0F);Add($B6);Add($C0);
          Add($83);Add($C0);Add($01);
        end else if Opcode='111' then begin
          if Length(N.Children)<>3 then Fail('Неправильна арність D3:111');
          { Реальна 16-байтова машинна комірка pair:
            результати обох підформ є tagged QWord.
            PUSH/POP ізолює перший операнд, поки другий може
            рекурсивно алокувати інші комірки у R12-арені.
            При цьому R12 незалежний від тимчасового RSP.
            Арифметики чи загального CAR/CDR у цьому backend немає. }
          EmitExpr(N.Children[1],Depth+1);
          Add($50); { push rax: перше машинне значення }
          EmitExpr(N.Children[2],Depth+1);
          Add($59); { pop rcx: перше машинне значення }
          Add($49);Add($89);Add($0C);Add($24); { mov [r12],rcx }
          Add($49);Add($89);Add($44);Add($24);Add($08); { mov [r12+8],rax }
          Add($49);Add($8D);Add($04);Add($24); { lea rax,[r12] }
          Add($48);Add($83);Add($C8);Add($03); { or rax,3 }
          Add($49);Add($83);Add($C4);Add($10); { add r12,16 }
        end else Fail('Непідтриманий D3 механізм у вузькому ELF');
      end;
      else Fail('Фізична крапкова пара не є самостійним значенням');
    end;
  end;

  procedure Put(var B:RawByteString;Off:SizeInt;V:QWord;Count:SizeInt);
  var I:SizeInt;
  begin
    for I:=0 to Count-1 do begin
      B[Off+I+1]:=AnsiChar(V and $FF);
      V:=V shr 8;
    end;
  end;

var I,Total:SizeInt;
begin
  Result:='';Doc:=nil;Engine:=nil;Machine:='';LeafCount:=0;NodeCount:=0;
  try
    try
      Doc:=ReadD2T5M(Physical);
      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      if (Length(Doc.Roots)<>1) or (Doc.Roots[0]=nil) or
         (Doc.Roots[0].Kind<>dkList) or
         (Length(Doc.Roots[0].Children)<>2) or
         (Doc.Roots[0].Children[0]=nil) or
         (Doc.Roots[0].Children[0].Kind<>dkIdentity) or
         (Doc.Roots[0].Children[0].Width<>3) or
         (Doc.Roots[0].Children[0].Bits<>'010') then
        Fail('Потрібна одна фізична форма D3:010 (ATOM)');
      { Резервуємо фіксовану арену ДО машинного обчислення.
        За MaxAtomLeaves<=128 не більше 128 фізичних пар по 16 байтів;
        2048 байтів достатньо навіть коли всі вузли — пари.
        Цей bounded stack arena живе до Linux exit, не SENS heap/GC. }
      Add($48);Add($81);Add($EC);Add($00);Add($08);Add($00);Add($00);
      Add($49);Add($89);Add($E4); { mov r12,rsp }
      EmitExpr(Doc.Roots[0],0);
      if LeafCount<>Length(Bound) then
        Fail('Не всі фізичні слова пройшли точне зв’язування');
      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Answer:=Engine.ExecutePhysical(Physical);
      if (Answer<>'0') and (Answer<>'1') then
        Fail('Виконавець не підтвердив двійковий результат ATOM');
      { Машинна конверсія: tag 1/2 -> ASCII '0'/'1', далі
        Linux write(1, rsp,2), exit(0), без Pascal runtime. }
      Add($83);Add($E8);Add($01);Add($04);Add($30);
      Add($48);Add($83);Add($EC);Add($08); { sub rsp,8 }
      Add($88);Add($04);Add($24);          { mov [rsp],al }
      Add($C6);Add($44);Add($24);Add($01);Add($0A); { LF }
      Add($B8);Add($01);Add(0);Add(0);Add(0);    { write }
      Add($BF);Add($01);Add(0);Add(0);Add(0);    { fd=stdout }
      Add($48);Add($89);Add($E6);               { rsi=rsp }
      Add($BA);Add($02);Add(0);Add(0);Add(0);    { count=2 }
      Add($0F);Add($05);                         { syscall }
      Add($B8);Add($3C);Add(0);Add(0);Add(0);    { exit }
      Add($31);Add($FF);Add($0F);Add($05);
      Total:=CodeOffset+Length(Machine);
      SetLength(Result,Total);
      for I:=1 to Total do Result[I]:=#0;
      Put(Result,0,$464C457F,4);
      Put(Result,4,2,1);Put(Result,5,1,1);Put(Result,6,1,1);
      Put(Result,16,2,2);Put(Result,18,62,2);Put(Result,20,1,4);
      Put(Result,24,ELFBase+CodeOffset,8);Put(Result,32,64,8);
      Put(Result,52,64,2);Put(Result,54,56,2);Put(Result,56,1,2);
      Put(Result,64,1,4);Put(Result,68,5,4);
      Put(Result,80,ELFBase,8);Put(Result,88,ELFBase,8);
      Put(Result,96,Total,8);Put(Result,104,Total,8);Put(Result,112,$1000,8);
      for I:=1 to Length(Machine) do Result[CodeOffset+I]:=Machine[I];
    except
      on E:EElfAtomError do raise;
      on E:Exception do raise EElfAtomError.Create(
        UA('Нативна D3:010 форма не допущена: ')+E.Message);
    end;
  finally
    Engine.Free;
    Doc.Free;
  end;
end;

{ G6.243 — відділяємо фізичний D3:010 admission та старий
  машинний ABI від безпечної host ASCII публікації.
  Physical / AuthorityRoot — borrowed; BuildAtomELF повертає owned
  legacy ET_EXEC, який є донором для фізичного T5M backend.
  RequireCompleteNativeWrite повертає НОВИЙ owned, verified ET_EXEC:
  Linux stdout '0'/'1'+LF, два host bytes, не канонічний D1 T5M.
  Linux host write=2 -> exit(0); -EBADF/-ENOSPC/short -> exit(1).
  EElfAtomError забезпечує fail-closed без публікації часткового ELF.
  1) Чому BuildAtomT5MELF потребує незмінного raw OldSuffix?
  2) Чому внутрішній донор не повинен обробляти host stdout двічі?
  3) Чому ASCII/LF — лише проєкція, а не фізична SENS програма?
  4) Хто володіє перевіреним ELF після повернення wrapper? }
function BuildCheckedAtomELF(
  const Physical,AuthorityRoot:RawByteString):RawByteString;
begin
  Result:='';
  try
    Result:=RequireCompleteNativeWrite(
      BuildAtomELF(Physical,AuthorityRoot));
  except
    on E:EElfAtomError do raise;
    on E:Exception do begin
      Result:='';
      raise EElfAtomError.Create(
        UA('Нативний D3 ATOM host stdout відхилено: ')+E.Message);
    end;
  end;
end;
end.
