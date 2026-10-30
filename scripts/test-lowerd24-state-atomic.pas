{ G6.264 — атомарність фізичного admission і стану D24 lowering.
  Справжній T5M D7 параметр походить з pinned D7, D24 — точний W24.
  Borrowed фізичні слова і короткоживучий ELF належать цьому тесту.
  1) Чому D1:1 заборонений там, де потрібен D24?
  2) Чому відмова до ParseD2 має відновлювати State?
  3) Чому не можна назвати машинний exit незалежним SENS oracle?
  4) Хто видаляє тимчасовий ELF при помилці?
  5) Чому чужий параметр не повинен ставати доступним після відмови? }
program test_lowerd24_state_atomic;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix,
  wsm.t5m, wsm.d7text, wsm.lowerd24;

const Names:array[0..5] of String =
  ('величина','додаток','третя','четверта','пята','шоста');
var
  Map:TD7Map;
  Keys, Args:array[0..5] of RawByteString;
  Bad:RawByteString;
  I,Cases:SizeInt;

procedure Need(Yes:Boolean;const Why:String);
begin
  if not Yes then raise Exception.Create('STATE-ATOMIC-FAIL '+Why);
  Inc(Cases);
end;

function One(const Bits:RawByteString):TExactWords;
begin
  SetLength(Result,1);Result[0]:=Bits;
end;

{ Вхідне ім'я — лише pinned D7 проєкція, вихід — фізичний D2 список.
  Бітова послідовність не є новим мовним законом. }
function NameKey(const LabelText:String):RawByteString;
var W:TExactWords;Bits:RawByteString;I:SizeInt;
begin
  DecodeT5M(EncodeD7Text(RawByteString(LabelText),Map,dsUk),W);
  Bits:='';
  for I:=0 to High(W) do Bits:=Bits+W[I];
  Need((Length(Bits)>0) and (Length(Bits) mod 7=0),'exact D7 name');
  SetLength(W,Length(Bits) div 7+2);
  W[0]:='10';
  for I:=1 to Length(Bits) div 7 do W[I]:=Copy(Bits,(I-1)*7+1,7);
  W[High(W)]:='01';
  Result:=EncodeT5M(W);
end;

function D24(Value:LongWord):RawByteString;
var Bits:RawByteString;I:SizeInt;
begin
  SetLength(Bits,24);
  for I:=1 to 24 do
    if (Value and (LongWord(1) shl (24-I)))<>0 then Bits[I]:='1'
    else Bits[I]:='0';
  Result:=EncodeT5M(One(Bits));
end;

function RunELF(const Image:RawByteString):SizeInt;
var Path:String;F:TFileStream;Status:LongInt;
begin
  Need((Length(Image)>120) and (Copy(Image,1,4)=#127+'ELF'),
       'physical ELF64 header');
  Path:=GetTempDir(False)+'sens-state-atomic-'+IntToStr(fpGetPID)+'.elf';
  F:=TFileStream.Create(Path,fmCreate);
  try F.WriteBuffer(Image[1],Length(Image));
  finally F.Free end;
  try
    Need(fpChmod(Path,&700)=0,'private executable');
    Status:=fpSystem(PChar(Path));
    Need(WIFEXITED(Status),'native Linux ELF exit');
    Result:=WEXITSTATUS(Status);
  finally DeleteFile(Path) end;
end;

{ Без лексичного оголошення навіть попередньо використане D7-ім'я
  мусить залишитися невідомим: повний ELF не повинен виникнути. }
procedure NoPhantom(const ForeignBody:RawByteString;const Tag:String);
var Refused:Boolean;Image:RawByteString;
begin
  Refused:=False; Image:='';
  try Image:=LowerBodyELF(ForeignBody,Keys[0],Args[0]);
  except on E:ELowerD24Error do Refused:=True end;
  Need(Refused,Tag+' undeclared D7 rejected');
  Need(Image='',Tag+' no ELF');
end;

procedure Positive(const Tag:String);
var Image:RawByteString;
begin
  Image:=LowerBodyELF(Keys[0],Keys[0],Args[0]);
  Need(RunELF(Image)=17,Tag+' recovered native ELF');
end;

var Refused:Boolean;Image:RawByteString;
    K,A:array of RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  LoadPinnedD7Map(ParamStr(1),Map);
  Cases:=0;
  for I:=0 to 5 do begin
    Keys[I]:=NameKey(Names[I]);
    Args[I]:=D24(17+I);
  end;
  Bad:=EncodeT5M(One('1')); { D1, НЕ D24. }
  NoPhantom(Keys[1],'initial');
  Positive('initial');

  { Прямий одноаргументний entry також має відновити State до викиду. }
  Refused:=False;Image:='';
  try Image:=LowerBodyELF(Keys[0],Keys[0],Bad);
  except on E:ELowerD24Error do Refused:=True end;
  Need(Refused and (Image=''),'one W1 refused');
  NoPhantom(Keys[1],'after-one');
  Positive('after-one');

  Refused:=False;Image:='';
  try Image:=LowerBodyTwoParamsELF(Keys[1],Keys[0],Keys[1],Args[0],Bad);
  except on E:ELowerD24Error do Refused:=True end;
  Need(Refused and (Image=''),'two W1 refused');
  NoPhantom(Keys[1],'after-two');
  Positive('after-two');
  Need(RunELF(LowerBodyTwoParamsELF(Keys[1],Keys[0],Keys[1],
       Args[0],Args[1]))=18,'two valid ELF64');

  Refused:=False;Image:='';
  try Image:=LowerBodyThreeParamsELF(Keys[2],Keys[0],Keys[1],Keys[2],
                                      Args[0],Args[1],Bad);
  except on E:ELowerD24Error do Refused:=True end;
  Need(Refused and (Image=''),'three W1 refused');
  NoPhantom(Keys[2],'after-three');
  Positive('after-three');
  Need(RunELF(LowerBodyThreeParamsELF(Keys[2],Keys[0],Keys[1],Keys[2],
       Args[0],Args[1],Args[2]))=19,'three valid ELF64');

  SetLength(K,6);SetLength(A,6);
  for I:=0 to 5 do begin K[I]:=Keys[I]; A[I]:=Args[I] end;
  A[5]:=Bad;
  Refused:=False;Image:='';
  try Image:=LowerBodyNParamsELF(Keys[5],K,A);
  except on E:ELowerD24Error do Refused:=True end;
  Need(Refused and (Image=''),'six W1 refused');
  NoPhantom(Keys[5],'after-six');
  Positive('after-six');
  A[5]:=Args[5];
  Need(RunELF(LowerBodyNParamsELF(Keys[5],K,A))=22,'six valid ELF64');
  Writeln('LOWER24-STATE-ATOMIC-PASS checks=',Cases,
          ' negatives=4 native=7 phantom=blocked energy=NOT-MEASURED oracle=NOT-RUN');
end.
