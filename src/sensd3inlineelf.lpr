{ G6.135 — окремий фізичний інтерфейс до машинного inlining D3:101.
  Читає виключно повну packed .sens, pinned backend допускає закон.
  Код машинної EQ не відтворюємо, публікуємо вже перевірений ELF64
  існуючим PublishNewELF64 (private mkstemp+fpLink no-clobber).
  Path позичений host текст, Physical/Image — owned RawByteString,
  TFileStream та приватний inode мають короткий гарантований lifetime.
  Жодних Core1, чисел D12+, української поверхні як semantic dispatch.
  Запитання: 1) чому .lisp не можна трактувати як packed .sens?
  2) як pinned IR відхиляє неправильну голову?
  3) чому повторні виклики не перезаписують ELF?
  4) де перевіряється no-call optimized machine?
  5) чому це не повний компілятор SENS? }
program sensd3inlineelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irnestedinline,wsm.elfpublish,wsm.elfgeometry;
type EInlineCLIError=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise EInlineCLIError.Create('Потрібен точний фізичний файл .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EInlineCLIError.Create('Порожня або надмірна фізична програма');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Send(const Msg:RawByteString;Failure:Boolean);
var H:THandleStream;Data:RawByteString;
begin
  Data:=Msg+#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(Data[1],Length(Data))
  finally H.Free end;
end;

procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--породити-вбудовану-рівність')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EInlineCLIError.Create(
      'Виклик: sensd3inlineelf --породити-вбудовану-рівність програма.sens новий.elf');
  {$IFNDEF LINUX}
  raise EInlineCLIError.Create('Потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EInlineCLIError.Create('Потрібен процесор x86-64');
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildPhysicalNestedEqInlineELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Send(UA('ВБУДОВАНА-D3-РІВНІСТЬ-ГОТОВО ELF64-байтів=')+
    IntToStr(G.FileBytes)+' CALL=0 RET=0 INLINE=3 energy=NOT_MEASURED',False);
end;

begin
  try Run
  except on E:Exception do begin
    Send(UA('ВБУДОВАНА-D3-РІВНІСТЬ-ВІДМОВА: ')+
      UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
