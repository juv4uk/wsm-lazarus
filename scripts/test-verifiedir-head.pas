{ G6.229 — точний фізичний компіляторний VerifiedIR без локального
  реєстру законів і без текстового dispatch. Джерело координат —
  pinned external/sens; тестуємо структуру, НЕ мовну викличність. }
program test_verifiedir_head;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.t5m,wsm.verifiedir,wsm.domain;

function Pack(const Tokens:array of RawByteString):RawByteString;
var W:TExactWords;I:SizeInt;
begin
  SetLength(W,Length(Tokens));
  for I:=0 to High(Tokens) do W[I]:=Tokens[I];
  Result:=EncodeT5M(W);
end;

procedure Need(Condition:Boolean;const Why:RawByteString);
begin
  if not Condition then raise Exception.Create(String(Why));
end;

var
  Root:RawByteString;
  Good:RawByteString;
  Passed,Rejected,Recovered:SizeInt;

{ Власник контексту — один виклик. Повернені dynamic arrays у полях
  позичені, після Ctx.Free недоступні. 1) Чому pinned D3:101 ще
  не означає доказ виконання? 2) Чому exact width важливий? }
procedure Positive;
var Ctx:TVerifiedIR;
begin
  Ctx:=TVerifiedIR.Create(Good,Root);
  try
    Need(Ctx.IsValid,'позитивний verified IR невалідний');
    Need(Ctx.CanonicalT5M=Good,'відмінні T5M байти');
    Need((Ctx.HeadWidth=3) and (Ctx.HeadBits='101'),
      'неправильна точна голова D3:101');
    Need(Length(Ctx.Exact)=5,'втрачені структурні фізичні слова');
    Need((Length(Ctx.Bound)=3) and (Ctx.Bound[0].WordIndex=2),
      'неповний фізичний binder');
    Need((Ctx.Bound[0].Key.Width=3) and
      (KeyBits(Ctx.Bound[0].Key)='101') and
      (not Ctx.Bound[0].IsEmpty),'невірна pinned адреса голови');
    Inc(Passed);
  finally Ctx.Free end;
end;

{ У разі відмови Create не повертає жодного часткового контексту.
  Message перевіряємо на непорожність, але не замінюємо діагностику
  текстовим oracle. Після кожного негативу — повний повторний успіх. }
procedure Negative(const LabelText,Physical:RawByteString);
var Ctx:TVerifiedIR;Failed:Boolean;Details:String;
begin
  Ctx:=nil;Failed:=False;Details:='';
  try
    try
      Ctx:=TVerifiedIR.Create(Physical,Root);
    except
      on E:Exception do begin
        Failed:=True;
        Details:=E.Message;
      end;
    end;
    Need(Failed,'хибно прийнято '+LabelText);
    Need(Details<>'','немає діагностики для '+LabelText);
    Inc(Rejected);
  finally Ctx.Free end;
  Positive;
  Inc(Recovered);
end;

begin
  if ParamCount<>1 then Halt(64);
  Root:=RawByteString(ParamStr(1));
  { Лише T5M фізичні слова, .lisp проєкція не є оракулом. }
  Good:=Pack(['10','101','0','0','01']);
  Passed:=0;Rejected:=0;Recovered:=0;
  Positive;
  Negative('nested-head',Pack(['10','10','0','01','1','01']));
  Negative('empty-head-D3',Pack(['10','000','0','01']));
  Negative('empty-application',Pack(['10','01']));
  Negative('atom-root',Pack(['101']));
  Negative('two-roots',Pack(['10','101','0','0','01','1']));
  Negative('unclosed',Pack(['10','101','0','0']));
  Negative('bad-T5M',#$FF);
  Negative('zero-bytes','');
  Need((Passed=9) and (Rejected=8) and (Recovered=8),
    'неповний набір відновлення');
  WriteLn('VERIFIED-IRHEAD-PASS positives=',Passed,
    ' negatives=',Rejected,' recovered=',Recovered,
    ' physical=T5M pinned=head-only oracle=NOT-RUN');
end.
