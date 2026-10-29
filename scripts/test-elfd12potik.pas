{ G6.88 — canonical pinned W12 fixtures для runtime stdin.
  Host .frame = конкатенація ДВОХ ОКРЕМИХ packed .sens атомів:
  це не один канонічний багатослівний .sens файл.
  Чинний wsm.numericplane формує обидва фізичні атоми, а
  wsm.numericadd формує очікуване число для byte-exact порівняння. }
program test_elfd12potik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.numericadd,wsm.t5m;

procedure EmitUTF8(const Message:UnicodeString);
var Bytes:RawByteString;H:THandleStream;
begin
  Bytes:=RawByteString(UTF8Encode(Message))+#10;
  H:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try H.WriteBuffer(Bytes[1],Length(Bytes))
  finally H.Free end;
end;

procedure Save(const Path:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Data<>'' then Stream.WriteBuffer(Data[1],Length(Data));
  finally Stream.Free end;
end;

{ Arg L,R: borrowed human signed numbers — лише тестова проєкція.
  Encoded values: owned raw T5M with exact width 12.
  Output expected.sens is checked using upstream-admitted Pascal
  numeric mechanism, and then INDEPENDENT pinned SENS REPL in CI. }
procedure Pair(const Dir,Name,L,R:RawByteString;ShouldFit:Boolean);
var A,B,E:RawByteString;X:TExplicitNumeric;Accepted:Boolean;
begin
  A:=EncodeNumericDecimal(L,12);
  B:=EncodeNumericDecimal(R,12);
  if (Length(A)<>3) or (Length(B)<>3) then
    raise Exception.Create('D12 має рівно 3 T5M байти');
  Save(Dir+'/'+String(Name)+'.frame',A+B);
  Save(Dir+'/'+String(Name)+'-a.sens',A);
  Save(Dir+'/'+String(Name)+'-b.sens',B);
  E:=AddNumericPhysical(A,B,12);
  Accepted:=False;
  try X:=ReadNumericPhysical(E,12);Accepted:=X.DomainWidth=12;
  except on E2:ENumericPlaneError do Accepted:=False end;
  if Accepted<>ShouldFit then
    raise Exception.Create('очікуваний D12 результат має невірну ширину');
  if Accepted then begin
    Save(Dir+'/'+String(Name)+'-expected.sens',E);
    WriteLn(Name,#9,L,#9,R);
  end;
end;

var
  Dir:String;Frame,A,B:RawByteString;
  One:TExactWords;
begin
  SetTextCodePage(Output,CP_UTF8);
  if ParamCount<>1 then Halt(2);
  Dir:=ParamStr(1); ForceDirectories(Dir);

  Pair(Dir,'00','0','0',True);
  Pair(Dir,'01','1','1',True);
  Pair(Dir,'02','-1','1',True);
  Pair(Dir,'03','-2048','0',True);
  Pair(Dir,'04','2047','0',True);
  Pair(Dir,'05','2046','1',True);
  Pair(Dir,'06','-2047','-1',True);
  Pair(Dir,'07','111','-22',True);
  Pair(Dir,'08','1024','-1024',True);
  Pair(Dir,'09','-130','500',True);
  Pair(Dir,'10','-999','1000',True);
  Pair(Dir,'11','500','500',True);
  Pair(Dir,'12','2020','-300',True);

  Pair(Dir,'overflow-up','2047','1',False);
  Pair(Dir,'overflow-down','-2048','-1',False);
  Pair(Dir,'overflow-wide','2047','2047',False);

  A:=EncodeNumericDecimal('1',12);
  B:=EncodeNumericDecimal('1',12);
  Frame:=A+B;
  Save(Dir+'/empty.frame','');
  Save(Dir+'/short1.frame',Copy(Frame,1,1));
  Save(Dir+'/short5.frame',Copy(Frame,1,5));
  Save(Dir+'/extra.frame',Frame+#0);
  Save(Dir+'/invalid243.frame',#$FF+Copy(Frame,2,5));
  Save(Dir+'/badfirst.frame',#$02+Copy(Frame,2,5));
  Save(Dir+'/badsecond.frame',Copy(Frame,1,3)+#$02+Copy(Frame,5,2));
  Save(Dir+'/badthird.frame',Copy(Frame,1,2)+#0+Copy(Frame,4,3));
  Save(Dir+'/badlast.frame',Copy(Frame,1,5)+#0);
  Save(Dir+'/newline.frame',Frame+#10);
  Save(Dir+'/projection.frame','(додати 1 1)'+#10);
  SetLength(One,1);
  One[0]:='1';Save(Dir+'/d1.frame',EncodeT5M(One)+EncodeT5M(One));

  { Діагностика точною UTF-8, не локальним кодовим перетворенням WriteLn. }
  EmitUTF8('Д12-ПОТІК-СВІДКИ-ГОТОВО позитивів=13 переповнень=3 фізичних-негативів=12');
end.