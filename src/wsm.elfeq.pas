{ G6.13: справжній ELF64 x86-64 для ратифікованого D3:101 на двох D1 атомах.
  Не підміняти закон D3:101 константою: CMP/SETE працює всередині ELF.
  Машинний ELF є виходом backend, не канонічним .sens. }
unit wsm.elfeq;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfEqError=class(Exception);
function BuildEqELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.d2source,wsm.binarybind,wsm.bind,wsm.domain,
  wsm.binaryexec;
const
  ELFBase:QWord=$400000;
  ELFCodeOffset=64+56;
  MaxMachineBytes=256;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;

function BuildEqELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Doc:TD2Document;
  Bound:TBinaryWords;
  Tables:TDomainSet;
  Engine:TBinaryExecutor;
  Exact:TExactWords;
  Machine,Answer:RawByteString;
  I,Total:SizeInt;
  LeftBit,RightBit:Byte;

  procedure Fail(const Why:UnicodeString);
  begin raise EElfEqError.Create(UA(Why)); end;

  procedure Add(B:Byte);
  begin
    if Length(Machine)>=MaxMachineBytes then
      Fail('Перевищено розмір машинної програми EQ');
    Machine:=Machine+AnsiChar(B);
  end;

  procedure Put(Offset:SizeInt; V:QWord; Count:SizeInt);
  var J:SizeInt;
  begin
    if (Offset<0) or (Count<1) or (Count>8) or
       (Offset>Length(Result)-Count) then
      Fail('Зіпсована межа машинного ELF');
    for J:=0 to Count-1 do begin
      Result[Offset+J+1]:=AnsiChar(Byte(V and $FF));
      V:=V shr 8;
    end;
  end;

  function ExactD1(N:TD2Node; At:SizeInt):Byte;
  var Bits:RawByteString;
  begin
    if (N=nil) or (N.Kind<>dkIdentity) or (N.Width<>1) or
       (Length(N.Bits)<>1) or (At>=Length(Bound)) then
      Fail('D3:101 допускає тільки точний атом D1');
    Bits:=KeyBits(Bound[At].Key);
    if (Bound[At].RootIndex<>0) or
       (Bound[At].WordIndex<>N.WordIndex) or
       (Bound[At].Key.Width<>1) or Bound[At].IsEmpty or
       (Bits<>N.Bits) then
      Fail('Порушено pinned доменну тотожність атома D1');
    if Bits='0' then Result:=0
    else if Bits='1' then Result:=1
    else Fail('Невідомий двійковий атом D1');
  end;

begin
  Result:='';Doc:=nil;Engine:=nil;Machine:='';
  try
    try
      { Канонічність і ратифікований binder перед генерацією ELF. }
      DecodeT5M(Physical,Exact);
      if EncodeT5M(Exact)<>Physical then
        Fail('Фізичний T5M не є канонічним');
      Doc:=ParseD2Words(Exact);
      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      if (Length(Doc.Roots)<>1) or (Doc.Roots[0]=nil) or
         (Doc.Roots[0].Kind<>dkList) or
         (Length(Doc.Roots[0].Children)<>3) or
         (Length(Bound)<>3) then
        Fail('Потрібна одна двоаргументна фізична форма D3:101');
      if (Doc.Roots[0].Children[0]=nil) or
         (Doc.Roots[0].Children[0].Kind<>dkIdentity) or
         (Doc.Roots[0].Children[0].Width<>3) or
         (Doc.Roots[0].Children[0].Bits<>'101') or
         (Bound[0].Key.Width<>3) or
         (KeyBits(Bound[0].Key)<>'101') or
         (Bound[0].WordIndex<>Doc.Roots[0].Children[0].WordIndex) or
         (Bound[0].RootIndex<>0) or Bound[0].IsEmpty then
        Fail('Потрібна точна pinned голова D3:101');
      LeftBit:=ExactD1(Doc.Roots[0].Children[1],1);
      RightBit:=ExactD1(Doc.Roots[0].Children[2],2);
      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Answer:=Engine.ExecutePhysical(Physical);
      if (Answer<>'0') and (Answer<>'1') then
        Fail('Чинний D3 виконавець не підтвердив двійковий результат');
      { Тільки вхідні D1 біти стають imm32, не результат порівняння.
        Linux x86-64:
          mov eax,L; mov ecx,R; cmp eax,ecx; sete al;
          movzx eax,al; add al,0x30; ... write(stdout); exit(0).
        D1:0 і D1:1 не залежать від host boolean чи тексту укр. }
      Add($B8);Add(LeftBit);Add(0);Add(0);Add(0);
      Add($B9);Add(RightBit);Add(0);Add(0);Add(0);
      Add($39);Add($C8);               { cmp eax,ecx }
      Add($0F);Add($94);Add($C0);      { sete al }
      Add($0F);Add($B6);Add($C0);      { movzx eax,al }
      Add($04);Add($30);               { ASCII після машинного EQ }
      Add($48);Add($83);Add($EC);Add($08);
      Add($88);Add($04);Add($24);     { mov [rsp],al }
      Add($C6);Add($44);Add($24);Add($01);Add($0A);
      Add($B8);Add($01);Add(0);Add(0);Add(0);
      Add($BF);Add($01);Add(0);Add(0);Add(0);
      Add($48);Add($89);Add($E6);     { rsi=rsp }
      Add($BA);Add($02);Add(0);Add(0);Add(0);
      Add($0F);Add($05);
      Add($B8);Add($3C);Add(0);Add(0);Add(0);
      Add($31);Add($FF);Add($0F);Add($05);
      Total:=ELFCodeOffset+Length(Machine);
      SetLength(Result,Total);
      for I:=1 to Total do Result[I]:=#0;
      { ELF64 ET_EXEC, EM_X86_64, один RX PT_LOAD. }
      Put(0,$464C457F,4);
      Put(4,2,1);Put(5,1,1);Put(6,1,1);
      Put(16,2,2);Put(18,62,2);Put(20,1,4);
      Put(24,ELFBase+ELFCodeOffset,8);Put(32,64,8);
      Put(52,64,2);Put(54,56,2);Put(56,1,2);
      Put(64,1,4);Put(68,5,4);
      Put(80,ELFBase,8);Put(88,ELFBase,8);
      Put(96,Total,8);Put(104,Total,8);Put(112,$1000,8);
      for I:=1 to Length(Machine) do Result[ELFCodeOffset+I]:=Machine[I];
    except
      on E:EElfEqError do raise;
      on E:Exception do raise EElfEqError.Create(
        UA('Машинну форму D3:101 відхилено: ')+E.Message);
    end;
  finally
    Engine.Free;
    Doc.Free;
  end;
end;
end.
