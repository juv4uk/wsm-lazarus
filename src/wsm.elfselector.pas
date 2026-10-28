{ G6.19 — справжнє машинне виконання D3:100/011 над D3:111.
  Мова — тільки pinned SENS; Pascal реалізує фізичний допуск і ELF64.
  Обмежена форма: (CAR|CDR (CONS D1 D1)), жодного host-спелінг dispatch.
  Селектор обирає регістр під час машинного виконання, не константу. }
unit wsm.elfselector;
{$mode objfpc}{$H+}{$codepage utf8}

interface
uses SysUtils;

type EElfSelectorError=class(Exception);

function BuildSelectorELF(const Physical,AuthorityRoot:RawByteString):RawByteString;

implementation
uses wsm.t5m,wsm.d2source,wsm.bind,wsm.binarybind,wsm.domain,wsm.binaryexec;

const
  ELFBase:QWord=$400000;
  CodeOffset=64+56;
  MachineSize=75; { 2 QWord + адресне читання + Linux write/exit }
  MaxMachineBytes=256;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

function BuildSelectorELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Exact:TExactWords;
  Doc:TD2Document;
  Tables:TDomainSet;
  Bound:TBinaryWords;
  Engine:TBinaryExecutor;
  Outer,Inner:TD2Node;
  Code,Answer:RawByteString;
  I,Total:SizeInt;
  LeftBit,RightBit:Byte;
  Selector:RawByteString;

  procedure Fail(const Why:UnicodeString);
  begin raise EElfSelectorError.Create(UA(Why)); end;

  procedure Add(B:Byte);
  begin
    if Length(Code)>=MaxMachineBytes then
      Fail('Перевищено машинну квоту селектора');
    Code:=Code+AnsiChar(B);
  end;

  procedure Put(At:SizeInt;V:QWord;Width:SizeInt);
  var J:SizeInt;
  begin
    if (At<0) or (Width<1) or (Width>8) or (At>Length(Result)-Width) then
      Fail('Внутрішня помилка розміру ELF64');
    for J:=0 to Width-1 do begin
      Result[At+J+1]:=AnsiChar(Byte(V and $FF));
      V:=V shr 8;
    end;
  end;

  procedure CheckHead(N:TD2Node; Index:SizeInt;
    const AllowedA,AllowedB:RawByteString);
  var Bits:RawByteString;
  begin
    if (N=nil) or (N.Kind<>dkIdentity) or
       (N.Width<>3) or (Index>=Length(Bound)) then
      Fail('Недопустима фізична D3 голова');
    Bits:=KeyBits(Bound[Index].Key);
    if (Bits<>N.Bits) or (Bound[Index].Key.Width<>3) or
       (Bound[Index].WordIndex<>N.WordIndex) or
       (Bound[Index].RootIndex<>0) or Bound[Index].IsEmpty or
       ((Bits<>AllowedA) and (Bits<>AllowedB)) then
      Fail('Голова не підтверджена pinned D3 координатою');
  end;

  function D1Bit(N:TD2Node;Index:SizeInt):Byte;
  var Bits:RawByteString;
  begin
    if (N=nil) or (N.Kind<>dkIdentity) or (N.Width<>1) or
       (Index>=Length(Bound)) then
      Fail('Селектор допускає тільки два точні D1 атоми');
    Bits:=KeyBits(Bound[Index].Key);
    if (Bound[Index].Key.Width<>1) or Bound[Index].IsEmpty or
       (Bound[Index].RootIndex<>0) or
       (Bound[Index].WordIndex<>N.WordIndex) or (Bits<>N.Bits) then
      Fail('Порушено точне зв’язування фізичного D1 слова');
    if Bits='0' then Result:=0
    else if Bits='1' then Result:=1
    else begin Fail('Невідомий біт D1');Result:=0;end;
  end;

