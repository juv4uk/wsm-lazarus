{ G6.168 — шість справжніх фізичних D3 ELF через єдиний pinned WideIR.
  Це механічний test harness, а НЕ новий SENS evaluator чи семантичний закон. }
program test_irwide_d3_elf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.binaryexec,wsm.irwidefront,
     wsm.elfquotet5m,wsm.elfeqt5m,wsm.elfselectort5m,wsm.elfgeometry;
type
  TProfile=(prQuote,prEq,prSelector);
var
  Root,OutDir:String;
  Engine:TBinaryExecutor;
  Positives,Negatives:SizeInt;

{ Token — borrowed exact bit word; Result — owned canonical packed T5M.
  Жодна друкована D7 проєкція не використовується як opcode/джерело.
  1. Чому вхід містить фізичні D2 10/01?
  2. Чому провідні нулі W7 незмінні?
  3. Хто звільняє масив Words?
  4. Чому packed byte не ідентифікує закон без домену? }
function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for I:=0 to High(Tokens) do Words[I]:=Tokens[I];
  Result:=EncodeT5M(Words);
end;

procedure Check(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('Д3-ШИРОКИЙ-ЕЛФ-ВІДМОВА: '+Why);
end;

procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(OutDir+'/'+Name,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

{ Source — borrowed T5M D2 form, Expected — canonical pinned D3 result.
  Shared/Dedicated — independently allocated complete ELF64 buffers.
  Temporary executor owns no machine memory; machine stdout tested in shell.
  1. Чому exact ELF bytes мають збігатися з раніше доведеним backend?
  2. Чому Pinned D3 executor не є незалежним SENS REPL?
  3. Чому Kind є лише тестовим індексом, не dispatch у компіляторі?
  4. Чому ET_DYN/entry=120 самі не доводять мовну семантику? }
procedure Positive(const LabelText:String;Kind:TProfile;
                   const Tokens,ExpectedTokens:array of RawByteString);
var Source,Expected,Shared,Dedicated,Actual:RawByteString;Geo:TELFGeometry;
begin
  Source:=Pack(Tokens);Expected:=Pack(ExpectedTokens);
  Actual:=Engine.ExecutePhysicalT5M(Source);
  Check(Actual=Expected,LabelText+': pinned D3 runtime');
  Shared:=BuildVerifiedWideELF(Source,RawByteString(Root));
  case Kind of
    prQuote:Dedicated:=BuildQuoteT5MELF(Source,RawByteString(Root));
    prEq:Dedicated:=BuildEqT5MELF(Source,RawByteString(Root));
    prSelector:Dedicated:=BuildSelectorT5MELF(Source,RawByteString(Root));
  end;
  Check((Shared=Dedicated) and (Length(Shared)>120),
        LabelText+': різні фізичні машинні байти');
  VerifySENSELF64(Shared,Geo);
  Check((Geo.Kind=3) and (Geo.Entry=120) and
        (Geo.FileBytes=Length(Shared)),LabelText+': ELF64 PIE geometry');
  Save(LabelText+'.sens',Source);
  Save(LabelText+'.expected.sens',Expected);
  Save(LabelText+'.elf',Shared);
  Inc(Positives);
end;

procedure Reject(const LabelText:String;const Source:RawByteString);
var Image:RawByteString;Rejected:Boolean;
begin
  Rejected:=False;
  try
    Image:=BuildVerifiedWideELF(Source,RawByteString(Root));
    Check(False,LabelText+': неприпустима форма скомпільована '+IntToStr(Length(Image)));
  except
    on E:Exception do begin
      { Лише відома причина не-успіху. Check усередині try теж має
        Exception, але з catch тут недостатньо: нижче перевіримо Image. }
      Rejected:=True;
      if Pos('неприпустима форма скомпільована',E.Message)>0 then raise;
    end;
  end;
  Check(Rejected,LabelText+': не відхилено');
  Inc(Negatives);
end;

begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);OutDir:=ParamStr(2);
  Check(ForceDirectories(OutDir),'каталог свідків');
  Positives:=0;Negatives:=0;
  Engine:=TBinaryExecutor.Create(RawByteString(Root));
  try
    Positive('цитата-д7',prQuote,['10','001','0010110','01'],['0010110']);
    Positive('цитата-д1',prQuote,['10','001','1','01'],['1']);
    Positive('рівність-ні',prEq,['10','101','0','1','01'],['0']);
    Positive('рівність-так',prEq,['10','101','1','1','01'],['1']);
    Positive('перше-сполучення',prSelector,
      ['10','100','10','111','0','1','01','01'],['0']);
    Positive('решта-сполучення',prSelector,
      ['10','011','10','111','0','1','01','01'],['1']);
    Reject('непідтримана атом-голова',Pack(['10','010','1','01']));
    Reject('зайвий аргумент цитати',Pack(['10','001','0','1','01']));
    Reject('неповна рівність',Pack(['10','101','0','01']));
    Reject('перший без пари',Pack(['10','100','1','01']));
    Reject('другий без другої частини пари',
      Pack(['10','011','10','111','0','01','01']));
    Reject('два корені',Pack(['10','001','0','01','1']));
    Reject('невідома D7 голова',Pack(['10','0010110','0','01']));
    Reject('незакрита форма',Pack(['10','101','0','1']));
    Reject('зіпсований T5M',#$FF);
    Reject('не двійкова .lisp проєкція',RawByteString('(цитата 0)'));
    Check((Positives=6) and (Negatives=10),'покриття');
    WriteLn('G6.168-WIDE-D3-ELF-OK positives=6 negatives=10 oracle=INTERNAL-D3 energy=NOT-MEASURED');
  finally Engine.Free end;
end.
