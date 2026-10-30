{ G6.201 — реальна фізична D5:10111→WideIR→ELF64 перевірка.
  Вісім D12/D24 CQO/IDIV свідків; побайтове порівняння зі старим
  pinned маршрутом; виконання ELF із суворим exit/stderr guard;
  fail-closed негативи та одноразовість контексту.
  1) Чому stdout існує навіть після аварійного exit?
  2) Чому ширина результату зберігається у фізичному T5M?
  3) Чому byte equality не підміняє SENS REPL oracle?
  4) Хто очищає тимчасові файли у випадку exception?
  5) Чому другий Lower після першого виконання заборонений? }
program test_verifiedquot;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix,
     wsm.t5m, wsm.numericplane, 
     wsm.verifiedwidecontext, wsm.verifiedquot,
     wsm.irwidequot, wsm.irwidefront, wsm.elfd12quot;

var Checks:Integer=0; Root:String; Contexts:LongInt=0;

procedure Check(Ok:Boolean;const Title:String);
begin
  Inc(Checks);
  if Ok then WriteLn('VQ-OK ',Title)
  else begin WriteLn('VQ-ЗБІЙ ',Title);Halt(1) end;
end;

function PackedForm(const Items:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Items));
  for I:=0 to High(Items) do W[I]:=Items[I];
  Result:=EncodeT5M(W);
end;

function QuotProgram(const LDec,RDec:RawByteString):RawByteString;
var L,R:TExplicitNumeric;
begin
  L:=ReadNumericPhysical(EncodeNumericDecimal(LDec,12),12);
  R:=ReadNumericPhysical(EncodeNumericDecimal(RDec,12),12);
  Result:=PackedForm(['10','10111',L.ExactBits,R.ExactBits,'01']);
end;

function ExpectedPhysical(const Number:RawByteString;Width:SizeInt):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Number,Width),Width);
  Result:=PackedForm([N.ExactBits]);
end;

{ Image — borrowed exact native bytes; Output має власне збереження
  лише ПІСЛЯ exit=0, створення stdout і порожнього stderr.
  /tmp файл унікальний для PID і послідовності тестів, завжди прибирається. }
function RunELF(const Image:RawByteString;out Output:RawByteString):Boolean;
var Path,OutPath,ErrPath,Cmd:String;F:TFileStream;
    Status:LongInt;ErrEmpty:Boolean;
begin
  Result:=False;Output:='';
  Path:='/tmp/vq-'+IntToStr(GetProcessID)+'-'+IntToStr(Checks)+'.elf';
  OutPath:=Path+'.out';ErrPath:=Path+'.err';
  DeleteFile(OutPath);DeleteFile(ErrPath);
  try
    F:=TFileStream.Create(Path,fmCreate);
    try
      if Length(Image)>0 then F.WriteBuffer(Image[1],Length(Image));
    finally F.Free end;
    if fpChmod(Path,&755)<>0 then Exit;
    Cmd:='/bin/sh -c ''timeout 10s "'+Path+
         '" > "'+OutPath+'" 2> "'+ErrPath+'"''';
    Status:=fpSystem(PChar(Cmd));
    if (Status<>0) or (not FileExists(OutPath)) or
       (not FileExists(ErrPath)) then Exit;
    F:=TFileStream.Create(ErrPath,fmOpenRead or fmShareDenyWrite);
    try ErrEmpty:=F.Size=0;finally F.Free end;
    if not ErrEmpty then Exit;
    F:=TFileStream.Create(OutPath,fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Output,SizeInt(F.Size));
      if F.Size>0 then F.ReadBuffer(Output[1],F.Size);
    finally F.Free end;
    Result:=True;
  finally
    DeleteFile(Path);DeleteFile(OutPath);DeleteFile(ErrPath);
  end;
end;

function BuildViaContext(const Physical:RawByteString):RawByteString;
var C:TVerifiedWideContext;
begin
  C:=TVerifiedWideContext.Create(Physical,Root);
  try
    Inc(Contexts);
    Result:=C.Lower(@LowerVerifiedQuot);
  finally C.Free end;
end;

type TCase=record L,R,Wanted:RawByteString;Width:SizeInt end;
var Cases:array[0..7] of TCase;
    I:Integer;Prog,OldELF,NewELF,Expected,OutBytes:RawByteString;
    LeftPhysical,RightPhysical:RawByteString;
    C:TVerifiedWideContext;

