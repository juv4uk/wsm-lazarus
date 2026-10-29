{ G6.35 — атомарна публікація ТІЛЬКИ перевіреного native ELF64.
  Формат/геометрію незалежно підтверджує злитий wsm.elfgeometry;
  мовний pinned admission лишається у наявних D3 emitters. }
unit wsm.elfpublish;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils,wsm.elfgeometry;
type EELFPublishError=class(Exception);
procedure PublishNewELF64(const Path:String;const Image:RawByteString;
  ExpectedKind:Word;out Geometry:TELFGeometry);
implementation
uses
  {$IFDEF UNIX}BaseUnix{$ELSE}Classes{$ENDIF};

{$IFDEF UNIX}
function CreatePrivateTemp(Template:PChar):cint; cdecl; external 'c' name 'mkstemp';
{ FPC 3.2.2 BaseUnix не експортує fpFChmod: POSIX fchmod через libc.
  mode_t у Linux x86-64 — беззнакове 32-бітове; не міняє SENS семантику. }
function SetExecutableMode(FD:cint; Mode:LongWord):cint; cdecl;
  external 'c' name 'fchmod';
{$ENDIF}

{ Image — borrowed, fully admitted ELF64 bytes; Path — borrowed host
  destination. mkstemp atomically opens a fresh private 0600 inode and
  returns FD. Short writes loop on the original FD, fchmod marks executable
  only AFTER all ELF bytes are written, close before atomic fpLink. Temp
  inode is unlinked even if validation/publication fails. No separate
  fmCreate/reopen with a path-dependent race or umask-dependent permissions.
  Geometry stays zero until a fully published ELF is available.
  Questions: 1) Why fchmod on the open FD instead of pathname?
  2) Why is fpLink a no-clobber publication even for dangling symlinks?
  3) What is the lifetime of the temporary inode and FD?
  4) Why are ELF kinds 2/3 host ABI, not SENS D2/D3 semantics?
  5) What guarantees that executable bytes remain unchanged? }
procedure PublishNewELF64(const Path:String;const Image:RawByteString;
  ExpectedKind:Word;out Geometry:TELFGeometry);
var
  Admitted:TELFGeometry;
{$IFDEF UNIX}
  Temp:RawByteString;
  FD:cint;
  Offset,Written:SizeInt;
  Created:Boolean;
{$ENDIF}
begin
  FillChar(Geometry,SizeOf(Geometry),0);
  try
    if (ExpectedKind<>2) and (ExpectedKind<>3) then
      raise EELFPublishError.Create('Непідтриманий host тип ELF64');
    if Path='' then
      raise EELFPublishError.Create('Відсутнє ім’я вихідного ELF');
    VerifySENSELF64(Image,Admitted);
    if (Admitted.Kind<>ExpectedKind) or
       (Admitted.FileBytes<>Length(Image)) or (Admitted.MachineBytes<1) then
      raise EELFPublishError.Create('ELF64 не збігся із перевіреним host профілем');
    {$IFDEF UNIX}
    Temp:=''; FD:=-1; Created:=False;
    try
      Temp:=RawByteString(IncludeTrailingPathDelimiter(
        ExtractFilePath(ExpandFileName(Path)))+'senXXXXXX');
      UniqueString(Temp);  { C mkstemp змінює шість символів на місці }
      FD:=CreatePrivateTemp(PChar(Temp));
      if FD<0 then
        raise EELFPublishError.Create('Не створено приватний ELF64');
      Created:=True;
      Offset:=0;
      while Offset<Length(Image) do begin
        Written:=fpWrite(FD,Image[Offset+1],Length(Image)-Offset);
        if Written<=0 then
          raise EELFPublishError.Create('Не записано повний перевірений ELF64');
        Inc(Offset,Written);
      end;
      if SetExecutableMode(FD,&700)<>0 then
        raise EELFPublishError.Create('Не встановлено права 0700 для ELF64');
      if fpClose(FD)<>0 then begin
        FD:=-1;
        raise EELFPublishError.Create('Не закрито повний ELF64');
      end;
      FD:=-1;
      if fpLink(PChar(Temp),PChar(Path))<>0 then
        raise EELFPublishError.Create('Ціль ELF64 уже існує або захищена');
      Geometry:=Admitted;
    finally
      if FD>=0 then fpClose(FD);
      if Created then fpUnlink(PChar(Temp));
    end;
    {$ELSE}
    raise EELFPublishError.Create('Атомарний ELF64 на цій системі не підтримується');
    {$ENDIF}
  except
    on E:Exception do begin
      FillChar(Geometry,SizeOf(Geometry),0);
      if E is EELFPublishError then raise;
      raise EELFPublishError.Create('Відхилено створення ELF64: '+E.Message);
    end;
  end;
end;

{ Контракт: вихід Geometry — обнулений на відмові, чинний тільки
  після успішного fd-запису/зміни прав/закриття/атомарної публікації.
  SENS — авторитет форми; ELF64 — виключно механізм Linux x86-64.
  .sens лишається двійковим, .lisp і всі поверхні — людськими. }
end.
