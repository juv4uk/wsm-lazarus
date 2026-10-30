{ G6.192 — тестовий постійний host-сеанс без кешування результатів.
  Вхід LE32+packed T5M; вихід status(1/0)+LE32+ELF/UTF8 diagnostic.
  ЦЕ HOST транспорт, а не SENS D2 чи D12+ семантика.
  --звичайний викликає чинний спільний компілятор для порівняння;
  --контекст дозволяє точно одну pinned WideIR→D6 модуль компіляцію. }
program senswideabskontekst;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,wsm.irwidefront,wsm.irwideabs,
     wsm.verifiedwidecontext,wsm.elfgeometry;
const MaxFrames=48; MaxT5M=65536; MaxELF=1048576;
type EContextSession=class(Exception);

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Host payloads — owned exact bytes, source borrowed TStream.
  EOF accepted ONLY between complete 4-byte headers.
  1) Чому короткий кадр не є SENS EOF?
  2) Хто володіє THandleStream?
  3) Чому status byte не є мовним D1?
  4) Як уникаємо часткового ELF на compiler rejection? }
function ReadExact(Src:TStream;N:SizeInt;AtBoundary:Boolean;
                   out Data:RawByteString):Boolean;
var Got,R:SizeInt;
begin
  Result:=False;Data:='';
  if (N<=0) or (N>MaxT5M) then
    raise EContextSession.Create('host довжина поза квотою');
  SetLength(Data,N); Got:=0;
  while Got<N do begin
    R:=Src.Read(Data[Got+1],N-Got);
    if R<0 then raise EContextSession.Create('помилка stdin');
    if R=0 then begin
      if AtBoundary and (Got=0) then begin Data:=''; Exit(False) end;
      raise EContextSession.Create('обірваний host кадр');
    end;
    Inc(Got,R);
  end;
  Result:=True;
end;

{ Header borrowed, Result host LE32, ніколи не SENS number. }
function LE32(const Header:RawByteString):QWord;
begin
  if Length(Header)<>4 then raise EContextSession.Create('хибний LE32');
  Result:=QWord(Byte(Header[1])) or
         (QWord(Byte(Header[2])) shl 8) or
         (QWord(Byte(Header[3])) shl 16) or
         (QWord(Byte(Header[4])) shl 24);
end;

{ Data owned, Dest borrowed host stdout; no bytes until compiler succeeds. }
procedure Respond(Dest:TStream;OK:Boolean;const Data:RawByteString);
var H:array[0..4] of Byte;N:QWord;
begin
  N:=Length(Data);
  if (N=0) or (N>MaxELF) or ((not OK) and (N>4096)) then
    raise EContextSession.Create('вихід host поза квотою');
  if OK then H[0]:=1 else H[0]:=0;
  H[1]:=Byte(N and $FF); H[2]:=Byte((N shr 8) and $FF);
  H[3]:=Byte((N shr 16) and $FF); H[4]:=Byte((N shr 24) and $FF);
  Dest.WriteBuffer(H,SizeOf(H));
  Dest.WriteBuffer(Data[1],Length(Data));
end;

{ На кожен фізичний host кадр власний TVerifiedWideContext.Create/Free.
  Не передаємо жодного стану/ELF наступній програмі. При помилці
  виняток знищує незавершений object, caller діагностує лише status=0.
  1) Чому цю процедуру не називаємо загальним SENS REPL?
  2) Хто перевіряє pinned domain-width head?
  3) Чому контекст не може обслуговувати другу програму?
  4) Чому нижній x86 emitter однаковий?
  5) Де закриваються приватні IR managed arrays? }
function CompileOne(const Physical:RawByteString;Fast:Boolean):RawByteString;
var Context:TVerifiedWideContext;G:TELFGeometry;
begin
  if Fast then begin
    Context:=TVerifiedWideContext.Create(Physical,'external/sens');
    try Result:=BuildIRWideAbsFromContext(Context)
    finally Context.Free end;
  end else
    Result:=BuildVerifiedWideELF(Physical,'external/sens');
  VerifySENSELF64(Result,G);
  if (G.Kind<>3) or (G.Entry<>120) or
     (G.FileBytes<>Length(Result)) or (Length(Result)>MaxELF) then
    raise EContextSession.Create('неприпустима ELF64 PIE геометрія');
end;

procedure Serve(Fast:Boolean);
var Src,Dst:THandleStream;Header,Physical,Image,Diagnostic:RawByteString;
    Count,Frame:QWord;
begin
  Src:=THandleStream.Create(TextRec(Input).Handle);
  try
    Dst:=THandleStream.Create(TextRec(Output).Handle);
    try
      Frame:=0;
      while ReadExact(Src,4,True,Header) do begin
        Inc(Frame);
        if Frame>MaxFrames then
          raise EContextSession.Create('забагато host кадрів');
        Count:=LE32(Header);
        if (Count<1) or (Count>MaxT5M) then
          raise EContextSession.Create('host довжина .sens поза квотою');
        if not ReadExact(Src,SizeInt(Count),False,Physical) then
          raise EContextSession.Create('обірвано фізичну програму');
        try
          Image:=CompileOne(Physical,Fast);
          Respond(Dst,True,Image);
        except on E:Exception do begin
          Diagnostic:=RawByteString(E.Message);
          if (Length(Diagnostic)=0) or (Length(Diagnostic)>4096) then
            Diagnostic:=Ukr('відхилена фізична SENS програма');
          Respond(Dst,False,Diagnostic);
        end end;
      end;
      if Frame=0 then raise EContextSession.Create('порожній host сеанс');
    finally Dst.Free end;
  finally Src.Free end;
end;

begin
  ExitCode:=0;
  try
    {$IFNDEF LINUX}
    raise EContextSession.Create('потрібен Linux');
    {$ENDIF}
    {$IFNDEF CPUX86_64}
    raise EContextSession.Create('потрібен x86-64');
    {$ENDIF}
    if (ParamCount<>1) then
      raise EContextSession.Create('виклик: --звичайний або --контекст');
    if RawByteString(ParamStr(1))=Ukr('--звичайний') then Serve(False)
    else if RawByteString(ParamStr(1))=Ukr('--контекст') then Serve(True)
    else raise EContextSession.Create('невідомий host режим');
  except on E:Exception do begin
    WriteLn(StdErr,'КОНТЕКСТ-СЕАНС-ВІДМОВА: ',E.Message);
    ExitCode:=2;
  end end;
end.
