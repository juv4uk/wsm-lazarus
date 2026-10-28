{ G5.22: справжні українські `.lisp` проєкції існуючих pinned
  фізичних Core4 T5M викликів. Немає таблиць законів у генераторі. }
program test_core4_uk_session;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.bind,wsm.ukroundtrip,wsm.t5m,wsm.core4runtime;

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

{ Побудова фізичного недопустимого ВИКЛИКУ тільки зі справжнього
  pinned D7-ідентифікатора атомного глобала з Core4: ім'я є відомим,
  але в ролі функції воно не викличне. Жодного нового opcode. }
function GlobalAsCall(const Global:RawByteString):RawByteString;
var Words,CallWords:TExactWords;I:SizeInt;
begin
  DecodeT5M(Global,Words);
  Require(Length(Words)>=3,'фізична D7 послідовність глобала');
  SetLength(CallWords,Length(Words)+3);
  CallWords[0]:='10';
  for I:=0 to High(Words) do CallWords[I+1]:=Words[I];
  CallWords[Length(Words)+1]:='1';
  CallWords[Length(Words)+2]:='01';
  Result:=EncodeT5M(CallWords);
end;

var Root,Dir:String; Tables:TDomainSet; Longs:TLongProjection;
    Tak,Ni,Physical,Projection,Repacked,BadPhysical,BadText,PackageText:RawByteString;
    Rejected:Boolean;I:SizeInt;Runtime:TCore4Runtime;
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

  { Дві/три/64 канонічні українські проєкції pinned фізичних форм. }
  Save(Dir+'ukr-paket2.lisp',Tak+Ni);
  Save(Dir+'ukr-paket3.lisp',Tak+Ni+Tak);
  PackageText:='';
  for I:=1 to 64 do PackageText:=PackageText+Tak;
  Save(Dir+'ukr-paket64.lisp',PackageText);
  Save(Dir+'ukr-paket65.lisp',PackageText+Tak);

  { Третя форма — фізично оборотна і pinned, але не підтримується
    чинним вузьким Core4 evaluator: D7 атомний глобал у call-position.
    Це справжній ПІЗНІЙ semantic negative після двох успішних форм. }
  BadPhysical:=GlobalAsCall(ReadPhysical(Dir+'05-global-d24-0.sens'));
  BadText:=PhysicalToUkrainian(BadPhysical,Tables,Longs);
  Require(UkrainianToPhysical(BadText,Tables,Longs)=BadPhysical,
    'помилкова runtime форма має лишатися точно оборотною у T5M');
  Runtime:=TCore4Runtime.Create(ParamStr(1));
  try
    Rejected:=False;
    try
      Runtime.ExecutePhysicalCall(BadPhysical);
    except on E:ECore4RuntimeError do Rejected:=True end;
    Require(Rejected,'третя форма повинна реально відхилятися Core4 runtime');
  finally Runtime.Free end;
  Save(Dir+'ukr-paket-late.lisp',Tak+Ni+BadText);
  Save(Dir+'ukr-paket-invalid.lisp',Tak+'невідоме'#10);

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
  WriteLn('CORE4-УКР-ПАКЕТ-СВІДКИ-ГАРАЗД фізичні=2,3,64,65 пізня-недопустима=3 байти=тотожні');
end.
