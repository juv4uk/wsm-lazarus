{ G3 / #803 — незалежний свідок, що внутрішній native handle
  НЕ може бути порожнім успішним значенням. Contract 12.0 незмінний.
  Чому ncClosure не є D1? Хто відповідає за D10 admission?
  Чому ESourceError не можна підмінити пустим T5M?
  Хто володіє AST і тимчасовими native cells після винятку? }
program test_nativeeval_output_guard;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,wsm.nativeeval,wsm.source,wsm.domain,wsm.t5m;

var E:TNativeEvaluator; Checks:SizeInt;

procedure Need(Ok:Boolean;const Reason:String);
begin
  Inc(Checks);
  if not Ok then raise Exception.Create(Reason);
end;

procedure ExpectText(const Source,Value:RawByteString);
var Got:RawByteString;
begin
  Got:=E.EvaluateSource(Source);
  Need(Got=Value,'неправильний результат підтриманої форми');
end;

{ Погана внутрішня форма досягла саме Render, а не була відхилена
  у pinned binder чи на помилці арності. }
procedure RejectInternal(const Source:RawByteString);
var Failed:Boolean;
begin
  Failed:=False;
  try E.EvaluateSource(Source);
  except
    on X:ENativeEvalError do begin
      Need(Pos('внутрішній тип',X.Message)>0,
        'відмова відбулася не на межі native output');
      Failed:=True;
    end;
  end;
  Need(Failed,'внутрішнє native-значення видано як успішний результат');
end;

procedure ExpectPhysicalDomain;
var Doc:TSourceDocument; Keys:TNativeKeyedAtoms;
    Words:TExactWords; Got:RawByteString;
begin
  Doc:=ReadUkrainianSource('так');
  try
    SetLength(Keys,1);
    Keys[0].Node:=Doc.Forms[0];
    Keys[0].Key:=ExactKey('1');
    SetLength(Words,1); Words[0]:='1';
    Got:=E.EvaluateKeyedNodePhysical(Doc.Forms[0],Keys);
    Need(Got=EncodeT5M(Words),'зламано canonical фізичний D1');
  finally Doc.Free; end;
end;

procedure RejectPhysicalClosure;
var Doc:TSourceDocument; Keys:TNativeKeyedAtoms;
    Failed:Boolean;
begin
  { Тут текст — лише borrowed AST. Виклична ідентичність надається
    тільки точним D10 key, а не назвою чи Pascal selector. }
  Doc:=ReadUkrainianSource('(створити-лямбда-замикання () так)');
  try
    SetLength(Keys,1);
    Keys[0].Node:=Doc.Forms[0].Children[0];
    Keys[0].Key:=ExactKey('0100111100');
    Failed:=False;
    try E.EvaluateKeyedNodePhysical(Doc.Forms[0],Keys);
    except
      on X:ENativeEvalError do begin
        Need(Pos('внутрішній тип',X.Message)>0,
          'фізичний writer не відхилив внутрішнє замикання');
        Failed:=True;
      end;
    end;
    Need(Failed,'внутрішнє замикання стало порожнім успішним T5M');
  finally Doc.Free; end;
end;

begin
  Checks:=0;
  E:=TNativeEvaluator.Create('external/sens');
  try
    ExpectText('так','1');
    ExpectText('ні','0');
    ExpectText('()','()');
    RejectInternal('(створити-лямбда-замикання () так)');
    ExpectText('(сполучити так ())','(1)');
    RejectInternal('(сполучити (створити-лямбда-замикання () так) ())');
    ExpectText('ні','0');
    ExpectPhysicalDomain;
    RejectPhysicalClosure;
    { Після невдалого фізичного writer той самий evaluator живий. }
    ExpectText('так','1');
    ExpectPhysicalDomain;
    WriteLn('NATIVEEVAL-OUTPUT-GUARD-PASS checks=',Checks,
      ' closure=REJECTED physical=REJECTED recovery=YES',
      ' Core1=NOT_VERIFIED oracle=NOT_RUN');
  finally E.Free; end;
end.
