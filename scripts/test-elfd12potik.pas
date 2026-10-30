{ G6.88 — canonical pinned W12 fixtures для runtime stdin.
  Host .frame = конкатенація ДВОХ ОКРЕМИХ packed .sens атомів:
  це не один канонічний багатослівний .sens файл.
  Чинний wsm.numericplane формує обидва фізичні атоми, а
  wsm.numericadd формує очікуване число для byte-exact порівняння. }
program test_elfd12potik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.numericadd,wsm.t5m,
     wsm.elfd12potik,wsm.x64frameio,wsm.elfgeometry;

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

procedure VerifyFramedContract;
var Base,Framed,Again:RawByteString; G:TELFGeometry; Rejected:Boolean;
begin
  Base:=BuildD12StreamAddELF;
  Framed:=BuildD12StreamAddFramedELF;
  Again:=BuildD12StreamAddFramedELF;
  if (Length(Framed)<=Length(Base)) or (Framed<>Again) then
    raise Exception.Create('не збережено одноразовий детермінований host prefix');
  if (Copy(Base,125,2)<>#$31#$C0) or
     (Copy(Framed,125,3)<>#$45#$31#$D2) then
    raise Exception.Create('донор або EOF prefix мають помилкову початкову структуру');
  VerifySENSELF64(Base,G);
  if (G.Kind<>3) or (G.Entry<>120) or (G.FileBytes<>Length(Base)) then
    raise Exception.Create('незагорнутий донор має пошкоджену PIE геометрію');
  VerifySENSELF64(Framed,G);
  if (G.Kind<>3) or (G.Entry<>120) or (G.FileBytes<>Length(Framed)) then
    raise Exception.Create('загорнутий CLI має пошкоджену PIE геометрію');
  Rejected:=False;
  try WrapExactSixByteFrame(Framed)
  except on E:EFrameIO do Rejected:=True end;
  if not Rejected then raise Exception.Create('помилково дозволено подвійний host prefix');
  EmitUTF8('Д12-ПОТІК-КАДР-ГАРАЗД donor=unchanged prefix=once double=reject geometry=PIE');
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

  { G6.231: перевірка розділених API та справжня негативна відмова.
    Базовий донор залишається НЕЗАГОРНУТИМ для інших AOT emitter-ів;
    CLI framed шлях має один x64 EOF prefix, другий — заборонений.
    1) Чому потрібні обидва типи повернутого ELF?
    2) Чому повторний wrapper мав би бути відхилений?
    3) Хто володіє трьома managed RawByteString?
    4) Чому перевіряється точна PIE-геометрія? }
  VerifyFramedContract;

  { Діагностика точною UTF-8, не локальним кодовим перетворенням WriteLn. }
  EmitUTF8('Д12-ПОТІК-СВІДКИ-ГОТОВО позитивів=13 переповнень=3 фізичних-негативів=12');
end.