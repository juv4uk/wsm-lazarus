{ G6.90 — ФІЗИЧНІ host-фрейми для одного native batch ELF.
  Це НЕ SENS .sens документ: у .frame конкатеновано 256 окремих
  canonical packed T5M/W1 атомів; .order — лише ASCII host-метадані
  порядку, НЕ доменна проєкція чи закон.
  Значення чотирьох відповідей визначає ІНШИЙ canonical D3 witness
  і pinned незалежний SENS REPL, а не цей генератор. }
program test_elfd1paket128;
{$mode objfpc}{$H+}
uses SysUtils,Classes,wsm.t5m;
var Root:String;
    NoByte,YesByte,A,B,OrderA,OrderB,V,D7:RawByteString;
    W:TExactWords;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Root+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

function Atom(const Bits:RawByteString):RawByteString;
var Words:TExactWords;
begin
  SetLength(Words,1);Words[0]:=Bits;
  Result:=EncodeT5M(Words);
  if Length(Result)<>1 then
    raise ET5MError.Create('W1 має бути один packed байт');
end;

procedure Batch(const FileName:String;Shift,Stride:SizeInt;
  out Frame,Order:RawByteString);
var I,N:SizeInt;L,R:RawByteString;
begin
  Frame:='';Order:='';
  for I:=0 to 127 do begin
    N:=(I*Stride+Shift) mod 4;
    if (N and 2)=0 then L:=NoByte else L:=YesByte;
    if (N and 1)=0 then R:=NoByte else R:=YesByte;
    Frame:=Frame+L+R;
    Order:=Order+AnsiChar(Ord('0')+N);
  end;
  if (Length(Frame)<>256) or (Length(Order)<>128) then
    raise ET5MError.Create('неповний пакет свідків');
  Save(FileName+'.frame',Frame);
  Save(FileName+'.order',Order);
end;

begin
  if ParamCount<>1 then Halt(64);
  Root:=ParamStr(1);
  if not ForceDirectories(Root) then Halt(2);
  NoByte:=Atom('0');
  YesByte:=Atom('1');
  if NoByte=YesByte then Halt(2);
  Batch('batch-a',3,37,A,OrderA);
  Batch('batch-b',2,13,B,OrderB);
  Save('empty.frame','');
  Save('one-byte.frame',Copy(A,1,1));
  Save('odd-255.frame',Copy(A,1,255));
  Save('extra-257.frame',A+NoByte);
  Save('extra-258.frame',A+NoByte+YesByte);
  Save('ascii.frame',StringOfChar('0',256));
  V:=A; V[1]:=#$F3;Save('invalid-first.frame',V);
  V:=A; V[128]:=#$00;Save('invalid-middle.frame',V);
  V:=A; V[256]:=#$FF;Save('invalid-last.frame',V);
  SetLength(W,1);W[0]:='0010110';
  V:=A; D7:=EncodeT5M(W); V[20]:=D7[1];Save('d7-one.frame',V);
  V:=B;V[20]:=#$01;Save('invalid-variant.frame',V);
  Save('noncanonical-text.frame','(тотожне? так ні)');
  WriteLn('D1-BATCH128-FRAMES-OK sets=2 each=128 negatives=12');
end.
