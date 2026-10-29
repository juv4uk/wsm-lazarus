{ G6.115 — дев'ятий профіль: D6:010100 через той самий verified WideIR.
  Позичені bytes фізичних 28 програм і 21 negative з pinned G6.102.
  Result — owned managed ELF64, виконання й SENS oracle — у shell/CI.
  Питання: 1) Чим D6 W6 відрізняється від W12 payload?
  2) Чому два незалежні entrypoint мусять дати байтово той самий ELF?
  3) Чому IDIV C-знакова остача не є SENS-правилом?
  4) Де виконується signed D12 admission?
  5) Хто володіє TFileStream/RawByteString після винятку? }
program TestIRWideFrontRest;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidefront,wsm.irwiderest,wsm.elfgeometry;
var Directory:String;Count,Neg,I:SizeInt;G:TELFGeometry;
procedure Need(OK:Boolean;const Why:String);
begin
  if not OK then raise Exception.Create('ДЕВЯТЬ-ПРОФІЛІВ-ПРОВАЛ: '+Why);
end;
function Bytes(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    Need((Stream.Size>=0) and (Stream.Size<=65536),'надмірний фізичний файл');
    SetLength(Result,SizeInt(Stream.Size));
    if Length(Result)>0 then Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;
procedure Positive(const LabelText:String);
var Input,Actual,Old,Expected:RawByteString;
begin
  Input:=Bytes(Directory+'/'+LabelText+'.sens');
  Expected:=Bytes(Directory+'/'+LabelText+'.expected.sens');
  Actual:=BuildVerifiedWideELF(Input,'external/sens');
  Old:=BuildIRWideRestELF(Input,'external/sens');
  Need((Actual=Old) and (Length(Actual)>120),
    'спільний frontend змінив перевірений ELF '+LabelText);
  VerifySENSELF64(Actual,G);
  Need((G.Kind=3) and (G.Entry=120) and (G.FileBytes=Length(Actual)),
    'некоректна ELF PIE геометрія');
  Need(Length(Expected)=3,'фізичний результат не D12');
  Inc(Count);
end;
{ Негативи потрібні для СПІЛЬНОГО front, а не тільки спеціального.
  Borrowed input залишається незмінним; Candidate локальний.
  1) Чому fail-closed не повертає D1:0?
  2) Чому коректна, але непідтримана голова також відхиляється?
  3) Чому фізичний T5M має бути канонічним? }
procedure Refuse(const Name:String);
var Candidate:RawByteString;Rejected:Boolean;
begin
  Rejected:=False;Candidate:='';
  try Candidate:=BuildVerifiedWideELF(
    Bytes(Directory+'/'+Name+'.sens'),'external/sens')
  except on E:Exception do Rejected:=True end;
  Need(Rejected and (Candidate=''),'не відхилено '+Name);
  Inc(Neg);
end;
begin
  Need(ParamCount=1,'потрібна тека свідків');
  Directory:=ParamStr(1);
  Need(DirectoryExists(Directory),'тека відсутня');
  Count:=0;Neg:=0;
  for I:=1 to 28 do Positive(Format('%.2d',[I]));
  Refuse('other-d7');
  Refuse('d1');
  Refuse('d3-empty');
  Refuse('d7');
  Refuse('d24');
  Refuse('missing');
  Refuse('extra');
  Refuse('nested');
  Refuse('two-roots');
  Refuse('dotted');
  Refuse('root-atom');
  Refuse('unclosed');
  Refuse('close-only');
  Refuse('bad-t5m');
  Refuse('empty');
  Refuse('div-zero');
  Refuse('d24-right');
  Refuse('d48-left');
  Refuse('min-left');
  Refuse('min-right');
  Refuse('min-both');
  Refuse('positive-negdiv-width');
  Need((Count=28) and (Neg=22),'неповний набір 28/22');
  WriteLn('NINE-WIDEIR-REST-OK physical=28 negatives=22 identical=28');
end.
