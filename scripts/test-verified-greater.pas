{ G6.192 — реальні 16 фізичних pinned D5:11011, два compiler routes
  в одному FPC процесі; 16 машинних ELF реально запускає shell.
  Host-expected тут лише fixture, незалежний oracle окремо.
  Немає жодного нового SENS закону чи emitter. }
program test_verified_greater;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,
     wsm.irwidegreater,wsm.verifiedwidecontext,wsm.elfgeometry;
type ETestGreater=class(Exception);
var Root,OutputDir:String;Records:TStringList;
    Total,Rejected:SizeInt;
procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise ETestGreater.Create(Why) end;

{ Path: host filesystem; Physical: owned canonical packed T5M bytes.
  Caller owns FPC reference; FileStream always released.
  1) Чому .sens містить фізичні байти, а не D7 текст?
  2) Чому тут не зберігається глобальний compiler context?
  3) Хто звільняє файл після exception? }
procedure Save(const Name:String;const Physical:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(OutputDir+'/'+Name,fmCreate);
  try if Length(Physical)>0 then
    Stream.WriteBuffer(Physical[1],Length(Physical))
  finally Stream.Free end;
end;

{ Bits — borrowed exact bit strings з ратифікованою pinned width.
  Result — owned T5M program, не людиночитаний Lisp і не AST.
  1) Чому D2 (10,01) є окремими словами?
  2) Хто відповідає за canonical padding?
  3) Чому W12 не визначає автоматично D12 закон? }
function Pack(const Values:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Values));
  for I:=0 to High(Values) do W[I]:=Values[I];
  Result:=EncodeT5M(W);
end;

function Bits12(const Decimal:String):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12),
    'пошкоджено pinned D12 тестовий атом');
  Result:=N.ExactBits;
end;

{ Physical — canonical borrowed input, Context живе одну компіляцію.
  Old/New — own ELF64 ET_DYN bytes, порівнюються побайтово.
  No execution until shell launches real machine ELF.
  1) Які перевірки контекст робить перед backend?
  2) Яку D5 перевірку повторює лише backend?
  3) Чому відсутній другий x86 emitter?
  4) Хто знищує managed context?
  5) Чому byte parity не є незалежним SENS oracle? }
function CompilePair(const Physical:RawByteString):RawByteString;
var Context:TVerifiedWideContext; Old,NewELF:RawByteString;G:TELFGeometry;
begin
  Old:=BuildPhysicalGreaterELF(Physical,RawByteString(Root));
  Context:=TVerifiedWideContext.Create(Physical,RawByteString(Root));
  try NewELF:=BuildPhysicalGreaterFromContext(Context)
  finally Context.Free end;
  Need((Length(NewELF)>0) and (Old=NewELF),
       'змінено точні машинні байти після verified context');
  VerifySENSELF64(NewELF,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(NewELF)) and (G.MachineBytes>0),
       'неповноцінний ELF64 x86-64');
  Result:=NewELF;
end;

{ Expected — тільки тестовий fixture/Host bool, а НЕ compiler SENS law.
  Незалежний pinned SENS REPL викликається shell у PR.
  1) Чому ці числа можна змінити без перекомпіляції Pascal?
  2) Чому fixture не дозволяє семантичний dispatch по імені?
  3) Де фактичний D1 обирає CMP/SETG? }
procedure Valid(const Name,Left,Right:String;Expected:Boolean);
var Physical,Image,Truth:RawByteString;
begin
  Physical:=Pack(['10','11011',Bits12(Left),Bits12(Right),'01']);
  Image:=CompilePair(Physical);
  Save(Name+'.sens',Physical);
  Save(Name+'.elf',Image);
  if Expected then Truth:='1' else Truth:='0';
  Save(Name+'.expected.sens',Pack([Truth]));
  Save(Name+'.lisp',RawByteString('(більше? '+Left+' '+Right+')'+#10));
  Records.Add(Name+#9+Left+#9+Right+#9+String(Truth));
  Inc(Total);
end;

{ Відмови мають бути симетричні у старого й нового admission.
  Жоден malformed source не отримує ні ELF bytes, ні stale state.
  1) Чому навіть valid інша D5 голова є негативом?
  2) Чому W24 не можна мовчки звузити до D12?
  3) Хто руйнує частково створений контекст за помилки? }
procedure Reject(const Physical:RawByteString);
var Context:TVerifiedWideContext;GotError:Boolean;ResultELF:RawByteString;
begin
  GotError:=False;
  try
    ResultELF:=BuildPhysicalGreaterELF(Physical,RawByteString(Root))
  except on E:Exception do GotError:=True end;
  Need(GotError,'старий backend помилково допустив негатив');
  GotError:=False;
  try
    Context:=TVerifiedWideContext.Create(Physical,RawByteString(Root));
    try ResultELF:=BuildPhysicalGreaterFromContext(Context)
    finally Context.Free end
  except on E:Exception do GotError:=True end;
  Need(GotError,'новий context помилково допустив негатив');
  Inc(Rejected);
end;

procedure Run;
var Z,B24:RawByteString;Num:TExplicitNumeric;
    Image,Recovered:RawByteString;
begin
  Need(ParamCount=1,'потрібен один каталог фізичних тестів');
  OutputDir:=ExpandFileName(ParamStr(1));
  Need(ForceDirectories(OutputDir),'каталог свідків недоступний');
  Root:=ExpandFileName('external/sens');
  Records:=TStringList.Create;
  try
    Total:=0;Rejected:=0;
    Valid('01','0','0',False);
    Valid('02','1','0',True);
    Valid('03','0','1',False);
    Valid('04','-1','0',False);
    Valid('05','0','-1',True);
    Valid('06','-1','-2',True);
    Valid('07','-2','-1',False);
    Valid('08','2047','-2048',True);
    Valid('09','-2048','2047',False);
    Valid('10','2047','2047',False);
    Valid('11','-2048','-2048',False);
    Valid('12','7','42',False);
    Valid('13','42','7',True);
    Valid('14','-7','7',False);
    Valid('15','1234','1233',True);
    Valid('16','1233','1234',False);
    Need(Total=16,'не вистачає 16 унікальних фізичних програм');
    Z:=Bits12('0');
    Num:=ReadNumericPhysical(EncodeNumericDecimal('0',24),24);
    B24:=Num.ExactBits;
    Reject(Pack(['10','11010',Z,Z,'01']));
    Reject(Pack(['10','11011',Z,'01']));
    Reject(Pack(['10','11011',Z,Z,Z,'01']));
    Reject(Pack(['10','11011',Z,B24,'01']));
    Reject(Pack(['10','11011','1',Z,'01']));
    Reject(Pack(['10','11011',Z,Z]));
    Reject(Pack(['10','11011',Z,Z,'01','1']));
    Reject(#$FF);
    Reject('');
    Need(Rejected=9,'не вистачає дев''яти фізичних негативів');
    Image:=Pack(['10','11011',Bits12('42'),Bits12('7'),'01']);
    Recovered:=CompilePair(Image);
    Need(Recovered=CompilePair(Image),
      'після негативу відтворений ELF не збігається');
    Records.SaveToFile(OutputDir+'/cases.tsv');
    WriteLn('VG-PASS physical=',Total,' negatives=',Rejected,
      ' recovery=1 old-new-elf=identical');
  finally Records.Free end;
end;

begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'VG-FAIL ',E.Message);
    ExitCode:=2;
  end end;
end.
