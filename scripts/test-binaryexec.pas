program test_binaryexec;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.binaryexec;
var E:TBinaryExecutor; Checks:SizeInt;
procedure Require(Ok:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Ok then begin WriteLn(StdErr,'ДВІЙКОВИЙ-ТЕСТ-ПОМИЛКА ',Why); Halt(1); end;
end;
function WordsOf(const Data:array of RawByteString):TExactWords;
var I:SizeInt;
begin
  SetLength(Result,Length(Data));
  for I:=0 to High(Data) do Result[I]:=Data[I];
end;
procedure Expect(const Data:array of RawByteString;
  const Expected:RawByteString);
var Actual:RawByteString;
begin
  Actual:=E.ExecutePhysical(EncodeT5M(WordsOf(Data)));
  Require(Actual=Expected,'неправильний результат '+String(Actual));
end;
procedure Reject(const Data:array of RawByteString;
  ExpectedIndex:SizeInt);
var Failed:Boolean;
begin
  Failed:=False;
  try E.ExecutePhysical(EncodeT5M(WordsOf(Data)));
  except on X:EBinaryExecutionError do begin
    Failed:=True;
    if ExpectedIndex>=0 then
      Require(X.WordIndex=ExpectedIndex,'неправильний індекс слова');
  end; end;
  Require(Failed,'непідтверджена форма не була відхилена');
end;
procedure WriteBinary(const Name:String;
  const Data:array of RawByteString);
var F:TFileStream; B:RawByteString;
begin
  B:=EncodeT5M(WordsOf(Data));
  F:=TFileStream.Create(Name,fmCreate);
  try F.WriteBuffer(B[1],Length(B));
  finally F.Free; end;
end;
var Failed:Boolean;
begin
  Checks:=0;
  E:=TBinaryExecutor.Create('external/sens');
  try
    Expect(['1'],'1');
    Expect(['0'],'0');
    Expect(['000'],'()');
    Expect(['10','01'],'()');
    Expect(['10','111','1','000','01'],'(1)');
    Expect(['10','111','1','0','01'],'(1 . 0)');
    Expect(['10','100','10','111','0','000','01','01'],'0');
    Expect(['10','011','10','111','1','000','01','01'],'()');
    Expect(['10','010','10','111','1','000','01','01'],'0');
    Expect(['10','010','000','01'],'1');
    Reject(['10','001','000','01'],2); { D3 quote }
    Reject(['10','111','1','11','0','01'],1); { dotted }
    Reject(['10','110','1','01'],1); { відсутній native D3 cond }
    Reject(['1111111'],1); { D7 без непідтвердженого dispatch }
    Reject(['111111111'],1); { D9 }
    Reject(['1','0'],2); { дві форми }
    Reject(['00'],1); { немає форм }
    Reject(['01'],1); { D2 close }
    Reject(['10','1'],3); { D2 не закрито }
    Reject(['10','111','1','01'],1); { arity }
    Failed:=False;
    try E.ExecutePhysical(#243);
    except on X:EBinaryExecutionError do begin
      Failed:=True; Require(X.WordIndex=0,'зіпсований T5M має index=0');
    end; end;
    Require(Failed,'пошкоджений байт T5M допущено');
    Failed:=False;
    try E.ExecutePhysical(#242);
    except on X:EBinaryExecutionError do Failed:=True; end;
    Require(Failed,'пошкоджений padding T5M допущено');
    WriteBinary('build/m0.2/binaryexec-valid.sens',
      ['10','111','1','000','01']);
    WriteBinary('build/m0.2/binaryexec-invalid.sens',
      ['10','001','000','01']);
  finally E.Free; end;
  WriteLn('ДВІЙКОВЕ-ВИКОНАННЯ-ОК перевірок=',Checks,
    ' фізичний=T5M структура=D2 підмножина=D1/D3 цитата=БЛОК',
    ' Core4=НЕ_ВИКОНУЄТЬСЯ');
end.
