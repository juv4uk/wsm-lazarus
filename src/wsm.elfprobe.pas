{ G6.34: виклик ТІЛЬКИ власного фізично допущеного D3:110 ELF64.
  G6.42: усі п'ять машинних профілів проходять pinned ExactIR provenance.
  Не запускаємо чужий файл, не створюємо нового мовного evaluator. }
unit wsm.elfprobe;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils;
type
  EELFProbeError=class(Exception);
  { Вибір УЖЕ ІСНУЮЧОГО host emitter, не enum мовних законів. }
  TNativeELFProfile=(npQuote,npAtom,npEq,npSelector,npCond);
procedure ExecutePinnedNativeELF(const Physical,AuthorityRoot:RawByteString;
  Profile:TNativeELFProfile;out Answer:RawByteString);
procedure ExecutePinnedCondELF(const Physical,AuthorityRoot:RawByteString;
  out Answer:RawByteString);
implementation
uses Classes,Process,Pipes,BaseUnix,
  wsm.bind,wsm.exactir,wsm.exactirtoelf,wsm.elfgeometry,
  wsm.binaryexec,wsm.t5m;

procedure ExecutePinnedNativeELF(const Physical,AuthorityRoot:RawByteString;
  Profile:TNativeELFProfile;out Answer:RawByteString);
var
  Image,Expected,Received,ErrBytes:RawByteString;
  Words:TExactWords; Geometry:TELFGeometry;
  Tables:TDomainSet; CandidateIR:TExactIR;
  ExpectedELFKind:Word;
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
    try
    if (Length(Physical)<1) or (Length(Physical)>65536) then
      raise EELFProbeError.Create('Фізичний T5M поза host-межею');
    { G6.42: перед створенням ELF профільний probe ЗАВЖДИ будує
      фізичний ExactIR зі свіжих pinned доменів, а потім передає
      його до вже злитих BuildVerified*IR. Кожний такий місток
      вдруге відтворює всі T5M/D2/word/trit/byte координати,
      перевіряє позичений IR та викликає старий machine emitter.
      Ці host-профілі не є реєстром мовних законів; D7 залишається
      даними, D12+ ніколи не перетворюється на D1. }
    LoadPinnedDomains(AuthorityRoot,Tables);
    BuildExactIR(Physical,Tables,CandidateIR);
    case Profile of
      npQuote: begin
        Image:=BuildVerifiedQuoteIR(Physical,AuthorityRoot,CandidateIR);
        ExpectedELFKind:=3;
      end;
      npAtom: begin
        Image:=BuildVerifiedAtomIR(Physical,AuthorityRoot,CandidateIR);
        ExpectedELFKind:=2;
      end;
      npEq: begin
        Image:=BuildVerifiedEqIR(Physical,AuthorityRoot,CandidateIR);
        ExpectedELFKind:=3;
      end;
      npSelector: begin
        Image:=BuildVerifiedSelectorIR(Physical,AuthorityRoot,CandidateIR);
        ExpectedELFKind:=3;
      end;
      npCond: begin
        Image:=BuildVerifiedCondIR(Physical,AuthorityRoot,CandidateIR);
        ExpectedELFKind:=2;
      end;
      else raise EELFProbeError.Create('Непідтриманий host ELF профіль');
    end;
    VerifySENSELF64(Image,Geometry);
    if (Geometry.Kind<>ExpectedELFKind) or
       (Geometry.FileBytes<>Length(Image)) then
      raise EELFProbeError.Create('Неприпустима геометрія профілю ELF64');
    Executor:=TBinaryExecutor.Create(AuthorityRoot);
    try Expected:=Executor.ExecutePhysicalT5M(Physical);
    finally Executor.Free; end;
    DecodeT5M(Expected,Words);
    if (EncodeT5M(Words)<>Expected) or (Length(Expected)<1) or
       (Length(Expected)>4096) or (Length(Words)<1) then
      raise EELFProbeError.Create('Нативний D3 не повернув canonical T5M');
    { D3:001 може цитувати точну D7 або структурну D2-форму.
      Для предикатів/селекторів/умови лишаємо вузьку перевірку
      ратифікованого РЕЗУЛЬТАТУ, не переносимо закони в Pascal.
      Єдиний oracle тут — чинний native executor, не SENS REPL. }
    if Profile<>npQuote then
      if (Length(Words)<>1) or (Length(Expected)<>1) or
         ((Words[0]<>'0') and (Words[0]<>'1') and
          ((Profile<>npCond) or (Words[0]<>'000'))) then
        raise EELFProbeError.Create(
          'Фізичний результат не відповідає підтвердженому вузькому D3');
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

{ Зберігаємо незмінний публічний API графічного Lazarus G6.34:
  той самий D3:110 emitter після G6.42 ExactIR guard, той самий run+compare, без другого
  процесу, друга чи послаблення тестів. }
procedure ExecutePinnedCondELF(const Physical,AuthorityRoot:RawByteString;
  out Answer:RawByteString);
begin
  ExecutePinnedNativeELF(Physical,AuthorityRoot,npCond,Answer);
end;

{ Пам'ять/форма: Physical — borrowed canonical packed T5M RawByteString;
  Tables:TDomainSet — локальні pinned D1–D10 таблиці, CandidateIR:TExactIR
  містить керовані FPC масиви вузлів і коренів та не переживає цей виклик.
  Вони не мають окремого manual-free: звільняються за scope процедури.
  Image та Expected живуть лише до кінця синхронного виклику.
  Answer (out) — packed canonical T5M тільки після машинного exit=0,
  збігу з нативним evaluator і порожнього stderr; інакше Answer=''.
  Тимчасовий ELF — виключно в host каталозі mode 0700 з видаленням у finally.
  Цей запуск локального executable НЕ є sandbox.
  Питання: 1) Чому Generate ELF виконується з Physical щоразу?
  2) Чому ELF geometry не доводить SENS-семантики?
  3) Як D3:000 відрізняється від D1:0 у T5M?
  4) Чому stdout перевіряється побайтово без UTF-8?
  5) Що саме очищається після timeout або неканонічного входу?
  6) Чому навіть структурно правильний CandidateIR перевіряється вдруге? }
end.
