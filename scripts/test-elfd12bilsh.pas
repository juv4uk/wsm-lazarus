{ G6.78 — окремі canonical фізичні D12 свідки знакового порівняння.
  Оголошені очікувані D1 відповіді — лише тестові вектори, не
  реалізація SENS predicate. Єдиний незалежний oracle — upstream REPL.
  Усі .sens файли створює чинний точний D12/T5M кодек. }
program test_elfd12bilsh;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.t5m;
var Folder:String;Count:SizeInt;Words:TExactWords;


{ Український CI-текст пишемо ЯВНИМИ UTF-8 байтами; FPC WriteLn
  може залежати від locale/кодового аркуша при перенаправленні pipe.
  Фізичні .sens байти залишаються незалежними від цього host-виводу. }
procedure RawLine(const Text:UnicodeString;UseErr:Boolean);
var B:RawByteString;F:THandleStream;
begin
  B:=RawByteString(UTF8Encode(Text))+#10;
  if UseErr then F:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else F:=THandleStream.Create(TextRec(Output).Handle);
  try F.WriteBuffer(B[1],Length(B))
  finally F.Free end;
end;

procedure Save(const FileName:String;const Data:RawByteString);
var F:TFileStream;
begin
  F:=TFileStream.Create(IncludeTrailingPathDelimiter(Folder)+FileName,fmCreate);
  try if Data<>'' then F.WriteBuffer(Data[1],Length(Data))
  finally F.Free end;
end;

function D1(const B:RawByteString):RawByteString;
var W:TExactWords;
begin
  SetLength(W,1);W[0]:=B;
  Result:=EncodeT5M(W);
end;

procedure CaseOf(const Name,L,R:RawByteString;Expected:Boolean);
var P:RawByteString;
begin
  Save(String(Name)+'-l.sens',EncodeNumericDecimal(L,12));
  Save(String(Name)+'-r.sens',EncodeNumericDecimal(R,12));
  if Expected then begin
    P:='1';Save(String(Name)+'-expected.sens',D1(P));
    RawLine(UnicodeString(Name)+#9+UnicodeString(L)+#9+
      UnicodeString(R)+#9+'ТАК',False);
  end else begin
    P:='0';Save(String(Name)+'-expected.sens',D1(P));
    RawLine(UnicodeString(Name)+#9+UnicodeString(L)+#9+
      UnicodeString(R)+#9+'НІ',False);
  end;
  Inc(Count);
end;

begin
  if ParamCount<>1 then Halt(64);
  Folder:=ParamStr(1);
  if not ForceDirectories(Folder) then Halt(2);
  Count:=0;
  CaseOf('01','-2048','-2048',False);
  CaseOf('02','-2048','2047',False);
  CaseOf('03','2047','-2048',True);
  CaseOf('04','0','-1',True);
  CaseOf('05','-1','0',False);
  CaseOf('06','3','2',True);
  CaseOf('07','2','3',False);
  CaseOf('08','7','7',False);
  CaseOf('09','-1024','-1500',True);
  CaseOf('10','-1024','-1000',False);
  CaseOf('11','2047','2046',True);
  CaseOf('12','2046','2047',False);
  Save('bad24.sens',EncodeNumericDecimal('1',24));
  Save('bad1.sens',D1('1'));
  SetLength(Words,1);Words[0]:='0010110';Save('bad7.sens',EncodeT5M(Words));
  Save('corrupt.sens',#$FF);
  Save('empty.sens','');
  if Count<>12 then Halt(2);
  RawLine('ЕЛФ-Д12-БІЛЬШЕ-СВІДКИ-ГОТОВО пар='+IntToStr(Count)+
    ' негативів=5',True);
end.
