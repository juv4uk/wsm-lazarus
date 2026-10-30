{ G6.102 — реальний signed D12 → машинний D6 парності → фізичний D1.
  Власність: FPC managed RawByteString; тимчасовий ELF у приватній теці.
  D6:010000/010001 зі pinned SENS, не локальна таблиця законів.
  Питання: 1) Чому sign не впливає на LSB?
  2) Чому D12 перевіряємо до тесту?
  3) Чому два різних ELF потрібні для SETE/SETNE?
  4) Хто звільняє Bytes? 5) Чому це ще не загальний compiler? }
program TestD6ParityStream;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.elfd6parnpotik;
const Numbers:array[0..15] of LongInt=(0,1,-1,2,-2,3,-3,17,-17,
                   1024,-1024,2047,-2048,-2047,2046,-2046);
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create(Why) end;
procedure Save(const Path:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(B)>0 then F.WriteBuffer(B[1],Length(B))
  finally F.Free end;
end;
var Dir,Physical,Expected,LabelText,EvenImage,OddImage:RawByteString;
    W,Root:TExactWords; I,Mode:SizeInt; P:TExplicitNumeric; IsOdd:Boolean;
begin
  Need(ParamCount=1,'потрібна приватна тека для фізичних свідків');
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  Need(DirectoryExists(Dir),'немає теки свідків');
  EvenImage:=BuildD12ParityStreamELF(False);
  OddImage:=BuildD12ParityStreamELF(True);
  Need((Length(EvenImage)>120) and (Length(OddImage)>120),
       'порожній машинний ELF');
  Need(EvenImage<>OddImage,'парне й непарне мають різні машинні інструкції');
  Need(EvenImage=BuildD12ParityStreamELF(False),'недетермінований ELF парне');
  Need(OddImage=BuildD12ParityStreamELF(True),'недетермінований ELF непарне');
  Save(Dir+'parne.elf',EvenImage);
  Save(Dir+'neparne.elf',OddImage);
  SetLength(W,1);
  SetLength(Root,4);Root[0]:='10';Root[3]:='01';
  for I:=Low(Numbers) to High(Numbers) do begin
    LabelText:=Format('%.2d',[I]);
    Physical:=EncodeNumericDecimal(IntToStr(Numbers[I]),12);
    P:=ReadNumericPhysical(Physical,12);
    Need((P.DomainWidth=12) and (Length(P.ExactBits)=12) and
      (Length(Physical)=3),'порушено фізичну D12 тотожність');
    Save(Dir+LabelText+'.sens',Physical);
    IsOdd:=P.ExactBits[12]='1';
    Root[2]:=P.ExactBits;
    for Mode:=0 to 1 do begin
      if (Mode=0) and (not IsOdd) or (Mode=1) and IsOdd then W[0]:='1'
      else W[0]:='0';
      Expected:=EncodeT5M(W);
      Need(Length(Expected)=1,'D1 втратив однобайтовий T5M');
      if Mode=0 then begin
        Save(Dir+LabelText+'.parne.sens',Expected);
        Root[1]:='010000';
        Save(Dir+LabelText+'.parne.call.sens',EncodeT5M(Root));
      end else begin
        Save(Dir+LabelText+'.neparne.sens',Expected);
        Root[1]:='010001';
        Save(Dir+LabelText+'.neparne.call.sens',EncodeT5M(Root));
      end;
    end;
  end;
  WriteLn('D6-PARITY-STREAM-BUILD-OK files=2 vectors=16 checks=32');
end.
