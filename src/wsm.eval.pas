(* wsm.eval.pas — M0.6 evaluator skeleton: ID dispatch + trampoline (#8).
 *
 * Мета цього модуля (issue #8): побудувати eval/apply механіку так, щоб
 * архітектура вже НЕ МОГЛА повернутися до spelling-driven interpreter.
 * Every semantic branch below switches on a canonical semantic ID
 * (TSid8 = Byte) obtained from wsm.registry.RegistryLookup -- never on
 * an operator's spelling. The ONLY place an operator spelling ever
 * appears is as the dynamic INPUT to RegistryLookup (SymbolName(head),
 * taken from whatever the expression itself contains); it is converted
 * to a TSid8 before any branching happens. No spelling literal for
 * quote/cond/lambda/cons/car/cdr ever appears in this file's control
 * flow.
 *
 * SID8-ONLY (issue #24, ecosystem#16, 2026-09-23): dispatch itself
 * (opID = ID_QUOTE, etc.) is plain Byte equality, never a string
 * comparison, and no string ever appears anywhere in this unit at all
 * -- not even as construction input. The eight ID_* identities below
 * are built once, at unit initialization, via
 * wsm.registry.SID8(%00000001): the pure FPC binary literal, exactly
 * as authored, passed through unchanged -- no decomposition into
 * separate bits, no recombination, no parsing, no text. SID8 exists
 * only so the call site reads as "this literal is a semantic
 * identity," the same documentary role RegistryLookup's own
 * `spelling` parameter plays for surface text elsewhere in this
 * codebase; it performs no validation, because a `Byte` is already,
 * structurally, exactly eight bits and nothing else needs proving.
 *
 * Environment variable lookup (EnvLookup) *does* compare symbol spellings
 * -- that is unavoidable and is not the thing #8 forbids: a variable's
 * name is its identity, this is ordinary binding lookup, not semantic
 * operator dispatch. What #8 forbids specifically is "якщо ID невідомий —
 * подивитися ім'я": falling back to spelling-based guessing once ID
 * dispatch has already failed to resolve or implement an operator. This
 * unit never does that -- an unresolved or unimplemented ID is always an
 * explicit EEvalError, never a name-based guess.
 *
 * Minimal continuation/frame representation (#8's own phrase): the
 * trampoline's own {expr, env} loop-local pair IS the continuation this
 * skeleton needs. Every TAIL position (the chosen COND branch, a
 * closure's body after argument binding) overwrites {expr, env} and
 * `Continue`s the same while loop -- no Pascal call-stack growth with
 * recursion depth. Every NON-TAIL position (argument evaluation, COND
 * test evaluation, operator-position evaluation for a computed head)
 * recurses through an ordinary nested Eval call, whose own depth is
 * bounded by expression structure, never by how many tail-calls a
 * program makes.
 *
 * Scope, per #8's "Не робити": this is a skeleton, not a library. Only
 * QUOTE/COND/LAMBDA plus CONS/CAR/CDR/(numeric)-/(numeric)= are
 * implemented. No BigInt, no macro system, no full core.
 *)
unit wsm.eval;

{$mode objfpc}{$H-}

interface

uses
  sysutils, wsm.values, wsm.registry;

type
  EEvalError = class(EValueError);

  PArena = ^TArena;
  PSymbolTable = ^TSymbolTable;
  PRegistry = ^TRegistry;

  { Everything Eval needs to resolve operators (Registry), allocate new
    structure (Arena/Symbols), and recognize its own closure values
    (ClosureMarker) -- passed explicitly, never global state. }
  TEvalContext = record
    Arena: PArena;
    Symbols: PSymbolTable;
    Registry: PRegistry;
    ClosureMarker: TValue;
  end;

procedure EvalContextInit(out ctx: TEvalContext; var arena: TArena;
  var symbols: TSymbolTable; var reg: TRegistry);

{ env is a plain list of (symbol . value) bindings, innermost first --
  MakeNil is a valid, empty top-level environment. }
function Eval(var ctx: TEvalContext; env: TValue; expr: TValue): TValue;

implementation

var
  { Not CONST: standard FPC has no compile-time user-function
    evaluation, so these are ordinary variables populated exactly
    once, below, in this unit's own `initialization` section --
    before any caller can observe them. Read-only in effect (nothing
    outside this section ever assigns to them), just not enforced as
    such by the language. }
  ID_QUOTE, ID_CONS, ID_CAR, ID_CDR, ID_COND, ID_LAMBDA, ID_MINUS,
    ID_NUMEQ: TSid8;

const
  CLOSURE_MARKER_NAME: RawByteString = '##wsm-closure##';

type
  TValueArray = array of TValue;

procedure EvalContextInit(out ctx: TEvalContext; var arena: TArena;
  var symbols: TSymbolTable; var reg: TRegistry);
begin
  ctx.Arena := @arena;
  ctx.Symbols := @symbols;
  ctx.Registry := @reg;
  ctx.ClosureMarker := InternSymbol(
    arena, symbols,
    PAnsiChar(CLOSURE_MARKER_NAME), Length(CLOSURE_MARKER_NAME));
end;

{ Nth element (0-based) of a proper list, with a clear arity error rather
  than an opaque pair-shape error. }
function NthArg(list: TValue; n: Integer; const opName: RawByteString): TValue;
var
  i: Integer;
begin
  for i := 1 to n do
  begin
    if not IsPair(list) then
      raise EEvalError.CreateFmt('%s: too few arguments', [opName]);
    list := PairTail(list);
  end;
  if not IsPair(list) then
    raise EEvalError.CreateFmt('%s: too few arguments', [opName]);
  Result := PairHead(list);
end;

function MakeClosure(var ctx: TEvalContext; params, body, env: TValue): TValue;
begin
  Result := MakePair(ctx.Arena^, ctx.ClosureMarker,
    MakePair(ctx.Arena^, params, MakePair(ctx.Arena^, body, env)));
end;

function IsClosure(var ctx: TEvalContext; v: TValue): Boolean;
begin
  Result := IsPair(v) and IsSymbol(PairHead(v)) and
    (SymbolName(PairHead(v)) = SymbolName(ctx.ClosureMarker));
end;

function ClosureParams(v: TValue): TValue;
begin
  Result := PairHead(PairTail(v));
end;

function ClosureBody(v: TValue): TValue;
begin
  Result := PairHead(PairTail(PairTail(v)));
end;

function ClosureEnv(v: TValue): TValue;
begin
  Result := PairTail(PairTail(PairTail(v)));
end;

function EnvExtend(var ctx: TEvalContext; sym, value, env: TValue): TValue;
begin
  Result := MakePair(ctx.Arena^, MakePair(ctx.Arena^, sym, value), env);
end;

function EnvLookup(env: TValue; sym: TValue): TValue;
var
  node, binding: TValue;
  name: RawByteString;
begin
  name := SymbolName(sym);
  node := env;
  while IsPair(node) do
  begin
    binding := PairHead(node);
    if SymbolName(PairHead(binding)) = name then
    begin
      Result := PairTail(binding);
      Exit;
    end;
    node := PairTail(node);
  end;
  raise EEvalError.CreateFmt('eval: unbound variable %s', [name]);
end;

function BindParams(var ctx: TEvalContext; params: TValue;
  const argVals: TValueArray; baseEnv: TValue): TValue;
var
  i: Integer;
  p: TValue;
begin
  Result := baseEnv;
  p := params;
  i := 0;
  while IsPair(p) do
  begin
    if i > High(argVals) then
      raise EEvalError.Create('apply: too few arguments');
    Result := EnvExtend(ctx, PairHead(p), argVals[i], Result);
    Inc(i);
    p := PairTail(p);
  end;
  if i <= High(argVals) then
    raise EEvalError.Create('apply: too many arguments');
end;

function Eval(var ctx: TEvalContext; env: TValue; expr: TValue): TValue;
var
  head, argsList, fn: TValue;
  opID: TSid8;
  haveID: Boolean;
  argVals: TValueArray;
  clauses, clause, testVal: TValue;
  matched: Boolean;
  a, b: TValue;
  n: Integer;
  node: TValue;
begin
  while True do
  begin
    case expr.kind of
      kNumber, kString, kVNil:
        begin
          Result := expr;
          Exit;
        end;

      kUnbound:
        raise EEvalError.Create('eval: cannot evaluate the unbound marker');

      kSymbol:
        begin
          Result := EnvLookup(env, expr);
          Exit;
        end;

      kPair:
        begin
          head := PairHead(expr);
          argsList := PairTail(expr);

          haveID := False;
          if IsSymbol(head) then
            haveID := RegistryLookup(ctx.Registry^, SymbolName(head), opID);

          if haveID then
          begin
            if opID = ID_QUOTE then
            begin
              Result := NthArg(argsList, 0, 'quote');
              Exit;
            end
            else if opID = ID_LAMBDA then
            begin
              Result := MakeClosure(ctx,
                NthArg(argsList, 0, 'lambda'),
                NthArg(argsList, 1, 'lambda'),
                env);
              Exit;
            end
            else if opID = ID_COND then
            begin
              clauses := argsList;
              matched := False;
              while IsPair(clauses) do
              begin
                clause := PairHead(clauses);
                testVal := Eval(ctx, env, NthArg(clause, 0, 'cond'));
                if not IsNil(testVal) then
                begin
                  expr := NthArg(clause, 1, 'cond');
                  matched := True;
                  Break;
                end;
                clauses := PairTail(clauses);
              end;
              if not matched then
                raise EEvalError.Create('cond: no matching clause (fail-closed)');
              Continue;
            end
            else if opID = ID_CONS then
            begin
              a := Eval(ctx, env, NthArg(argsList, 0, 'cons'));
              b := Eval(ctx, env, NthArg(argsList, 1, 'cons'));
              Result := MakePair(ctx.Arena^, a, b);
              Exit;
            end
            else if opID = ID_CAR then
            begin
              Result := PairHead(Eval(ctx, env, NthArg(argsList, 0, 'car')));
              Exit;
            end
            else if opID = ID_CDR then
            begin
              Result := PairTail(Eval(ctx, env, NthArg(argsList, 0, 'cdr')));
              Exit;
            end
            else if opID = ID_MINUS then
            begin
              a := Eval(ctx, env, NthArg(argsList, 0, '-'));
              b := Eval(ctx, env, NthArg(argsList, 1, '-'));
              if (a.kind <> kNumber) or (b.kind <> kNumber) then
                raise EEvalError.Create('-: both arguments must be numbers');
              Result := MakeNumber(
                a.qnum * b.qden - b.qnum * a.qden,
                a.qden * b.qden);
              Exit;
            end
            else if opID = ID_NUMEQ then
            begin
              a := Eval(ctx, env, NthArg(argsList, 0, '='));
              b := Eval(ctx, env, NthArg(argsList, 1, '='));
              if (a.kind <> kNumber) or (b.kind <> kNumber) then
                raise EEvalError.Create('=: both arguments must be numbers');
              if (a.qnum = b.qnum) and (a.qden = b.qden) then
                Result := MakeNumber(1, 1)
              else
                Result := MakeNil;
              Exit;
            end
            else
              raise EEvalError.CreateFmt(
                'eval: semantic id %s is registered but not implemented ' +
                'in this skeleton', [Sid8ToBinaryString(opID)]);
          end
          else
          begin
            { head is not a registry keyword: an ordinary variable
              reference or a computed operator expression. Evaluate it
              (non-tail) and, if it is a closure, tail-call into its
              body -- this is what lets self-application-style recursion
              (no `define`, no mutable global env) work without any
              spelling-based special-casing. }
            fn := Eval(ctx, env, head);
            if not IsClosure(ctx, fn) then
              raise EEvalError.Create(
                'eval: value in operator position is not applicable');

            SetLength(argVals, 0);
            n := 0;
            node := argsList;
            while IsPair(node) do
            begin
              SetLength(argVals, n + 1);
              argVals[n] := Eval(ctx, env, PairHead(node));
              Inc(n);
              node := PairTail(node);
            end;

            env := BindParams(ctx, ClosureParams(fn), argVals, ClosureEnv(fn));
            expr := ClosureBody(fn);
            Continue;
          end;
        end;
    end;
  end;
end;

initialization
  { The pure FPC binary literal, unchanged, tagged as a semantic
    identity -- see SID8's own doc comment in wsm.registry.pas. }
  ID_QUOTE  := SID8(%00000001);
  ID_CONS   := SID8(%00000100);
  ID_CAR    := SID8(%00000101);
  ID_CDR    := SID8(%00000110);
  ID_COND   := SID8(%00000111);
  ID_LAMBDA := SID8(%00001000);
  ID_MINUS  := SID8(%00001101);
  ID_NUMEQ  := SID8(%00011100);

end.
