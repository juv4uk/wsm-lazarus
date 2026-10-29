{ G6.89: усі 16 фізичних D1-четвірок для runtime stdin та ОКРЕМО
  16 справжніх D2/T5M програм SENS (тільки для незалежного oracle).
  Формат host stdin: concatenation 4 окремих W1 T5M байтів,
  не один .sens документ; не додавати D7 текст до семантики.
  Питання: чому oracle має D2 framing, а stdin host frame — ні?
  Чому D3:000 при вичерпанні не є D1:0?
  Як доводимо, що кожна W1 проєкція фізично канонічна?
  Чому test manifest не стає джерелом нових мовних законів? }
program test_d1umovapotik;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m;
var Dir:String;Count,Exhausted,First,Second:SizeInt;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function W(const Parts:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Parts));
  for I:=0 to High(Parts) do Result[I]:=Parts[I];
end;

procedure Save(const Name:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Dir+Name,fmCreate);
  try
    if Data<>'' then Stream.WriteBuffer(Data[1],Length(Data));
  finally Stream.Free end;
end;

{ T0/E0/T1/E1: тільки D1 exact bits, borrowed.
  Output: 4 окремі packed host input bytes; самостійна D2-форма .sens;
  expected physical T5M із структурним D3:000 при вичерпанні.
  Питання: чому ці два входи не взаємозамінні?
  Чому наявність двох хибних тестів не повертає D1:0?
  Що означає E1, якщо T0=1? }
procedure Fixture(T0,E0,T1,E1:RawByteString);
var Name:String; ResultBits,LabelText:RawByteString;
begin
  Name:=Format('пара-%2.2d',[Count+1]);
  if T0='1' then begin
    ResultBits:=E0;LabelText:='перша';
    Inc(First);
  end else if T1='1' then begin
    ResultBits:=E1;LabelText:='друга';
    Inc(Second);
  end else begin
    ResultBits:='000';LabelText:='вичерпано';
    Inc(Exhausted);
  end;
  Save(Name+'.frame',EncodeT5M(W([T0,E0,T1,E1])));
  Save(Name+'.sens',EncodeT5M(W(
    ['10','110','10',T0,E0,'01','10',T1,E1,'01','01'])));
  Save(Name+'.expected.sens',EncodeT5M(W([ResultBits])));
  if ResultBits='000' then Save(Name+'.oracle.txt','()'+#10)
  else Save(Name+'.oracle.txt',ResultBits+#10);
  WriteLn(Name,#9,T0,#9,E0,#9,T1,#9,E1,#9,ResultBits,#9,LabelText);
  Inc(Count);
end;

var A,B,C,D:SizeInt; Zero,One:RawByteString;
begin
  if ParamCount<>1 then Halt(64);
  Dir:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Dir) then Halt(2);
  Zero:=EncodeT5M(W(['0']));One:=EncodeT5M(W(['1']));
  if (Length(Zero)<>1) or (Length(One)<>1) or (One=Zero) then Halt(4);
  Count:=0;First:=0;Second:=0;Exhausted:=0;
  for A:=0 to 1 do
    for B:=0 to 1 do
      for C:=0 to 1 do
        for D:=0 to 1 do
          Fixture(IntToStr(A),IntToStr(B),IntToStr(C),IntToStr(D));
  if (Count<>16) or (First<>8) or (Second<>4) or
    (Exhausted<>4) then Halt(5);
  Save('порожній.frame','');
  Save('короткий-1.frame',Zero);
  Save('короткий-2.frame',Zero+One);
  Save('короткий-3.frame',Zero+One+Zero);
  Save('зайвий.frame',Zero+Zero+Zero+Zero+One);
  Save('зіпсований-1.frame',#$FF+Zero+Zero+One);
  Save('зіпсований-2.frame',Zero+#$FF+Zero+One);
  Save('зіпсований-3.frame',Zero+Zero+#$FF+One);
  Save('зіпсований-4.frame',Zero+Zero+Zero+#$FF);
  Save('неканонічний.frame',#0+#0+#0+#0);
  Save('текстова.lisp',UA('(за-умовою (так ні) (ні так))')+#10);
  WriteLn(StdErr,UA('Д1-УМОВА-СВІДКИ-ГАРАЗД четвірок='),
    Count,UA(' перша='),First,UA(' друга='),Second,
    UA(' вичерпано='),Exhausted);
end.
