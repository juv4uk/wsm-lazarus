{ G6.82 — вузьке машинне lowering D6:001111 до перевіреного D12 SUB.
  Авторитет: pinned SENS Contract 12, d6.lisp та current-domain-x86-64.lisp.
  Жодна назва/проєкція не є semantic dispatch; це exact координата.
  Вхід: owned/borrowed packed T5M, один D2:10 (D6:001111 D12) D2:01.
  Вихід: власні байти ELF64 PIE, machine SUB, T5M у stdout при запуску.
  D12 позитивний 1..2047 — вузька межа pinned CPU fast-path. }
unit wsm.ird6sub1;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRD6Sub1Error=class(Exception);
function BuildD6Sub1ELF(const FormPhysical,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.t5m,wsm.d2source,wsm.bind,wsm.domain,
     wsm.numericplane,wsm.elfd12sub;

procedure Need(Ok:Boolean;const MessageText:String);
begin
  if not Ok then raise EIRD6Sub1Error.Create(MessageText);
end;

{ FormPhysical — запозичений повний T5M буфер, AuthorityRoot —
  шлях до вже pinned повних D1..D10 таблиць; вони стають локальними
  керованими масивами. Жодне число не конвертується через decimal.
  1) Чому потрібен D2, а не підрахунок байтів?
  2) Чому ідентичність W6 перевіряється окремо від W12?
  3) Чому назва «відняти-1» не є ключем виконання?
  4) Де перевіряється 1..2047? 5) Хто звільняє дерево D2? }
function BuildD6Sub1ELF(const FormPhysical,AuthorityRoot:RawByteString):RawByteString;
var
  Words,AtomWords:TExactWords;
  Doc:TD2Document;
  Tables:TDomainSet;
  Row:TDomainRow;
  OperatorNode,ArgumentNode:TD2Node;
  K:TDomainKey;
  AtomPhysical,OnePhysical:RawByteString;
  N:TExplicitNumeric;
begin
  Result:='';
  Need((Length(FormPhysical)>0) and (Length(FormPhysical)<=128),
    'порожній або завеликий фізичний D6 вираз');
  DecodeT5M(FormPhysical,Words);
  Need(EncodeT5M(Words)=FormPhysical,
    'неканонічне фізичне T5M кодування');
  Doc:=ParseD2WordsWide(Words);
  try
    Need(Length(Doc.Roots)=1,'потрібна рівно одна D2 форма');
    Need(Doc.Roots[0].Kind=dkList,'корінь має бути D2 списком');
    Need(Length(Doc.Roots[0].Children)=2,
      'D6 відняти-1 приймає рівно один аргумент');
    OperatorNode:=Doc.Roots[0].Children[0];
    ArgumentNode:=Doc.Roots[0].Children[1];
    Need((OperatorNode.Kind=dkIdentity) and
         (OperatorNode.Width=6) and
         (OperatorNode.Bits='001111'),
         'очікується exact D6:001111');
    Need((ArgumentNode.Kind=dkIdentity) and
         (ArgumentNode.Width=12),
         'очікується саме атом D12, не D1/D7/D24');

    { Таблиця лише підтверджує фізичну координату в pinned домені.
      Це НЕ новий реєстр законів і НЕ dispatch за проєкційним іменем. }
    LoadPinnedDomains(AuthorityRoot,Tables);
    K:=ExactKey(OperatorNode.Bits);
    Need(DomainRowByKey(Tables[6],K,Row) and
         SameKey(Row.Key,ExactKey('001111')),
         'D6:001111 відсутній у pinned таблиці');

    SetLength(AtomWords,1);
    AtomWords[0]:=ArgumentNode.Bits;
    AtomPhysical:=EncodeT5M(AtomWords);
    N:=ReadNumericPhysical(AtomPhysical,12);
    Need((N.ExactBits[1]='0') and
         (N.ExactBits<>'000000000000'),
         'CPU fast-path D6 відняти-1 дозволено лише D12 >= 1');
    AtomWords[0]:='000000000001';
    OnePhysical:=EncodeT5M(AtomWords);
    { Машинний SUB, promotion і фізичний T5M output — тільки вже
      перевірений backend; тут немає precomputed machine-result. }
    Result:=BuildD12SubELF(AtomPhysical,OnePhysical);
  finally
    Doc.Free;
  end;
end;
end.
