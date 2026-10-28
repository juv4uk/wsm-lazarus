program test_oglyadmodel;
{$mode objfpc}{$H+}
{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.oglyadmodel;
var
  Model: TOghliadModel;
  W: TExactWords;
  R: TOghliadWord;
  Physical,Path: RawByteString;
  F:TFileStream;
  I:SizeInt;
  Rejected:Boolean;

procedure Check(const Good:Boolean;const Why:String);
begin
  if not Good then begin
    WriteLn(StdErr,'ОГЛЯД-ПОМИЛКА: ',Why);
    Halt(1);
  end;
end;

procedure Reject(const Bytes:RawByteString;const Why:String);
var BeforeCount,BeforeBytes:SizeInt; Before:RawByteString;
begin
  BeforeCount:=Model.WordCount;
  BeforeBytes:=Model.ByteCount;
  if BeforeCount>0 then Before:=Model.WordAt(0).Bits else Before:='';
  Rejected:=False;
  try Model.LoadBytes(Bytes);
  except on E:Exception do Rejected:=True; end;
  Check(Rejected,Why+' — джерело прийнято');
  Check((Model.WordCount=BeforeCount) and
    (Model.ByteCount=BeforeBytes),Why+' — частковий документ');
  if BeforeCount>0 then
    Check(Model.WordAt(0).Bits=Before,Why+' — старі дані змінено');
end;

begin
  Model:=TOghliadModel.Create;
  try
    { Спільний фізичний байт: 10 і 01 є різними двобітовими словами. }
    SetLength(W,2);
    W[0]:='10'; W[1]:='01';
    Physical:=EncodeT5M(W);
    Check(Physical=#100,'незалежний T5M gold 100');
    Model.LoadBytes(Physical);
    Check((Model.WordCount=2) and (Model.RootCount=1) and
      (Model.ByteCount=1),'D2 список або фізична довжина');
    R:=Model.WordAt(0);
    Check((R.Index=1) and (R.Width=2) and (R.Bits='10') and
      (R.TritStart=0) and (R.TritEnd=2) and
      (R.ByteStart=0) and (R.ByteEnd=1),'позиція першого D2');
    R:=Model.WordAt(1);
    Check((R.Index=2) and (R.Width=2) and (R.Bits='01') and
      (R.TritStart=3) and (R.TritEnd=5) and
      (R.ByteStart=0) and (R.ByteEnd=1),'спільний байт D2');
    Check((Model.HexAt(0)='64') and (Model.HexAt(1)='64'),
      'фізичні hex bytes');

    { D1:0 і D3:000 не мають спільної тотожності. }
    W[0]:='0'; W[1]:='000';
    Model.LoadBytes(EncodeT5M(W));
    Check((Model.RootCount=2) and (Model.WordAt(0).Width=1) and
      (Model.WordAt(1).Width=3),'домен D1/D3 переплутано');
    Check((Model.WordAt(0).Bits='0') and
      (Model.WordAt(1).Bits='000') and
      (Model.WordAt(0).Kind<>Model.WordAt(1).Kind),
      'порожня структура сплутана з бітом нуль');

    Reject(#243,'заборонений фізичний байт');
    W[0]:='01'; SetLength(W,1);
    Reject(EncodeT5M(W),'D2 закривальна дужка поза списком');
    W[0]:='10';
    Reject(EncodeT5M(W),'незакрита D2 структура');
    Reject('','порожній файл');
    Reject(StringOfChar('0',MaxOghliadBytes+1),'ліміт фізичних байтів');

    SetLength(W,MaxOghliadWords+1);
    for I:=0 to High(W) do W[I]:='0';
    Reject(EncodeT5M(W),'ліміт видимих слів');

    { Справжнє читання з файлової системи, з відмовою на bad input. }
    Path:=RawByteString(GetTempFileName(GetTempDir(False),'sen'));
    try
      W[0]:='10'; W[1]:='01'; SetLength(W,2);
      Physical:=EncodeT5M(W);
      F:=TFileStream.Create(String(Path),fmCreate);
      try F.WriteBuffer(Physical[1],Length(Physical)); finally F.Free; end;
      Model.LoadFile(String(Path));
      Check((Model.WordCount=2) and (Model.HexAt(0)='64'),
        'фізичний файл не прочитано');
      Rejected:=False;
      try Model.LoadFile(String(Path)+'.відсутній');
      except on E:Exception do Rejected:=True; end;
      Check(Rejected and (Model.WordCount=2),
        'відсутній файл знищив попередній допущений документ');
    finally
      DeleteFile(String(Path));
    end;
    Rejected:=False;
    try R:=Model.WordAt(-1);
    except on E:EOghliadError do Rejected:=True; end;
    Check(Rejected,'від’ємний індекс прийнято');
    Rejected:=False;
    try R:=Model.WordAt(Model.WordCount);
    except on E:EOghliadError do Rejected:=True; end;
    Check(Rejected,'завеликий індекс прийнято');
    WriteLn('LAZARUS-MODEL-OK фізичне-T5M=1 D2=1 точні-позиції=1 ',
      'D1-не-D3=1 межі=відмова атомарність=1');
  finally Model.Free; end;
end.
