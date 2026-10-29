{ G6.144: two valid D5 source anchors, 16 exact negative cases.
  Reused static pinned WideIR proves call heads; machine source does not
  inherit example constant arguments. Managed buffers finalized by FPC.
  1) Why two anchors generate byte-identical runtime machine?
  2) Why rejected source is not D1 false?
  3) Why use exact width and exact bits?
  4) Why negative arbitrary D7 head and two roots? }
program test_irwidedynadd;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.irwidedynadd,wsm.elfd12potik,wsm.x64frameio,wsm.elfgeometry;
var Folder:String;A,B,W24,Src,Image,Other,Candidate:RawByteString;
    G:TELFGeometry;Neg:SizeInt;
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;
procedure Require(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('D5-DYN-FAIL: '+Why) end;
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;
procedure Reject(const Why:String;const Physical:RawByteString);
var Failed:Boolean;OutBytes:RawByteString;
begin
  Failed:=False;OutBytes:='';
  try OutBytes:=BuildVerifiedDynamicD12AddELF(Physical,'external/sens')
  except on E:Exception do Failed:=True end;
  Require(Failed and (OutBytes=''),'не відхилено '+Why);
  Inc(Neg);
end;
begin
  Require(ParamCount=1,'потрібна тека');
  Folder:=ParamStr(1);Require(DirectoryExists(Folder),'немає теки');
  A:=ReadNumericPhysical(EncodeNumericDecimal('0',12),12).ExactBits;
  B:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits;
  W24:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24).ExactBits;
  Src:=Pack(['10','01010',A,A,'01']);Save('first.sens',Src);
  Image:=BuildVerifiedDynamicD12AddELF(Src,'external/sens');
  VerifySENSELF64(Image,G);
  Require((G.Kind=3) and (G.Entry=120) and (Length(Image)>120),
          'не ELF64 PIE');
  Other:=BuildVerifiedDynamicD12AddELF(Src,'external/sens');
  Require(Image=Other,'недетермінований код');
  Candidate:=WrapExactSixByteFrame(BuildD12StreamAddELF);
  Require(Image=Candidate,'донор змінено');
  Src:=Pack(['10','01010',A,B,'01']);Save('second.sens',Src);
  Other:=BuildVerifiedDynamicD12AddELF(Src,'external/sens');
  Require(Image=Other,'джерельні константи потрапили в runtime');
  Neg:=0;
  Reject('empty','');
  Reject('corrupt',#$FF);
  Reject('wrong-D5',Pack(['10','01011',A,B,'01']));
  Reject('wrong-D6',Pack(['10','010010',A,B,'01']));
  Reject('D7',Pack(['10','0010110',A,B,'01']));
  Reject('D1-arg',Pack(['10','01010','1',B,'01']));
  Reject('D24-arg',Pack(['10','01010',W24,B,'01']));
  Reject('missing',Pack(['10','01010',A,'01']));
  Reject('extra',Pack(['10','01010',A,B,B,'01']));
  Reject('nested',Pack(['10','01010','10',A,'01',B,'01']));
  Reject('two-roots',Pack(['10','01010',A,B,'01','0']));
  Reject('dotted',Pack(['10','01010','11',A,B,'01']));
  Reject('unclosed',Pack(['10','01010',A,B]));
  Reject('root-atom',Pack([A]));
  Reject('extra-close',Pack(['10','01010',A,B,'01','01']));
  Reject('oversize',StringOfChar(#$FF,65537));
  Require(Neg=16,'неповні 16 відмов');
  WriteLn('D5-DYN-ANCHOR-OK valid=2 identical=3 negatives=',Neg);
end.
