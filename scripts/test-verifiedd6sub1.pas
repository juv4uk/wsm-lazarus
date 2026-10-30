{ G6: дві реальні машини FPC O1/O2, тільки pinned D6:001111.
  Тест не визначає числового закону, звіряє машинні байти з
  існуючим BuildD6Sub1ELF і фізичний D12 результат з num-plane.
  Семантичний upstream REPL свідок вже існує у test-ird6sub1.sh;
  цей тест не заявляє нового незалежного oracle.
  1) Чому прямий backend є порівнянням механізму, а не SENS законом?
  2) Чому T5M має містити D2 маркери?
  3) Хто звільняє verified IR після callback?
  4) Чому D12 0 чи -1 відхиляється лише цим вузьким CPU fast-path? }
program test_verifiedd6sub1;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.numericplane, wsm.numericsub,
  wsm.verifiedwidecontext, wsm.verifiedd6sub1, wsm.ird6sub1;

const
  Values:array[0..7] of LongInt=(1,2,3,7,15,127,1024,2047);
var
  Root,Dir:String;
  Positive,Negative,Contexts:LongInt;

procedure Demand(Condition:Boolean;const Reason:String);
begin
  if not Condition then raise Exception.Create(Reason);
end;

function Word12(Value:LongInt):RawByteString;
var W:TExactWords;
begin
  DecodeT5M(EncodeNumericDecimal(IntToStr(Value),12),W);
  Demand((Length(W)=1) and (Length(W[0])=12),'числове слово не є D12');
  Result:=W[0];
end;

function Packed(const Bits:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Bits));
  for I:=0 to High(Bits) do W[I]:=Bits[I];
  Result:=EncodeT5M(W);
end;

function Form(const Head,Atom:RawByteString):RawByteString;
begin
  Result:=Packed(['10',Head,Atom,'01']);
end;

function ViaContext(const Source:RawByteString):RawByteString;
var C:TVerifiedWideContext;
begin
  C:=TVerifiedWideContext.Create(Source,Root);
  try
    Inc(Contexts);
    Result:=C.Lower(@LowerVerifiedD6Sub1);
  finally C.Free end;
end;

procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try
    if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

procedure Reject(const Name:String;const Source:RawByteString);
var Image:RawByteString;Rejected:Boolean;
begin
  Rejected:=False;
  try Image:=ViaContext(Source)
  except on E:Exception do Rejected:=True end;
  Demand(Rejected,'помилково допущено '+Name);
  Inc(Negative);
end;

procedure Run;
var I:SizeInt; V:LongInt; Source,NewELF,OldELF,Want:RawByteString;
    C:TVerifiedWideContext; Rejected:Boolean;
begin
  Demand(ParamCount=2,'потрібні pinned root і тека доказів');
  Root:=ParamStr(1);
  Dir:=IncludeTrailingPathDelimiter(ParamStr(2));
  Demand(DirectoryExists(Root),'немає pinned authority');
  Demand(ForceDirectories(Dir),'не створено теку доказів');
  Positive:=0;Negative:=0;Contexts:=0;

  for I:=Low(Values) to High(Values) do begin
    V:=Values[I];
    Source:=Form('001111',Word12(V));
    NewELF:=ViaContext(Source);
    OldELF:=BuildD6Sub1ELF(Source,Root);
    Demand((Length(NewELF)>120) and (NewELF=OldELF),
      'відрізняється фізичний ELF для '+IntToStr(V));
    Want:=SubtractNumericPhysical(
      EncodeNumericDecimal(IntToStr(V),12),EncodeNumericDecimal('1',12),12);
    Save(Dir+IntToStr(V)+'.sens',Source);
    Save(Dir+IntToStr(V)+'.elf',NewELF);
    Save(Dir+IntToStr(V)+'.expected.sens',Want);
    Inc(Positive);
  end;

  Reject('інша pinned D6 голова',Form('001110',Word12(3)));
  Reject('D1 замість D12',Form('001111','1'));
  Reject('D7 замість D12',Form('001111','0000001'));
  Reject('D24 замість D12',Form('001111',
    StringOfChar('0',23)+'1'));
  Reject('нуль',Form('001111',Word12(0)));
  Reject('від'+'ємне D12',Form('001111',Word12(-1)));
  Reject('мінімальне signed D12',Form('001111',Word12(-2048)));
  Reject('зіпсований T5M',#$FF);
  Reject('немає D2 закриття',Packed(['10','001111',Word12(3)]));
  Reject('другий фізичний корінь',
    Packed(['10','001111',Word12(3),'01','1']));

  { Спроба неправильного callback споживає verified context.
    Не можна retry тим самим контекстом після помилки. }
  Source:=Form('001111',Word12(5));
  C:=TVerifiedWideContext.Create(Source,Root);
  try
    NewELF:=C.Lower(@LowerVerifiedD6Sub1);
    Demand(Length(NewELF)>120,'перший Lower не створив ELF');
    Rejected:=False;
    try NewELF:=C.Lower(@LowerVerifiedD6Sub1)
    except on E:EVerifiedWideContext do Rejected:=True end;
    Demand(Rejected,'повторний Lower того самого контексту');
    Inc(Negative);
  finally C.Free end;

  { Немає таблиць authority — навіть з правильними байтами.
    Жодного stale-контексту від старого успішного виклику. }
  Rejected:=False;
  try
    C:=TVerifiedWideContext.Create(Source,Root+'/відсутній');
    try NewELF:=C.Lower(@LowerVerifiedD6Sub1) finally C.Free end;
  except on E:Exception do Rejected:=True end;
  Demand(Rejected,'не знайдено відмови без pinned authority');
  Inc(Negative);
  NewELF:=ViaContext(Source);
  Demand(NewELF=BuildD6Sub1ELF(Source,Root),
    'після відмови не відновилася компіляція');

  Demand((Positive=8) and (Negative=12) and (Contexts=16),
    'не збіглися механічні лічильники');
  WriteLn('VERIFIED-D6SUB1-OK positives=',Positive,
    ' negatives=',Negative,' contexts=',Contexts,
    ' exact-ELF=8 independent-oracle=NOT-RUN energy=NOT-MEASURED');
end;

begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'VERIFIED-D6SUB1-FAIL ',E.Message);
    Halt(1);
  end end;
end.
