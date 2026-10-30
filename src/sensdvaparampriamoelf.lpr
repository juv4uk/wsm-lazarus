{ G6.182 — один FPC-прохід від 3 canonical T5M .sens до ELF64.
  Мовні закони не визначаємо: рівно існуючий source-backed D24
  lowering → фізичний stdout → два runtime T5M stdin.
  Вхід — позичені шляхи; три фізичні owned byte strings та три
  проміжні ELF живуть лише до завершення Run.
  1) Чому D24 placeholder не є початковим аргументом виконання?
  2) Чому .lisp не приймається за машинне джерело?
  3) Чому різні D7 параметри перевіряємо за точними бітами?
  4) Хто володіє всіма трьома ELF-буферами?
  5) Чому no-clobber потрібен після останнього VerifySENSELF64? }
program sensdvaparampriamoelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.domain,
     wsm.lowerd24,wsm.bodyt5mstdout,wsm.bodytwot5mstdin,
     wsm.elfpublish,wsm.elfgeometry;
type EDirectD24Error=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(Ok:Boolean;const Why:UnicodeString);
begin if not Ok then raise EDirectD24Error.Create(String(UA(Why))) end;

{ ReadPhysical — тільки canonical фізичні байти, не D7 текст.
  Керований Result володіє пам'яттю, TFileStream завжди Free.
  Неповний/неканонічний packed потік відхиляється до AOT. }
function ReadPhysical(const Path:String;MaxBytes:SizeInt):RawByteString;
var F:TFileStream;Words:TExactWords;
begin
  Result:='';
  Need((Path<>'') and (Length(Path)<=4096) and
       (ExtractFileExt(Path)='.sens'),'потрібен файл canonical .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((F.Size>0) and (F.Size<=MaxBytes),'вхідні T5M байти поза квотою');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
  DecodeT5M(Result,Words);
  Need(EncodeT5M(Words)=Result,'неканонічні байти T5M');
end;

{ D7 параметр — список точних W7 гліфів, не назва функції.
  Повертає повну двійкову послідовність W7; два параметри
  не можуть мати однаковий повний ключ попри різні поверхні. }
function ExactD7Name(const Physical:RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  DecodeT5M(Physical,Words);
  Need((Length(Words)>=3) and (Words[0]='10') and
       (Words[High(Words)]='01'),'параметр має бути D2 списком D7');
  Result:='';
  for I:=1 to High(Words)-1 do begin
    Need(Length(Words[I])=7,'параметр містить не D7 слово');
    Result:=Result+Words[I];
  end;
  Need(Result<>'','порожній параметр');
end;

procedure WriteError(const S:RawByteString);
var Stream:THandleStream;Line:RawByteString;
begin
  Line:=S+#10;
  Stream:=THandleStream.Create(TextRec(ErrOutput).Handle);
  try Stream.WriteBuffer(Line[1],Length(Line));finally Stream.Free end;
end;

procedure Run;
var Tables:TDomainSet;
    Body,P1,P2,Zero,ExitImage,PhysicalImage,DynamicImage:RawByteString;
    G:TELFGeometry;Target:String;
begin
  {$IFNDEF LINUX}
  Need(False,'потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  Need(False,'потрібен x86-64');
  {$ENDIF}
  Need((ParamCount=5) and
    (RawByteString(ParamStr(1))=UA('--скомпілювати-два-D24-stdin')),
    'виклик: sensdvaparampriamoelf --скомпілювати-два-D24-stdin тіло.sens параметр1.sens параметр2.sens новий.elf');
  Target:=ParamStr(5);
  Need((Target<>'') and (Length(Target)<=4096) and
       (ExtractFileExt(Target)='.elf'),'ціль має бути новим .elf');
  { Pinned таблиці — лише upstream авторитет, без Pascal-реєстру.
    Вхідна команда не читає .lisp і не виводить law зі spelling. }
  LoadPinnedDomains('external/sens',Tables);
  Body:=ReadPhysical(ParamStr(2),8192);
  P1:=ReadPhysical(ParamStr(3),512);
  P2:=ReadPhysical(ParamStr(4),512);
  Need(ExactD7Name(P1)<>ExactD7Name(P2),
       'дубльований фізичний D7 параметр');
  { Обидва immediate стануть runtime-аргументами: чинний postpass
    замінить початкові 10 байтів на JMP і читає 2×W24 зі stdin.
    Константа 0 тут ТІЛЬКИ технічний початковий ABI placeholder,
    не новий D12/D24 закон і не результат компіляції. }
  Zero:=EncodeNumericDecimal('0',24);
  ExitImage:=LowerBodyTwoParamsELF(Body,P1,P2,Zero,Zero);
  PhysicalImage:=BodyD24T5MStdoutELF(ExitImage);
  DynamicImage:=DynamicTwoD24StdinELF(PhysicalImage);
  VerifySENSELF64(DynamicImage,G);
  Need((G.Kind=2) and (G.Entry=$400078) and
       (G.FileBytes=Length(DynamicImage)),'ELF64 не пройшов фінальну перевірку');
  PublishNewELF64(Target,DynamicImage,2,G);
  Writeln('ДВА-D24-ПРЯМО-ELF-ГОТОВО bytes=',G.FileBytes,
    ' source=physical-T5M args=2 input=10-byte-T5M',
    ' result=D24-T5M energy=NOT_MEASURED');
end;

begin
  try Run
  except on E:Exception do begin
    WriteError(UA('ДВА-D24-ПРЯМО-ВІДМОВА: ')+RawByteString(E.Message));
    ExitCode:=2;
  end end;
end.