begin
  if ParamCount<>1 then begin
    WriteLn('VQ-БЛОК: потрібен шлях до pinned external/sens');
    Halt(64);
  end;
  Root:=ParamStr(1);
  Cases[0].L:='1';Cases[0].R:='1';Cases[0].Wanted:='1';Cases[0].Width:=12;
  Cases[1].L:='2';Cases[1].R:='2';Cases[1].Wanted:='1';Cases[1].Width:=12;
  Cases[2].L:='7';Cases[2].R:='7';Cases[2].Wanted:='1';Cases[2].Width:=12;
  Cases[3].L:='-1';Cases[3].R:='-1';Cases[3].Wanted:='1';Cases[3].Width:=12;
  Cases[4].L:='-7';Cases[4].R:='-7';Cases[4].Wanted:='1';Cases[4].Width:=12;
  Cases[5].L:='31';Cases[5].R:='31';Cases[5].Wanted:='1';Cases[5].Width:=12;
  Cases[6].L:='-512';Cases[6].R:='-512';Cases[6].Wanted:='1';Cases[6].Width:=12;
  Cases[7].L:='-2048';Cases[7].R:='-2048';Cases[7].Wanted:='1';Cases[7].Width:=12;

  for I:=0 to High(Cases) do begin
    Prog:=QuotProgram(Cases[I].L,Cases[I].R);
    LeftPhysical:=EncodeNumericDecimal(Cases[I].L,12);
    RightPhysical:=EncodeNumericDecimal(Cases[I].R,12);
    Expected:=ExpectedPhysical(Cases[I].Wanted,Cases[I].Width);
    Check(LeftPhysical=RightPhysical,
      'побайтово однакові ненульові фізичні D12 операнди');
    OldELF:=BuildVerifiedWideELF(Prog,Root);
    NewELF:=BuildViaContext(Prog);
    Check(NewELF=OldELF,
          'новий verified контекст дає побайтово той самий ELF');
    Check(NewELF=BuildIRWideQuotELF(Prog,Root),
          'машинні байти збігаються із прямим CQO/IDIV профілем');
    if RunELF(NewELF,OutBytes) then
      Check(OutBytes=Expected,
        'справжній CQO/IDIV ELF видає фізичний D'+IntToStr(Cases[I].Width))
    else Check(False,'справжній ELF не виконався');
  end;
  Check(Contexts=Length(Cases),'рівно один verified context на програму');

  Prog:=QuotProgram('7','-7');
  try
    NewELF:=BuildViaContext(Prog+#0);
    Check(False,'хвіст T5M прийнято');
  except on E:Exception do Check(True,'неканонічний T5M відхилено') end;

  try
    NewELF:=BuildViaContext(PackedForm(['10','01011',
      ReadNumericPhysical(EncodeNumericDecimal('7',12),12).ExactBits,
      ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits,'01']));
    Check(False,'чужа D5:01011 голова прийнята як частки');
  except on E:EVerifiedQuotError do Check(True,'чужа D5 голова відхилена') end;

  try
    NewELF:=BuildViaContext(PackedForm(['10','10111','1',
      ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits,'01']));
    Check(False,'D1 листок прийнято як числовий D12');
  except on E:EVerifiedQuotError do Check(True,'D1 не є числовим D12') end;

  try
    NewELF:=BuildViaContext(PackedForm(['10','10111',
      ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits,
      ReadNumericPhysical(EncodeNumericDecimal('2',12),12).ExactBits,
      ReadNumericPhysical(EncodeNumericDecimal('3',12),12).ExactBits,'01']));
    Check(False,'три аргументи прийнято');
  except on E:EVerifiedQuotError do Check(True,'зайва арність відхилена') end;

  try
    C:=TVerifiedWideContext.Create(Prog,Root+'/немає');
    try C.Lower(@LowerVerifiedQuot);finally C.Free end;
    Check(False,'недоступний pinned root прийнято');
  except on E:Exception do Check(True,'недоступний authority відхилено') end;

  try
    NewELF:=BuildViaContext(PackedForm(['10','10111',
      ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits,
      ReadNumericPhysical(EncodeNumericDecimal('1',12),12).ExactBits]));
    Check(False,'обірваний D2 прийнято');
  except on E:Exception do Check(True,'обірваний D2 відхилено') end;

  C:=TVerifiedWideContext.Create(Prog,Root);
  try
    NewELF:=C.Lower(@LowerVerifiedQuot);
    Check(Length(NewELF)>120,'перший Lower породив ELF64');
    try
      NewELF:=C.Lower(@LowerVerifiedQuot);
      Check(False,'повторний Lower прийнято');
    except on E:EVerifiedWideContext do
      Check(True,'повторний Lower відхилено') end;
  finally C.Free end;

  { Реальний IDIV backend повинен відхилити нуль та нерівні D12.
    Ніби-успішний ELF після виключення тут не допускається. }
  try
    NewELF:=BuildViaContext(QuotProgram('0','0'));
    Check(False,'ділення 0/0 прийнято');
  except on E:ED12QuotELFError do Check(True,'0/0 явно відхилено') end;
  try
    NewELF:=BuildViaContext(QuotProgram('7','3'));
    Check(False,'різні D12 прийнято вузьким IDIV');
  except on E:ED12QuotELFError do Check(True,'різні D12 явно відхилено') end;

  Check(not RunELF('#!/bin/sh'+#10+'printf bad'+#10+'exit 7'+#10,
    OutBytes),'stdout з exit=7 не є доказом ELF');
  Check(OutBytes='','stdout після exit=7 не витікає');
  Check(not RunELF('#!/bin/sh'+#10+'printf bad'+#10+
    'printf error >&2'+#10+'exit 0'+#10,OutBytes),
    'stderr забороняє позитивний машинний доказ');
  Check(OutBytes='','stdout після stderr не витікає');

  WriteLn('VQ-PASS checks=',Checks);
end.
