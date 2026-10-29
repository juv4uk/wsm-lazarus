{ G6.132 — ТІЛЬКИ host-механізм виконання вже допущеного ELF64.
  Image: borrowed exact byte image; ResultRaw: owned packed T5M stdout.
  Не розпізнає жодної назви/оператора/числового закону SENS.
  Private mkdtemp 0700 -> єдиний чинний PublishNewELF64 no-clobber ->
  TProcess без shell, 3 сек/64 байти, exit=0 -> Decode/Encode T5M.
  Повернення повністю транзакційне; temp ELF і каталог прибираються.
  Запитання: 1) Чому не можна виконувати шлях до довільного ELF?
  2) Навіщо приватний каталог і no-clobber? 3) Хто володіє TProcess?
  4) Чому W12-байти не надають числового закону?
  5) Як обмежено час, обсяг і помилковий stdout? }
unit wsm.elfexecute;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type EVerifiedELFRun=class(Exception);
procedure RunVerifiedELF(const Image:RawByteString;out ResultRaw:RawByteString);
implementation
uses Classes,Process,BaseUnix,wsm.elfpublish,wsm.elfgeometry,wsm.t5m;
const MaxNativeStdout=64;MaxNativeMillis=3000;
function CreatePrivateDirectory(Template:PChar):PChar;cdecl;external 'c' name 'mkdtemp';

procedure RunVerifiedELF(const Image:RawByteString;out ResultRaw:RawByteString);
var Folder,Executable,Buffer:RawByteString;
    Proc:TProcess;Geometry:TELFGeometry;Words:TExactWords;
    N,Pending:LongInt;StartTime:QWord;Started:Boolean;
begin
  ResultRaw:='';
  {$IFNDEF LINUX}
  raise EVerifiedELFRun.Create('виконання доступне лише на Linux');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EVerifiedELFRun.Create('потрібний процесор x86-64');
  {$ENDIF}
  { Перевіряємо образ до створення будь-якого об’єкта на файловій системі. }
  VerifySENSELF64(Image,Geometry);
  if (Geometry.Kind<>3) or (Geometry.Entry<>120) or
     (Geometry.FileBytes<>Length(Image)) or (Geometry.MachineBytes<1) then
    raise EVerifiedELFRun.Create('не допущений перевірений ELF64 PIE');
  Folder:=RawByteString(IncludeTrailingPathDelimiter(GetTempDir(False))+
    'sens-native-XXXXXX');
  UniqueString(Folder);
  if CreatePrivateDirectory(PChar(Folder))=nil then
    raise EVerifiedELFRun.Create('не створено приватний каталог запуску');
  Executable:=Folder+'/native.elf';
  try
    PublishNewELF64(String(Executable),Image,3,Geometry);
    Proc:=TProcess.Create(nil);
    try
      Proc.Executable:=String(Executable);
      Proc.Options:=[poUsePipes,poStderrToOutput];
      Proc.Parameters.Clear;{ Ніяких аргументів / shell або довільного path. }
      Started:=False;
      Proc.Execute;
      Started:=True;
      StartTime:=GetTickCount64;
      Buffer:='';
      repeat
        Pending:=LongInt(Proc.Output.NumBytesAvailable);
        if Pending>0 then begin
          if (Pending>MaxNativeStdout-Length(Buffer)) then
            raise EVerifiedELFRun.Create('перевищено межу фізичного stdout');
          N:=Length(Buffer);SetLength(Buffer,N+Pending);
          if Proc.Output.Read(Buffer[N+1],Pending)<>Pending then
            raise EVerifiedELFRun.Create('неповний stdout нативного процесу');
        end;
        if not Proc.Running then Break;
        if GetTickCount64-StartTime>MaxNativeMillis then
          raise EVerifiedELFRun.Create('перевищено час нативного процесу');
        Sleep(5);
      until False;
      if (not Proc.WaitOnExit(300)) or (Proc.ExitStatus<>0) then
        raise EVerifiedELFRun.Create('нативний процес завершився помилкою');
      { Фінальні байти залишаються в pipe після зупинки процесу. }
      Pending:=LongInt(Proc.Output.NumBytesAvailable);
      if Pending>MaxNativeStdout-Length(Buffer) then
        raise EVerifiedELFRun.Create('завеликий фізичний stdout');
      if Pending>0 then begin
        N:=Length(Buffer);SetLength(Buffer,N+Pending);
        if Proc.Output.Read(Buffer[N+1],Pending)<>Pending then
          raise EVerifiedELFRun.Create('неповний останній фізичний stdout');
      end;
      DecodeT5M(Buffer,Words);
      if (Length(Words)<>1) or (EncodeT5M(Words)<>Buffer) then
        raise EVerifiedELFRun.Create('stdout не є одним канонічним словом T5M');
      ResultRaw:=Buffer;
    finally
      if Assigned(Proc) then begin
        if Started and Proc.Running then begin
          Proc.Terminate(9);
          Proc.WaitOnExit(1000);
        end;
        Proc.Free;
      end;
    end;
  finally
    fpUnlink(PChar(Executable));
    if not RemoveDir(String(Folder)) then
      raise EVerifiedELFRun.Create('не очищено приватний каталог запуску');
  end;
end;
end.
