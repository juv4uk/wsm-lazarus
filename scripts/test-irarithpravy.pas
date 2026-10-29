{ G6.141: фізичні right-nested canonical D5 ADD/SUB, позитиви і негативи.
  Очікування — незалежна signed integer арифметика ТЕСТУ, не закон SENS. }
program test_irarithpravy;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.irarithpravy;
const Bases:array[0..3] of Integer=(-1900,-7,0,1200);
      Lefts:array[0..3] of Integer=(3,-7,11,-2);
var Folder:String;Positive,Negative:Integer;
function Bits12(V:Integer):RawByteString;
var I:Integer;
begin
  if (V< -2048) or (V>2047) then raise Exception.Create('out of D12');
  if V<0 then V:=V+4096;
  SetLength(Result,12);
  for I:=12 downto 1 do begin
    if (V and 1)<>0 then Result[I]:='1' else Result[I]:='0';
    V:=V shr 1;
  end;
end;
function WordPhysical(const Bits:RawByteString):RawByteString;
var W:TExactWords;
begin SetLength(W,1);W[0]:=Bits;Result:=EncodeT5M(W) end;

{ Build canonical D2 list із позичених Bits12 W12; повертає owned packed
  T5M. Вкладені слова не втрачають ширину, жодного D7 dispatch.
  1) Чому правий ChildIndex=2? 2) Чому W12 тут точно 12 біт?
  3) Чому бінарний file, а не текст .lisp?
  4) Хто звільняє W після повернення? }
function MakeForm(Depth,Base,BadHeadAt,BadLeftAt:Integer;
  const BadHead,BadLeft,BadBase:RawByteString):RawByteString;
var W,Next:TExactWords;I,J:Integer;Head,Left:RawByteString;
begin
  SetLength(W,1);
  if BadBase<>'' then W[0]:=BadBase else W[0]:=Bits12(Base);
  for I:=Depth-1 downto 0 do begin
    if I mod 2=0 then Head:='01010' else Head:='01011';
    if I=BadHeadAt then Head:=BadHead;
    Left:=Bits12(Lefts[I mod 4]);
    if I=BadLeftAt then Left:=BadLeft;
    SetLength(Next,Length(W)+4);
    Next[0]:='10';Next[1]:=Head;Next[2]:=Left;
    for J:=0 to High(W) do Next[J+3]:=W[J];
    Next[High(Next)]:='01';
    W:=Next;
  end;
  Result:=EncodeT5M(W);
end;
function Form(Depth,Base:Integer):RawByteString;
begin Result:=MakeForm(Depth,Base,-1,-1,'','','') end;

procedure WriteFile(const Path:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Path,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data));
  finally F.Free end;
end;
procedure Reject(const Tag:String;const Physical:RawByteString);
var B:RawByteString;
begin
  try B:=BuildIRArithPravyELF(Physical,'external/sens')
  except on E:Exception do begin Inc(Negative);Exit end end;
  raise Exception.Create('неправомірний допуск '+Tag+' ELF='+IntToStr(Length(B)));
end;
procedure Run;
var Depth,BaseIndex,I,Want:Integer;Physical,Image,LabelName:RawByteString;
    Words,Other:TExactWords;
begin
  if ParamCount<>1 then raise Exception.Create('потрібна тестова тека');
  Folder:=IncludeTrailingPathDelimiter(ParamStr(1));
  if not ForceDirectories(Folder) then raise Exception.Create('не створено теку');
  Positive:=0;Negative:=0;
  for Depth:=1 to 16 do begin
    if (Depth>8) and (Depth<>16) then Continue;
    for BaseIndex:=0 to 3 do begin
      Physical:=Form(Depth,Bases[BaseIndex]);
      Image:=BuildIRArithPravyELF(Physical,'external/sens');
      Want:=Bases[BaseIndex];
      for I:=Depth-1 downto 0 do
        if I mod 2=0 then Want:=Lefts[I mod 4]+Want
        else Want:=Lefts[I mod 4]-Want;
      if (Want< -2048) or (Want>2047) then
        raise Exception.Create('позитивний тест вийшов за D12');
      LabelName:=IntToStr(Depth)+'-'+IntToStr(BaseIndex);
      WriteFile(Folder+String(LabelName)+'.sens',Physical);
      WriteFile(Folder+String(LabelName)+'.elf',Image);
      WriteFile(Folder+String(LabelName)+'.expected.sens',
                WordPhysical(Bits12(Want)));
      Inc(Positive);
    end;
  end;
  Reject('порожній','');
  Reject('зіпсований T5M',#$FF);
  Reject('немає жодного виклику',WordPhysical(Bits12(5)));
  Reject('17 рівнів',Form(17,0));
  Reject('чужа D5 голова',MakeForm(2,0,0,-1,'10110','',''));
  Reject('чужа внутрішня голова',MakeForm(16,0,15,-1,'10110','',''));
  Reject('D6 замість D5',MakeForm(1,0,0,-1,'001110','',''));
  Reject('не D12 лівий',MakeForm(2,0,-1,0,'','1',''));
  Reject('не D12 глибокий лівий',MakeForm(16,0,-1,15,'','1',''));
  Reject('не D12 базовий',MakeForm(2,0,-1,-1,'','','1'));
  Reject('D24 базовий',MakeForm(1,0,-1,-1,'','',
         StringOfChar('0',23)+'1'));
  Reject('D24 лівий',MakeForm(1,0,-1,0,'',
         StringOfChar('0',23)+'1',''));
  { Мінімальний signed overflow: 3 + 2047 = 2050. }
  Reject('підвищення D24 на внутрішньому кроці',
         Form(1,2047));
  { Додавання D5(-2048, -2) дає D24 — не звужувати. }
  Reject('відємне підвищення D24',
         MakeForm(1,-2048,-1,0,'',Bits12(-2),''));
  DecodeT5M(Form(1,0),Words);
  SetLength(Words,Length(Words)-1);
  Reject('незакритий список',EncodeT5M(Words));
  DecodeT5M(Form(1,0),Words);
  SetLength(Other,Length(Words)+1);
  for I:=0 to High(Words) do Other[I]:=Words[I];
  Other[High(Other)]:='1';
  Reject('зайвий корінь',EncodeT5M(Other));
  if (Positive<>36) or (Negative<>16) then
    raise Exception.Create('неповні тести: pos='+IntToStr(Positive)+
      ' neg='+IntToStr(Negative));
  WriteLn('Д5-ПРАВИЙ-WIDEIR-UNIT-ГОТОВО positive=36 negative=16');
end;
begin
  try Run
  except on E:Exception do begin
    WriteLn(StdErr,'Д5-ПРАВИЙ-WIDEIR-ВІДМОВА: ',E.Message);
    Halt(1);
  end end;
end.
