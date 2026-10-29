{ G1.22. D7 v2: 128 точних W7 координат; 95 друкованих «ук/укр».
  Цей механізм лише проєктує фізичні D7 text-data, НЕ програми SENS.
  Таблиця завжди походить із pinned lib/domains/d7.lisp, не з Unicode
  значень символів, ASCII, англійських назв або нових Pascal-законів. }
unit wsm.d7text;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type
  ED7TextError=class(Exception);
  TD7Surface=(dsUk,dsUkr);
  TD7Glyph=record
    Uk,Ukr:RawByteString;
  end;
  TD7Map=array[0..127] of TD7Glyph;
procedure ParseD7Map(const Source:RawByteString;out Map:TD7Map);
procedure LoadPinnedD7Map(const RepoRoot:String;out Map:TD7Map);
function EncodeD7Text(const Text:RawByteString;const Map:TD7Map;
  Surface:TD7Surface):RawByteString;
function DecodeD7Text(const Physical:RawByteString;const Map:TD7Map;
  Surface:TD7Surface):RawByteString;
implementation
uses Classes,wsm.source,wsm.t5m;
const MaxTextGlyphs=4096; { host ресурс, не SENS семантика }

procedure Fail(const Why:String);
begin raise ED7TextError.Create('D7-проєкцію відхилено: '+Why) end;

function SingleGlyph(const S:RawByteString):Boolean;
var U:UnicodeString;
begin
  Result:=False;
  if (Length(S)=0) or (Length(S)>4) then Exit;
  U:=UTF8Decode(S);
  { Перевіряємо байти/Unicode без нормалізації чи транслітерації.
    D7 v2 має лише один BMP скаляр на друковану координату. }
  Result:=(Length(U)=1) and (Ord(U[1])>31) and (Ord(U[1])<>127) and
    (Ord(U[1])<$D800) and (RawByteString(UTF8Encode(U))=S);
end;

function SurfaceOf(const Row:TD7Glyph;Mode:TD7Surface):RawByteString;
begin
  if Mode=dsUk then Result:=Row.Uk else Result:=Row.Ukr;
end;

