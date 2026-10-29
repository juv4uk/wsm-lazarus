{ G6.150 — лише тестові signed D24 вектори, НЕ мовні закони.
  Вхід RepoRoot / Folder borrowed; Map — pinned D7 map, owned manifest.
  Вихід — фізичні packed T5M тіла, Linux ELF64 ET_EXEC, точний manifest.
  1) Чому W7 береться з pinned D7, а не з ASCII коду імені?
  2) Чому 24 бітів з провідними нулями обов'язкові?
  3) Хто вивільняє TStringList?
  4) Чому machine exit=0/1 не доказ універсального D1 runtime?
  5) Чому оракул виконується іншим CLI, а не цим Pascal тестом? }
program test_lowerd24_parnist;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.d7text,wsm.lowerd24;
const Vectors:array[0..7] of LongInt=
  (-8388608,-13,-2,-1,0,1,2,8388607);
var Map:TD7Map;Folder:String;Manifest:TStringList;
    Key,Foreign:RawByteString;Positive,Rejected:SizeInt;

function NameBits(const S:RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  DecodeT5M(EncodeD7Text(S,Map,dsUk),W);
  Result:='';
  for I:=0 to High(W) do Result:=Result+W[I];
end;
function D7Name(const Bits:RawByteString):TExactWords;
var I,J:SizeInt;
begin
  if (Length(Bits)=0) or ((Length(Bits) mod 7)<>0) then
    raise Exception.Create('не точний фізичний D7 ключ');
  SetLength(Result,Length(Bits) div 7+2);
  Result[0]:='10';J:=1;
  for I:=1 to Length(Bits) div 7 do begin
    Result[J]:=Copy(Bits,(I-1)*7+1,7);Inc(J);
  end;
  Result[J]:='01';
end;
function Bit24(V:LongInt):RawByteString;
var W:LongWord;I:SizeInt;
begin
  W:=LongWord(V) and $FFFFFF;SetLength(Result,24);
  for I:=24 downto 1 do begin
    if (W and 1)=1 then Result[I]:='1' else Result[I]:='0';
    W:=W shr 1;
  end;
end;
function Words(const S:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(S));
  for I:=0 to High(S) do Result[I]:=S[I];
end;
function Join(const Parts:array of TExactWords):TExactWords;
var I,J,K:SizeInt;
begin
  SetLength(Result,0);K:=0;
  for I:=0 to High(Parts) do
    for J:=0 to High(Parts[I]) do begin
      SetLength(Result,K+1);Result[K]:=Parts[I][J];Inc(K)
    end;
end;
function Unary(const Head:RawByteString;const Arg:TExactWords):RawByteString;
begin
  Result:=EncodeT5M(Join([Words(['10',Head]),Arg,Words(['01'])]));
end;
function Quote(const B:RawByteString):TExactWords;
begin Result:=Words(['10','001',B,'01']) end;
function Atom(const B:RawByteString):RawByteString;
begin Result:=EncodeT5M(Words([B])) end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
procedure Reject(const LabelText:String;const Body:RawByteString);
var ELF:RawByteString;
begin
  try
    ELF:=LowerBodyELF(Body,EncodeT5M(D7Name(Key)),Atom(Bit24(3)))
  except on E:Exception do begin Inc(Rejected);Exit end end;
  raise Exception.Create('помилково прийнято '+LabelText+
    ' ELF='+IntToStr(Length(ELF)));
end;

procedure Run;
var I,Kind,Parity,Expected:SizeInt;Head,Tag,Expression,Image:RawByteString;
    Source,Arg:TExactWords;
begin
  if ParamCount<>2 then raise Exception.Create('корінь і каталог обовʼязкові');
  LoadPinnedD7Map(ParamStr(1),Map);
  Folder:=IncludeTrailingPathDelimiter(ParamStr(2));
  if not ForceDirectories(Folder) then raise Exception.Create('не створено каталог');
  Key:=NameBits('величина');Foreign:=NameBits('інше');
  Manifest:=TStringList.Create;
  try
    Positive:=0;Rejected:=0;
    for Kind:=0 to 1 do
      for Parity:=0 to 1 do
        for I:=0 to High(Vectors) do begin
          if Parity=0 then Head:='010000' else Head:='010001';
          if Kind=0 then Arg:=D7Name(Key)
          else Arg:=Quote(Bit24(Vectors[I]));
          Source:=Words(['10',Head]);
          Tag:=IntToStr(Kind)+'-'+IntToStr(Parity)+'-'+IntToStr(I);
          Image:=LowerBodyELF(Unary(Head,Arg),
            EncodeT5M(D7Name(Key)),Atom(Bit24(Vectors[I])));
          if Length(Image)<150 then
            raise Exception.Create('порожній машинний ELF');
          Save(String(Tag)+'.sens',Unary(Head,Arg));
          Save(String(Tag)+'.elf',Image);
          if ((LongWord(Vectors[I]) and 1)=0) = (Parity=0) then
            Expected:=1 else Expected:=0;
          if Parity=0 then Expression:='(парне? '
          else Expression:='(непарне? ';
          Expression:=Expression+IntToStr(Vectors[I])+')';
          Manifest.Add(String(Tag)+#9+IntToStr(Expected)+#9+String(Expression));
          Inc(Positive);
        end;
    Reject('порожня програма','');
    Reject('неканонічний T5M',#$FF);
    Reject('інший D6',Unary('010010',D7Name(Key)));
    Reject('не D6 голова',Unary('01000',D7Name(Key)));
    Reject('відсутній аргумент',EncodeT5M(Words(['10','010000','01'])));
    Reject('два аргументи',EncodeT5M(Join([
      Words(['10','010001']),D7Name(Key),D7Name(Key),Words(['01'])])));
    Reject('D12 цитата',Unary('010000',Quote('000000000001')));
    Reject('D1 цитата',Unary('010001',Quote('1')));
    Reject('чужий D7 параметр',Unary('010000',D7Name(Foreign)));
    Reject('вкладена арифметика',
      Unary('010000',Words(['10','01010','000000000001','000000000010','01'])));
    Manifest.SaveToFile(Folder+'cases.tsv');
    if (Positive<>32) or (Rejected<>10) then
      raise Exception.Create('недостатньо точних перевірок');
    WriteLn('G6.150-D24-PARITY-FIXTURES-OK physical=32 native=32 rejects=10');
  finally Manifest.Free end;
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'D24-ПАРНІСТЬ-ВІДМОВА: ',E.Message);Halt(1)
  end end;
end.
