{ G6.71 — фізичний host backend для переповненого D12 ADD -> D24.
  Український CLI режим не є викличною головою SENS; numeric law — pinned.
  Два вхідні canonical .sens, вихід новий ELF64 PIE no-clobber. }
program sensd12promoteelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.elfd12promote, wsm.elfpublish, wsm.elfgeometry;
const
  ModeAddWide:RawByteString=#$2d+#$2d+#$D0+#$B4+#$D0+#$BE+#$D0+#$B4+#$D0+#$B0+#$D1+#$82+#$D0+#$B8+#$2d+#$D1+#$80+#$D0+#$BE+#$D0+#$B7+#$D1+#$88+#$D0+#$B8+#$D1+#$80+#$D0+#$B5+#$D0+#$BD+#$D0+#$BE+#$2d+#$44+#$31+#$32;

function ReadAtom(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (ExtractFileExt(Path)<>'.sens') or (Length(Path)>4096) then
    raise ED12PromoteELFError.Create('потрібен канонічний D12 .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>64) then
      raise ED12PromoteELFError.Create('фізичний D12 файл поза межею');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Результат читання — owned RawByteString T5M, ніколи host-десяткове число.
  Image — owned перевірені ELF байти, Publisher публікує лише відсутню ціль.
  1) Чому D24 визначає AddNumericPhysical, а не розмір файлу?
  2) Чому .lisp не відкривається як T5M?
  3) Чому перед створенням ELF потрібне точне слово D12?
  4) Чому вихід ELF не переписує наявну ціль?
  5) Чим ADD у машинному коді відрізняється від compiler constant fold? }
procedure WriteLineUTF8(const MessageText:RawByteString;IsError:Boolean);
var S:THandleStream; LF:AnsiChar;
begin
  LF:=#10;
  if IsError then S:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else S:=THandleStream.Create(TextRec(Output).Handle);
  try
    if Length(MessageText)>0 then S.WriteBuffer(MessageText[1],Length(MessageText));
    S.WriteBuffer(LF,1);
  finally S.Free end;
end;

procedure Run;
var Image,L,R:RawByteString; Geometry:TELFGeometry;
begin
  if (ParamCount<>4) or (RawByteString(ParamStr(1))<>ModeAddWide) or
     (ExtractFileExt(ParamStr(4))<>'.elf') then
    raise ED12PromoteELFError.Create(
      'виклик: sensd12promoteelf --додати-розширено-D12 ліве.sens праве.sens новий.elf');
  {$IFNDEF LINUX}
  raise ED12PromoteELFError.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12PromoteELFError.Create('потрібен x86-64');
  {$ENDIF}
  L:=ReadAtom(ParamStr(2));
  R:=ReadAtom(ParamStr(3));
  Image:=BuildD12PromotedAddELF(L,R);
  PublishNewELF64(ParamStr(4),Image,3,Geometry);
  WriteLineUTF8(RawByteString(UTF8Encode(UnicodeString(
    'ЕЛЬФ-Д24-ДОДАВАННЯ-ГОТОВО байтів=')))+IntToStr(Geometry.FileBytes)+
    ' host-тип='+IntToStr(Geometry.Kind)+' machine=ADD T5M=D24',False);
end;

begin
  try Run
  except on E:Exception do begin
    WriteLineUTF8(RawByteString(UTF8Encode(UnicodeString(
      'ЕЛЬФ-Д24-ДОДАВАННЯ-ВІДМОВА: ')))+RawByteString(E.Message),True);
    ExitCode:=2;
  end end;
end.
