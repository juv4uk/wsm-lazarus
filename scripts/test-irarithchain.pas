{ G6.97 / G6.137 / G6.138 — 71 canonical фізична програма й реальні ELF.
  Очікувані значення — ТІЛЬКИ existing signed D12 numeric gates.
  Глибини 9..16/50/100 проходять ті самі pinned закони й машинні емісії.
  Тестовий вектор має лише чотири аргументи, тому індекс mod 4
  обов’язковий і для побудови форми, і для незалежного очікування.
  24 негативи для фізичних ширин, доменів, арності, D24 promotion. }
program test_irarithchain;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
  wsm.numericsub,wsm.irarithchain;
const Bases:array[0..3] of Integer=(-2000,-5,0,2040);
      RightNumbers:array[0..3] of Integer=(3,-7,11,-2);
var Folder:String;Negatives:Integer;
function Bits12(V:Integer):RawByteString;
var I:Integer;
begin
  Result:=StringOfChar('0',12);
  if V<0 then V:=V+4096;
  for I:=12 downto 1 do begin
    if (V and 1)<>0 then Result[I]:='1';
    V:=V shr 1;
  end;
end;
function Atom(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W) end;
{ Форму завертаємо зсередини назовні в TExactWords. BadHead/BadRight
  не є registry: лише навмисне пошкодження фізичних test fixtures.
  Питання: чому D2:10/01 не можна замінити пробілами?
  Чому базовий D12 atom — окреме канонічне слово?
  Що доводить негатив для підміни W24? }
function MakeForm(Depth,Base,BadHeadAt,BadRightAt:Integer;
  const BadHead,BadRight,BadBase:RawByteString):RawByteString;
var W,Next:TExactWords;I,J:Integer;Op,Arg:RawByteString;
begin
  SetLength(W,1);
  if BadBase<>'' then W[0]:=BadBase else W[0]:=Bits12(Base);
  for I:=0 to Depth-1 do begin
    if (I mod 2)=0 then Op:='01011' else Op:='01010';
    if I=BadHeadAt then Op:=BadHead;
    Arg:=Bits12(RightNumbers[I mod 4]);
    if I=BadRightAt then Arg:=BadRight;
    SetLength(Next,Length(W)+4);
    Next[0]:='10';Next[1]:=Op;
    for J:=0 to High(W) do Next[J+2]:=W[J];
    Next[High(Next)-1]:=Arg;
    Next[High(Next)]:='01';
    W:=Next;
  end;
  Result:=EncodeT5M(W);
end;
function Form(Depth,Base:Integer):RawByteString;
begin Result:=MakeForm(Depth,Base,-1,-1,'','','') end;
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Reject(const Name:String;const Physical:RawByteString);
var Image:RawByteString;
begin
  try Image:=BuildIRArithChainELF(Physical,'external/sens')
  except on E:Exception do begin Inc(Negatives);Exit end end;
  raise Exception.Create('помилково прийнято '+Name+
    ' ELF='+IntToStr(Length(Image)));
end;
procedure Run;
var Depth,I,J,K,Base:Integer;W,T:TExactWords;
    Source,Image,Expected,Arg:RawByteString;
begin
  if ParamCount<>1 then raise Exception.Create('потрібен каталог доказів');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Folder) then
    raise Exception.Create('не створено каталог');
  Negatives:=0;
  for Depth:=1 to 100 do begin
    if (Depth>16) and (Depth<>50) and (Depth<>100) then Continue;
    for I:=0 to 4 do begin
      if (Depth>16) and (I=0) then Continue;
      if (I=4) and (Depth<>100) then Continue;
      { Довга підпрограма має 16 кроків із сумою -92; тестова основа
        -2000 на пізніх глибинах дала б D24 й не є позитивним D12. }
      if I=4 then Base:=-1473
      else if (Depth>8) and (I=0) then Base:=-1900
      else Base:=Bases[I];
      Source:=Form(Depth,Base);
      Image:=BuildIRArithChainELF(Source,'external/sens');
      Expected:=Atom(Bits12(Base));
      for J:=0 to Depth-1 do begin
        Arg:=Atom(Bits12(RightNumbers[J mod 4]));
        if (J mod 2)=0 then
          Expected:=SubtractNumericPhysical(Expected,Arg,12)
        else Expected:=AddNumericPhysical(Expected,Arg,12);
      end;
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.sens',Source);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.elf',Image);
      Save(Folder+IntToStr(Depth)+'-'+IntToStr(I)+'.expected.sens',Expected);
    end;
  end;
  Reject('чужа внутрішня D5 голова',MakeForm(2,5,0,-1,'10110','',''));
  Reject('чужа зовнішня D5 голова',MakeForm(2,5,1,-1,'10110','',''));
  Reject('D6 замість D5',MakeForm(2,5,0,-1,'001110','',''));
  Reject('D7 замість D5',MakeForm(1,5,0,-1,'0000001','',''));
  Reject('аргумент D1',MakeForm(2,5,-1,0,'','1',''));
  Reject('аргумент D7',MakeForm(2,5,-1,0,'','0000001',''));
  Reject('аргумент D24',MakeForm(2,5,-1,1,'',StringOfChar('0',23)+'1',''));
  Reject('основа D1',MakeForm(1,5,-1,-1,'','','1'));
  Reject('основа D7',MakeForm(1,5,-1,-1,'','','0000001'));
  Reject('основа D24',MakeForm(1,5,-1,-1,'','',StringOfChar('0',23)+'1'));
  Reject('переповнення на першому кроці',Form(1,-2048));
  Reject('переповнення на другому кроці',Form(2,-2045));
  Reject('понад 100 вкладень',Form(101,5));
  Reject('чужа D5 голова на шістнадцятому рівні',MakeForm(16,5,15,-1,'10110','',''));
  Reject('чужий D24 аргумент на шістнадцятому рівні',MakeForm(16,5,-1,15,'',StringOfChar('0',23)+'1',''));
  Reject('D12 переповнення лише на шістнадцятому кроці',Form(16,-1957));
  Reject('чужа голова на сотому кроці',MakeForm(100,5,99,-1,'10110','',''));
  Reject('D24 правий аргумент на сотому кроці',
    MakeForm(100,5,-1,99,'',StringOfChar('0',23)+'1',''));
  { 100 * (−3−7−11−2)/4 = −575. Мінімальне D12 −2048
    допустиме для -1473, а -1474 має відмовити саме на кроці 100. }
  Reject('D12 переповнення рівно на сотому кроці',Form(100,-1474));
  Reject('пошкоджений T5M',#$FF);
  Reject('порожня програма','');
  DecodeT5M(Form(2,5),W);
  SetLength(W,Length(W)-1);
  Reject('незакритий D2 список',EncodeT5M(W));
  DecodeT5M(Form(2,5),W);
  K:=Length(W);SetLength(W,K+1);W[K]:='1';
  Reject('зайвий другий корінь',EncodeT5M(W));
  DecodeT5M(Form(1,5),W);
  SetLength(T,Length(W)+1);
  for J:=0 to High(W)-1 do T[J]:=W[J];
  T[High(T)-1]:='1';T[High(T)]:=W[High(W)];
  Reject('зайвий аргумент D5',EncodeT5M(T));
  if Negatives<>24 then raise Exception.Create(
    'не всі негативи: '+IntToStr(Negatives));
  WriteLn('D5-ARITH-CHAIN-UNIT-OK positive=71 negative=24');
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'D5-ARITH-CHAIN-UNIT-FAIL: ',E.Message);Halt(1)
  end end;
end.
