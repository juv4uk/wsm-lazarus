{ G6.120 — справжні canonical packed D5:01010(W12,W12) програми.
  Числові фізичні пари походять із чинних G6.63 fixture файлів.  Перевірено, що всі перевірені байти T5M writer лишилися тими самими.
  Генератор НЕ семантичний oracle; oracle — pinned SENS REPL у CI.
  1) Чому '10' та '01' залишаються D2, не числом?
  2) Чому W12 без D5 не викличне?
  3) Чому у порівнянні ELF важливі всі байти, не тільки stdout?
  4) Де відхилені D24 overflow і multi-root? }
program test_irwidespilladd;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.irwiderexadd,wsm.irwidespilladd,wsm.elfgeometry;
var Dir:String;I,Good,Bad:SizeInt;L,R,L24,Zero,Head:RawByteString;
    Source,NewELF,OldELF,Invalid:RawByteString;N:TExplicitNumeric;
    G:TELFGeometry;LabelText:String;

procedure Need(Ok:Boolean;const Why:String);
begin
  if not Ok then raise Exception.Create('Д5-SPILL-ПРОВАЛ: '+Why);
end;

function GetBytes(const Path:String):RawByteString;
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((S.Size>=0) and (S.Size<=128),'файл фізичного атома завеликий');
    SetLength(Result,SizeInt(S.Size));
    if Length(Result)>0 then S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;

procedure Save(const Name:String;const Data:RawByteString);
var S:TFileStream;
begin
  S:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data));
  finally S.Free end;
end;

function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;K:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for K:=0 to High(Tokens) do Words[K]:=Tokens[K];
  Result:=EncodeT5M(Words);
end;

procedure Refuse(const Why:String;const Bytes:RawByteString);
var Candidate:RawByteString;Rejected:Boolean;
begin
  Candidate:='';Rejected:=False;
  try Candidate:=BuildIRWideSpillAddELF(Bytes,'external/sens')
  except on E:Exception do Rejected:=True end;
  Need(Rejected and (Candidate=''),'не відхилено '+Why);
  Inc(Bad);
end;

function Immediate(const S:RawByteString;Offset:SizeInt):QWord;
var K:SizeInt;
begin
  Need((Offset>=0) and (Offset<=Length(S)-8),'неповний original immediate');
  Result:=0;
  for K:=7 downto 0 do
    Result:=(Result shl 8) or QWord(Byte(S[Offset+K+1]));
end;

procedure WriteMachineReference(const Name:String;const Original:RawByteString);
var Lines:TStringList;K:Integer;RegName:String;
begin
  Lines:=TStringList.Create;
  try
    Lines.Add('.intel_syntax noprefix');
    Lines.Add('.text');
    Lines.Add('.global _start');
    Lines.Add('_start:');
    Lines.Add('  sub rsp,16');
    Lines.Add('  movabs rax,0x'+IntToHex(Immediate(Original,132),16));
    Lines.Add('  mov QWORD PTR [rsp],rax');
    Lines.Add('  movabs r8,0x'+IntToHex(Immediate(Original,122),16));
    for K:=1 to 7 do begin
      RegName:='r'+IntToStr(K+8);
      Lines.Add('  movabs '+RegName+',0x'+IntToHex(K*17+1,16));
    end;
    for K:=1 to 7 do begin
      RegName:='r'+IntToStr(K+8);
      Lines.Add('  xor r8,'+RegName);
      Lines.Add('  xor r8,'+RegName);
    end;
    Lines.Add('  mov rax,QWORD PTR [rsp]');
    Lines.Add('  add r8,rax');
    Lines.Add('  mov rax,r8');
    Lines.Add('  add rsp,16');
    Lines.SaveToFile(Dir+'/'+Name+'.prefix.s');
  finally Lines.Free end;
end;

begin
  Need(ParamCount=1,'потрібна приватна тека свідків');
  Dir:=ParamStr(1);
  Need(DirectoryExists(Dir),'фізична тека відсутня');
  Good:=0;Bad:=0;
  for I:=1 to 9 do begin
    LabelText:=Format('%.2d',[I]);
    L:=GetBytes(Dir+'/'+LabelText+'-l.sens');
    R:=GetBytes(Dir+'/'+LabelText+'-r.sens');
    N:=ReadNumericPhysical(L,12);L:=N.ExactBits;
    N:=ReadNumericPhysical(R,12);R:=N.ExactBits;
    Source:=Pack(['10','01010',L,R,'01']);
    Save(LabelText+'.sens',Source);
    NewELF:=BuildIRWideSpillAddELF(Source,'external/sens');
    OldELF:=BuildIRWideRexAddELF(Source,'external/sens');
    VerifySENSELF64(NewELF,G);
    Need((G.Kind=3) and (G.Entry=120),'не підтверджено ET_DYN ELF64');
    Need(Length(NewELF)=Length(OldELF)+128,'невірна довжина spill ELF');
    Need((Copy(NewELF,121,4)=#$48#$83#$EC#$10) and
         (Copy(NewELF,271,4)=#$48#$83#$C4#$10),
         'справжній стековий кадр відсутній');
    Need(Copy(NewELF,275,Length(NewELF)-274)=
         Copy(OldELF,147,Length(OldELF)-146),
         'змінено verified writer bytes поза прологом');
    Save(LabelText+'.prefix.bin',Copy(NewELF,121,154));
    WriteMachineReference(LabelText,OldELF);
    Save(LabelText+'.reference.elf',NewELF);
    Save(LabelText+'.prior.elf',OldELF);
    Inc(Good);
  end;
  L:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
  R:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
  L24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
  Refuse('інша голова D5',Pack(['10','01011',L,R,'01']));
  Refuse('інша голова D6',Pack(['10','010010',L,R,'01']));
  Refuse('голова D7',Pack(['10','0010110',L,R,'01']));
  Refuse('перший D1',Pack(['10','01010','1',R,'01']));
  Refuse('другий D24',Pack(['10','01010',L,L24,'01']));
  Refuse('бракує аргумента',Pack(['10','01010',L,'01']));
  Refuse('зайвий аргумент',Pack(['10','01010',L,R,R,'01']));
  Refuse('вкладений аргумент',Pack(['10','01010','10',L,'01',R,'01']));
  Refuse('два корені',Pack(['10','01010',L,R,'01','0']));
  Refuse('крапкова пара',Pack(['10','01010','11',L,R,'01']));
  Refuse('незакритий D2',Pack(['10','01010',L,R]));
  Refuse('неканонічний T5M',#$FF);
  Refuse('порожнє фізичне джерело','');
  L:=ReadNumericPhysical(EncodeNumericDecimal('2047',12),12).ExactBits;
  Refuse('позитивне D24 переповнення',Pack(['10','01010',L,R,'01']));
  L:=ReadNumericPhysical(EncodeNumericDecimal('-2048',12),12).ExactBits;
  R:=ReadNumericPhysical(EncodeNumericDecimal('-1',12),12).ExactBits;
  Refuse('негативне D24 переповнення',Pack(['10','01010',L,R,'01']));
  Need((Good=9) and (Bad=15),'невірний лічильник свідків');
  WriteLn('D5-SPILL-OK physical=9 tail-identical=9 negative=15 gnu-prefix=9');
end.
