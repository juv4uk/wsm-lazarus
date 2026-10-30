{ G6.211 — справжні signed D12 IMUL -> фізичні D12 або D24 T5M.
  Чинна pinned механіка wsm.numericmul — host expected, а не
  незалежний SENS oracle; машинний результат перевіряє Linux ELF.
  1) Чому 12-бітні вхідні слова зберігають exact width?
  2) Чому D24 результат повинен мати 5, а не 3 T5M байтів?
  3) Чим нативний IMUL відрізняється від host MultiplyNumericPhysical?
  4) Де закріплено негатив неканонічного фізичного слова? }
program test_elfmul_write;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.numericplane, wsm.numericmul, wsm.elfd12mul;
const
  LeftValue: array[0..7] of ShortString =
    ('0','1','-1','-2048','2047','2047','-2048','2047');
  RightValue: array[0..7] of ShortString =
    ('2047','1','1','1','1','2','2','-2048');
var Root:String; I,Width:Integer; A,B,Image,Expected:RawByteString;
    Number:TExplicitNumeric;

procedure SaveBytes(const Path:String;const Bytes:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then Stream.WriteBuffer(Bytes[1],Length(Bytes))
  finally Stream.Free end;
end;

begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'ЕЛФ-МНОЖЕННЯ-БЛОК: потрібен каталог');
    Halt(64)
  end;
  Root:=ParamStr(1);
  if not DirectoryExists(Root) then Halt(66);
  for I:=0 to High(LeftValue) do begin
    A:=EncodeNumericDecimal(RawByteString(LeftValue[I]),12);
    B:=EncodeNumericDecimal(RawByteString(RightValue[I]),12);
    Expected:=MultiplyNumericPhysical(A,B,12);
    if Length(Expected)=3 then Width:=12
    else if Length(Expected)=5 then Width:=24
    else raise Exception.Create('втрата exact ширини T5M');
    Number:=ReadNumericPhysical(Expected,Width);
    if Number.DomainWidth<>Width then raise Exception.Create('втрата фізичного домену');
    if (I<5) and (Width<>12) then raise Exception.Create('очікувався D12');
    if (I>=5) and (Width<>24) then raise Exception.Create('очікувався D24');
    Image:=BuildD12MulELF(A,B);
    if Length(Image)<=120 then raise Exception.Create('неповний машинний ELF');
    SaveBytes(Root+PathDelim+IntToStr(I)+'.elf',Image);
    SaveBytes(Root+PathDelim+IntToStr(I)+'.expected.sens',Expected);
  end;
  { Не можна пропустити malformed T5M, навіть якщо другий аргумент канонічний. }
  A:=EncodeNumericDecimal('1',12);
  try
    Image:=BuildD12MulELF('x',A);
    raise Exception.Create('ЗБІЙ: пошкоджений фізичний T5M прийнято');
  except
    on E:ENumericPlaneError do ; 
  end;
  WriteLn('ЕЛФ-МНОЖЕННЯ-СВІДКИ-ГОТОВО D12=5 D24=3 ELF64=8 malformed=відхилено');
end.
