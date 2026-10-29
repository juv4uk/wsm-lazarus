{ G6.64 — фізичний ExactIR D1 ATOM: direct vs pinned prior emitter.
  Input: owned T5M/ExactIR; output: binary ELF64 ET_EXEC.
  Questions: Why full byte equality? Who owns IR? Why no English names?
  Why cannot D12 replace D1? Where is ATOM computed at runtime? }
program test_exactir_atom_priamyi;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.bind,wsm.domain,wsm.exactir,
  wsm.exactirtoelf,wsm.elfatomt5m;
var Root,Folder:String;Tables:TDomainSet;IR:TExactIR;
    Physical,Image,Reference,Status:RawByteString;Checks,Rejected:SizeInt;
    Sink:THandleStream;
procedure Check(B:Boolean;const S:String);
begin
  if not B then raise Exception.Create('ПРЯМИЙ-АТОМ-ПРОВАЛ: '+S);
  Inc(Checks);
end;
function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;
procedure Save(const Name:String;const B:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(B)>0 then F.WriteBuffer(B[1],Length(B));
  finally F.Free end;
end;
procedure Prepare(const A:TExactWords);
begin
  Physical:=EncodeT5M(A);
  BuildExactIR(Physical,Tables,IR);
end;
procedure Positive(const Bit,Name:RawByteString);
begin
  Prepare(W(['10','010',Bit,'01']));
  Image:=BuildVerifiedAtomIR(Physical,RawByteString(Root),IR);
  Reference:=BuildAtomT5MELF(Physical,RawByteString(Root));
  Check(Image=Reference,'старий ELF відрізняється '+String(Name));
  Check((Length(Image)>150) and (Ord(Image[17])=2) and
    (Ord(Image[19])=62),'ELF64 ET_EXEC');
  Check(Pos(#$83#$E0#$03#$83#$F8#$03#$0F#$95#$C0,Image)>0,
    'машинні AND/CMP/SETNE');
  Check(BuildVerifiedAtomIR(Physical,RawByteString(Root),IR)=Image,
    'недетермінований binary ELF');
  Save(String(Name)+'.elf',Image);
  Save(String(Name)+'.expected.sens',EncodeT5M(W(['1'])));
  Save(String(Name)+'.input.sens',Physical);
end;
procedure Reject(const S:String);
var B:RawByteString;Failed:Boolean;
begin
  Failed:=False;B:='';
  try B:=BuildVerifiedAtomIR(Physical,RawByteString(Root),IR)
  except on E:EVerifiedIRELFError do Failed:=True end;
  Check(Failed and (B=''),'не відхилено '+S);
  Inc(Rejected);
end;
begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);Folder:=ParamStr(2);Checks:=0;Rejected:=0;
  Check(ForceDirectories(Folder),'каталог свідків');
  LoadPinnedDomains(RawByteString(Root),Tables);
  Positive('0','д1-нуль');
  Positive('1','д1-один');
  Prepare(W(['10','010','000','01']));
  Check(BuildVerifiedAtomIR(Physical,RawByteString(Root),IR)=
    BuildAtomT5MELF(Physical,RawByteString(Root)),'fallback D3:000');
  Prepare(W(['10','010','10','111','0','1','01','01']));
  Check(BuildVerifiedAtomIR(Physical,RawByteString(Root),IR)=
    BuildAtomT5MELF(Physical,RawByteString(Root)),'fallback D3:111');
  Prepare(W(['10','010','0','01']));IR.Nodes[2].Key:=ExactKey('1');
  Reject('D1 bit');
  Prepare(W(['10','010','0','01']));IR.Nodes[2].ParentIndex:=42;
  Reject('parent');
  Prepare(W(['10','010','0','01']));Inc(IR.Nodes[2].WordIndex);
  Inc(IR.Nodes[2].Physical.WordIndex);Reject('word location');
  Prepare(W(['10','010','0','01']));
  Physical:=EncodeT5M(W(['10','010','1','01']));Reject('physical mismatch');
  Prepare(W(['10','010','0','01']));Physical:=#$F3;Reject('bad T5M');
  Prepare(W(['10','010','0','01']));IR.Nodes[1].Key:=ExactKey('001');
  Reject('D3 head');
  Positive('1','д1-відновлено');
  Check(Rejected=6,'лічильник негативів');
  { Нативний FPC TextRec конвертує кирилицю через host locale.
    Приватний UTF-8 статус — лише діагностика, не .sens або SENS закон. }
  Status:=RawByteString(UTF8Encode(UnicodeString(
    'ПРЯМИЙ-АТОМ-ГАРАЗД FPC=так machine=3 fallback=2 негативи=')))+
    RawByteString(IntToStr(Rejected))+
    RawByteString(UTF8Encode(UnicodeString(' перевірок=')))+
    RawByteString(IntToStr(Checks))+#10;
  Sink:=THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Status[1],Length(Status))
  finally Sink.Free end;
end.
