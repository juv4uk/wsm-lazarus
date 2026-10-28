{ G7.9 — великі справжні exact-key фрейми та канонічний WSMIMG1.
  Всі ключі — host механіка TDomainKey D1..D10, не SENS numeric D12+. }
program test_image_growth;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.domain, wsm.envframe, wsm.image;

type TKeys=array of TDomainKey;
var
  Frame, Loaded, Sparse:IEnvFrame;
  Ascending, Descending, Mutant:TKeys;
  Positive, Reverse, Invalid:TMemoryStream;
  D,B,I,N,Checks:SizeInt;
  K:TDomainKey;
  Handle:QWord;

procedure Check(Ok:Boolean;const Why:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create('ОБРАЗ-ЗРОСТАННЯ-ПОМИЛКА: '+Why);
end;

function EncodedValue(const Key:TDomainKey):QWord;
begin
  Result:=(QWord(Key.Width) shl 32) or QWord(Key.Bits);
end;

function BytesOf(S:TMemoryStream):RawByteString;
begin
  SetLength(Result,SizeInt(S.Size));
  if S.Size>0 then Move(S.Memory^,Result[1],SizeInt(S.Size));
end;

procedure Reject(const Keys:array of TDomainKey;const Why:String;
  F:IEnvFrame);
var Rejected:Boolean;
begin
  Invalid.Clear;
  Rejected:=False;
  try
    SaveFrameImage(F,Keys,Invalid);
  except on E:EImageError do Rejected:=True end;
  Check(Rejected,Why+' не відхилено');
  Check(Invalid.Size=0,Why+' оприлюднив частковий WSMIMG1');
end;

begin
  Checks:=0;
  N:=0;
  for D:=1 to 10 do Inc(N,1 shl D);
  Check(N=2046,'помилкова кількість точних host ключів');
  Frame:=NewEnvFrame(nil);
  SetLength(Ascending,N);
  I:=0;
  for D:=1 to 10 do
    for B:=0 to (1 shl D)-1 do begin
      K.Width:=D; K.Bits:=B;
      Check(SameKey(ExactKey(KeyBits(K)),K),
        'координата не проходить чинну перевірку ширини/бітів');
      Ascending[I]:=K;
      Frame.InstallLocal(K,EncodedValue(K));
      Inc(I);
    end;
  SetLength(Descending,N);
  for I:=0 to N-1 do Descending[I]:=Ascending[N-I-1];
  Positive:=TMemoryStream.Create;
  Reverse:=TMemoryStream.Create;
  Invalid:=TMemoryStream.Create;
  try
    SaveFrameImage(Frame,Ascending,Positive);
    SaveFrameImage(Frame,Descending,Reverse);
    Check((Positive.Size=12+N*11+4) and
      (Positive.Size=Reverse.Size),'невірна довжина приватного WSMIMG1');
    Check(BytesOf(Positive)=BytesOf(Reverse),
      'сортування змінило канонічні фізичні байти');
    Positive.Position:=0;
    Loaded:=LoadFrameImage(Positive);
    for I:=0 to N-1 do begin
      K:=Ascending[I];
      Check(Loaded.Resolve(K)=EncodedValue(K),
        'втрата точного ключа чи opaque значення');
    end;

    { Дубль на ОСТАННЬОМУ кроці навіть після багатьох успішних ключів. }
    SetLength(Mutant,N);
    for I:=0 to N-1 do Mutant[I]:=Descending[I];
    Mutant[N-1]:=Mutant[0];
    Reject(Mutant,'пізній duplicate exact-key',Frame);

    for I:=0 to N-1 do Mutant[I]:=Descending[I];
    Mutant[N-1].Width:=0;
    Reject(Mutant,'пізній нульовий домен',Frame);

    for I:=0 to N-1 do Mutant[I]:=Descending[I];
    Mutant[N-1].Bits:=1024;
    Mutant[N-1].Width:=10;
    Reject(Mutant,'пізня координата поза D10',Frame);

    SetLength(Mutant,MaxImageBindings+1);
    for I:=0 to High(Mutant) do Mutant[I]:=Ascending[0];
    Reject(Mutant,'4097 ключів понад host-ліміт',Frame);

    Sparse:=NewEnvFrame(nil);
    Sparse.InstallLocal(Ascending[0],0);
    Reject(Ascending,'відсутнє локальне зв’язування',Sparse);
    Check(Loaded.Resolve(Ascending[0])=EncodedValue(Ascending[0]),
      'помилка не змінила вже відновлений образ');
    Check(Loaded.Resolve(Ascending[N-1])=EncodedValue(Ascending[N-1]),
      'пізня помилка не змінила останню координату');
    WriteLn('ОБРАЗ-ЗРОСТАННЯ-ГАРАЗД ключів=',N,
      ' канонічні-байти=',Positive.Size,
      ' порядок=байт-в-байт відмови=5 перевірок=',Checks,
      ' закони=pinned-only');
  finally
    Invalid.Free; Reverse.Free; Positive.Free;
  end;
end.
