{ G5.22: справжні українські `.lisp` проєкції існуючих pinned
  фізичних Core4 T5M викликів. Немає таблиць законів у генераторі. }
program test_core4_uk_session;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.bind,wsm.ukroundtrip;

procedure Require(Condition:Boolean;const Message:String);
begin
  if not Condition then raise Exception.Create('УКР-СЕАНС-СВІДОК: '+Message);
end;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Require((F.Size>0) and (F.Size<=1024*1024),'розмір фізичного джерела');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Data<>'' then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

var Root,Dir:String; Tables:TDomainSet; Longs:TLongProjection;
    Tak,Ni,Physical,Projection,Repacked:RawByteString; Rejected:Boolean;
begin
  Require(ParamCount=2,'потрібні корінь репозиторію та тека фізичних свідків');
  Root:=IncludeTrailingPathDelimiter(ParamStr(1))+'external/sens';
  Dir:=IncludeTrailingPathDelimiter(ParamStr(2));
  LoadPinnedDomains(RawByteString(Root),Tables);
  LoadPinnedLongProjection(RawByteString(Root),Tables,Longs);

  Physical:=ReadPhysical(Dir+'01-tak.sens');
  Tak:=PhysicalToUkrainian(Physical,Tables,Longs);
  Repacked:=UkrainianToPhysical(Tak,Tables,Longs);
  Require(Repacked=Physical,'D7 identity + D1:1 .lisp→.sens НЕ побайтово тотожний');
  Save(Dir+'01-tak.lisp',Tak);

  Physical:=ReadPhysical(Dir+'03-ni.sens');
  Ni:=PhysicalToUkrainian(Physical,Tables,Longs);
  Repacked:=UkrainianToPhysical(Ni,Tables,Longs);
  Require(Repacked=Physical,'D7 identity + D1:0 round-trip НЕ побайтовий');
  Save(Dir+'03-ni.lisp',Ni);

  Save(Dir+'multi.lisp',Tak+Ni);
  Save(Dir+'невідома.lisp','невідоме'#10);
  Save(Dir+'порожня.lisp','');
  Save(Dir+'число.lisp','24'#10);

  { Числа D12+ не вгадуються за host-шириною або людською цифрою.
    D24 фізичний виклик НЕ є оборотною проєкцією піднабору D1–D9. }
  Rejected:=False;
  try
    Projection:=PhysicalToUkrainian(
      ReadPhysical(Dir+'04-d24-argument.sens'),Tables,Longs);
  except on E:EUkRoundtripError do Rejected:=True end;
  Require(Rejected,'D24 не може мовчки стати D1–D9 українською проєкцією');

  Rejected:=False;
  try
    Repacked:=UkrainianToPhysical('24'#10,Tables,Longs);
  except on E:EUkRoundtripError do Rejected:=True end;
  Require(Rejected,'людське 24 не стало D24 без ратифікованого кодера');

  WriteLn('CORE4-УКР-СВІДКИ-ГАРАЗД pinned-D7+D1=exact-byte-roundtrip D12+=відхилено');
end.
