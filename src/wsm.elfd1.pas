{ G6.8 — вузький нативний backend: один перевірений фізичний D1.
  ELF64/x86-64 Linux є машинним артефактом, НЕ канонічним .sens.
  Немає текстового dispatch чи власних законів SENS: точні біти
  допускає pinned binder, значення підтверджує чинний evaluator. }
unit wsm.elfd1;
{$mode objfpc}{$H+}
{$codepage utf8}
interface
uses SysUtils;
type
  EELFD1Error = class(Exception);
function BuildD1ELF(const Physical, AuthorityRoot: RawByteString): RawByteString;
{ D3:000 — окремий допуск, без зміни D1/PIE ABI. }
function BuildExactLiteralELF(const Physical, AuthorityRoot: RawByteString): RawByteString;
function BuildD1PIE(const Physical, AuthorityRoot: RawByteString): RawByteString;
implementation
uses wsm.t5m, wsm.d2source, wsm.binarybind,
  wsm.bind, wsm.domain, wsm.binaryexec;
function UkrBytes(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)); end;
const
  ELFBase = $400000;
  CodeOffset = 64+56;
  CodeSize = 33;
  FileSize = CodeOffset+CodeSize+2;
  { sys_write(1,&digit,2); sys_exit(0). lea disp32=16
    відразу за командою до двох константних байтів 0/1, LF.
    Строго Linux x86-64 ABI, без heap, FPC runtime або ELF sections. }
  MachineCode: array[0..CodeSize-1] of Byte = (
    $B8,$01,$00,$00,$00, $BF,$01,$00,$00,$00,
    $48,$8D,$35,$10,$00,$00,$00,
    $BA,$02,$00,$00,$00, $0F,$05,
    $B8,$3C,$00,$00,$00, $31,$FF,$0F,$05
  );
function BuildLiteralELF(const Physical, AuthorityRoot: RawByteString;
  AllowD3Empty: Boolean): RawByteString;
var
  Doc: TD2Document;
  Bound: TBinaryWords;
  Tables: TDomainSet;
  E: TBinaryExecutor;
  Witness, Bits, Printed: RawByteString;
  I,J: SizeInt;
  procedure Put(Offset:SizeInt; Number:QWord; Count:SizeInt);
  var K:SizeInt;
  begin
    for K:=0 to Count-1 do begin
      Result[Offset+K+1]:=AnsiChar(Byte(Number and $FF));
      Number:=Number shr 8;
    end;
  end;
begin
  Result:='';
  Doc:=nil; E:=nil;
  try
    try
      { Читання, точний pinned binder і чинне виконання — до ELF. }
      Doc:=ReadD2T5M(Physical);
      LoadPinnedDomains(AuthorityRoot,Tables);
      BindD2Binary(Doc,Tables,Bound);
      if (Length(Doc.Roots)<>1) or (Length(Bound)<>1) or
        (Doc.Roots[0]=nil) or (Bound[0].RootIndex<>0) or
        (Bound[0].WordIndex<>Doc.Roots[0].WordIndex) then
        raise EELFD1Error.Create(UkrBytes('ELF допускає рівно один точний фізичний літерал'));
      Bits:=KeyBits(Bound[0].Key);
      if (Doc.Roots[0].Bits<>Bits) or
         (Doc.Roots[0].Width<>Bound[0].Key.Width) then
        raise EELFD1Error.Create(UkrBytes('Порушено точне зв’язування домену і бітів'));
      { D1:0 залишається відмінним від D3:000. Ні текстових
        імен, ні припущень за десятковим значенням бітів. }
      if (Doc.Roots[0].Kind=dkIdentity) and
         (Bound[0].Key.Width=1) and not Bound[0].IsEmpty and
         ((Bits='0') or (Bits='1')) then
        Printed:=Bits+#10
      else if AllowD3Empty and (Doc.Roots[0].Kind=dkEmpty) and
          (Bound[0].Key.Width=3) and Bound[0].IsEmpty and
          (Bits='000') then
        Printed:='()'+#10
      else
        raise EELFD1Error.Create(UkrBytes('Нативний ELF не підтримує цей фізичний літерал'));
      E:=TBinaryExecutor.Create(AuthorityRoot);
      Witness:=E.ExecutePhysical(Physical);
      if Witness<>Copy(Printed,1,Length(Printed)-1) then
        raise EELFD1Error.Create(UkrBytes('Нативний літерал не підтверджений чинним виконавцем'));
      SetLength(Result,CodeOffset+CodeSize+Length(Printed));
      for I:=1 to Length(Result) do Result[I]:=#0;
      { ELF64 заголовок: ELFCLASS64, little-endian, ET_EXEC, EM_X86_64. }
      Put(0,$464C457F,4);
      Put(4,2,1); Put(5,1,1); Put(6,1,1);
      Put(16,2,2); Put(18,62,2); Put(20,1,4);
      Put(24,ELFBase+CodeOffset,8); Put(32,64,8);
      Put(52,64,2); Put(54,56,2); Put(56,1,2);
      { Єдиний PT_LOAD RX; сторінкове вирівнювання та точний розмір. }
      Put(64,1,4); Put(68,5,4);
      Put(80,ELFBase,8); Put(88,ELFBase,8);
      Put(96,Length(Result),8); Put(104,Length(Result),8); Put(112,$1000,8);
      for J:=0 to CodeSize-1 do
        if J=18 then
          { x86 mov edx,imm32: довжина друку — 2 або 3 байти. }
          Result[CodeOffset+J+1]:=AnsiChar(Length(Printed))
        else Result[CodeOffset+J+1]:=AnsiChar(MachineCode[J]);
      for J:=1 to Length(Printed) do
        Result[CodeOffset+CodeSize+J]:=Printed[J];
    except
      on E: EELFD1Error do raise;
      on E: Exception do raise EELFD1Error.Create(
        UkrBytes('Нативний допуск відхилено: ')+E.Message);
    end;
  finally
    E.Free;
    Doc.Free;
  end;
