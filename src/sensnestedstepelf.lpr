{ G6.93 — компілятор вкладених фізичних D6:001110 форм 1..5.
  Host CLI UTF-8 не визначає SENS ідентичність чи закони. }
program sensnestedstepelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irnestedstep,wsm.elfpublish,wsm.elfgeometry;
type ENestedCLIError=class(Exception);
function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;
procedure PrintBytes(const Bytes:RawByteString;IsErr:Boolean);
var S:THandleStream;H:THandle;
begin
  if IsErr then H:=TextRec(StdErr).Handle else H:=TextRec(Output).Handle;
  S:=THandleStream.Create(H);
  try if Length(Bytes)>0 then S.WriteBuffer(Bytes[1],Length(Bytes));
  finally S.Free end;
end;
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if ExtractFileExt(Path)<>'.sens' then
    raise ENestedCLIError.Create(UA('джерело повинно бути фізичним .sens'));
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=0) or (F.Size>512) then
      raise ENestedCLIError.Create(UA('фізичне джерело поза межею'));
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;
{ Physical та Image — owned managed raw bytes; FPC звільняє їх при виході.
  PublishNewELF64 перевіряє геометрію і створює атомарно no-clobber.
  1) Чому CLI не підтримує .lisp як canonical джерело?
  2) Чому вся семантична робота делегується pinned SENS?
  3) Де відхиляємо спробу перезапису ELF?
  4) Чому вивід CLI — metadata, а не machine-result? }
procedure Run;
var Physical,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or
     (RawByteString(ParamStr(1))<>UA('--вкладене-додавання-D6')) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise ENestedCLIError.Create(UA(
       'виклик: sensnestedstepelf --вкладене-додавання-D6 вхід.sens новий.elf'));
  {$IFNDEF LINUX}
  raise ENestedCLIError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ENestedCLIError.Create(UA('потрібен x86-64'));
  {$ENDIF}
  Physical:=ReadPhysical(ParamStr(2));
  Image:=BuildNestedStepELF(Physical,'external/sens');
  PublishNewELF64(ParamStr(3),Image,3,G);
  PrintBytes('D6-NESTED-ELF64 bytes='+RawByteString(IntToStr(G.FileBytes))+
             ' type=ET_DYN output=T5M'+#10,False);
end;
begin
  try Run
  except on E:Exception do begin
    PrintBytes(UA('КОМПІЛЯТОР-ВКЛАДЕНЕ-Д6-ВІДМОВА: ')+
               RawByteString(E.Message)+#10,True);
    ExitCode:=2;
  end end;
end.
