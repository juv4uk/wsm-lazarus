program test_nativeeval;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, wsm.nativeeval, wsm.source;
var E:TNativeEvaluator; Root, Got:RawByteString; Checks:Integer;
procedure Check(const Good:Boolean; const Why:String);
begin
  Inc(Checks);
  if not Good then begin WriteLn(StdErr,'NATIVEEVAL-FAIL ',Why); Halt(1); end;
end;
procedure Expect(const Source,Expected:RawByteString);
begin
  Got:=E.EvaluateSource(Source);
  Check(Got=Expected,'source='+Source+' expected='+Expected+' actual='+Got);
end;
procedure Reject(const Source:RawByteString);
var Failed:Boolean;
begin
  Failed:=False;
  try E.EvaluateSource(Source);
  except on X:ESourceError do begin
    Check((X.Line>0) and (X.ByteOffset>0) and (X.ByteColumn>0),'missing position');
    Failed:=True;
  end; end;
  Check(Failed,'accepted '+Source);
end;
begin
  Root:='external/sens';
  if ParamCount>=1 then Root:=ParamStr(1);
  E:=TNativeEvaluator.Create(Root);
  try
    if (ParamCount=3) and (ParamStr(2)='--eval') then begin
      try WriteLn(E.EvaluateSource(ParamStr(3)));
      except on X:ESourceError do begin
        WriteLn(StdErr,'NATIVEEVAL-ERROR line=',X.Line,' column=',X.ByteColumn,
          ' byte=',X.ByteOffset,' ',X.Message); ExitCode:=2;
      end; end;
      Exit;
    end;
    Expect('(як-є кіт)','(1110010 1110011 1101110)');
    Expect('()','()'); Expect('так','1'); Expect('ні','0');
    Expect('(як-є ())','()'); Expect('(як-є (()))','(())');
    Expect('(як-є так)','(1101110 1100110 1110010)');
    Expect('(перше (як-є (кіт пес)))','(1110010 1110011 1101110)');
    Expect('(решта (як-є (кіт пес)))','((1100111 1110100 1100011))');
    Expect('(сполучити так ())','(1)');
    Expect('(сполучити так ні)','(1 . 0)');
    Expect('(перше (сполучити ні ()))','0');
    Expect('(решта (сполучити так ()))','()');
    Expect('(атом? ())','1'); Expect('(атом? ні)','1');
    Expect('(атом? (як-є (кіт)))','0');
    Expect('(атом? (перше (сполучити ні ())))','1');
    Expect('(атом? (сполучити так ()))','0');
    Reject('(перше ())'); Reject('(решта ні)');
    Reject('(сполучити так)'); Reject('(як-є)'); Reject('(атом? так ні)');
    Reject('(car ())'); Reject('(так ())'); Reject('невідома-змінна');
    Expect('(за-умовою (так так))','1');
    Reject('(як-є (а . б))'); Reject('(як-є "кіт")');
    Reject('(як-є ''кіт)'); Reject('(як-є 123)');
    Reject('так ні'); Reject(''); Reject('(перше');
    Expect('(сполучити ні ())','(0)');
  finally E.Free; end;
  E:=TNativeEvaluator.Create(Root,4,64);
  try
    Reject('(як-є кіт)');
    Expect('(сполучити так ())','(1)');
    Reject('(перше ())');
    Expect('ні','0');
  finally E.Free; end;
  E:=TNativeEvaluator.Create(Root,64,2);
  try Reject('(сполучити так ())'); finally E.Free; end;
  E:=TNativeEvaluator.Create(Root,64,64,2);
  try Reject('(як-є (((()))))'); finally E.Free; end;
  WriteLn('NATIVEEVAL-OK checks=',Checks,
    ' cell-bytes=',SizeOf(TNativeCell),' handle-bytes=',SizeOf(SizeInt),
    ' D1=exact D3=bounded D7=pinned negative=reject Core4=NOT_EXECUTED');
end.
