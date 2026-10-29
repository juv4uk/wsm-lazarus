{ G6.84 — host AOT-вхід до pinned D6:110101 мінімального D12.
  --найменше-D12 — explicit host mode, не мовний dispatch за D7.
  Мовні закони лишаються в juv4uk/sens pinned Contract 12.0. }
program sensd12naimensheelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd12min,wsm.elfpublish,wsm.elfgeometry;
const
  ModeMin:RawByteString='--'+#$D0#$BD#$D0#$B0#$D0#$B9#$D0#$BC#$D0#$B5#$D0#$BD#$D1#$88#$D0#$B5+'-D12';

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Filename: borrowed OS UTF-8 path; Result: owned packed T5M RawByteString.
  Ресурсна межа не встановлює домен; ReadNumericPhysical робить це.
  1) Чому .lisp заборонено? 2) Чому open share-deny-write?
  3) Хто звільняє потік? 4) Де код машинної арифметики? }
function ReadPhysical(const Path:String):RawByteString;
var Stream:TFileStream;
begin
  if ExtractFileExt(Path)<>'.sens' then
    raise ED12MinELFError.Create('потрібен канонічний .sens');
  Stream:=TFileStream.Create(Path,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<1) or (Stream.Size>64) then
      raise ED12MinELFError.Create('порожній або завеликий фізичний атом');
    SetLength(Result,SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1],Length(Result));
  finally Stream.Free end;
end;

{ THandleStream: host діагностика, не SENS value. Owned Bytes managed.
  1) Чому status ніколи не в ELF stdout? 2) Чому UTF-8 raw?
  3) Де запобігаємо перезапису? }
procedure PrintBytes(Handle:THandle;const Bytes:RawByteString);
var S:THandleStream;
begin
  S:=THandleStream.Create(Handle);
  try if Length(Bytes)>0 then S.WriteBuffer(Bytes[1],Length(Bytes))
  finally S.Free end;
end;

procedure Execute;
var L,R,Image:RawByteString;G:TELFGeometry;
begin
  if (ParamCount<>4) or (RawByteString(ParamStr(1))<>ModeMin) then
    raise ED12MinELFError.Create(
      'виклик: sensd12naimensheelf --найменше-D12 ліве.sens праве.sens новий.elf');
  if ExtractFileExt(ParamStr(4))<>'.elf' then
    raise ED12MinELFError.Create('потрібна нова ELF64 ціль');
  {$IFNDEF LINUX}
  raise ED12MinELFError.Create('потрібен Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ED12MinELFError.Create('потрібен x86-64');
  {$ENDIF}
  L:=ReadPhysical(ParamStr(2));
  R:=ReadPhysical(ParamStr(3));
  Image:=BuildD12MinELF(L,R);
  PublishNewELF64(ParamStr(4),Image,3,G);
  PrintBytes(TextRec(Output).Handle,
    'D12-MIN-ELF-OK machine=CMP/CMOVG bytes='+IntToStr(G.FileBytes)+
    ' stdout=T5M'+#10);
end;

begin
  try Execute
  except on E:Exception do begin
    PrintBytes(TextRec(ErrOutput).Handle,
      UA('D12-MIN-ВІДМОВА: ')+UA(UnicodeString(E.Message))+#10);
    ExitCode:=2;
  end end;
end.

{ Вхід не визначає SENS-примітив із назви файла чи UTF-8.
  Output CLI — метадані, ELF process stdout — лише packed D12 T5M.
  1) Хто встановлює D6:110101? 2) Чому не загальний компілятор?
  3) Де CMP/CMOVG? 4) Чому атомарний no-clobber важливий? }
