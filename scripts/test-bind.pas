program test_bind;
{$mode objfpc}{$H+}
uses SysUtils, wsm.domain, wsm.bind;
var T:TDomainSet; K:TDomainKey; Raised:Boolean;
procedure Expect(B:Boolean; const Why:String);
begin if not B then begin WriteLn(StdErr,'BIND-FAIL ',Why); Halt(1); end; end;
begin
  LoadPinnedDomains('external/sens',T);
  K:=BindUkrainian(T,'так');
  Expect(SameKey(K,ExactKey('1')),'D1 yes');
  K:=BindUkrainian(T,'відкрити');
  Expect(SameKey(K,ExactKey('10')),'D2 open');
  K:=BindUkrainian(T,'за-умовою');
  Expect(SameKey(K,ExactKey('110')),'D3 cond');
  Raised:=False;
  try K:=BindUkrainian(T,'quote'); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'foreign spelling accepted');
  Raised:=False;
  try K:=BindUkrainian(T,''); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'empty spelling accepted');
  T[1][0].Ukrainian:='за-умовою';
  Raised:=False;
  try K:=BindUkrainian(T,'за-умовою'); except on E:EBindError do Raised:=True; end;
  Expect(Raised,'cross-domain ambiguity accepted');
  WriteLn('BIND-OK pinned D1-D3 exact coordinates, unknown and ambiguity rejected');
end.
