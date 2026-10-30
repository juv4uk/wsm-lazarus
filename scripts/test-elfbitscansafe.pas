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
     wsm.numericplane,wsm.t5m,wsm.x64code,wsm.x64pie,wsm.elfgeometry;
const
  Numbers:array[0..7] of String=
    ('0','1','8','12','-1','-2048','2047','1024');
  FirstParity:array[0..7] of Byte=(2,0,1,0,0,1,0,0);
  LastParity:array[0..7] of Byte=(2,0,1,1,1,1,0,0);
var
  Path,Filename,Physical,Image,Again:RawByteString;
  I,J,Positive,Zero,Bad:SizeInt;
  Words:TExactWords;
  Borrowed:TX64Code;
  Machine:RawByteString;
  Geo:TELFGeometry;

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

{ Здатність відхилити unknown enum має перевіряти саме machine API,
  тому вимикаємо range check тільки на створенні invalid тестового enum. }
function InvalidOpcode:TX64BitScan;
var Raw:Byte;
begin
  Raw:=255;
  {$R-}
  Result:=TX64BitScan(Raw);
  {$R+}
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
  { В FPC managed return assignment може очистити Local ще до винятку. }
  { Жоден з цих станів не містить навіть часткового ELF payload. }
  Check((Local='') or (Local='NO-ELF'),
        'виняток залишив машинний payload '+Why);
  Inc(Bad);
end;

{ G6.258: спільний ELF64 конструктор — незалежний механічний
  свідок, а не окремий SENS інтерпретатор. Дані borrowed managed;
  тест не передає мовних назв у функціональну позицію. }
procedure SharedPIENegatives;
var Code:TX64Code; Before,Image:RawByteString;
    CaseNo:Integer; Failed:Boolean; Geom:TELFGeometry;
begin
  for CaseNo:=0 to 1 do begin
    X64Reset(Code);
    if CaseNo=1 then Code.Bytes:=StringOfChar(#$90,257);
    Code.PatchedRIP:=#$03;
    Before:=Code.Bytes;
    Failed:=False;
    try Image:=BuildX64PIE(Code)
    except on E:EX64PIEError do Failed:=True end;
    Check(Failed and (Code.Bytes=Before) and
          (Code.PatchedRIP=#$03),
      'спільний PIE не зберіг дані на 0/257-байтовій відмові');
  end;
  X64Reset(Code);Code.Bytes:=#$C3;
  Image:=BuildX64PIE(Code);
  VerifySENSELF64(Image,Geom);
  Check((Length(Image)=121) and (Image[121]=#$C3) and
    (Geom.Kind=3) and (Geom.MachineBytes=1),
    'спільний PIE не відновився після відмов');
  WriteLn('G6.258-PIE-BOUNDARIES-OK negative=2 recovery=1');
end;

begin
  Check(ParamCount=1,'потрібна приватна тека');
  Path:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Path),'немає теки');
  Positive:=0;Zero:=0;Bad:=0;
  SharedPIENegatives;
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
      { Кожний із 16 фізичних D12 свідків має збігтися ПОБАЙТОВО
        з єдиним BuildX64PIE, а CPU-тіло й вихідний T5M не змінюються. }
      Machine:=Copy(Image,121,Length(Image)-120);
      X64Reset(Borrowed);
      Borrowed.Bytes:=Machine;
      Check(Image=BuildX64PIE(Borrowed),
        'ELF64 не збігся зі спільним x86-64 PIE');
      Check(Borrowed.Bytes=Machine,
        'спільний PIE пошкодив позичені байти машини');
      VerifySENSELF64(Image,Geo);
      Check((Geo.Kind=3) and (Geo.Entry=120) and
            (Geo.MachineBytes=Length(Machine)) and
            (Geo.FileBytes=Length(Image)),
        'втрачено перевірену ELF64 PIE геометрію');
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
  Reject(EncodeNumericDecimal('1',12),InvalidOpcode,'невідомий opcode');
  Check((Positive=14) and (Zero=2) and (Bad=6),'лічильники');
  WriteLn('G6.258-PIE-SHARED-OK machine-ELF=16 negative=2 recovery=1');
  WriteLn('BSF-BSR-ЗАХИСТ-ГОТОВО physical-D12=8 machine-ELF=16',
    ' positive=14 zero-exit2=2 negative=6 repeat=16 energy=NOT-MEASURED');
end.
