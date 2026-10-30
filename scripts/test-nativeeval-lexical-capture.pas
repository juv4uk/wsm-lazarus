{ G3/#803 — свідок захоплення лексичного оточення у D10-замиканні.
  Це не нова мова: exact координати визначає pinned SENS Contract 12.0.
  Усі слова джерела — українська людська проєкція, не canonical .sens.
  FClosureEnvs тримає лише borrowed handle FCells до одного Reset.
  Питання: чому локальний x переживає вихід із зовнішнього виклику?
  Чому caller Env не може затіняти captured x? Як обробляється арність?
  Чому відмова не залишає Env для наступної форми? }
program test_nativeeval_lexical_capture;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.nativeeval,wsm.source;
var E:TNativeEvaluator; Checks:SizeInt;
procedure Need(const OK:Boolean;const Why:String);
begin
  Inc(Checks);
  if not OK then raise Exception.Create(Why);
end;
procedure Expect(const Source,Expected:RawByteString);
var Got:RawByteString;
begin
  Got:=E.EvaluateSource(Source);
  Need(Got=Expected,'порушено lexical capture у '+Source+
    ' результат='+Got+' очікувано='+Expected);
end;
procedure Reject(const Source,Code:RawByteString);
var Failed:Boolean;
begin
  Failed:=False;
  try
    E.EvaluateSource(Source);
  except
    on X:ESourceError do begin
      Failed:=True;
      Need((X.Line>0) and (X.ByteOffset>0) and (X.ByteColumn>0),
        'відмова без фізичної позиції');
      Need(Pos(Code,X.Message)>0,'хибний код відмови: '+X.Message);
    end;
  end;
  Need(Failed,'неправильна форма успішно виконалася');
end;
begin
  Checks:=0;
  E:=TNativeEvaluator.Create('external/sens');
  try
    { Замикання створено всередині виклику: x=так залишається
      доступним навіть тоді, коли зовнішня функція вже повернулась. }
    Expect('(((створити-лямбда-замикання (х) '+
      '(створити-лямбда-замикання (у) х)) так) ні)','1');
    Expect('(((створити-лямбда-замикання (х) '+
      '(створити-лямбда-замикання (у) х)) ні) так)','0');
    { У caller є своє х=ні, але повернене замикання повинно
      пам'ятати лексичне х=так зі свого місця створення. }
    Expect('((створити-лямбда-замикання (х) '+
      '(((створити-лямбда-замикання (х) '+
      '(створити-лямбда-замикання (у) х)) так) ні)) ні)','1');
    { Локальний у затінює захоплений у, а х не підмінюється. }
    Expect('(((створити-лямбда-замикання (у) '+
      '(створити-лямбда-замикання (у) у)) так) ні)','0');
    Reject('(((створити-лямбда-замикання (х) '+
      '(створити-лямбда-замикання (у) х)) так))',
      'ARITY: TOO-FEW-ARGUMENTS');
    Reject('(((створити-лямбда-замикання (х) '+
      '(створити-лямбда-замикання (у) х)) так) ні так)',
      'ARITY: TOO-MANY-ARGUMENTS');
    Expect('((створити-лямбда-замикання (х) х) так)','1');
    Reject('х','unsupported native value domain');
    Expect('((створити-лямбда-замикання (х) х) ні)','0');
    Writeln('NATIVEEVAL-LEXICAL-CAPTURE-PASS checks=',Checks,
      ' returned-closure=YES caller-shadow=ISOLATED',
      ' arity=REJECTED recovery=YES oracle=NOT_RUN',
      ' core1=NOT_VERIFIED physical-sens=NOT_VERIFIED');
  finally
    E.Free;
  end;
end.
