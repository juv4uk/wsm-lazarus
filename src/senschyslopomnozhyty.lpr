{ G3.43. Одноразовий host CLI canonical фізичного D12+ множення.
  Це НЕ D5-оператор, не Core1 evaluator та не текстова проєкція. }
program senschyslopomnozhyty;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.numericplane, wsm.numericmul;
const MaxPhysicalBytes=64;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise Exception.Create('очікується фізичний .sens, а не .lisp');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxPhysicalBytes) then
      raise Exception.Create('порожній або надмірний фізичний атом');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ RawByteString — власний packed T5M, публікується тільки після
  повного decode/multiply/re-encode. THandleStream не володіє stdout.
  Питання: чому error не повертає D1:0? Чому немає часткових байтів?
  Чому .lisp не читається як .sens? Хто задає Dn? }
function Run:Integer;
var W:SizeInt; L,R,P:RawByteString; Sink:THandleStream;
begin
  if ParamCount<>3 then begin
    WriteLn(StdErr,'Виклик: senschyslopomnozhyty D12|D24|D48|D96|D192 ліве.sens праве.sens > добуток.sens');
    Exit(64);
  end;
  try
    W:=SelectedNumericDomain(RawByteString(ParamStr(1)));
    L:=ReadPhysical(ParamStr(2));
    R:=ReadPhysical(ParamStr(3));
    P:=MultiplyNumericPhysical(L,R,W);
    if Length(P)<1 then raise Exception.Create('порожній фізичний добуток');
    Sink:=THandleStream.Create(TextRec(Output).Handle);
    try Sink.WriteBuffer(P[1],Length(P));
    finally Sink.Free end;
    Result:=0;
  except on E:Exception do begin
    WriteLn(StdErr,RawByteString(
      #$D0#$9C#$D0#$9D#$D0#$9E#$D0#$96#$D0#$95#$D0#$9D#$D0#$9D#$D0#$AF+
      #$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$3A#$20),E.Message);
    Result:=2;
  end end;
end;
begin Halt(Run);end.