end;
{ Старе API лишає незмінну заборону D3 для паралельних D1 emitter. }
function BuildD1ELF(const Physical, AuthorityRoot: RawByteString): RawByteString;
begin
  Result:=BuildLiteralELF(Physical,AuthorityRoot,False);
end;

function BuildExactLiteralELF(const Physical, AuthorityRoot: RawByteString): RawByteString;
begin
  Result:=BuildLiteralELF(Physical,AuthorityRoot,True);
end;

{ ET_DYN є лише іншим фізичним ELF контейнером тих самих
  підтверджених двох літералів D1. Жодних нових opcode, SENS законів,
  decoder чи семантичного dispatch. Код використовує RIP-relative LEA. }
function BuildD1PIE(const Physical, AuthorityRoot: RawByteString): RawByteString;
var
  I: SizeInt;
  ELFBytes: RawByteString;
  function GetLE(At, Count:SizeInt):QWord;
  var J:SizeInt;
  begin
    if (At<0) or (Count<1) or (Count>8) or
       (At>Length(ELFBytes)-Count) then
      raise EELFD1Error.Create('Неприпустима межа заголовка ELF');
    Result:=0;
    for J:=Count-1 downto 0 do
      Result:=(Result shl 8) or Byte(ELFBytes[At+J+1]);
  end;
  procedure PutLE(At:SizeInt; V:QWord; Count:SizeInt);
  var J:SizeInt;
  begin
    if (At<0) or (Count<1) or (Count>8) or
       (At>Length(ELFBytes)-Count) then
      raise EELFD1Error.Create('Неприпустима межа запису ELF');
    for J:=0 to Count-1 do begin
      ELFBytes[At+J+1]:=AnsiChar(Byte(V and $FF));
      V:=V shr 8;
    end;
  end;
begin
  { Включає реальний pinned binder і native D1 evaluator. }
  Result:='';
  ELFBytes:=BuildD1ELF(Physical,AuthorityRoot);
  { Fail-closed: не змінювати контейнер, якщо базовий emitter
    коли-небудь змінив машинний шаблон або розмітку заголовка. }
  if (Length(ELFBytes)<>FileSize) or
     (Copy(ELFBytes,1,4)<>#$7F'ELF') or
     (GetLE(16,2)<>2) or (GetLE(18,2)<>62) or
     (GetLE(24,8)<>ELFBase+CodeOffset) or
     (GetLE(32,8)<>64) or
     (GetLE(52,2)<>64) or (GetLE(54,2)<>56) or
     (GetLE(56,2)<>1) or
     (GetLE(64,4)<>1) or (GetLE(68,4)<>5) or
     (GetLE(80,8)<>ELFBase) or (GetLE(88,8)<>ELFBase) or
     (GetLE(96,8)<>FileSize) or (GetLE(104,8)<>FileSize) or
     (GetLE(112,8)<>$1000) then
    raise EELFD1Error.Create('Базовий машинний ELF змінив контракт заголовка');
  for I:=0 to CodeSize-1 do
    if Byte(ELFBytes[CodeOffset+I+1])<>MachineCode[I] then
      raise EELFD1Error.Create('Базовий ELF змінив машинні інструкції');
  { ET_DYN, entry=0x78, одна RX PT_LOAD із vaddr/paddr=0.
    Linux додає випадкову/залежну від loader базу завантаження.
    Ми доводимо переміщуваність і виконання, НЕ ентропію ASLR. }
  PutLE(16,3,2);
  PutLE(24,CodeOffset,8);
  PutLE(80,0,8);
  PutLE(88,0,8);
  Result:=ELFBytes;
end;

end.