begin
  Result:=''; Doc:=nil; Engine:=nil; Code:='';
  try
    try
      { Всі допуски відбуваються перед створенням машинних байтів. }
      DecodeT5M(Physical,Exact);
      if EncodeT5M(Exact)<>Physical then
        Fail('Фізичний T5M не є канонічним');
      Doc:=ParseD2Words(Exact);
      if (Length(Doc.Roots)<>1) or (Doc.Roots[0]=nil) or
         (Doc.Roots[0].Kind<>dkList) then
        Fail('Потрібна одна фізична форма селектора D3');
      Outer:=Doc.Roots[0];
      if (Length(Outer.Children)<>2) or (Outer.Children[1]=nil) or
         (Outer.Children[1].Kind<>dkList) then
        Fail('Потрібна форма (селектор (сполучити D1 D1))');
      Inner:=Outer.Children[1];
      if Length(Inner.Children)<>3 then
        Fail('D3:111 вимагає два точні аргументи');

      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      if Length(Bound)<>4 then
        Fail('Фізична форма не має рівно чотири D3/D1 слова');
      CheckHead(Outer.Children[0],0,'100','011');
      CheckHead(Inner.Children[0],1,'111','111');
      Selector:=Outer.Children[0].Bits;
      LeftBit:=D1Bit(Inner.Children[1],2);
      RightBit:=D1Bit(Inner.Children[2],3);

      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Answer:=Engine.ExecutePhysical(Physical);
      if (Answer<>'0') and (Answer<>'1') then
        Fail('Наявний фізичний D3 виконавець не підтвердив результат');
      if ((Selector='100') and (Answer<>AnsiChar(LeftBit+Ord('0')))) or
         ((Selector='011') and (Answer<>AnsiChar(RightBit+Ord('0')))) then
        Fail('Перевірений native D3 результат відрізняється від входу');

      { Машинна програма Linux x86-64:
        mov eax,left; mov ecx,right;
        sub rsp,16; mov [rsp],rax; mov [rsp+8],rcx;
        lea rsi,[rsp]; mov rdx,[rsi+0|8];
        add dl,0x30; mov [rsp],dl; write(1,rsp,2); exit(0).
        Пара — СПРАВЖНІ 2 QWord (16 байтів) у машинному стеку.
        Час життя: від sub rsp до sys_exit; НЕ SENS heap і не GC.
        В ELF є тільки аргументи D1, а не попередньо виведена відповідь. }
      Add($B8);Add(LeftBit);Add(0);Add(0);Add(0);
      Add($B9);Add(RightBit);Add(0);Add(0);Add(0);
      Add($48);Add($83);Add($EC);Add($10); { sub rsp,16 }
      Add($48);Add($89);Add($04);Add($24); { mov [rsp],rax }
      Add($48);Add($89);Add($4C);Add($24);Add($08); { mov [rsp+8],rcx }
      Add($48);Add($8D);Add($34);Add($24); { lea rsi,[rsp] }
      Add($48);Add($8B);Add($56);
      if Selector='100' then Add($00) else Add($08); { mov rdx,[rsi+disp8] }
      Add($80);Add($C2);Add($30);
      Add($48);Add($83);Add($EC);Add($08);
      Add($88);Add($14);Add($24);
      Add($C6);Add($44);Add($24);Add($01);Add($0A);
      Add($B8);Add($01);Add(0);Add(0);Add(0);
      Add($BF);Add($01);Add(0);Add(0);Add(0);
      Add($48);Add($89);Add($E6);
      Add($BA);Add($02);Add(0);Add(0);Add(0);
      Add($0F);Add($05);
      Add($B8);Add($3C);Add(0);Add(0);Add(0);
      Add($31);Add($FF);Add($0F);Add($05);
      if Length(Code)<>MachineSize then
        Fail('Внутрішня довжина машини селектора змінилася');

      Total:=CodeOffset+Length(Code);
      SetLength(Result,Total);
      for I:=1 to Total do Result[I]:=#0;
      { ELF64 ET_EXEC, EM_X86_64, єдиний RX PT_LOAD. }
      Put(0,$464C457F,4);
      Put(4,2,1);Put(5,1,1);Put(6,1,1);
      Put(16,2,2);Put(18,62,2);Put(20,1,4);
      Put(24,ELFBase+CodeOffset,8);Put(32,64,8);
      Put(52,64,2);Put(54,56,2);Put(56,1,2);
      Put(64,1,4);Put(68,5,4);
      Put(80,ELFBase,8);Put(88,ELFBase,8);
      Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
      for I:=1 to Length(Code) do Result[CodeOffset+I]:=Code[I];
    except
      on E:EElfSelectorError do raise;
      on E:Exception do
        raise EElfSelectorError.Create(UA('Фізичний селектор не допущено: ')+E.Message);
    end;
  finally
    Engine.Free;
    Doc.Free;
  end;
end;
end.
