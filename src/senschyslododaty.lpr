{ G3.38 — host CLI двох фізичних D12+ атомів. Не Lisp evaluator. }
program senschyslododaty;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.numericplane,wsm.numericadd;
const MaxPhysicalBytes=64;
{ Позичений шлях .sens -> власні обмежені фізичні байти T5M.
  TFileStream звільняється при помилці. Питання: чому .lisp —
  тільки людська проєкція? Чому межу перевіряємо перед SetLength?
  Хто володіє Result? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise Exception.Create('очікується фізичний .sens, не .lisp');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>MaxPhysicalBytes) then
      raise Exception.Create('порожній або надмірний фізичний атом');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Output — позичений host stdout; THandleStream не володіє ним.
  Весь admission завершено ДО першого байта. Питання: чому
  WriteBuffer, а не WriteLn? Чи можливий stdout при вхідній
  помилці? Чому це не повний SENS REPL? }
procedure PublishPhysical(const Physical:RawByteString);
var H:THandleStream;
begin
  if Physical='' then raise Exception.Create('порожня фізична відповідь');
  H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(Physical[1],Length(Physical));
  finally H.Free end;
end;
function Run:Integer;
var W:SizeInt; L,R,Sum:RawByteString;
begin
  if ParamCount<>3 then begin
    WriteLn(StdErr,'Виклик: senschyslododaty D12|D24|D48|D96|D192 ліве.sens праве.sens > сума.sens');
    Exit(64);
  end;
  try
    W:=SelectedNumericDomain(RawByteString(ParamStr(1)));
    L:=ReadPhysical(ParamStr(2));
    R:=ReadPhysical(ParamStr(3));
    Sum:=AddNumericPhysical(L,R,W);
    PublishPhysical(Sum);
    Result:=0;
  except on E:Exception do begin
    WriteLn(StdErr,RawByteString(#$D0#$A7#$D0#$98#$D0#$A1#$D0#$9B#$D0#$9E#$D0#$92#$D0#$95#$2D#$D0#$94#$D0#$9E#$D0#$94#$D0#$90#$D0#$92#$D0#$90#$D0#$9D#$D0#$9D#$D0#$AF#$2D#$D0#$9F#$D0#$9E#$D0#$9C#$D0#$98#$D0#$9B#$D0#$9A#$D0#$90#$3A#$20),E.Message);
    Result:=2;
  end end;
end;
begin Halt(Run);end.
