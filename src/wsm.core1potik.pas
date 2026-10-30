{ G6.161 — pinned Core1 DEFINE/LAMBDA до повторно використовуваного ELF.
  Оригінальні тіла додавання/віднімання читаються лише з core1.sens
  через чинний wsm.lowerpinnedcore1add. Код не містить їхніх визначень.
  Runtime: рівно два окремі packed T5M D12 атоми, 6 host байтів stdin.
  Якщо signed D12 вихід не вміщується — exit 2, без звуження D24. }
unit wsm.core1potik;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type
  ECore1Potik = class(Exception);
  TCore1PotikMachine = (cpAdd,cpSub); { лише host профіль, не закон SENS }
function BuildPinnedCore1StreamELF(const RepoRoot:String;
  Machine:TCore1PotikMachine):RawByteString;
implementation
uses wsm.t5m,wsm.numericplane,wsm.lowerpinnedcore1add,
     wsm.irwidefront,wsm.irwidedynadd,wsm.elfd12subpotik,
     wsm.x64frameio,wsm.elfgeometry;

procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise ECore1Potik.Create(Why) end;

{ RepoRoot: позичений шлях до робочого дерева із pinned external/sens.
  Machine: host-вибір між ДВОМА вже ратифікованими фізичними Core1 тілами.
  Result: власний managed RawByteString ELF64 PIE. Zero-атоми отримано
  лише через чинний D12-кодек; StaticProof — машинний свідок справжнього
  фізичного DEFINE/LAMBDA, не Pascal-репліка його бібліотечного тіла.
  Після незалежної byte-exact звірки з canonical D5/WideIR-якорем
  використовується вже перевірений runtime x86 emitter. Жодного
  захопленого heap-об’єкта між викликами, тимчасові рядки керовані FPC.

  1) Чому двійковий DEFINE із core1.sens перевіряється до dynamic ELF?
  2) Навіщо зіставляти повні байти StaticProof і WideIRWitness?
  3) Чому 2×W12 зі stdin — не одна канонічна програма .sens?
  4) Хто відхиляє D12-результат, для якого потрібний D24?
  5) Чому Machine не можна використовувати як мовний dispatch за D7? }
function BuildPinnedCore1StreamELF(const RepoRoot:String;
  Machine:TCore1PotikMachine):RawByteString;
var Zero,ZeroBits,Head,Authority,Anchor,StaticProof,WideIRWitness:RawByteString;
    N:TExplicitNumeric;W:TExactWords;G:TELFGeometry;
begin
  Result:='';
  Need((RepoRoot<>'') and (Length(RepoRoot)<=4096),
       'відсутній корінь робочого дерева pinned SENS');
  Zero:=EncodeNumericDecimal('0',12);
  N:=ReadNumericPhysical(Zero,12);
  Need((N.DomainWidth=12) and (Length(N.ExactBits)=12) and
       (Length(Zero)=3),'нуль не є canonical signed D12');
  ZeroBits:=N.ExactBits;
  case Machine of
    cpAdd:begin
      Head:='01010';
      StaticProof:=BuildPinnedCore1AddELF(RepoRoot,Zero,Zero);
    end;
    cpSub:begin
      Head:='01011';
      StaticProof:=BuildPinnedCore1SubELF(RepoRoot,Zero,Zero);
    end;
    else raise ECore1Potik.Create('невідомий машинний профіль');
  end;
  Authority:=RawByteString(IncludeTrailingPathDelimiter(
     ExpandFileName(RepoRoot))+'external/sens');
  SetLength(W,5);
  W[0]:='10';W[1]:=Head;W[2]:=ZeroBits;
  W[3]:=ZeroBits;W[4]:='01';
  Anchor:=EncodeT5M(W);
  WideIRWitness:=BuildVerifiedWideELF(Anchor,Authority);
  Need(StaticProof=WideIRWitness,
       'оригінальний pinned Core1 DEFINE не збігся з точним D5/WideIR');
  VerifySENSELF64(StaticProof,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(StaticProof)),
       'статичний pinned Core1 не є ELF64 PIE');
  case Machine of
    cpAdd:Result:=BuildVerifiedDynamicD12AddELF(Anchor,Authority);
    cpSub:Result:=WrapExactSixByteFrame(
              BuildVerifiedD12SubStreamELF(Anchor,Authority));
  end;
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.MachineBytes>0) and (G.FileBytes=Length(Result)),
       'динамічний Core1 не породив перевірений ELF64 PIE');
end;
end.
