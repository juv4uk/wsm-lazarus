{ Фізичний FPC свідок G7.8; лише приватні фрейми, не SENS semantics. }
program test_imagecatalog;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain, wsm.envframe, wsm.image,
  wsm.imagecatalog;

var
  Checks: Integer;
  Frame: IEnvFrame;
  Keys: array of TDomainKey;
  Original, Mutant: RawByteString;
  Catalog: TImageCatalog;
  Stream: TMemoryStream;
  F: TFileStream;

procedure Check(OK: Boolean; const Why: String);
begin
  Inc(Checks);
  if not OK then begin
    WriteLn(StdErr, 'КАТАЛОГ-ОБРАЗУ-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;

function MakeImage: RawByteString;
var S: TMemoryStream;
begin
  Frame := NewEnvFrame(nil);
  Frame.InstallLocal(ExactKey('0'), 0);
  Frame.InstallLocal(ExactKey('01'), 42);
  Frame.InstallLocal(ExactKey('000'), 9);
  Frame.InstallLocal(ExactKey('001'), High(QWord));
  SetLength(Keys,4);
  Keys[0]:=ExactKey('001');
  Keys[1]:=ExactKey('000');
  Keys[2]:=ExactKey('01');
  Keys[3]:=ExactKey('0');
  S:=TMemoryStream.Create;
  try
    SaveFrameImage(Frame,Keys,S);
    SetLength(Result,S.Size);
    Move(S.Memory^,Result[1],S.Size);
  finally S.Free; end;
end;

procedure ReadBytes(const Data: RawByteString; out Rows: TImageCatalog);
var S:TMemoryStream;
begin
  S:=TMemoryStream.Create;
  try
    if Length(Data)>0 then S.WriteBuffer(Data[1],Length(Data));
    S.Position:=0;
    ReadImageCatalog(S,Rows);
  finally S.Free; end;
end;

procedure Reject(const Data: RawByteString; const Why: String);
var C:TImageCatalog; Rejected:Boolean;
begin
  SetLength(C,1);
  Rejected:=False;
  try ReadBytes(Data,C);
  except
    on E:EImageError do Rejected:=True;
    on E:EImageCatalogError do Rejected:=True;
  end;
  Check(Rejected,Why+' прийнято');
  Check(Length(C)=0,Why+' залишило частковий каталог');
end;

begin
  Checks:=0;
  Original:=MakeImage;
  Check(Length(Original)=8+4+4*11+4,'довжина приватного формату');
  ReadBytes(Original,Catalog);
  Check(Length(Catalog)=4,'точне число реально відновлених координат');
  Check((Catalog[0].Key.Width=1) and
    (KeyBits(Catalog[0].Key)='0') and
    (Catalog[0].OpaqueHandle=0),'D1:0, host нуль');
  Check((Catalog[1].Key.Width=2) and
    (KeyBits(Catalog[1].Key)='01') and
    (Catalog[1].OpaqueHandle=42),'D2:01, host 42');
  Check((Catalog[2].Key.Width=3) and
    (KeyBits(Catalog[2].Key)='000') and
    (Catalog[2].OpaqueHandle=9),'D3:000 окреме від D1:0');
  Check((Catalog[3].Key.Width=3) and
    (KeyBits(Catalog[3].Key)='001') and
    (Catalog[3].OpaqueHandle=High(QWord)),'opaque u64 без втрати бітів');
  Check(not SameKey(Catalog[0].Key,Catalog[2].Key),'D1:0 не є D3:000');

  Reject('','порожній образ');
  Reject(Copy(Original,1,Length(Original)-1),'обрізаний образ');
  Reject(Original+#0,'хвостові байти');
  Mutant:=Original; Mutant[1]:='X';
  Reject(Mutant,'неправильна магія');
  Mutant:=Original; Mutant[16]:=AnsiChar(Ord(Mutant[16]) xor 1);
  Reject(Mutant,'змінений payload/контрольна сума');

  { Вхідний потік зі зміщенням не є допущеним образом. }
  Stream:=TMemoryStream.Create;
  try
    Stream.WriteBuffer(Original[1],Length(Original));
    Stream.Position:=1;
    SetLength(Catalog,1);
    try
      ReadImageCatalog(Stream,Catalog);
      Check(False,'вхід із зміщенням прийнято');
    except
      on E:EImageError do Check(Length(Catalog)=0,
        'помилка зсуву залишила каталог');
    end;
  finally Stream.Free; end;
  SetLength(Catalog,1);
  try
    ReadImageCatalog(nil,Catalog);
    Check(False,'відсутній потік прийнято');
  except
    on E:EImageCatalogError do Check(Length(Catalog)=0,
      'порожній потік залишив каталог');
  end;

  if (ParamCount=2) and (ParamStr(1)='--створити-фікстуру') then begin
    F:=TFileStream.Create(ParamStr(2),fmCreate);
    try F.WriteBuffer(Original[1],Length(Original));
    finally F.Free; end;
    WriteLn('КАТАЛОГ-ОБРАЗУ-ФІКСТУРА-ГАРАЗД файл=створено');
  end else begin
    Check(ParamCount=0,'неприпустимі параметри');
    WriteLn('КАТАЛОГ-ОБРАЗУ-ГАРАЗД перевірок=',Checks,
      ' фізичний=так D1_не_D3=так opaque=так ',
      'канонічність=байт-в-байт пошкоджений=відхилено ',
      'системний_образ_SENS=ні');
  end;
end.
