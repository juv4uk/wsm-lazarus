program test_bind;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.bind;
var T:TDomainSet; K:TDomainKey; Row:TDomainRow;
    Raised:Boolean; D,I,Count:Integer;
procedure Expect(B:Boolean; const Why:String);
begin if not B then begin WriteLn(StdErr,'BIND-FAIL ',Why); Halt(1); end; end;
begin
  LoadPinnedDomains('external/sens',T);
  Count:=0;
  for D:=FirstDomain to LastDomain do begin
    Expect(Length(T[D])=(1 shl D),'pinned domain incomplete');
    for I:=0 to High(T[D]) do begin
      Expect(T[D][I].Key.Width=D,'domain width mismatch');
      Expect(T[D][I].Key.Bits=I,'domain coordinate not ordered');
      if T[D][I].Ukrainian='' then Continue;
      K:=BindUkrainian(T,T[D][I].Ukrainian);
      Expect(SameKey(K,T[D][I].Key),'global Ukrainian lookup not invertible');
      K:=BindUkrainianInDomain(T,T[D][I].Ukrainian,D);
      Expect(SameKey(K,T[D][I].Key),'scoped Ukrainian lookup not invertible');
      Expect(DomainRowByKey(T[D],K,Row),'coordinate reverse lookup missing');
      Expect(Row.Ukrainian=T[D][I].Ukrainian,'coordinate reverse projection mismatch');
      Inc(Count);
    end;
  end;
  K:=BindUkrainian(T,'так');
  Expect(SameKey(K,ExactKey('1')),'D1 yes');
  K:=BindUkrainian(T,'відкрити');
  Expect(SameKey(K,ExactKey('10')),'D2 open');
  K:=BindUkrainian(T,'за-умовою');
  Expect(SameKey(K,ExactKey('110')),'D3 cond');
  K:=BindUkrainian(T,'функція');
  Expect(SameKey(K,ExactKey('0010')),'D4 lambda');
  K:=BindUkrainian(T,'довжина');
  Expect(SameKey(K,ExactKey('000000')),'D6 length');
  K:=BindUkrainian(T,'символ-за-кодом');
  Expect(SameKey(K,ExactKey('00000000')),'D8 code-char');
  K:=BindUkrainian(T,'пояснити-відповідь');
  Expect(SameKey(K,ExactKey('000000001')),'D9 answer');
  K:=BindUkrainian(T,'якщо');
  Expect(SameKey(K,ExactKey('0000000110')),'D10 if');
  Raised:=False;
  try K:=BindUkrainian(T,'quote'); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'foreign spelling accepted');
  Raised:=False;
  try K:=BindUkrainian(T,''); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'empty spelling accepted');
  Raised:=False;
  try K:=BindUkrainianInDomain(T,'так',3); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'wrong-domain lookup accepted');
  Raised:=False;
  try K:=BindUkrainianInDomain(T,'так',0); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'unsupported domain accepted');
  T[1][0].Ukrainian:='за-умовою';
  Raised:=False;
  try K:=BindUkrainian(T,'за-умовою'); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'cross-domain ambiguity accepted');
  WriteLn('BIND-OK domains=10 checked=',Count,' unknown=reject ambiguity=reject');
end.
