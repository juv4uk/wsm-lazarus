{ G6.81 — admitted exact D6 call lowered to the pinned x86-64 ADD path. }
unit wsm.elfd6add1;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type ED6Add1ELFError=class(Exception);
function BuildD6Add1ELF(const Physical,MachineProfilePath:RawByteString):RawByteString;
implementation
uses Classes,wsm.t5m,wsm.d2source,wsm.domain,wsm.bind,wsm.numericplane,
  wsm.numericadd,wsm.elfgeometry,wsm.source;
const ELFHeaderBytes=120;
function ReadSmallFile(const Path:RawByteString;Limit:SizeInt):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(String(Path),fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>Limit) then raise ED6Add1ELFError.Create('розмір pinned машинного профілю поза межею');
    SetLength(Result,F.Size); F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ED6Add1ELFError.Create(Why) end;
function IsAtom(N:TSourceNode;const S:RawByteString):Boolean;
begin Result:=(N<>nil) and (N.Kind=skAtom) and (N.Text=S) end;
procedure AdmitMachineProfile(const Path:RawByteString);
var S:RawByteString; Doc:TSourceDocument; Root,Rows,Row:TSourceNode; I,Matches:SizeInt;
begin
  S:=ReadSmallFile(Path,1024*1024); Doc:=ReadUkrainianSource(S);
  try
    Need((Length(Doc.Forms)=1),'машинний профіль має одну кореневу форму'); Root:=Doc.Forms[0];
    Need((Root.Kind=skList) and (Length(Root.Children)=5) and IsAtom(Root.Children[0],'machine-domain-profile-3'),'невідома структура машинного профілю');
    Need((Root.Children[1].Kind=skList) and (Length(Root.Children[1].Children)=2) and IsAtom(Root.Children[1].Children[0],'target') and IsAtom(Root.Children[1].Children[1],'x86-64'),'машинний профіль не для x86-64');
    Need((Root.Children[2].Kind=skList) and (Length(Root.Children[2].Children)=2) and IsAtom(Root.Children[2].Children[0],'cpu') and IsAtom(Root.Children[2].Children[1],'intel-core-i5-6400'),'машинний профіль не для Intel Core i5-6400');
    Need((Root.Children[3].Kind=skList) and (Length(Root.Children[3].Children)=2) and IsAtom(Root.Children[3].Children[0],'key-shape') and IsAtom(Root.Children[3].Children[1],'domain+ukr-resident'),'машинний профіль має іншу форму ключа');
    Rows:=Root.Children[4]; Need((Rows.Kind=skList) and (Length(Rows.Children)>0) and IsAtom(Rows.Children[0],'rows'),'відсутні машинні рядки'); Matches:=0;
    for I:=1 to High(Rows.Children) do begin
      Row:=Rows.Children[I];
      if (Row.Kind=skList) and (Length(Row.Children)=4) and
        IsAtom(Row.Children[0],'домен-шостий') and IsAtom(Row.Children[1],'додати-1') then begin
        Inc(Matches); Need(IsAtom(Row.Children[2],'fast-path') and
          (Row.Children[3].Kind=skString) and
          (UTF8Decode(Row.Children[3].Text)='"ADD / точний 64-бітний вхід не перевищує найбільше значення мінус два; правий операнд = 1"'),
          'D6 fast path не дозволяє очікуваний ADD');
      end;
    end;
    Need(Matches=1,'машинний профіль має рівно один рядок D6 додати-1');
  finally Doc.Free end;
end;
function Immediate12(const Bits:RawByteString):LongWord;
var I:SizeInt;
begin
  Need((Length(Bits)=12) and (Bits[1]='0'),'для fast path потрібен невід’ємний D12'); Result:=0;
  for I:=1 to 12 do begin Need(Bits[I] in ['0','1'],'пошкоджений D12'); Result:=(Result shl 1) or (Ord(Bits[I])-Ord('0')) end;
end;
function T5MByte(Chunk,Index:SizeInt):Byte;
var Bits,Encoded:RawByteString; W:TExactWords; I,Count,Start:SizeInt;
begin
  Start:=Chunk*5; Count:=12-Start; if Count>5 then Count:=5;
  Need((Chunk>=0) and (Chunk<3) and (Index>=0) and (Index<(1 shl Count)),'T5M table index outside byte'); Bits:=StringOfChar('0',12);
  for I:=0 to Count-1 do if (Index and (1 shl (Count-I-1)))<>0 then Bits[Start+I+1]:='1';
  SetLength(W,1); W[0]:=Bits; Encoded:=EncodeT5M(W); Result:=Byte(Encoded[Chunk+1]);
