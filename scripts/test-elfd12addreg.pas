{ G6.96 — реальний старий D12 ELF проти нового ALU32 ELF.
  Тести фізичних вхідних пар використовують pinned T5M свідки
  попередньо перевіреного G6.63; незалежний SENS REPL — у shell.
  Вихід: файлові ELF; жодного успішного артефакту при відмові.
  Питання: чому порівнюємо байти незмінного хвоста?
  Чому не досить порівняти лише ELF заголовок?
  Чому host регістровий ADD — не довільна SENS функція? }
program test_elfd12addreg;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.elfd12add,wsm.elfd12addreg,
     wsm.elfgeometry,wsm.numericplane,wsm.t5m;
var Dir:String; I,Good,Bad:SizeInt; LabelText:String;
    L,R,OldELF,NewELF,Invalid,Extra:RawByteString;
    OldG,NewG:TELFGeometry; Words:TExactWords;

procedure Check(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('D12-РЕГІСТРИ-ПРОВАЛ: '+Why);
end;

function LoadFile(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Check((F.Size>=0) and (F.Size<=128),'вхід не вміщується у фізичну квоту');
    SetLength(Result,SizeInt(F.Size));
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;

procedure Refuse(const What:String;const P,Q:RawByteString);
var Failed:Boolean; Ignore:RawByteString;
begin
  Failed:=False;Ignore:='';
  try Ignore:=BuildD12RegisterAddELF(P,Q)
  except on E:Exception do Failed:=True end;
  Check(Failed and (Ignore=''),'не відхилено або опубліковано '+What);
  Inc(Bad);
end;

begin
  Check(ParamCount=1,'потрібна тека свідків');
  Dir:=ParamStr(1);
  Check(DirectoryExists(Dir),'каталог фізичних файлів відсутній');
  Good:=0;Bad:=0;
  for I:=1 to 9 do begin
    LabelText:=Format('%.2d',[I]);
    L:=LoadFile(Dir+'/'+LabelText+'-l.sens');
    R:=LoadFile(Dir+'/'+LabelText+'-r.sens');
    OldELF:=BuildD12AddELF(L,R);
    NewELF:=BuildD12RegisterAddELF(L,R);
    VerifySENSELF64(OldELF,OldG);
    VerifySENSELF64(NewELF,NewG);
    Check((OldG.Kind=3) and (NewG.Kind=3) and
          (NewG.FileBytes=OldG.FileBytes+2),
          'не збережено геометрію ELF або +2');
    Check((NewELF[121]=#$B8) and (NewELF[126]=#$B9) and
          (NewELF[131]=#$01) and (NewELF[132]=#$C8),
          'немає справжнього машинного MOV ECX;ADD EAX,ECX');
    Check(Copy(NewELF,133,Length(NewELF)-132)=
          Copy(OldELF,131,Length(OldELF)-130),
          'RIP-relative код/таблиці T5M змінилися');
    Check(Copy(NewELF,1,96)=Copy(OldELF,1,96),
          'змінено незаявлені ELF поля');
    Check(Copy(NewELF,113,8)=Copy(OldELF,113,8),
          'змінено ELF вирівнювання');
    Save(Dir+'/'+LabelText+'-reg.elf',NewELF);
    Save(Dir+'/'+LabelText+'-old.elf',OldELF);
    Inc(Good);
  end;
  { Відмови — без створення output; для успішних форм окремий
    shell перевіряє stdout виконуваного ELF, readelf/objdump. }
  L:=LoadFile(Dir+'/02-l.sens');R:=LoadFile(Dir+'/02-r.sens');
  Refuse('overflow-plus',
         LoadFile(Dir+'/overplus-l.sens'),LoadFile(Dir+'/overplus-r.sens'));
  Refuse('overflow-minus',
         LoadFile(Dir+'/overminus-l.sens'),LoadFile(Dir+'/overminus-r.sens'));
  Refuse('D24',LoadFile(Dir+'/bad24.sens'),R);
  Refuse('D1',LoadFile(Dir+'/bad1.sens'),R);
  Refuse('D7',LoadFile(Dir+'/bad7.sens'),R);
  Refuse('corrupt',LoadFile(Dir+'/corrupt.sens'),R);
  Refuse('empty',LoadFile(Dir+'/empty.sens'),R);
  Refuse('truncated',Copy(L,1,Length(L)-1),R);
  Refuse('noncanonical-byte',L,R+#$FF);
  Refuse('text-projection','(додати 1 2)',R);
  SetLength(Words,2);Words[0]:='000000000000';Words[1]:='000000000000';
  Extra:=EncodeT5M(Words);
  Refuse('два слова замість одного D12',Extra,R);
  Invalid:=EncodeNumericDecimal('123',12);
  Refuse('неприпустимий правий D1',L,LoadFile(Dir+'/bad1.sens'));
  Check((Good=9) and (Bad=12),'підсумок тестової матриці');
  WriteLn('D12-ALU-REG-ГОТОВО ELF=9 negative=12 invariant=TAIL-EXACT');
end.
