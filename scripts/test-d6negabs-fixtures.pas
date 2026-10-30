{ G6.181 — фізичні канонічні T5M свідки для вкладеного D6.
  Таблиця очікувань — лише механічний тест; незалежний pinned SENS REPL
  у workflow має підтвердити семантику кожного позитивного випадку. }
program test_d6negabs_fixtures;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.t5m,wsm.numericplane;
var Folder:String;Cases:TStringList;Count:SizeInt;

procedure Need(OK:Boolean;const Why:String);
begin if not OK then raise Exception.Create('Д6-ЗНАК-МОДУЛЬ-СВІДОК: '+Why) end;

{ Filename borrowed host path, Data owned binary bytes; FileStream owned.
  1) Чому використовуємо WriteBuffer, а не WriteLn?
  2) Де зберігаються exact bits/leading zeros?
  3) Як гарантовано закриття FD при помилці? }
procedure Save(const Name:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(Folder+'/'+Name,fmCreate);
  try if Length(Data)>0 then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

{ Tokens — exact bit words incl. D2 open/close; all physical words
  borrowed FPC managed strings; Result owned canonical T5M. }
function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;

{ Numeric helper checks exact W12 identity; projection is never
  used as source and the numeric domain is explicitly D12. }
function D12Bits(const Decimal:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,12),12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12),
       'немає точного signed D12');
  Result:=N.ExactBits;
end;

{ Program W12 atom => nested D6:010011(D6:010010 W12) physical source.
  No Pascal evaluation of the nested SENS expression. }
function Form(const ExactBits:RawByteString):RawByteString;
begin
  Result:=Pack(['10','010011','10','010010',ExactBits,'01','01']);
end;

function D24Bits(const Decimal:RawByteString):RawByteString;
var N:TExplicitNumeric;
begin
  N:=ReadNumericPhysical(EncodeNumericDecimal(Decimal,24),24);
  Need((N.DomainWidth=24) and (Length(N.ExactBits)=24),'немає точного signed D24');
  Result:=N.ExactBits;
end;

procedure Positive(const LabelText,Decimal,Wanted:RawByteString;
                   Width:SizeInt);
begin
  Save(String(LabelText)+'.sens',Form(D12Bits(Decimal)));
  Save(String(LabelText)+'.expected.sens',EncodeNumericDecimal(Wanted,Width));
  Cases.Add(String(LabelText)+#9+String(Decimal)+#9+
            String(Wanted)+#9+IntToStr(Width));
  Inc(Count);
end;
var A,B:RawByteString;
begin
  try
    Need(ParamCount=1,'потрібен каталог свідків');
    Folder:=ParamStr(1);
    Need(ForceDirectories(Folder),'не вдалося створити каталог');
    Cases:=TStringList.Create;
    try
      Count:=0;
      Positive('01','0','0',12);
      Positive('02','1','1',12);
      Positive('03','-1','1',12);
      Positive('04','17','17',12);
      Positive('05','-17','17',12);
      Positive('06','2047','2047',12);
      Positive('07','-2047','2047',12);
      Positive('08','-2048','2048',24);
      Positive('09','1024','1024',12);
      Positive('10','-1024','1024',12);
      Positive('11','-2','2',12);
      Positive('12','2','2',12);
      Positive('13','-1234','1234',12);
      Positive('14','1234','1234',12);
      Need(Count=14,'має бути 14 точних свідків');
      A:=D12Bits('0');B:=D12Bits('1');
      Save('other-outer.sens',Pack(['10','010010','10','010010',A,'01','01']));
      Save('other-inner.sens',Pack(['10','010011','10','010011',A,'01','01']));
      Save('swapped.sens',Pack(['10','010010','10','010011',A,'01','01']));
      Save('bare.sens',Pack(['10','010011',A,'01']));
      Save('d24.sens',Pack(['10','010011','10','010010',
                           D24Bits('1'),
                           '01','01']));
      Save('d1.sens',Pack(['10','010011','10','010010','1','01','01']));
      Save('d3.sens',Pack(['10','010011','10','010010','000','01','01']));
      Save('extra.sens',Pack(['10','010011','10','010010',A,'01',B,'01']));
      Save('missing.sens',Pack(['10','010011','10','010010','01','01']));
      Save('unclosed.sens',Pack(['10','010011','10','010010',A,'01']));
      Save('two-roots.sens',Pack(['10','010011','10','010010',A,'01','01',B]));
      Save('root-atom.sens',Pack([A]));
      Save('dotted.sens',Pack(['10','010011','10','010010','11',A,'01','01']));
      Save('bad-t5m.sens',#$FF);
      Save('empty.sens','');
      Save('fake.lisp',Form(A));
      Cases.SaveToFile(Folder+'/cases.tsv');
      WriteLn('Д6-ЗНАК-МОДУЛЬ-СВІДКИ-ГОТОВО позитивів=14 негативів=16');
    finally Cases.Free end;
  except on E:Exception do begin
    WriteLn(StdErr,'Д6-ЗНАК-МОДУЛЬ-СВІДКИ-ПРОВАЛ: ',E.Message);
    Halt(1)
  end end;
end.
