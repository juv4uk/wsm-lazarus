{ G2.26 — pinned 2046 рядків D1..D10; не мовний oracle. }
program test_projectioncatalog;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.projectioncatalog;
var Catalog:TProjectionCatalog; Src,Mutated:RawByteString;
    F:TFileStream; Root:String; D,I,Good,Bad:SizeInt;
    Rows:TProjectionRows;

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Require(C:Boolean;const Why:String);
begin if not C then raise Exception.Create('ПРОЄКЦІЇ-ПОМИЛКА: '+Why) end;
procedure Rejected(const Data:RawByteString;const Why:String);
var WasBad:Boolean; Partial:TProjectionRows;
begin
  WasBad:=False;SetLength(Partial,1);Partial[0].Bits:='OLD';
  try Partial:=ParseProjectionTable(Data,3)
  except on E:EProjectionCatalogError do WasBad:=True end;
  Require(WasBad,Why);
  Require((Length(Partial)=1) and (Partial[0].Bits='OLD'),
    'відмова переписала caller snapshot: '+Why);
  Inc(Bad);
end;
begin
  if ParamCount<>1 then begin WriteLn(StdErr,'потрібен корінь репозиторію');Halt(64) end;
  Root:=ParamStr(1);
  Good:=0;Bad:=0;
  LoadProjectionCatalog(Root,Catalog);
  for D:=1 to 10 do begin
    Require(Length(Catalog[D])=(1 shl D),'немає повного домену '+IntToStr(D));
    for I:=0 to High(Catalog[D]) do begin
      Require(Length(Catalog[D][I].Bits)=D,'не збережено exact-width');
      Inc(Good);
    end;
  end;
  Require(Good=2046,'повний D1..D10 має 2046 точних координат');
  Require(Catalog[1][0].Names[psUk]=UA('ні'),'D1:0 українська');
  Require(Catalog[1][0].Names[psEn]='no','D1:0 англійська');
  Require(Catalog[1][0].Names[psLisp]='NIL','LISP лише історичний display');
  Require(Catalog[2][2].Names[psSan]=UA('udghāṭana'),'D2 san');
  Require(Catalog[3][2].Bits='010','D3 exact 010');
  Require(Catalog[3][2].Names[psUk]=UA('атом?'),'D3:010 ук');
  Require(Catalog[3][2].Names[psUkr]=UA('атом?'),'D3:010 укр');
  Require(Catalog[3][2].Names[psSan]=UA('aṇu'),'D3:010 санскрит');
  Require(Catalog[3][2].Names[psEn]='atom?','D3:010 English');
  Require(Catalog[3][2].Names[psLisp]='ATOM','D3:010 LISP тільки довідка');
  Require(Catalog[3][2].Names[psSym]='.?','D3:010 символ');
  Require(Catalog[4][5].Names[psUk]=UA('порожнє?'),'D4:0101 коротка');
  Require(Catalog[4][5].Names[psUkr]=UA('порожній?'),'D4:0101 повна');
  Require(Catalog[7][48].Bits='0110000','D7 цифра має 7 біт');
  Require(Catalog[7][48].Names[psUk]='0','D7 цифра текстові дані');
  Require(Catalog[7][40].Names[psUk]='(','D7 дужка текстові дані');
  Require(Catalog[7][41].Names[psUk]=')','D7 дужка текстові дані');
  Require(Catalog[7][22].Names[psUk]='','SYN керувальний');
  Require(Catalog[7][22].Names[psLisp]='','D7 без LISP викличності');
  Require(Catalog[10][0].Bits='0000000000','D10 не втратив 10 нулів');
  Require(Catalog[10][1023].Bits='1111111111','D10 повний');
  Require(ProjectionColumnName(psSan)='san','точна назва san');
  Require(ProjectionColumnName(psLisp)='LISP','історична колонка');

  F:=TFileStream.Create(Root+'/external/sens/lib/domains/d3.lisp',
    fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Src,SizeInt(F.Size));F.ReadBuffer(Src[1],Length(Src));
  finally F.Free end;
  Rejected('','порожній текст');
  Rejected(Copy(Src,1,Length(Src)-10),'усічена таблиця');
  Rejected(StringReplace(Src,UA('(010 (ук атом?)'),UA('(011 (ук атом?)'),[]),
    'повторна точна координата');
  Rejected(StringReplace(Src,UA('(010 (ук атом?)'),UA('(0101 (ук атом?)'),[]),
    'ширина і провідні нулі');
  Rejected(StringReplace(Src,UA('(san aṇu)'),UA('(sa aṇu)'),[]),
    'san не можна міняти на sa');
  Rejected(StringReplace(Src,'(LISP ATOM)','(english ATOM)',[]),
    'не виводимо історичний LISP');
  Rejected(StringReplace(Src,UA('(ук атом?)'),UA('(ук (неочікуване))'),[]),
    'невідома складена поверхня');
  Rejected(StringReplace(Src,'(sym .?)','(sym "неекрановане \\q")',[]),
    'заборонений escape');
  Rejected(Src+#$FF,'неканонічний UTF-8');

  { Відмови не можна замовчувати як порожній повний каталог. }
  try
    Rows:=LoadProjectionTable(Root,11);
    Require(False,'D11 поза цим переглядачем')
  except on E:EProjectionCatalogError do Inc(Bad) end;
  Require(Bad=10,'не пройдено всі негативні перевірки');
  WriteLn('ПРОЄКЦІЇ-D1-D10-ГАРАЗД rows=',Good,
    ' surfaces=ук/укр/san/en/LISP/sym negatives=',Bad,
    ' D7=дані D12=не-число');
end.
