{ G6.144 — pinned D5 physical source -> verified WideIR -> dynamic ADD ELF.
  Borrowed canonical T5M anchor, borrowed pinned authority directory;
  Result: owned managed ELF64 PIE bytes. Runtime uses two separate W12
  atoms as a six-byte stdin host frame, not one source program.
  Existing compiler checks D5:01010/arity/numeric, donor performs CPU ADD.
  No Pascal numeric law, local registry, Common Lisp or text dispatch.
  1) Why is a W12 atom opaque without the D5 law?
  2) Why is source admission distinct from runtime stdin admission?
  3) Who owns proof, donor and result?
  4) Why check ELF geometry twice?
  5) Where does six-byte EOF framing occur? }
unit wsm.irwidedynadd;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EIRWideDynamicAddError=class(Exception);
function BuildVerifiedDynamicD12AddELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
implementation
uses wsm.irwideaddreg,wsm.elfd12potik,wsm.x64frameio,wsm.elfgeometry;
procedure Need(Ok:Boolean;const Why:String);
begin if not Ok then raise EIRWideDynamicAddError.Create(Why) end;
function BuildVerifiedDynamicD12AddELF(
  const PhysicalAnchor,AuthorityRoot:RawByteString):RawByteString;
var Proof,Donor:RawByteString;G:TELFGeometry;
begin
  Result:='';
  Proof:=BuildIRWideAddRegisterELF(PhysicalAnchor,AuthorityRoot);
  VerifySENSELF64(Proof,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.MachineBytes>0),
       'pinned D5 source WideIR не породив ELF64');
  Donor:=BuildD12StreamAddELF;
  VerifySENSELF64(Donor,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.MachineBytes>0),
       'донор D12 runtime не підтверджено');
  Result:=WrapExactSixByteFrame(Donor);
  VerifySENSELF64(Result,G);
  Need((G.Kind=3) and (G.Entry=120) and
       (G.FileBytes=Length(Result)) and
       (G.MachineBytes>G.MachineBytes-Length(Donor)+120),
       'фізичний EOF-кадр або ELF64 geometry пошкоджено');
end;
end.