end;
function BuildD6Add1ELF(const Physical,MachineProfilePath:RawByteString):RawByteString;
var Doc:TD2Document; Tables:TDomainSet; Key:TDomainKey; Row:TDomainRow;
  Arg,Output,Image,Code:RawByteString; Words:TExactWords; Num:TExplicitNumeric;
  Value:LongWord; I,J,N,Shift,Mask,TableOffset,PosLEA:SizeInt; Geometry:TELFGeometry;
  LEAs,TableOffsets:array[0..2] of SizeInt;
  procedure Put(Off:SizeInt;V:QWord;Count:SizeInt);
  var J:SizeInt;
  begin Need((Off>=0) and (Count>0) and (Off+Count<=Length(Image)),'ELF поле поза образом'); for J:=0 to Count-1 do begin Image[Off+J+1]:=AnsiChar(Byte(V)); V:=V shr 8 end end;
  procedure Emit32(V:LongWord);
  var J:SizeInt;
  begin for J:=0 to 3 do begin Code:=Code+AnsiChar(V and $FF); V:=V shr 8 end end;
begin
  Result:=''; AdmitMachineProfile(MachineProfilePath);
  try Doc:=ReadD2T5MWide(Physical); except on E:Exception do
    raise ED6Add1ELFError.Create(RawByteString(UTF8Encode(UTF8Decode('відхилено фізичний D2/T5M виклик: ')+UnicodeString(E.Message)))) end;
  try
    Need((Length(Doc.Roots)=1) and (Doc.Roots[0].Kind=dkList) and (Length(Doc.Roots[0].Children)=2),'очікується один список: голова й один аргумент');
    Need((Doc.Roots[0].Children[0].Width=6) and (Doc.Roots[0].Children[0].Bits='001110'),'голова не є точним D6 ключем 001110');
    LoadPinnedDomains('external/sens',Tables); Key:=ExactKey('001110');
    Need(DomainRowByKey(Tables[6],Key,Row) and (UTF8Decode(Row.Ukrainian)='додати-1'),'точний D6 ключ відсутній у pinned таблиці');
    Arg:=EncodeT5M(TExactWords([Doc.Roots[0].Children[1].Bits]));
    Num:=ReadNumericPhysical(Arg,12); Value:=Immediate12(Num.ExactBits);
    Need(Value<=2045,'вхід виходить за межу pinned D6 ADD fast path або переповнює D12');
    Output:=AddNumericPhysical(Arg,EncodeNumericDecimal('1',12),12);
    Need(ReadNumericPhysical(Output,12).DomainWidth=12,'результат не лишився точним D12');
    DecodeT5M(Output,Words); Need((Length(Words)=1) and (Length(Words[0])=12),'некоректний результат T5M');
  finally Doc.Free end;
  Code:=''; Code:=Code+#$B8; Emit32(Value); Code:=Code+#$05; Emit32(1); { mov eax,imm32; add eax,1 }
  Code:=Code+#$48#$83#$EC#$08;
  for I:=0 to 2 do begin
    N:=12-I*5; if N>5 then N:=5; Shift:=12-(I*5+N); Mask:=(1 shl N)-1;
    Code:=Code+#$89#$C1; if Shift>0 then begin Code:=Code+#$C1#$E9; Code:=Code+AnsiChar(Shift) end;
    Code:=Code+#$83#$E1; Code:=Code+AnsiChar(Mask); LEAs[I]:=Length(Code);
    Code:=Code+#$48#$8D#$35#0#0#0#0#$8A#$14#$0E;
    if I=0 then Code:=Code+#$88#$14#$24 else begin Code:=Code+#$88#$54#$24; Code:=Code+AnsiChar(I) end;
  end;
  Code:=Code+#$B8#$01#0#0#0#$BF#$01#0#0#0#$48#$89#$E6#$BA#$03#0#0#0#$0F#$05#$B8#$3C#0#0#0#$31#$FF#$0F#$05;
  TableOffset:=Length(Code);
  for I:=0 to 2 do begin
    TableOffsets[I]:=TableOffset; N:=12-I*5; if N>5 then N:=5;
    for J:=0 to (1 shl N)-1 do Code:=Code+AnsiChar(T5MByte(I,J)); Inc(TableOffset,1 shl N);
  end;
  for I:=0 to 2 do begin
    PosLEA:=LEAs[I]; TableOffset:=ELFHeaderBytes+TableOffsets[I]-(ELFHeaderBytes+PosLEA+7);
    for J:=0 to 3 do begin Code[PosLEA+4+J]:=AnsiChar(TableOffset and $FF); TableOffset:=TableOffset shr 8 end;
  end;
  SetLength(Image,ELFHeaderBytes+Length(Code)); FillChar(Image[1],Length(Image),0);
  Put(0,$464C457F,4); Put(4,2,1); Put(5,1,1); Put(6,1,1); Put(16,3,2); Put(18,62,2); Put(20,1,4); Put(24,ELFHeaderBytes,8); Put(32,64,8); Put(52,64,2); Put(54,56,2); Put(56,1,2); Put(64,1,4); Put(68,5,4); Put(96,Length(Image),8); Put(104,Length(Image),8); Put(112,$1000,8);
  for I:=1 to Length(Code) do Image[ELFHeaderBytes+I]:=Code[I]; VerifySENSELF64(Image,Geometry);
  Need((Geometry.Kind=3) and (Geometry.FileBytes=Length(Image)),'ELF64 PIE geometry failed'); Result:=Image;
end;
end.
