{ G6.201 — фізична відтворюваність D5:10110 між FPC -O1/-O2.
  Точні T5M програми породжують ELF через той самий verified WideIR.
  Не породжує нових SENS законів і не підміняє SENS REPL oracle.
  Програмні байти / ELF / очікувані фізичні значення належать caller,
  тимчасовий verified контекст завжди звільняється в finally.
  1) Чому дві збірки повинні мати різні -FU каталоги?
  2) Чому D12/D24 порівнюються у packed T5M, не десятковим текстом?
  3) Чому однакова машинна геометрія слабша за побайтовий cmp?
  4) Що перевіряє negative malformed frame?
  5) Чому це ще не вимір електроенергії? }
program test_verifiedmul_vidtvoriuvanist;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.numericplane, wsm.numericmul,
     wsm.verifiedwidecontext, wsm.verifiedmul, wsm.elfgeometry;

type
  TCase = record
    L, R, Wanted: RawByteString;
    Width: SizeInt;
  end;
var
  Cases:array[0..7] of TCase;
  Root,Dir:String;
  Checks,I:SizeInt;
  L,R,Prog,Expected,Generated,ActualValue:RawByteString;
  LNum,RNum:TExplicitNumeric;
  Context:TVerifiedWideContext;
  Geometry:TELFGeometry;
  Failed:Boolean;

procedure Check(OK:Boolean;const Why:String);
begin
  Inc(Checks);
  if not OK then begin
    WriteLn('VMR-ЗБІЙ ',Why);
    Halt(1)
  end
end;

function Pack(const Items:array of RawByteString):RawByteString;
var W:TExactWords;J:SizeInt;
begin
  SetLength(W,Length(Items));
  for J:=0 to High(Items) do W[J]:=Items[J];
  Result:=EncodeT5M(W)
end;

{ Bytes — позичена FPC-managed RawByteString. На диску — власний
  фізичний файл, що живе до очищення приватного mktemp каталогу. }
procedure Save(const FileName:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+FileName,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end
end;

{ 8 детермінованих випадків — зокрема обидві межі D12,
  D24 з розширенням та від'ємне множення. }
procedure Populate;
begin
  Cases[0].L:='0';Cases[0].R:='2047';Cases[0].Wanted:='0';Cases[0].Width:=12;
  Cases[1].L:='12';Cases[1].R:='12';Cases[1].Wanted:='144';Cases[1].Width:=12;
  Cases[2].L:='23';Cases[2].R:='10';Cases[2].Wanted:='230';Cases[2].Width:=12;
  Cases[3].L:='-3';Cases[3].R:='-3';Cases[3].Wanted:='9';Cases[3].Width:=12;
  Cases[4].L:='7';Cases[4].R:='-7';Cases[4].Wanted:='-49';Cases[4].Width:=12;
  Cases[5].L:='2047';Cases[5].R:='2047';Cases[5].Wanted:='4190209';Cases[5].Width:=24;
  Cases[6].L:='-2048';Cases[6].R:='-2048';Cases[6].Wanted:='4194304';Cases[6].Width:=24;
  Cases[7].L:='-2048';Cases[7].R:='2047';Cases[7].Wanted:='-4192256';Cases[7].Width:=24;
end;

begin
  if ParamCount<>2 then begin
    WriteLn('VMR-БЛОК: потрібні pinned SENS root та окрема фізична тека');
    Halt(64)
  end;
  Root:=ParamStr(1);
  Dir:=ParamStr(2);
  if (not DirectoryExists(Dir)) or
     (not FileExists(Root+'/lib/domains/d5.lisp')) then begin
    WriteLn('VMR-БЛОК: немає приватної теки або pinned SENS D5');
    Halt(66)
  end;
  Checks:=0;
  Populate;
  for I:=0 to High(Cases) do begin
    L:=EncodeNumericDecimal(Cases[I].L,12);
    R:=EncodeNumericDecimal(Cases[I].R,12);
    LNum:=ReadNumericPhysical(L,12);
    RNum:=ReadNumericPhysical(R,12);
    Prog:=Pack(['10','10110',LNum.ExactBits,RNum.ExactBits,'01']);
    ActualValue:=MultiplyNumericPhysical(L,R,12);
    Expected:=EncodeNumericDecimal(Cases[I].Wanted,Cases[I].Width);
    Check(ActualValue=Expected,'підтвердження pinned D12/D24 numeric plane');
    Context:=TVerifiedWideContext.Create(Prog,Root);
    try Generated:=Context.Lower(@LowerVerifiedMul)
    finally Context.Free end;
    VerifySENSELF64(Generated,Geometry);
    Check((Geometry.Kind=3) and (Geometry.Entry=120) and
      (Geometry.FileBytes=Length(Generated)) and
      (Geometry.MachineBytes>0),'машинний образ ELF64 PIE');
    Save('case'+Format('%.2d',[I+1])+'.elf',Generated);
    Save('case'+Format('%.2d',[I+1])+'.program.sens',Prog);
    Save('case'+Format('%.2d',[I+1])+'.expected.sens',
      Pack([ReadNumericPhysical(Expected,Cases[I].Width).ExactBits]));
  end;
  { Пошкоджені фізичні біти і зниклий upstream — fail closed,
    жоден нібито успішний ELF не зберігається. }
  Failed:=False;
  try
    Context:=TVerifiedWideContext.Create(Prog+#0,Root);
    try Generated:=Context.Lower(@LowerVerifiedMul)
    finally Context.Free end
  except on E:Exception do Failed:=True end;
  Check(Failed,'неканонічний T5M має відмовляти');
  Failed:=False;
  try
    Context:=TVerifiedWideContext.Create(Prog,Root+'/немає');
    try Generated:=Context.Lower(@LowerVerifiedMul)
    finally Context.Free end
  except on E:Exception do Failed:=True end;
  Check(Failed,'недоступний pinned authority має відмовляти');
  WriteLn('VMR-PASS checks=',Checks,' elfs=',Length(Cases));
end.