function SourceLiteral(N:TSourceNode):RawByteString;
var I:SizeInt; C:AnsiChar;
begin
  Result:='';
  if N=nil then Fail('немає текстового вузла');
  if N.Kind=skList then begin
    if Length(N.Children)<>0 then Fail('непорожня структурна поверхня');
    Exit; { Нормативне () — відсутній символ, не glyph. }
  end;
  if N.Kind=skAtom then Result:=N.Text
  else if N.Kind=skString then begin
    if (Length(N.Text)<2) or (N.Text[1]<>'"') or
       (N.Text[Length(N.Text)]<>'"') then
      Fail('невірна лапкова D7 поверхня');
    I:=2;
    while I<Length(N.Text) do begin
      C:=N.Text[I];
      if C='\' then begin
        Inc(I);
        if I>=Length(N.Text) then Fail('обірване D7 екранування');
        C:=N.Text[I];
        if not (C in ['\','"']) then
          Fail('непідтверджене D7 екранування');
      end;
      Result:=Result+C;
      Inc(I);
    end;
  end else Fail('невідомий D7 вузол');
  if not SingleGlyph(Result) then Fail('D7 поверхня має бути одним Unicode символом');
end;

function Column(Row:TSourceNode;Index:SizeInt;const Name:RawByteString):TSourceNode;
var C:TSourceNode;
begin
  if (Row=nil) or (Index<1) or (Index>=Length(Row.Children)) then
    Fail('немає обов’язкової колонки D7');
  C:=Row.Children[Index];
  if (C=nil) or (C.Kind<>skList) or (Length(C.Children)<>2) or
     (C.Children[0]=nil) or (C.Children[0].Kind<>skAtom) or
     (C.Children[0].Text<>Name) then
    Fail('змінено порядок чи ім’я колонки D7: '+String(Name));
  Result:=C.Children[1];
end;

procedure ParseD7Map(const Source:RawByteString;out Map:TD7Map);
const Names:array[1..6] of RawByteString=('ук','укр','san','en','LISP','sym');
var Doc:TSourceDocument; Form,Row,N:TSourceNode;
    Candidate:TD7Map; I,J,K,M:SizeInt; Bits:RawByteString;
    V:SizeInt;
begin
  { Керовані UTF-8 рядки: очищати присвоєнням, а не FillChar. }
  for I:=0 to 127 do begin
    Map[I].Uk:='';Map[I].Ukr:='';
    Candidate[I].Uk:='';Candidate[I].Ukr:='';
  end;
  Doc:=nil;
  try
    Doc:=ReadUkrainianSource(Source);
    if (Length(Doc.Forms)<>1) then Fail('потрібна одна pinned таблиця D7');
    Form:=Doc.Forms[0];
    if (Form.Kind<>skList) or (Length(Form.Children)<>129) or
       (Form.Children[0].Kind<>skAtom) or
       (Form.Children[0].Text<>'domain-table-1') then
      Fail('неповна таблиця D7: очікуємо рівно 128 координат');
    for I:=0 to 127 do begin
      Row:=Form.Children[I+1];
      if (Row=nil) or (Row.Kind<>skList) or (Length(Row.Children)<>7) or
         (Row.Children[0]=nil) or (Row.Children[0].Kind<>skAtom) then
        Fail('пошкоджено D7 рядок');
      Bits:=Row.Children[0].Text;
      if Length(Bits)<>7 then Fail('порушено ширину W7');
      V:=0;
      for J:=1 to 7 do begin
        V:=V*2;
        if Bits[J]='1' then Inc(V)
        else if Bits[J]<>'0' then Fail('небінарна координата D7');
      end;
      if V<>I then Fail('дублікат/перестановка/пропуск координати D7');
      for J:=1 to 6 do begin
        N:=Column(Row,J,Names[J]);
        if J=1 then Candidate[I].Uk:=SourceLiteral(N)
        else if J=2 then Candidate[I].Ukr:=SourceLiteral(N)
        else if J=5 then begin
          if (N.Kind<>skList) or (Length(N.Children)<>0) then
            Fail('D7 не має викличних LISP-голів');
        end;
      end;
      if ((I<32) or (I=127)) then begin
        if (Candidate[I].Uk<>'') or (Candidate[I].Ukr<>'') then
          Fail('керувальній D7 координаті надано текст');
      end else if (Candidate[I].Uk='') or (Candidate[I].Ukr='') then
        Fail('друкована D7 координата без української проєкції');
      for K:=0 to I-1 do
        for M:=0 to 1 do begin
          if (M=0) and (Candidate[I].Uk<>'') and
             (Candidate[I].Uk=Candidate[K].Uk) then
            Fail('колізія однакової ук-проєкції');
          if (M=1) and (Candidate[I].Ukr<>'') and
             (Candidate[I].Ukr=Candidate[K].Ukr) then
            Fail('колізія однакової укр-проєкції');
        end;
    end;
    Map:=Candidate; { одна точка публікації після 128 перевірок }
  except
    on E:ED7TextError do raise;
    on E:Exception do Fail('структура pinned D7: '+E.Message);
  finally Doc.Free end;
end;

procedure LoadPinnedD7Map(const RepoRoot:String;out Map:TD7Map);
var Stream:TFileStream; Path:String; Data:RawByteString; I:SizeInt;
begin
  for I:=0 to 127 do begin Map[I].Uk:='';Map[I].Ukr:='' end;
  Path:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
    'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim+
    'domains'+PathDelim+'d7.lisp';
  try
    Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
    try
      if (Stream.Size<100) or (Stream.Size>65536) then
        Fail('некоректний розмір pinned D7 таблиці');
      SetLength(Data,SizeInt(Stream.Size));
      Stream.ReadBuffer(Data[1],Length(Data));
    finally Stream.Free end;
    ParseD7Map(Data,Map);
  except
    on E:ED7TextError do raise;
    on E:Exception do Fail('немає pinned D7: '+E.Message);
  end;
end;

function EncodeD7Text(const Text:RawByteString;const Map:TD7Map;
  Surface:TD7Surface):RawByteString;
var U:UnicodeString; W:TExactWords; I,J,Index:SizeInt;
    Glyph:RawByteString; Found:Boolean;
begin
  Result:='';
  U:=UTF8Decode(Text);
  if (Text='') or (RawByteString(UTF8Encode(U))<>Text) or
     (Length(U)<1) or (Length(U)>MaxTextGlyphs) then
    Fail('неприпустимий UTF-8 текст/межа D7');
  SetLength(W,Length(U));
  for I:=1 to Length(U) do begin
    Glyph:=RawByteString(UTF8Encode(Copy(U,I,1)));
    Found:=False;Index:=-1;
    for J:=32 to 126 do
      if SurfaceOf(Map[J],Surface)=Glyph then begin
        Found:=True;Index:=J;Break;
      end;
    if not Found then Fail('символ не має pinned D7 uk/ukr координати');
    SetLength(W[I-1],7);
    for J:=1 to 7 do
      if (Index and (1 shl (7-J)))<>0 then W[I-1][J]:='1'
      else W[I-1][J]:='0';
  end;
  Result:=EncodeT5M(W);
end;

function DecodeD7Text(const Physical:RawByteString;const Map:TD7Map;
  Surface:TD7Surface):RawByteString;
var W:TExactWords; I,J,Code:SizeInt; S:RawByteString;
begin
  Result:='';
  DecodeT5M(Physical,W);
  if (Length(W)<1) or (Length(W)>MaxTextGlyphs) or
     (EncodeT5M(W)<>Physical) then Fail('неканонічний/надмірний D7 T5M');
  for I:=0 to High(W) do begin
    if Length(W[I])<>7 then Fail('фізичне слово не має точної ширини D7');
    Code:=0;
    for J:=1 to 7 do begin
      Code:=Code*2;
      if W[I][J]='1' then Inc(Code)
      else if W[I][J]<>'0' then Fail('небінарне W7 слово');
    end;
    S:=SurfaceOf(Map[Code],Surface);
    if S='' then Fail('керувальне/непроєктоване D7 слово');
    Result:=Result+S;
  end;
end;

{ П'ять питань: 1) Чому кодпойнт Unicode не є D7 координатою?
  2) Чому «0» як W7 не є D1:0 або числом D12?
  3) Чому лапкові дужки з pinned таблиці — дані, а не D2?
  4) Чому ін'єктивність двох українських поверхонь перевіряємо окремо?
  5) Чому контролі W7, зокрема SYN, відхиляємо без підміни? }
end.
