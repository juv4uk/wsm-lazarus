{ G6.134 — 8 фізичних D12 бітових свідків × BSF/BSR.
  Вхід: тимчасова тека; результат: там же 16 дійсних ELF64 і
  рівно 14 фізичних W1 еталонів. На нулі — 2 машинні exit(2).
  Питання: 1) Чому числове -1 не означає 32-бітову маску?
  2) Чому physical expected генерує pinned EncodeT5M?
  3) Чому окремі позитивні й негативні stdout?
  4) Навіщо друге складання byte-identical ELF? }
program test_elfbitscansafe;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.elfbitscansafe,wsm.x64bitscan,
     wsm.numericplane,wsm.t5m;
const
  Numbers:array[0..7] of String=
    ('0','1','8','12','-1','-2048','2047','1024');
  FirstParity:array[0..7] of Byte=(2,0,1,0,0,1,0,0);
  LastParity:array[0..7] of Byte=(2,0,1,1,1,1,0,0);
var
  Path,Filename,Physical,Image,Again:RawByteString;
  I,J,Positive,Zero,Bad:SizeInt;
  Words:TExactWords;

procedure Check(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('BSF-BSR-ЗАХИСТ-ПРОВАЛ: '+Why) end;

procedure Save(const FileName:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(FileName,fmCreate);
  try
    if Length(Bytes)>0 then
      Check(F.Write(Bytes[1],Length(Bytes))=Length(Bytes),'неповний запис');
  finally F.Free end;
end;

function PackedD1(Bit:Byte):RawByteString;
begin
  Check(Bit in [0,1],'невідомий D1-біт');
  SetLength(Words,1);
  if Bit=0 then Words[0]:='0' else Words[0]:='1';
  Result:=EncodeT5M(Words);
  Check(Length(Result)=1,'D1 має фізично один байт');
end;

procedure Reject(const Candidate:RawByteString;Operation:TX64BitScan;
                 const Why:String);
var Local:RawByteString; Rejected:Boolean;
begin
  Local:='NO-ELF';
  Rejected:=False;
  try
    Local:=BuildGuardedD12BitScanELF(Candidate,Operation);
  except on E:Exception do Rejected:=True end;
  Check(Rejected,'не відхилено '+Why);
  Check(Local='NO-ELF','частковий ELF після відмови '+Why);
  Inc(Bad);
end;

begin
  Check(ParamCount=1,'потрібна приватна тека');
  Path:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Path),'немає теки');
  Positive:=0;Zero:=0;Bad:=0;
  for I:=0 to 7 do begin
    Physical:=EncodeNumericDecimal(Numbers[I],12);
    Check(Length(Physical)=3,'неочікуване D12 T5M пакування');
    for J:=0 to 1 do begin
      Filename:=Path+'case-'+IntToStr(I)+'-'+IntToStr(J);
      Save(Filename+'.input.sens',Physical);
      if J=0 then
        Image:=BuildGuardedD12BitScanELF(Physical,xbFirstSet)
      else
        Image:=BuildGuardedD12BitScanELF(Physical,xbLastSet);
      Check(Length(Image)>120,'порожній машинний ELF');
      if J=0 then
        Again:=BuildGuardedD12BitScanELF(Physical,xbFirstSet)
      else
        Again:=BuildGuardedD12BitScanELF(Physical,xbLastSet);
      Check(Image=Again,'нестабільний байтовий ELF');
      Save(Filename+'.elf',Image);
      Save(Filename+'.again.elf',Again);
      if Numbers[I]='0' then Inc(Zero)
      else begin
        if J=0 then
          Save(Filename+'.expected.sens',PackedD1(FirstParity[I]))
        else
          Save(Filename+'.expected.sens',PackedD1(LastParity[I]));
        Inc(Positive);
      end;
    end;
  end;
  Reject(EncodeNumericDecimal('1',24),xbFirstSet,'чужий D24');
  SetLength(Words,1);Words[0]:='1';
  Reject(EncodeT5M(Words),xbLastSet,'D1 замість D12');
  SetLength(Words,2);
  Words[0]:=StringOfChar('0',12);Words[1]:=StringOfChar('0',12);
  Reject(EncodeT5M(Words),xbFirstSet,'два слова замість одного');
  Reject(#$FF,xbLastSet,'пошкоджений T5M');
  Reject('',xbFirstSet,'порожній файл');
  Reject(EncodeNumericDecimal('1',12),TX64BitScan(255),'невідомий opcode');
  Check((Positive=14) and (Zero=2) and (Bad=6),'лічильники');
  WriteLn('BSF-BSR-ЗАХИСТ-ГОТОВО physical-D12=8 machine-ELF=16',
    ' positive=14 zero-exit2=2 negative=6 repeat=16 energy=NOT-MEASURED');
end.
