{ G6.34: виклик ТІЛЬКИ власного фізично допущеного D3:110 ELF64.
  Не запускаємо чужий файл, не створюємо нового мовного evaluator. }
unit wsm.elfprobe;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type EELFProbeError=class(Exception);
procedure ExecutePinnedCondELF(const Physical,AuthorityRoot:RawByteString;
  out Answer:RawByteString);
implementation
uses Classes,Process,BaseUnix,wsm.elfcondt5m,wsm.elfgeometry,
  wsm.binaryexec,wsm.t5m;

procedure ExecutePinnedCondELF(const Physical,AuthorityRoot:RawByteString;
  out Answer:RawByteString);
var
  Image,Expected,Received,ErrBytes:RawByteString;
  Words:TExactWords; Geometry:TELFGeometry;
  Executor:TBinaryExecutor;
  Child:TProcess;
  Stream:TFileStream;
  Dir,Executable:String;
  Guid:TGUID;
  Buffer:array[0..255] of Byte;
  Available,N:LongInt;
  Deadline:QWord;
  FolderMade:Boolean;
  function Drain(Pipe:TInputPipeStream;var Dest:RawByteString):Boolean;
  begin
    Result:=False;
    Available:=Pipe.NumBytesAvailable;
    if Available<=0 then Exit;
    if Available>SizeOf(Buffer) then Available:=SizeOf(Buffer);
    N:=Pipe.Read(Buffer[0],Available);
    if N<=0 then Exit;
    if (Length(Dest)>4096-N) then
      raise EELFProbeError.Create('Машинний stdout/stderr перевищив host-ліміт');
    SetLength(Dest,Length(Dest)+N);
    Move(Buffer[0],Dest[Length(Dest)-N+1],N);
    Result:=True;
  end;
begin
  Answer:='';
  Received:='';ErrBytes:='';Child:=nil;
  FolderMade:=False;Dir:='';Executable:='';
  {$IFNDEF LINUX}
  raise EELFProbeError.Create('Машинний процес дозволено тільки на Linux x86-64');
  {$ENDIF}
  {$IFNDEF CPUX86_64}
  raise EELFProbeError.Create('Машинний процес потребує CPU x86-64');
  {$ENDIF}
  try
    if (Length(Physical)<1) or (Length(Physical)>65536) then
      raise EELFProbeError.Create('Фізичний T5M поза host-межею');
    Image:=BuildCondT5MELF(Physical,AuthorityRoot);
    VerifySENSELF64(Image,Geometry);
    if (Geometry.Kind<>2) or (Geometry.FileBytes<>Length(Image)) then
      raise EELFProbeError.Create('Неприпустимий профіль ELF64 D3:110');
    Executor:=TBinaryExecutor.Create(AuthorityRoot);
    try Expected:=Executor.ExecutePhysicalT5M(Physical);
    finally Executor.Free; end;
    DecodeT5M(Expected,Words);
    if (EncodeT5M(Words)<>Expected) or (Length(Words)<>1) or
       ((Words[0]<>'0') and (Words[0]<>'1') and (Words[0]<>'000')) or
       (Length(Expected)<>1) then
      raise EELFProbeError.Create('Довірений фізичний результат не D1/D3');
    if CreateGUID(Guid)<>0 then
      raise EELFProbeError.Create('Не створено випадковий host-ідентифікатор');
    Dir:=IncludeTrailingPathDelimiter(GetTempDir(False))+
      'sens-elf-d3-'+GUIDToString(Guid);
    if fpMkdir(PChar(Dir),&700)<>0 then
      raise EELFProbeError.Create('Не створено приватний каталог ELF');
    FolderMade:=True;
    Executable:=IncludeTrailingPathDelimiter(Dir)+'машина.elf';
    Stream:=TFileStream.Create(Executable,fmCreate);
    try Stream.WriteBuffer(Image[1],Length(Image));
    finally Stream.Free; end;
    if fpChmod(PChar(Executable),&500)<>0 then
      raise EELFProbeError.Create('Не дозволено запуск приватного ELF');
    Child:=TProcess.Create(nil);
    Child.Executable:=Executable;
    Child.CurrentDirectory:=Dir;
    Child.Options:=[poUsePipes];
    Child.Execute;
    Deadline:=GetTickCount64+2000;
    repeat
      Drain(Child.Output,Received);
      Drain(Child.Stderr,ErrBytes);
      if (not Child.Running) and
         (Child.Output.NumBytesAvailable=0) and
         (Child.Stderr.NumBytesAvailable=0) then Break;
      if GetTickCount64>Deadline then
        raise EELFProbeError.Create('Перевищено двосекундний host-ліміт ELF');
      Sleep(5);
    until False;
    Child.WaitOnExit;
    if Child.ExitStatus<>0 then
      raise EELFProbeError.Create('Машинний ELF завершився з кодом '+
        IntToStr(Child.ExitStatus));
    if ErrBytes<>'' then
      raise EELFProbeError.Create('Машинний ELF написав у stderr');
    if Received<>Expected then
      raise EELFProbeError.Create('Машинний T5M побайтово не збігся з D3 runtime');
    Answer:=Received;
  except
    on E:Exception do begin
      Answer:='';
      raise EELFProbeError.Create('Фізичний ELF відхилено: '+E.Message);
    end;
  finally
    if Child<>nil then begin
      if Child.Running then begin
        Child.Terminate(9);
        Child.WaitOnExit;
      end;
      Child.Free;
    end;
    if Executable<>'' then DeleteFile(Executable);
    if FolderMade then RemoveDir(Dir);
  end;
end;

{ Пам'ять/форма: Physical — borrowed canonical packed T5M RawByteString;
  Image та Expected живуть лише до кінця синхронного виклику.
  Answer (out) — рівно один packed T5M байт тільки після машинного exit=0,
  збігу з нативним evaluator і порожнього stderr; інакше Answer=''.
  Тимчасовий ELF — виключно в host каталозі mode 0700 з видаленням у finally.
  Цей запуск локального executable НЕ є sandbox.
  Питання: 1) Чому Generate ELF виконується з Physical щоразу?
  2) Чому ELF geometry не доводить SENS-семантики?
  3) Як D3:000 відрізняється від D1:0 у T5M?
  4) Чому stdout перевіряється побайтово без UTF-8?
  5) Що саме очищається після timeout або неканонічного входу? }
end.
