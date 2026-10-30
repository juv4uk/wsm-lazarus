{ G3/#803: реальне застосування вже створеного D10 closure, без LABEL.
  Формат вводу — українська людиночитана проєкція. Її exact keys
  завантажуються чинним binder з pinned external/sens, а не із назв.
  Результат — D1 через наявний renderer; FCells/FNodes живуть в Eval.
  Питання: чому D10 має width=10? Що зберігає pairlis?
  Де перевіряється арність? Чому після винятку немає stale Env?
  Чому цей тест не доводить виконання всього Core1? }
program test_nativeeval_computed_closure;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.nativeeval,wsm.source,wsm.domain,wsm.t5m;

var E:TNativeEvaluator; Count:Integer;

procedure Need(OK:Boolean;const Why:String);
begin
  Inc(Count);
  if not OK then raise Exception.Create(Why);
end;

procedure Expect(const S,Want:RawByteString);
var Got:RawByteString;
begin
  Got:=E.EvaluateSource(S);
  Need(Got=Want,'неправильне обчислення: '+S+' actual='+Got);
end;

procedure Reject(const S,Why:RawByteString);
var Failed:Boolean;
begin
  Failed:=False;
  try
    E.EvaluateSource(S);
  except
    on X:ENativeEvalError do begin
      Failed:=True;
      Need((X.Line>0) and (X.ByteOffset>0) and (X.ByteColumn>0),
        'відмова втратила позицію форми');
      if Why<>'' then
        Need(Pos(Why,X.Message)>0,
          'хибна причина відмови: '+X.Message);
    end;
  end;
  Need(Failed,'помилковий виклик прийнято');
end;

procedure CheckPhysicalKeyed;
var Doc:TSourceDocument; Keys:TNativeKeyedAtoms;
    Words:TExactWords; Got:RawByteString;
begin
  { Це свідок exact-keyed AST→packed T5M, НЕ повний reader .sens.
    Обидві координати borrowed вузлів чинні тільки до Doc.Free. }
  Doc:=ReadUkrainianSource('((створити-лямбда-замикання (х) х) так)');
  try
    Need(Length(Doc.Forms)=1,'бракує форми');
    SetLength(Keys,2);
    Keys[0].Node:=Doc.Forms[0].Children[0].Children[0];
    Keys[0].Key:=ExactKey('0100111100');
    Keys[1].Node:=Doc.Forms[0].Children[1];
    Keys[1].Key:=ExactKey('1');
    SetLength(Words,1); Words[0]:='1';
    Got:=E.EvaluateKeyedNodePhysical(Doc.Forms[0],Keys);
    Need(Got=EncodeT5M(Words),'не збіглися фізичні байти результату D1');
  finally
    Doc.Free;
  end;
end;

begin
  Count:=0;
  E:=TNativeEvaluator.Create('external/sens');
  try
    Expect('((створити-лямбда-замикання (х) х) так)','1');
    Expect('((створити-лямбда-замикання (лів прав) прав) ні так)','1');
    Expect('((створити-лямбда-замикання (лів прав) лів) ні так)','0');
    Expect('((створити-лямбда-замикання (х) так) ні)','1');
    Reject('((створити-лямбда-замикання (х) х))',
      'ARITY: TOO-FEW-ARGUMENTS');
    Reject('((створити-лямбда-замикання (х) х) так ні)',
      'ARITY: TOO-MANY-ARGUMENTS');
    Reject('((як-є (так)) ні)','обчислена голова');
    Reject('((створити-лямбда-замикання (х) відсутнє) так)',
      'unknown native binding');
    Expect('((створити-лямбда-замикання (х) х) ні)','0');
    Reject('х','unsupported native value domain'); { Env поза викликом порожнє. }
    CheckPhysicalKeyed;
    Expect('так','1'); { немає stale стану після keyed виклику. }
    Writeln('NATIVEEVAL-COMPUTED-CLOSURE-PASS checks=',Count,
      ' closure=EXECUTED env=LEXICAL arity=REJECTED',
      ' keyed-t5m=EXACT core1=NOT_VERIFIED oracle=NOT_RUN');
  finally E.Free; end;
end.
