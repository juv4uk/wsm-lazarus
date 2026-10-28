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
function BuildD1ELF(const Physical, AuthorityRoot: RawByteString): RawByteString;
var
  Doc: TD2Document;
  Bound: TBinaryWords;
  Tables: TDomainSet;
  E: TBinaryExecutor;
  Witness, Bits: RawByteString;
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
        (Doc.Roots[0]=nil) or (Doc.Roots[0].Kind<>dkIdentity) or
        (Doc.Roots[0].Width<>1) or (Bound[0].Key.Width<>1) or
        (Bound[0].RootIndex<>0) or (Bound[0].WordIndex<>Doc.Roots[0].WordIndex) then
        raise EELFD1Error.Create(UkrBytes('Нативний ELF допускає лише один фізичний літерал D1'));
      Bits:=KeyBits(Bound[0].Key);
      if (Bits<>'0') and (Bits<>'1') then
        raise EELFD1Error.Create(UkrBytes('Непідтверджена двійкова координата D1'));
      if Doc.Roots[0].Bits<>Bits then
        raise EELFD1Error.Create(UkrBytes('Порушено точне зв’язування D1'));
      E:=TBinaryExecutor.Create(AuthorityRoot);
      Witness:=E.ExecutePhysical(Physical);
      if Witness<>Bits then
        raise EELFD1Error.Create(UkrBytes('Нативний літерал не підтверджений чинним виконавцем'));
      SetLength(Result,FileSize);
      for I:=1 to FileSize do Result[I]:=#0;
      { ELF64 заголовок: ELFCLASS64, little-endian, ET_EXEC, EM_X86_64. }
      Put(0,$464C457F,4);
      Put(4,2,1); Put(5,1,1); Put(6,1,1);
      Put(16,2,2); Put(18,62,2); Put(20,1,4);
      Put(24,ELFBase+CodeOffset,8); Put(32,64,8);
      Put(52,64,2); Put(54,56,2); Put(56,1,2);
      { Єдиний PT_LOAD RX; сторінкове вирівнювання та точний розмір. }
      Put(64,1,4); Put(68,5,4);
      Put(80,ELFBase,8); Put(88,ELFBase,8);
      Put(96,FileSize,8); Put(104,FileSize,8); Put(112,$1000,8);
      for J:=0 to CodeSize-1 do
        Result[CodeOffset+J+1]:=AnsiChar(MachineCode[J]);
      Result[CodeOffset+CodeSize+1]:=Bits[1];
      Result[CodeOffset+CodeSize+2]:=#10;
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
end.
