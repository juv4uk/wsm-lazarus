{ G6.125 — 9 канонічних .sens D5:01010 повних програм
  → pinned verified WideIR → SSE2 PADDQ XMM8/XMM9 ELF64.
  Генератор є ТІЛЬКИ host witness; semantic oracle — pinned REPL
  у незалежному CI. .sens є packed T5M, .lisp — лише людська «укр».
  Збірка/вихід managed RawByteString, TFileStream звільняється явно.
  1) Чому читати саме .sens, не .lisp як джерело машинного компілятора?
  2) Чому 9 результатів у stdout доводять обчислення лише разом із disasm?
  3) Чому оракул бере окремий pinned SENS CLI?
  4) Чому D12→D24 overflow треба відхилити до ELF?
  5) Чому порівняння хвоста попереднього ELF захищає T5M writer? }
program TestIRWideAddSSE2;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.irwideaddreg,wsm.irwideaddsse2,wsm.elfgeometry;
const HeaderBytes=120; PreviousPrologueBytes=12; SIMDPrologueBytes=30;
var Dir:String;I,Good,Bad:SizeInt;LabelText:String;
    Source,Base,Image,L,R,L24:RawByteString;Geom:TELFGeometry;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('Д5-SSE2-ТЕСТ: '+Why) end;
function ReadBytes(const Name:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>=0) and (F.Size<=65536),'завеликий фізичний свідок');
    SetLength(Result,SizeInt(F.Size));
    if Length(Result)>0 then F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes));
  finally F.Free end;
end;
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;J:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for J:=0 to High(Tokens) do W[J]:=Tokens[J];
  Result:=EncodeT5M(W);
end;
procedure Refuse(const LabelReject:String;const Physical:RawByteString);
var Candidate:RawByteString;Rejected:Boolean;
begin
  Candidate:='';Rejected:=False;
  try Candidate:=BuildIRWideAddSSE2ELF(Physical,'external/sens')
  except on E:Exception do begin
    Rejected:=E.Message<>'';
  end end;
  Need(Rejected and (Candidate=''),
       'не відхилено '+' '+LabelReject+' або частково опубліковано ELF');
  Inc(Bad);
end;
begin
  Need(ParamCount=1,'потрібен каталог фізичних свідків');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'каталог свідків не існує');
  Good:=0;Bad:=0;
  for I:=1 to 9 do begin
    LabelText:=Format('%.2d',[I]);
    Source:=ReadBytes(LabelText+'.sens');
    Base:=BuildIRWideAddRegisterELF(Source,'external/sens');
    Image:=BuildIRWideAddSSE2ELF(Source,'external/sens');
    VerifySENSELF64(Image,Geom);
    Need((Geom.Kind=3) and (Geom.Entry=120) and
         (Geom.FileBytes=Length(Image)) and
         (Length(Image)=Length(Base)+18),
         'ELF64 геометрія SSE2 замість host ADD');
    Need(Copy(Image,1,96)=Copy(Base,1,96),
         'неочікуваний змінений ELF header до size fields');
    Need(Copy(Image,113,8)=Copy(Base,113,8),
         'неочікуваний змінений ELF header після size fields');
    Need(Copy(Image,HeaderBytes+SIMDPrologueBytes+1,
        Length(Image)-HeaderBytes-SIMDPrologueBytes)=
         Copy(Base,HeaderBytes+PreviousPrologueBytes+1,
        Length(Base)-HeaderBytes-PreviousPrologueBytes),
        'змінено T5M writer або RIP-rel lookup під час SIMD lowering');
    Need(Copy(Image,HeaderBytes+21,5)=#$66#$45#$0F#$D4#$C1,
         'відсутній PADDQ xmm8,xmm9');
    Save(LabelText+'.sse2.elf',Image);
    Inc(Good);
  end;
  L:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
  R:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
  L24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
  Refuse('інша D5 голова',Pack(['10','01011',L,R,'01']));
  Refuse('D6 голова',Pack(['10','010010',L,R,'01']));
  Refuse('D7 голова',Pack(['10','0010110',L,R,'01']));
  Refuse('D1 перший аргумент',Pack(['10','01010','1',R,'01']));
  Refuse('D24 другий аргумент',Pack(['10','01010',L,L24,'01']));
  Refuse('бракує аргументу',Pack(['10','01010',L,'01']));
  Refuse('зайвий аргумент',Pack(['10','01010',L,R,R,'01']));
  Refuse('вкладена форма',Pack(['10','01010','10',L,'01',R,'01']));
  Refuse('два корені',Pack(['10','01010',L,R,'01','0']));
  Refuse('D2 крапкова пара',Pack(['10','01010','11',L,R,'01']));
  Refuse('незакритий D2',Pack(['10','01010',L,R]));
  Refuse('неканонічний T5M',#$FF);
  Refuse('порожнє джерело','');
  L:=ReadNumericPhysical(EncodeNumericDecimal('2047',12),12).ExactBits;
  Refuse('позитивне D12 переповнення',Pack(['10','01010',L,R,'01']));
  L:=ReadNumericPhysical(EncodeNumericDecimal('-2048',12),12).ExactBits;
  R:=ReadNumericPhysical(EncodeNumericDecimal('-1',12),12).ExactBits;
  Refuse('негативне D12 переповнення',Pack(['10','01010',L,R,'01']));
  Need((Good=9) and (Bad=15),'невірна кількість позитивів і відмов');
  WriteLn('Д5-SSE2-IR-ГАРАЗД physical=9 machine=9 negative=15 tail=identical');
end.
