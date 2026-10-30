{ G6.266 — негативи спільного D5/W24 WideIR входу без дублювання законів.
  Читання та exact admission наявні у BuildVerifiedWideELF і D24 lowerer.
  Всі bytes — канонічні T5M від pinned FPC-кодека; без .lisp dispatch.
  1) Чому D12 не можна прийняти як D24?
  2) Чому D5 SUB не обирає D5 ADD?
  3) Чому після помилки незмінний попередній ELF?
  4) Чому D24 переповнення потребує явної відмови? }
program test_widefrontd24_negatives;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.t5m,wsm.numericplane,wsm.irwidefront,
     wsm.irwided24carry,wsm.elfgeometry;
var Root:String; A,B,Small,MaxNum:TExplicitNumeric;
    Good,Before,Image:RawByteString;G:TELFGeometry;
    Negative,Positive:Integer;

function Pack(const Tokens:array of RawByteString):RawByteString;
var Words:TExactWords;I:SizeInt;
begin
  SetLength(Words,Length(Tokens));
  for I:=0 to High(Tokens) do Words[I]:=Tokens[I];
  Result:=EncodeT5M(Words);
end;

procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('СПІЛЬНИЙ-D24-ПРОВАЛ: '+Why);
end;

procedure Reject(const Source:RawByteString;const Tag:String);
var Refused:Boolean;
begin
  Before:=Image;
  Refused:=False;
  try
    Image:=BuildVerifiedWideELF(Source,Root);
  except
    on E:Exception do begin
      Need(E.Message<>'','порожня відмова '+Tag);
      Refused:=True;
    end;
  end;
  Need(Refused,'небезпечну форму прийнято: '+Tag);
  Need(Image=Before,'після відмови змінено ELF: '+Tag);
  Inc(Negative);
end;

procedure Accept(const Source:RawByteString);
var Expected:RawByteString;
begin
  Image:=BuildVerifiedWideELF(Source,Root);
  Expected:=BuildIRWideD24CarryELF(Source,Root);
  Need((Length(Image)>120) and (Image=Expected),
       'спільний та спеціалізований ELF різняться');
  VerifySENSELF64(Image,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Image)) and (G.MachineBytes>0),
       'машинний ELF не пройшов геометрію');
  Inc(Positive);
end;

begin
  Need(ParamCount=1,'потрібен pinned authority root');
  Root:=ParamStr(1);
  Need(DirectoryExists(Root),'відсутній pinned authority');
  A:=ReadNumericPhysical(EncodeNumericDecimal('65535',24),24);
  B:=ReadNumericPhysical(EncodeNumericDecimal('1',24),24);
  Small:=ReadNumericPhysical(EncodeNumericDecimal('1',12),12);
  MaxNum:=ReadNumericPhysical(EncodeNumericDecimal('8388607',24),24);
  Negative:=0;Positive:=0;
  Good:=Pack(['10','01010',A.ExactBits,B.ExactBits,'01']);
  Accept(Good);
  Reject(Pack(['10','01011',A.ExactBits,B.ExactBits,'01']),
         'D5 SUB, не ADD');
  Reject(Pack(['10','11010',A.ExactBits,B.ExactBits,'01']),
         'D5 LESS, не ADD');
  Reject(Pack(['10','01010',A.ExactBits,'01']),
         'бракує правого операнда');
  Reject(Pack(['10','01010',A.ExactBits,B.ExactBits,
               B.ExactBits,'01']),'зайвий операнд');
  Reject(Pack(['10','01010',Small.ExactBits,B.ExactBits,'01']),
         'D12 зліва');
  Reject(Pack(['10','01010',A.ExactBits,Small.ExactBits,'01']),
         'D12 справа');
  Reject(Pack(['10','01010','1',B.ExactBits,'01']),
         'D1 замість D24');
  Reject(Pack(['10','01010',A.ExactBits,B.ExactBits,'01','1']),
         'другий D2 корінь');
  Reject(Pack(['10','01010',A.ExactBits,B.ExactBits]),
         'незакрита D2 форма');
  Reject(#$FF,'зіпсований T5M');
  Reject('','порожній фізичний файл');
  Reject(Pack(['10','01010',MaxNum.ExactBits,B.ExactBits,'01']),
         'D24 overflow у D48');
  Need(Negative=12,'не збережено всі дванадцять відмов');
  Accept(Good);
  Need((Positive=2) and (Negative=12),
       'успішне відновлення після відмов не доведене');
  WriteLn('WIDEFRONT-D24-PAS-PASS positive=2 negative=12 recovery=1');
end.
