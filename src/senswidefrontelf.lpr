{ G6.97 — єдиний host CLI для чотирьох ратифікованих двійкових
  форм, без текстового, англійського або Lisp-dispatch.
  Фізичне .sens -> verified pinned WideIR -> існуючий ELF64 backend. }
program senswidefrontelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidefront,wsm.elfpublish,wsm.elfgeometry;
type EWideFrontCLI=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Path — borrowed host path. Result — owned physical T5M, not a D7
  text surface. A file ending .lisp is rejected before parsing.
  1) Хто володіє F:TFileStream?
  2) Чому ширина домену не встановлюється за розміром файла?
  3) Де перевіряється ратифікована голова? }
function ReadPhysical(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (ExtractFileExt(Path)<>'.sens') or
     (Length(Path)>4096) then
    raise EWideFrontCLI.Create('потрібна фізична канонічна програма .sens');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<1) or (F.Size>65536) then
      raise EWideFrontCLI.Create('фізичне джерело порожнє або завелике');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

{ Human host status is UTF-8, not source language or D1/T5M result.
  Handle is borrowed, stream and bytes are owned/freed after call.
  1) Чому output .elf не змінюється до повної верифікації?
  2) Чому stderr незалежний від фізичного stdout ELF?
  3) Який механізм захищає від перезапису існуючого ELF? }
procedure Say(const Value:RawByteString;Failure:Boolean);
var H:THandleStream;B:RawByteString;
begin
  B:=Value+#10;
  if Failure then H:=THandleStream.Create(TextRec(ErrOutput).Handle)
  else H:=THandleStream.Create(TextRec(Output).Handle);
  try H.WriteBuffer(B[1],Length(B)); finally H.Free end;
end;


{ Шлях — позичений host-шлях до вже створеного ELF, результат —
  власний bounded byte buffer. Жодного запису й жодного мовного dispatch.
  1) Чому ELF не має статусу канонічного SENS?
  2) Чому потрібна перевірка всього byte buffer, а не лише заголовка?
  3) Хто звільняє потік за помилки пізнього читання? }
function ReadNativeELF(const Path:String):RawByteString;
var F:TFileStream;
begin
  Result:='';
  if (Path='') or (ExtractFileExt(Path)<>'.elf') or
     (Length(Path)>4096) then
    raise EWideFrontCLI.Create('потрібен уже створений файл .elf');
  F:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=120) or (F.Size>1048576) then
      raise EWideFrontCLI.Create('машинний образ порожній або завеликий');
    SetLength(Result,SizeInt(F.Size));
    F.ReadBuffer(Result[1],Length(Result));
  finally F.Free end;
end;

procedure Run;
var Source,Image,OnDisk,Mode:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>3) or (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EWideFrontCLI.Create(
      'виклик: senswidefrontelf --скомпілювати-фізичну-форму|--звірити-походження джерело.sens машина.elf');
  Mode:=RawByteString(ParamStr(1));
  if (Mode<>UA('--скомпілювати-фізичну-форму')) and
     (Mode<>UA('--звірити-походження')) then
    raise EWideFrontCLI.Create('невідомий режим перевіреного компілятора');
  {$IFNDEF LINUX}
  raise EWideFrontCLI.Create('потрібен Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EWideFrontCLI.Create('потрібен x86-64');
  {$ENDIF}
  Source:=ReadPhysical(ParamStr(2));
  Image:=BuildVerifiedWideELF(Source,'external/sens');
  if Mode=UA('--звірити-походження') then begin
    { Повторне pinned зниження підтверджує не лише ELF geometry,
      а всі машинні байти. OnDisk/Image — два власні bounded буфери.
      Результат — тільки людський статус; не новий .sens-результат.
      1) Чому однакова геометрія не доводить походження?
      2) Навіщо вимагати точний pinned фронтенд для повторної збірки?
      3) Чому негатив не залишає навіть часткового статусу в stdout?
      4) Чому цей доказ не замінює незалежний SENS REPL oracle? }
    OnDisk:=ReadNativeELF(ParamStr(3));
    VerifySENSELF64(OnDisk,G);
    if (G.Kind<>3) or (G.Entry<>120) or
       (G.FileBytes<>Length(Image)) or (OnDisk<>Image) then
      raise EWideFrontCLI.Create(
        'ELF64 не збігається із фізичним джерелом та pinned compiler');
    Say(UA('ЕЛЬФ-ПОХОДЖЕННЯ-ГАРАЗД: байтів=')+IntToStr(G.FileBytes)+
        ' physical=T5M compiler=pinned-WideIR exact=так',False);
    Exit;
  end;
  PublishNewELF64(ParamStr(3),Image,3,G);
  Say(UA('ЕЛЬФ-ОБЄДНАНИЙ-ГОТОВО: байтів=')+IntToStr(G.FileBytes)+
      ' machine=pinned-exact-WideIR stdout=T5M',False);
end;
begin
  try Run
  except on E:Exception do begin
    Say(UA('ЕЛЬФ-ОБЄДНАНИЙ-ВІДМОВА: ')+UA(UnicodeString(E.Message)),True);
    ExitCode:=2;
  end end;
end.
