{ G6.210 — генератор чотирьох фізичних signed D12 T5M і нативних
  ELF64 через ЧИННИЙ ADD backend (без нового SENS закону).
  1) Чому кожний результат — канонічний трибайтовий T5M?
  2) Чому ми запускаємо ELF, а не лише порівнюємо константу?
  3) Чому D12:1 не є host exit status?
  4) Чому кожен ELF має окремий файловий lifetime? }
program test_elfadd_write;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.numericplane, wsm.elfd12add;
const Witness:array[0..3] of ShortString=('1','-1','-2048','2047');
var Root:String; I:Integer; Zero,Atom,Image,Expected:RawByteString;

procedure SaveBytes(const Path:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'ЕЛФ-ДОДАВАННЯ-БЛОК: потрібен каталог фізичних свідків');
    Halt(64)
  end;
  Root:=ParamStr(1);
  if not DirectoryExists(Root) then Halt(66);
  Zero:=EncodeNumericDecimal('0',12);
  if Length(Zero)<>3 then Halt(2);
  for I:=0 to High(Witness) do begin
    Atom:=EncodeNumericDecimal(RawByteString(Witness[I]),12);
    Expected:=Atom;
    Image:=BuildD12AddELF(Zero,Atom);
    if Length(Image)<=120 then Halt(3);
    SaveBytes(Root+PathDelim+IntToStr(I)+'.elf',Image);
    SaveBytes(Root+PathDelim+IntToStr(I)+'.expected.sens',Expected);
  end;
  WriteLn('ЕЛФ-ДОДАВАННЯ-СВІДКИ-ГОТОВО D12=4 ELF64=4');
end.
