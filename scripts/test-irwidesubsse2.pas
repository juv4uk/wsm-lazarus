{ G6.128 — фізичні 12 D5:01011 свідків із pinned WideIR → SSE2 PSUBQ.
  Значення й oracle належать pinned SENS, не цьому тестовому коду.
  Фізичні .sens створює чинний test-irwidesub; тут тільки host ISA.
  Вхід: borrowed canonical T5M; вихід: нові owned ELF64 байти.
  1) Чому D5 admission викликається до машинної заміни?
  2) Як довести цілісність хвоста з T5M writer?
  3) Чому 4 D24 випадки — окремий важливий тест?
  4) Як негатив не може опублікувати частковий ELF?
  5) Чому незалежний pinned SENS CLI запускається в shell CI? }
program TestIRWideSubSSE2;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.irwidesub,wsm.irwidesubsse2,wsm.elfgeometry;
const HeaderBytes=120;OldPrologue=10;NewPrologue=30;
var Dir,LabelText:String;I,Good,Bad:SizeInt;
    Source,Base,Image,Zero,One,D24:RawByteString;
    Geometry:TELFGeometry;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('D5-PSUBQ-ТЕСТ: '+Why) end;
function ReadBytes(const Name:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>=0) and (F.Size<=65536),'неочікуваний розмір свідка '+Name);
    SetLength(Result,SizeInt(F.Size));
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;
function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;J:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for J:=0 to High(Tokens) do Words[J]:=Tokens[J];
  Result:=EncodeT5M(Words);
end;
procedure Refuse(const Why:String;const Physical:RawByteString);
var Candidate:RawByteString;Rejected:Boolean;
begin
  Candidate:='';Rejected:=False;
  try Candidate:=BuildIRWideSubSSE2ELF(Physical,'external/sens')
  except on E:Exception do Rejected:=E.Message<>'' end;
  Need(Rejected and (Candidate=''),
       'не відхилено '+Why+' або опубліковано неповний ELF');
  Inc(Bad);
end;
begin
  Need(ParamCount=1,'потрібен каталог pinned свідків');
  Dir:=ParamStr(1);Need(DirectoryExists(Dir),'немає каталогу свідків');
  Good:=0;Bad:=0;
  for I:=1 to 12 do begin
    LabelText:=Format('%.2d',[I]);
    Source:=ReadBytes(LabelText+'.sens');
    Base:=ReadBytes(LabelText+'.reference.elf');
    Need(Base=BuildIRWideSubELF(Source,'external/sens'),
         'не збігається вже перевірений baseline SUB ELF');
    Image:=BuildIRWideSubSSE2ELF(Source,'external/sens');
    VerifySENSELF64(Image,Geometry);
    Need((Geometry.Kind=3) and (Geometry.Entry=120) and
         (Geometry.FileBytes=Length(Image)) and
         (Length(Image)=Length(Base)+20),
         'PSUBQ ELF64 має невірну геометрію');
    Need((Copy(Image,1,96)=Copy(Base,1,96)) and
         (Copy(Image,113,8)=Copy(Base,113,8)),
         'змінено не-size поля ELF заголовка');
    Need(Copy(Image,HeaderBytes+NewPrologue+1,
         Length(Image)-HeaderBytes-NewPrologue)=
         Copy(Base,HeaderBytes+OldPrologue+1,
         Length(Base)-HeaderBytes-OldPrologue),
         'змінено незмінний D12/D24 T5M writer');
    Need(Copy(Image,HeaderBytes+21,5)=#$66#$45#$0F#$FB#$C1,
         'немає фізичного SSE2 PSUBQ XMM8,XMM9');
    Need(Image=BuildIRWideSubSSE2ELF(Source,'external/sens'),
         'повторне кодогенерування недетерміноване');
    Save(LabelText+'.sse2.elf',Image);
    Inc(Good);
  end;
  Zero:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
  One:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
  D24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
  Refuse('чужа D5 голова',Pack(['10','01010',Zero,One,'01']));
  Refuse('чужа D6 голова',Pack(['10','010100',Zero,One,'01']));
  Refuse('чужа D7 голова',Pack(['10','0001011',Zero,One,'01']));
  Refuse('D1 замість D12',Pack(['10','01011','1',One,'01']));
  Refuse('D24 як другий аргумент',Pack(['10','01011',One,D24,'01']));
  Refuse('відсутній аргумент',Pack(['10','01011',One,'01']));
  Refuse('зайвий аргумент',Pack(['10','01011',One,One,One,'01']));
  Refuse('вкладений аргумент',
    Pack(['10','01011','10',One,'01',One,'01']));
  Refuse('два D2 корені',Pack(['10','01011',One,One,'01','0']));
  Refuse('D2 крапкова пара',Pack(['10','01011','11',One,One,'01']));
  Refuse('незакрита D2 форма',Pack(['10','01011',One,One]));
  Refuse('голий D12',Pack([One]));
  Refuse('неканонічний T5M',#$FF);
  Refuse('порожнє джерело','');
  Refuse('D3 порожнеча не D12',Pack(['10','01011','000',One,'01']));
  Refuse('надлишковий D2 хвіст',Pack(['10','01011',One,One,'01','01']));
  Need((Good=12) and (Bad=16),'неповна матриця позитивів/відмов');
  WriteLn('D5-PSUBQ-IR-ГАРАЗД positives=12 negatives=16 D24=4');
end.
