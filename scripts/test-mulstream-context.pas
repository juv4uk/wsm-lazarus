{ G6.205 — потік D5:10110 використовує той самий одноразовий WideIR.
  Це тест host-механізму. Очікувані значення фізично кодує чинна
  числова площина pinned SENS; тут не виникає нового закону.
  1) Чому один D2 якір не містить runtime stdin аргументів?
  2) Хто володіє TResult ELF і TFileStream?
  3) Навіщо порівнювати proof ELF зі старим BuildIRWideMulELF?
  4) Чому 2047*2 повинно дати відмову без часткового stdout?
  5) Чому D24 не можна неявно звужувати до D12? }
program test_mulstream_context;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.numericplane,
     wsm.irwidemul, wsm.verifiedwidecontext, wsm.verifiedmul,
     wsm.elfd12mulpotik, wsm.elfgeometry;

var
  Root, Dir:String;
  Count:Integer=0;
  FirstELF,Anchor,ProofOld,ProofNew,StreamELF:RawByteString;
  LeftNum,RightNum:TExplicitNumeric;
  C:TVerifiedWideContext;
  G:TELFGeometry;
  Bad:Boolean;

procedure Demand(OK:Boolean;const Text:String);
begin
  Inc(Count);
  if not OK then raise Exception.Create('Д5-КОНТЕКСТ-ПОТІК-ЗБІЙ: '+Text);
end;

{ Файли — приватні фізичні свідки: source .sens та ELF bytes.
  Result має точні packed T5M байти, TFileStream звільняє дескриптор.
  1) Чи зберігається остання неповна п’ятірка T5M?
  2) Чому не друкуємо фізичні bytes через WriteLn?
  3) Хто контролює життєвий цикл тимчасової теки? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Dir+'/'+Name,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end
end;

function Pack(const Elements:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Elements));
  for I:=0 to High(Elements) do W[I]:=Elements[I];
  Result:=EncodeT5M(W)
end;

function Source(const L,R:RawByteString):RawByteString;
var A,B:TExplicitNumeric;
begin
  A:=ReadNumericPhysical(EncodeNumericDecimal(L,12),12);
  B:=ReadNumericPhysical(EncodeNumericDecimal(R,12),12);
  Result:=Pack(['10','10110',A.ExactBits,B.ExactBits,'01'])
end;

{ Перевірити ТУ САМУ canonical форму обома реально наявними
  компіляторними допусками; байти ELF64 повністю повинні збігтись.
  ProofOld/ProofNew не використовуються як незалежний SENS oracle.
  1) Чи може різна форма з тим самим D5 законом змінити runtime ELF?
  2) Де ширина перевіряється до numeric engine?
  3) Як перевіряємо, що друге декодування не потрібне?
  4) Чому ELF PIE не тотожний файлу .sens? }
procedure Positive(const L,R:RawByteString);
begin
  Anchor:=Source(L,R);
  ProofOld:=BuildIRWideMulELF(Anchor,Root);
  C:=TVerifiedWideContext.Create(Anchor,Root);
  try ProofNew:=C.Lower(@LowerVerifiedMul)
  finally C.Free end;
  Demand(ProofOld=ProofNew,'старий та одноразовий D5 proof ELF не тотожні');
  StreamELF:=BuildVerifiedD12MulStreamELF(Anchor,Root);
  VerifySENSELF64(StreamELF,G);
  Demand((G.Kind=3) and (G.Entry=120) and
         (G.FileBytes=Length(StreamELF)) and (G.MachineBytes>0),
         'потоковий ELF64 PIE не підтверджено');
  if FirstELF='' then FirstELF:=StreamELF
  else Demand(FirstELF=StreamELF,'різні D12 якорі змінили динамічний ELF');
end;

{ Негатив: завжди виняток до видачі власних ELF bytes, навіть якщо
  T5M геометрично читається, але голова/арність чужа. }
procedure Reject(const Physical,Authority:RawByteString;const Title:String);
var Rejected:Boolean;Generated:RawByteString;
begin
  Rejected:=False;Generated:='';
  try Generated:=BuildVerifiedD12MulStreamELF(Physical,Authority)
  except on E:Exception do Rejected:=True end;
  Demand(Rejected and (Generated=''),'негатив прийнято: '+Title)
end;

procedure RuntimeFrame(const LabelText,L,R,Expected:RawByteString);
var Frame:RawByteString;
begin
  Frame:=EncodeNumericDecimal(L,12)+EncodeNumericDecimal(R,12);
  Demand(Length(Frame)=6,'невірний host кадр двох фізичних D12');
  Save(LabelText+'.frame',Frame);
  if Expected<>'' then Save(LabelText+'.expected.sens',
                           EncodeNumericDecimal(Expected,12));
end;

begin
  if ParamCount<>2 then Halt(64);
  Root:=ParamStr(1);Dir:=ParamStr(2);
  Demand(DirectoryExists(Dir) and
         FileExists(Root+'/lib/domains/d5.lisp'),
         'немає pinned authority або приватної теки');
  Positive('7','3');
  Positive('3','7');
  Positive('-42','42');
  Positive('2047','-2048');
  Save('потік.elf',FirstELF);
  Save('якір.sens',Anchor);
  RuntimeFrame('positive','7','3','21');
  RuntimeFrame('negative','-3','7','-21');
  RuntimeFrame('boundary','2047','1','2047');
  RuntimeFrame('overflow','2047','2','');
  Save('bad.frame',#$FF);
  Reject(Anchor+#0,Root,'неканонічний T5M');
  Reject(Pack(['10','01010','000000000111','000000000011','01']),
         Root,'чужа D5 голова');
  Reject(Pack(['10','10110','000000000111','01']),Root,'один аргумент');
  Reject(Pack(['10','10110','000000000111',
               '000000000011','000000000001','01']),Root,'три аргументи');
  Reject(Anchor,Root+'/немає','недоступний pinned SENS');
  LeftNum:=ReadNumericPhysical(EncodeNumericDecimal('7',12),12);
  RightNum:=ReadNumericPhysical(EncodeNumericDecimal('3',12),12);
  Reject(Pack(['10','10110','1',RightNum.ExactBits,'01']),
         Root,'D1 не є D12');
  Reject(Pack(['10','10110',LeftNum.ExactBits,
               RightNum.ExactBits]),Root,'обірваний D2');
  WriteLn('Д5-КОНТЕКСТ-ПОТІК-PASS checks=',Count,
          ' anchor-proofs=4 machine=ELF64 negatives=7');
end.
