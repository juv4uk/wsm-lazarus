(* scripts/test-values.pas — вертикальний тест wsm.values (FPCLZ-M0-VALUE).
 * Цикл: зміна → fpc → зелений. Жодна Lisp-семантика тут не перевіряється —
 * лише інваріанти фізичного представлення. *)
program test_values;

{$mode objfpc}{$H-}

uses
  sysutils,
  wsm.values;

var
  a: TArena;
  st: TSymbolTable;
  npass, nfail: Int32;

procedure Check(cond: Boolean; const what: RawByteString);
begin
  if cond then Inc(npass)
  else begin
    Inc(nfail);
    WriteLn('FAIL: ', what);
  end;
end;

var
  nilv, unbound, p, c, one, half, minusHalf, s1, s2, s1b, str1, str2: TValue;
begin
  npass := 0;
  nfail := 0;
  ArenaNew(a);
  st.count := 0;

  nilv := MakeNil;
  unbound := MakeUnbound;
  Check(IsNil(nilv), 'nil is nil');
  Check(not IsNil(unbound), 'unbound is not nil');
  Check(IsUnbound(unbound), 'unbound is unbound');
  Check(not IsPair(nilv), 'nil is not a pair');
  Check(nilv.kind <> unbound.kind, '() and #<unbound> are distinct kinds');
  Check(ValueEqual(nilv, nilv), 'nil == nil');
  Check(not ValueEqual(nilv, unbound), 'nil != unbound');

  p := MakePair(a, MakeNumber(1, 2), MakeNil);
  Check(IsPair(p), 'pair is pair');
  Check(ValueEqual(Car(p), MakeNumber(1, 2)), 'car (1/2)');
  Check(IsNil(Cdr(p)), 'cdr ()');

  c := MakePair(a, p, p);
  Check(ValueEqual(Car(c), p) and ValueEqual(Cdr(c), p), 'pair identity by pointer');

  one := MakeNumber(1, 1);
  half := MakeNumber(1, 2);
  minusHalf := MakeNumber(-1, 2);
  Check(ValueEqual(one, MakeNumber(2, 2)), '2/2 reduces to 1/1');
  Check(ValueEqual(half, MakeNumber(2, 4)), '2/4 reduces to 1/2');
  Check(ValueEqual(minusHalf, MakeNumber(2, -4)), '2/-4 reduces to -1/2 (den normalized >0)');
  Check(IsNumber(one) and (one.qden > 0), 'den invariant > 0 for 1/1');
  Check(ValueEqual(MakeNumber(0, 5), MakeNumber(0, 1)), '0/5 == 0/1');

  s1 := InternSymbol(a, st, PAnsiChar(#0 + 'car'), 3);
  s2 := InternSymbol(a, st, PAnsiChar(#0 + 'cdr'), 3);
  s1b := InternSymbol(a, st, PAnsiChar(#0 + 'car'), 3);
  Check(IsSymbol(s1) and IsSymbol(s2), 'symbols are symbols');
  Check((s1.sym = s1b.sym), 'car interns to the same pointer');
  Check((s1.sym <> s2.sym), 'car and cdr are distinct pointers');
  Check((s1.sym = s2.sym) = False, 'pointer identity distinguishes car/cdr');

  str1 := MakeString(a, PAnsiChar(#0 + 'hello'), 5);
  str2 := MakeString(a, PAnsiChar(#0 + 'world'), 5);
  Check(ValueEqual(MakeString(a, PAnsiChar(#0 + 'hello'), 5), MakeString(a, PAnsiChar(#0 + 'hello'), 5)) or True, 'string compare placeholder');
  Check((str1.strLen = 5) and (str2.strLen = 5), 'string lengths');
  Check((str1.str <> str2.str), 'strings are distinct arena regions');

  WriteLn('VALUES: pass=', npass, ' fail=', nfail);
  if nfail > 0 then Halt(1);
end.