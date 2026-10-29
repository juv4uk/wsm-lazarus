{ G6.65 — вичерпні фізичні свідки D3:110 для чинного компілятора.
  Генератор тестових входів, НЕ SENS evaluator/reader. Очікування за
  pinned Contract 12 K12.3 незалежно перевірить справжній SENS CLI. }
program test_ircond_vectors;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m;

function One(const Bits:RawByteString):TExactWords;
begin
  SetLength(Result,1);
  Result[0]:=Bits;
end;

function Form(const Count, Variant:SizeInt;
  out Expected:RawByteString):RawByteString;
var
  Items:TExactWords;
  I,P,Digit,TestBit,ExpressionBit,Remaining:SizeInt;
  Chosen:Boolean;
begin
  SetLength(Items,3+Count*4);
  P:=0;
  Items[P]:='10'; Inc(P); { D2 корінь }
  Items[P]:='110'; Inc(P); { точний D3 COND }
  Expected:='000'; Chosen:=False; Remaining:=Variant;
  for I:=0 to Count-1 do begin
    Digit:=Remaining mod 4;
    Remaining:=Remaining div 4;
    TestBit:=Digit div 2;
    ExpressionBit:=Digit mod 2;
    Items[P]:='10'; Inc(P);
    Items[P]:=RawByteString(IntToStr(TestBit)); Inc(P);
    Items[P]:=RawByteString(IntToStr(ExpressionBit)); Inc(P);
    Items[P]:='01'; Inc(P);
    if (TestBit=1) and (not Chosen) then begin
      Expected:=RawByteString(IntToStr(ExpressionBit));
      Chosen:=True;
    end;
  end;
  if Remaining<>0 then
    raise Exception.Create('неприпустима фізична комбінація D1');
  Items[P]:='01'; Inc(P);
  if P<>Length(Items) then
    raise Exception.Create('помилка D2 обрамлення');
  Result:=EncodeT5M(Items);
end;

{ Негатив: структурно правильний D2, але числовий D12 замість D1
  тесту. Ніякого приведення за шириною або текстовою проєкцією. }
function InvalidD12:RawByteString;
var Items:TExactWords;
begin
  SetLength(Items,7);
  Items[0]:='10'; Items[1]:='110'; Items[2]:='10';
  Items[3]:='000000000000'; Items[4]:='1';
  Items[5]:='01'; Items[6]:='01';
  Result:=EncodeT5M(Items);
end;

procedure Save(const Path:String;const Data:RawByteString);
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmCreate);
  try
    if Data<>'' then Stream.WriteBuffer(Data[1],Length(Data));
  finally Stream.Free end;
end;

var
  Dir,Name:String;
  Variants,Clauses,Variant,I,Total:SizeInt;
  Expected,Physical,Oracle:RawByteString;
  Manifest:RawByteString;
begin
  if ParamCount<>1 then begin
    WriteLn(StdErr,'Виклик: test-ircond-vectors КАТАЛОГ');
    Halt(64);
  end;
  Dir:=IncludeTrailingPathDelimiter(ExpandFileName(ParamStr(1)));
  if not ForceDirectories(Dir) then
    raise Exception.Create('не створено каталог фізичних свідків');
  Manifest:='';
  Total:=0;
    for Clauses:=0 to 2 do begin
      Variants:=1;
      for I:=1 to Clauses do Variants:=Variants*4;
      for Variant:=0 to Variants-1 do begin
        { Стабільний ASCII fixture-ID, незалежний від Unicode/Format
          locale та UTF-8 проєкцій; це не ім'я SENS-функції. }
        Name:='d3-'+IntToStr(Clauses)+'-';
        if Variant<10 then Name:=Name+'0';
        Name:=Name+IntToStr(Variant);
        Physical:=Form(Clauses,Variant,Expected);
        if (Physical='') or (Length(Physical)>65536) then
          raise Exception.Create('неналежний канонічний T5M');
        Save(Dir+Name+'.sens',Physical);
        Save(Dir+Name+'.expected.sens',EncodeT5M(One(Expected)));
        if Expected='000' then Oracle:='()'+#10
        else Oracle:=Expected+#10;
        Save(Dir+Name+'.oracle.txt',Oracle);
        { Протокол маніфесту: точні ASCII байти, TAB, LF; без BOM,
          локалезалежного TStringList.SaveToFile або CRLF. }
        Manifest:=Manifest+RawByteString(Name)+#9+Expected+#10;
        Inc(Total);
      end;
    end;
    if Total<>21 then
      raise Exception.Create('втрачено фізичні комбінації 1+4+16');
    Save(Dir+'d12-invalid.sens',InvalidD12);
    Save(Dir+'d3-vectors.tsv',Manifest);
    WriteLn('КОМПІЛЯТОР-УМОВИ-СВІДКИ=21 межа=0..2 D1=точний');
end;

{ Form: Count=0..2, Variant=0..4^Count-1, Expected: власні
  біти D1:0, D1:1 або D3:000. Items — FPC-managed слова; на виході
  owned RawByteString фізичних packed T5M. Питання:
  1) Чому комбінацій 21? 2) Чому D3:000 не є D1:0?
  3) Хто незалежно перевіряє Expected? 4) Чому не текстове джерело? }