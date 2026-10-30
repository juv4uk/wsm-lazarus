{ G6.161 — механічні D12/T5M свідки для повторно використовуваного
  ELF Core1. Очікувана арифметика у цьому тесті — fixture, не SENS
  закон: незалежний pinned SENS REPL перевіряє кожне expected. }
program test_core1potik_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Root:String;Accepted,Promoted:TStringList;ValidCount,WideCount:Integer;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise Exception.Create('ЯДРО1-ПОТІК-СВІДОК: '+Why) end;
procedure Save(const Name:String;const Bytes:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Root+'/'+Name,fmCreate);
  try if Length(Bytes)>0 then F.WriteBuffer(Bytes[1],Length(Bytes))
  finally F.Free end;
end;
function Atom(V:LongInt;Width:SizeInt):RawByteString;
var N:TExplicitNumeric;
begin
  Result:=EncodeNumericDecimal(IntToStr(V),Width);
  N:=ReadNumericPhysical(Result,Width);
  Need((N.DomainWidth=Width) and (Length(N.ExactBits)=Width),
    'не точний числовий атом');
end;
function Bits12(V:LongInt):RawByteString;
var N:TExplicitNumeric;
begin N:=ReadNumericPhysical(Atom(V,12),12);Result:=N.ExactBits end;
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;
{ Набір двох окремих signed D12 runtime чисел для ОБОХ режимів.
  Кожен canonical D2 source — фізичний pinned D5 call.
  Повернені .expected.sens містять рівно D12 або D24 згідно з
  явною шириною, але сам файл не є мовним oracle.
  1) Чому 6 host-байтів не є одним канонічним .sens?
  2) Де точно фіксується ширина числа зі знаком?
  3) Чому результат D24 не можна надрукувати як D12?
  4) Хто незалежно перевірить значення fixture? }
procedure CaseOf(const LabelText:String;A,B:LongInt;Subtract:Boolean);
var Head,Name,Frame,Expression,Expected,Row:RawByteString;
    Val,Width:LongInt;
begin
  if Subtract then begin Head:='01011';Name:='s'+LabelText;Val:=A-B end
  else begin Head:='01010';Name:='a'+LabelText;Val:=A+B end;
  Frame:=Atom(A,12)+Atom(B,12);
  Expression:=Pack(['10',Head,Bits12(A),Bits12(B),'01']);
  if (Val>=-2048) and (Val<=2047) then Width:=12 else Width:=24;
  Expected:=Atom(Val,Width);
  Save(String(Name)+'.frame',Frame);
  Save(String(Name)+'.sens',Expression);
  Save(String(Name)+'.expected.sens',Expected);
  Row:=Name+#9+Head+#9+IntToStr(A)+#9+IntToStr(B)+#9+
       IntToStr(Val)+#9+IntToStr(Width);
  if Width=12 then begin Accepted.Add(String(Row));Inc(ValidCount) end
  else begin Promoted.Add(String(Row));Inc(WideCount) end;
end;
var I:Integer;W:TExactWords;First,Second:RawByteString;
const
  A:array[0..19] of LongInt=
    (0,7,3,-7,7,-7,-1,1,2047,-2048,2047,-2048,
     2047,-2048,-2048,-2048,2047,100,-300,2046);
  B:array[0..19] of LongInt=
    (0,3,7,3,-3,-3,1,-1,0,0,2047,-2048,
     1,-1,1,2047,-2048,-200,300,1);
begin
  Need(ParamCount=1,'потрібен каталог свідків');
  Root:=ParamStr(1);
  Need(ForceDirectories(Root),'неможливо створити каталог');
  Accepted:=TStringList.Create;Promoted:=TStringList.Create;
  try
    ValidCount:=0;WideCount:=0;
    for I:=0 to High(A) do begin
      CaseOf(Format('%.2d',[I]),A[I],B[I],False);
      CaseOf(Format('%.2d',[I]),A[I],B[I],True);
    end;
    Need((ValidCount+WideCount=40) and
         (ValidCount>=25) and (WideCount>=5),
      'неповна знакова матриця D12/D24');
    Accepted.SaveToFile(Root+'/cases.tsv');
    Promoted.SaveToFile(Root+'/promotion.tsv');
    First:=Atom(7,12);Second:=Atom(3,12);
    Save('empty.frame','');
    Save('short.frame',Copy(First+Second,1,5));
    Save('extra.frame',First+Second+#0);
    Save('bad-first.frame',#$FF+Copy(First+Second,2,5));
    Save('bad-middle.frame',Copy(First+Second,1,3)+#$FF+
      Copy(Second,2,2));
    Save('text.frame',RawByteString(UTF8Encode(UnicodeString(
      '(додати 7 3)')))+#10);
    SetLength(W,1);W[0]:='1';
    Save('d1.frame',EncodeT5M(W)+EncodeT5M(W));
    WriteLn('CORE1-POTIK-FIXTURES-OK total=40 d12=',ValidCount,
      ' d24=',WideCount,' bad=7');
  finally Accepted.Free;Promoted.Free end;
end.
