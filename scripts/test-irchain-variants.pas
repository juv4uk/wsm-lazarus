{ G6.142 — механічний НЕрегулярний свідок реального D5 WideIR→ELF.
  Pinned SENS встановлює координати/закони; ця програма лише
  будує тестові canonical T5M та звіряє результат уже злитих числових
  механізмів. Українська .lisp — допоміжна проєкція лише для оракула. }
program test_irchain_variants;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane,wsm.numericadd,
  wsm.numericsub,wsm.irarithchain;

const Rights:array[0..5] of Integer=(7,-11,5,-3,13,-9);
      Bases:array[0..2] of Integer=(-400,0,400);
var Folder:String; Negatives:SizeInt;

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Need(Ok:Boolean;const Why:RawByteString);
begin if not Ok then raise Exception.Create(String(Why)) end;

{ Бінарні байти — owned RawByteString, потік живе тільки під час Save.
  Це не перекладач .lisp: жоден символ проєкції не бере участі
  у формуванні машиної координати D5.
  1. Чому T5M буфер не є UTF-8?
  2. Чому потік обов'язково звільняється у finally?
  3. Хто є власником збережених exact T5M байтів? }
procedure Save(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;

function IsAdd(Step,Variant:Integer):Boolean;
begin Result:=((Step+Variant) mod 7) in [0,2,3,6] end;
function RightOf(Step,Variant:Integer):Integer;
begin Result:=Rights[(Step*5+Variant) mod 6] end;

{ Depth ∈ 1/25/50/100, Variant ∈ 0..2, Base exact signed D12.
  Фізичний шлях: TExactWords→EncodeT5M. Незалежно від нього
  людська українська проєкція будується як текст для SENS oracle.
  Expected створює ЧИННИЙ numeric gate; арифметична сума Calc
  додатково перевіряє числовий результат без нового мовного закону.
  Усі managed RawByteString/TExactWords живуть до виходу зі scope.
  1. Чому опи входять в список як точні п'ятибітні слова?
  2. Чому не можна відкинути D2 початок/кінець форми?
  3. Де перевірено D12 на кожному проміжному кроці?
  4. Чому .lisp не читається для визначення exact key?
  5. Чому oracle іншою програмою потрібен попри Calc? }
procedure Compose(Depth,Variant,Base:Integer;out Physical,
  Expected,Projection:RawByteString;out Calc:Integer);
var Words,RightWords,NextWords:TExactWords;
    I,J,R:Integer;Atom,Head:RawByteString;N:TExplicitNumeric;
begin
  Expected:=EncodeNumericDecimal(RawByteString(IntToStr(Base)),12);
  DecodeT5M(Expected,Words);
  Need(Length(Words)=1,'D12 основа не є одним словом');
  Projection:=RawByteString(IntToStr(Base));
  Calc:=Base;
  for I:=0 to Depth-1 do begin
    R:=RightOf(I,Variant);
    Atom:=EncodeNumericDecimal(RawByteString(IntToStr(R)),12);
    DecodeT5M(Atom,RightWords);
    Need(Length(RightWords)=1,'D12 аргумент не є одним словом');
    if IsAdd(I,Variant) then begin
      Head:='01010';
      Expected:=AddNumericPhysical(Expected,Atom,12);
      Calc:=Calc+R;
      Projection:='('+Ukr('додати')+' '+Projection+' '+
        RawByteString(IntToStr(R))+')';
    end else begin
      Head:='01011';
      Expected:=SubtractNumericPhysical(Expected,Atom,12);
      Calc:=Calc-R;
      Projection:='('+Ukr('відняти')+' '+Projection+' '+
        RawByteString(IntToStr(R))+')';
    end;
    N:=ReadNumericPhysical(Expected,12);
    Need((N.DomainWidth=12) and
      (RenderNumericDecimal(N)=RawByteString(IntToStr(Calc))),
      'проміжний результат вийшов за exact D12');
    SetLength(NextWords,Length(Words)+4);
    NextWords[0]:='10';NextWords[1]:=Head;
    for J:=0 to High(Words) do NextWords[J+2]:=Words[J];
    NextWords[High(NextWords)-1]:=RightWords[0];
    NextWords[High(NextWords)]:='01';
    Words:=NextWords;
  end;
  Physical:=EncodeT5M(Words);
  DecodeT5M(Physical,NextWords);
  Need(EncodeT5M(NextWords)=Physical,'пошкоджено T5M round-trip');
end;

{ Відмови — контроль допуску чинного компілятора, не нові закони.
  Owned Image не публікується при винятку; очікуємо явну відмову.
  1. Чому невідомий exact head не можна викликати за написанням?
  2. Чому W24 замість W12 не є тим самим аргументом?
  3. Чому другий корінь не можна ігнорувати? }
procedure Reject(const LabelName:RawByteString;const Physical:RawByteString);
var Image:RawByteString;
begin
  Save(Folder+String(LabelName)+'.sens',Physical);
  try Image:=BuildIRArithChainELF(Physical,'external/sens')
  except on E:Exception do begin Inc(Negatives);Exit end end;
  raise Exception.Create('помилково допущено '+String(LabelName)+
    ' ELF='+IntToStr(Length(Image)));
end;

procedure Run;
var Depth,Variant,Base,Calc,I:Integer;P,E,TextForm:RawByteString;
    W:TExactWords;Name:String;Image:RawByteString;
begin
  Need(ParamCount=1,'потрібен каталог доказів');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  Need(ForceDirectories(Folder),'неможливо створити каталог');
  Negatives:=0;
  for I:=0 to 3 do begin
    case I of
       0:Depth:=1;
       1:Depth:=25;
       2:Depth:=50;
    else Depth:=100 end;
    for Variant:=0 to 2 do begin
      Base:=Bases[Variant];
      Compose(Depth,Variant,Base,P,E,TextForm,Calc);
      Image:=BuildIRArithChainELF(P,'external/sens');
      Need(Length(Image)>120,'не створено справжній ELF');
      Name:=IntToStr(Depth)+'-'+IntToStr(Variant);
      Save(Folder+Name+'.sens',P);
      Save(Folder+Name+'.expected.sens',E);
      Save(Folder+Name+'.lisp',TextForm+#10);
      WriteLn(Name,#9,Depth,#9,Variant,#9,Calc);
    end;
  end;
  Compose(1,0,0,P,E,TextForm,Calc);
  DecodeT5M(P,W);
  W[1]:='10110';
  Reject('bad-head',EncodeT5M(W));
  DecodeT5M(P,W);
  W[2]:=StringOfChar('0',23)+'1';
  Reject('bad-width',EncodeT5M(W));
  Compose(101,0,0,P,E,TextForm,Calc);
  Reject('bad-depth',P);
  Compose(1,0,0,P,E,TextForm,Calc);
  DecodeT5M(P,W);SetLength(W,Length(W)-1);
  Reject('bad-truncated',EncodeT5M(W));
  DecodeT5M(P,W);SetLength(W,Length(W)+1);W[High(W)]:='1';
  Reject('bad-two-roots',EncodeT5M(W));
  Reject('bad-corrupt',#$FF);
  Reject('bad-empty','');
  Need(Negatives=7,'не пройдені сім негативних тестів');
  WriteLn(StdErr,'D5-VARIANTS-UNIT-OK positive=12 negative=7 depths=1,25,50,100');
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'D5-VARIANTS-UNIT-FAIL: ',E.Message);Halt(1)
  end end;
end.
