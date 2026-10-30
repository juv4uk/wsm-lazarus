{ G6.171 — окремий фізичний компілятор ТІЛЬКИ D4( D5 нуль? D12 ).
  Canonical packed .sens → pinned WideIR → машинний ELF64 SETNE → D1.
  Це вузький CLI, не загальний frontend, REPL, компілятор Core1/4. }
program sensnenulelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidenenul,wsm.elfpublish,wsm.elfgeometry;
type ENenulCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — позичений шлях ОС; Result — власні фізичні двійкові T5M.
  Вхід із суфіксом .lisp навмисно відхиляємо.
  1) Хто звільняє TFileStream?
  2) Чому UTF-8 проєкція не може підмінити packed T5M?
  3) Де встановлюється pinned домен і числова ідентичність? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (ExtractFileExt(Path)<>'.sens') or
     (Length(Path)>4096) then
    raise ENenulCLI.Create('потрібне фізичне джерело .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise ENenulCLI.Create('неприпустимий фізичний розмір');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Human status — окремий host UTF-8, не SENS D1 і не ELF stdout.
  H належить виклику, байтовий буфер B — managed.
  1) Чому status не змішується з двійковим результатом?
  2) Чому помилка не може залишити частковий файл?
  3) Де забезпечується no-clobber? }
procedure Say(const Value:RawByteString;Failure:Boolean);
var H:THandleStream;B:RawByteString;
begin
  B:=Value+#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)); finally H.Free end;
end;

procedure Run;
var Source,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--скомпілювати-ненуль')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ENenulCLI.Create(
      'виклик: sensnenulelf --скомпілювати-ненуль форма.sens програма.elf');
  {$IFNDEF LINUX}
  raise ENenulCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ENenulCLI.Create('потрібен x86-64');
  {$ENDIF}
  Source:=ReadPhysical(ParamStr(2));
  Image:=BuildIRWideNenulELF(Source,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say(UA('НЕНУЛЬ-ЕЛЬФ-ГОТОВО: байтів=')+IntToStr(G.FileBytes)+
      ' source=physical-T5M machine=TEST-SETNE result=D1',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('НЕНУЛЬ-ЕЛЬФ-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
