{ G6.13 — вузький реальний Linux x86-64 backend D3:101 над exact D1.
  Машинний cmp/sete виконується ядром Linux; джерело — physical T5M
  і pinned Contract 12, без host dispatch за назвою функції. }
unit wsm.elfeq;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EElfEqError=class(Exception);
function BuildEqELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.d2source,wsm.binarybind,wsm.bind,wsm.domain,wsm.binaryexec;
const
  ELFBase:QWord=$400000;
  CodeOffset=64+56;
  MaxCodeBytes=128;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S));end;
function BuildEqELF(const Physical,AuthorityRoot:RawByteString):RawByteString;
var
  Doc:TD2Document;
  Bound:TBinaryWords;
  Tables:TDomainSet;
  Engine:TBinaryExecutor;
  Machine,Witness:RawByteString;
  LeftBit,RightBit:Byte;
  I,Total:SizeInt;
  procedure Fail(const Why:UnicodeString);
  begin raise EElfEqError.Create(UA(Why));end;
  function D1Value(N:TD2Node;Index:SizeInt):Byte;
  var Key:TDomainKey;
  begin
    if (N=nil) or (N.Kind<>dkIdentity) or (N.Width<>1) or
       (Index>=Length(Bound)) then
      Fail('Потрібен точний атом D1');
    Key:=Bound[Index].Key;
    if (Bound[Index].RootIndex<>0) or
       (Bound[Index].WordIndex<>N.WordIndex) or
       Bound[Index].IsEmpty or (Key.Width<>1) or
       (KeyBits(Key)<>N.Bits) then
      Fail('Пошкоджене зіставлення pinned D1 слова');
    if N.Bits='0' then Exit(0);
    if N.Bits='1' then Exit(1);
    Fail('Неприпустимі біти D1');
    Result:=0;
  end;
  procedure Add(B:Byte);
  begin
    if Length(Machine)>=MaxCodeBytes then Fail('Перевищено розмір коду');
    Machine:=Machine+AnsiChar(B);
  end;
  procedure Put(var B:RawByteString;Offset:SizeInt;V:QWord;Count:SizeInt);
  var J:SizeInt;
  begin
    if (Offset<0) or (Count<1) or (Count>8) or
       (Offset>Length(B)-Count) then Fail('За межами заголовка ELF');
    for J:=0 to Count-1 do begin
      B[Offset+J+1]:=AnsiChar(Byte(V and $FF)); V:=V shr 8;
    end;
  end;
begin
  Result:='';Doc:=nil;Engine:=nil;Machine:='';
  try
    try
      Doc:=ReadD2T5M(Physical);
      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      if (Length(Doc.Roots)<>1) or (Doc.Roots[0]=nil) or
         (Doc.Roots[0].Kind<>dkList) or
         (Length(Doc.Roots[0].Children)<>3) or
         (Length(Bound)<>3) then
        Fail('Потрібна одна форма D3:101 із двома D1');
      if (Doc.Roots[0].Children[0]=nil) or
         (Doc.Roots[0].Children[0].Kind<>dkIdentity) or
         (Doc.Roots[0].Children[0].Width<>3) or
         (Doc.Roots[0].Children[0].Bits<>'101') or
         (Bound[0].RootIndex<>0) or
         (Bound[0].WordIndex<>Doc.Roots[0].Children[0].WordIndex) or
         Bound[0].IsEmpty or
         (Bound[0].Key.Width<>3) or
         (KeyBits(Bound[0].Key)<>'101') then
        Fail('Голова не є pinned exact D3:101');
      LeftBit:=D1Value(Doc.Roots[0].Children[1],1);
      RightBit:=D1Value(Doc.Roots[0].Children[2],2);
      Engine:=TBinaryExecutor.Create(AuthorityRoot);
      Witness:=Engine.ExecutePhysical(Physical);
      if (Witness<>'0') and (Witness<>'1') then
        Fail('Чинний виконавець не підтвердив точний D1 результат');

      { mov eax,left; mov ecx,right; cmp eax,ecx; sete al;
        movzx eax,al; add al,48. Порівняння — runtime, не host. }
      Add($B8);Add(LeftBit);Add(0);Add(0);Add(0);
      Add($B9);Add(RightBit);Add(0);Add(0);Add(0);
      Add($39);Add($C8);
      Add($0F);Add($94);Add($C0);
      Add($0F);Add($B6);Add($C0);
      Add($04);Add($30);
      Add($48);Add($83);Add($EC);Add($08);
      Add($88);Add($04);Add($24);
      Add($C6);Add($44);Add($24);Add($01);Add($0A);
      Add($B8);Add($01);Add(0);Add(0);Add(0);
      Add($BF);Add($01);Add(0);Add(0);Add(0);
      Add($48);Add($89);Add($E6);
      Add($BA);Add($02);Add(0);Add(0);Add(0);
      Add($0F);Add($05);
      Add($B8);Add($3C);Add(0);Add(0);Add(0);
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
      Put(Result,96,Total,8);Put(Result,104,Total,8);
      Put(Result,112,$1000,8);
      for I:=1 to Length(Machine) do Result[CodeOffset+I]:=Machine[I];
    except
      on E:EElfEqError do raise;
      on E:Exception do raise EElfEqError.Create(
        UA('Нативна D3:101 форма не допущена: ')+E.Message);
    end;
  finally
    Engine.Free;Doc.Free;
  end;
end;
end.
