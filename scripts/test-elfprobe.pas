{ G6.34: реальний Free Pascal дочірній x86-64, T5M byte-exact. }
program test_elfprobe;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfprobe,wsm.t5m;
var Positives,Negatives:SizeInt;
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
function Load(const Path:String):RawByteString;
var S:TFileStream;
begin
  S:=TFileStream.Create(Path,fmOpenRead);
  try
    SetLength(Result,S.Size);
    if Result<>'' then S.ReadBuffer(Result[1],Length(Result));
  finally S.Free end;
end;
function Words(const Items:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Items));
  for I:=0 to High(Items) do Result[I]:=Items[I];
end;
procedure Must(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('МАШИНА-ТЕСТ-ПОМИЛКА: '+Why) end;
procedure Positive(const Dir,Name:String);
var Input,Expected,Actual:RawByteString;
begin
  Input:=Load(Dir+'/'+Name+'.sens');
  Expected:=Load(Dir+'/'+Name+'.expected.sens');
  Actual:='попередній';
  ExecutePinnedCondELF(Input,'external/sens',Actual);
  Must((Actual=Expected) and (Length(Actual)=1),Name+' T5M stdout');
  Inc(Positives);
end;
procedure Negative(const Source,Authority,Why:RawByteString);
var Actual:RawByteString;Rejected:Boolean;
begin
  Actual:='застарілий';Rejected:=False;
  try ExecutePinnedCondELF(Source,Authority,Actual)
  except on E:EELFProbeError do Rejected:=True end;
  Must(Rejected and (Actual=''),String(Why)+' fail-closed');
  Inc(Negatives);
end;
begin
  if ParamCount<>1 then
    raise Exception.Create('Потрібна тека з точними фізичними свідками');
  Positives:=0;Negatives:=0;
  Positive(ParamStr(1),'00');
  Positive(ParamStr(1),'01');
  Positive(ParamStr(1),'02');
  Positive(ParamStr(1),'03');
  Positive(ParamStr(1),'04');
  Positive(ParamStr(1),'05');
  Positive(ParamStr(1),'06');
  Positive(ParamStr(1),'07');
  Positive(ParamStr(1),'08');
  Negative('','external/sens','порожній T5M');
  Negative(#$F3,'external/sens','неканонічний T5M');
  Negative(EncodeT5M(Words(['0'])),'external/sens','D1 не є D3');
  Negative(EncodeT5M(Words(['10','110','10','000000000000',
    '1','01','01'])),'external/sens','D12 не є предикатом D1');
  Negative(EncodeT5M(Words(['10','110','10','000',
    '1','01','01'])),'external/sens','D3:000 не є предикатом D1');
  Negative(EncodeT5M(Words(['10','110','10','1',
    '000','01','01'])),'external/sens','D3:000 не є відповіддю D1');
  Negative(EncodeT5M(Words(['10','110','10','1','1','01','01',
    '1'])),'external/sens','два корені');
  Negative(Load(ParamStr(1)+'/01.sens'),
    'відсутній-authority','невідомий pinned authority');
  Negative(StringOfChar('x',65537),'external/sens',
    'host-limited physical input');
  Must((Positives=9) and (Negatives=9),'лічильники перевірок');
  WriteLn(UA('МАШИНА-ELF-D3-ГАРАЗД Linux=x86-64 ELF=9'),
    UA(' T5M=побайтово негативи='),Negatives,
    UA(' stderr=порожній timeout=2s тимчасові-файли=видалено'));
end.
