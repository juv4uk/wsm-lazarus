{ G6.89 — українська host-публікація універсального D1/D3:110 ELF.
  CLI лише компілює сталий kernel, stdin при виконанні приймає чотири
  ОКРЕМІ T5M W1 байти. Це не файл програми SENS і не REPL.
  Питання: чому опція CLI не є викличним іменем функції SENS?
  Чому PublishNewELF64 не може перезаписувати наявний executable?
  Хто володіє ELF RawByteString до публікації?
  Чому kernel не треба перевидавати для кожної четвірки D1? }
program sensd1umovapotikelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.elfd1umovapotik,wsm.elfpublish,wsm.elfgeometry;
type ECLIError=class(Exception);

function UA(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

procedure Emit(const Handle:THandle;const Bytes:RawByteString);
var Stream:THandleStream;
begin
  Stream:=THandleStream.Create(Handle);
  try if Bytes<>'' then Stream.WriteBuffer(Bytes[1],Length(Bytes));
  finally Stream.Free end;
end;

procedure Run;
var Image:RawByteString; G:TELFGeometry;
begin
  if (ParamCount<>2) or
    (RawByteString(ParamStr(1))<>UA('--зібрати-D1-умову')) then
    raise ECLIError.Create(UA(
      'виклик: sensd1umovapotikelf --зібрати-D1-умову новий.elf'));
  {$IFNDEF LINUX}
  raise ECLIError.Create(UA('потрібен Linux x86-64'));
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise ECLIError.Create(UA('потрібен процесор x86-64'));
  {$ENDIF}
  if ExtractFileExt(ParamStr(2))<>'.elf' then
    raise ECLIError.Create(UA('вихід має бути новим .elf'));
  Image:=BuildD1CondStreamELF;
  PublishNewELF64(ParamStr(2),Image,3,G);
  Emit(TextRec(Output).Handle,
    UA('Д1-УМОВА-ПОТІК-ГОТОВО ELF64 PIE machine=CMP/JNE/JMP D1|D3:000 байтів=')+
    IntToStr(G.FileBytes)+#10);
end;

begin
  try Run except on E:Exception do begin
    Emit(TextRec(ErrOutput).Handle,
      UA('Д1-УМОВА-КОМПІЛЯЦІЯ-ВІДМОВА: ')+
      UA(UnicodeString(E.Message))+#10);
    ExitCode:=2;
  end end;
end.
