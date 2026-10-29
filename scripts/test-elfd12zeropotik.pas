{ G6.97 — FPC створює реальні ELF та незалежні фізичні fixtures.
  Тест не називає native backend повним компілятором SENS. }
program TestD12ZeroStream;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.elfd12zero,
     wsm.elfd12zeropotik;
const Numbers:array[0..11] of LongInt=(0,1,-1,17,-17,1024,-1024,
                                      2047,-2048,-2047,2,-2);
procedure Check(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create(Why) end;
procedure Save(const Path:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;
var Dir,Name,Physical,Image,Expected:RawByteString;
    I:SizeInt; W:TExactWords;
begin
  Check(ParamCount=1,'потрібна приватна тека тестових файлів');
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  Check(DirectoryExists(Dir),'немає приватної теки');
  Image:=BuildD12ZeroStreamELF;
  Check(Length(Image)>120,'порожній нативний ELF');
  Save(Dir+'stream.elf',Image);
  SetLength(W,1);
  for I:=Low(Numbers) to High(Numbers) do begin
    Name:=Format('%.2d',[I]);
    Physical:=EncodeNumericDecimal(IntToStr(Numbers[I]),12);
    Check(Length(Physical)=3,'число D12 не має рівно 3 байти');
    Save(Dir+Name+'.sens',Physical);
    Save(Dir+Name+'.elf',BuildD12ZeroELF(Physical));
    if Numbers[I]=0 then W[0]:='1' else W[0]:='0';
    Expected:=EncodeT5M(W);
    Save(Dir+Name+'.expected.sens',Expected);
  end;
  WriteLn('D12-STREAM-BUILD-OK elf=1 vectors=12 oracle=existing-ELF');
end.
