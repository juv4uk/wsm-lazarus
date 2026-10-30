{ G6.97 — єдиний host CLI для чотирьох ратифікованих двійкових
  форм, без текстового, англійського або Lisp-dispatch.
  Фізичне .sens -> verified pinned WideIR -> існуючий ELF64 backend. }
program senswidefrontelf;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Classes,Process,wsm.irwidefront,wsm.elfpublish,wsm.elfgeometry;
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

{ Механічний шлях до вже pinned authority, не вибір мовного закону.
  У старому інтерфейсі cwd і далі задає external/sens; явний
  абсолютний шлях дозволяє IDE викликати той самий compiler із іншого cwd.
  Перевірка фактичного gitlink/Contract 12 залишається за check-pin.sh,
  а не за довільним текстом шляху.
  1) Чому host-шлях не є D7-іменем або координатою?
  2) Чому відносний шлях у новому режимі відхиляється?
  3) Хто перевіряє gitlink pinned SENS перед збіркою?
  4) Чому UI і CLI мають викликати один BuildVerifiedWideELF? }

{ Механічний Git preflight: перевіряємо НЕ status/index, а байти
  одинадцяти файлів проти tree pinned commit. Вхід Root — позичений
  host-каталог, Output — owned stdout git, ніякого SENS значення.
  Пам'ять TProcess, pipes і службових масивів звільняється в finally.
  1) Чому правильний HEAD не доводить робочі байти?
  2) Чому assume-unchanged не може сховати модифікацію від hash-object?
  3) Чому поява .lisp не створює новий мовний закон?
  4) Чому перевірка робиться раніше за читання .sens? }
function GitOutput(const Root:String;const Args:array of String):RawByteString;
var Proc:TProcess;I,N,Count,OldSize:SizeInt;Chunk:array[0..1023] of Byte;
begin
  Result:='';
  Proc:=TProcess.Create(nil);
  try
    Proc.Executable:='git';
    Proc.Options:=[poUsePipes,poStderrToOutput];
    Proc.Parameters.Add('-C');
    Proc.Parameters.Add(Root);
    for I:=Low(Args) to High(Args) do Proc.Parameters.Add(Args[I]);
    Proc.Execute;
    if not Proc.WaitOnExit(10000) then begin
      Proc.Terminate(9);
      Proc.WaitOnExit(1000);
      raise EWideFrontCLI.Create('вичерпано час перевірки pinned SENS');
    end;
    if Proc.ExitStatus<>0 then
      raise EWideFrontCLI.Create('не пройдено Git-перевірку pinned SENS');
    while Proc.Output.NumBytesAvailable>0 do begin
      N:=Proc.Output.NumBytesAvailable;
      if N>SizeOf(Chunk) then N:=SizeOf(Chunk);
      OldSize:=Length(Result);
      if (N<1) or (OldSize+N>8192) then
        raise EWideFrontCLI.Create('завелика відповідь Git-перевірки');
      SetLength(Result,OldSize+N);
      Count:=Proc.Output.Read(Chunk[0],N);
      if Count<>N then
        raise EWideFrontCLI.Create('неповна відповідь Git-перевірки');
      Move(Chunk[0],Result[OldSize+1],N);
    end;
  finally
    Proc.Free;
  end;
end;

procedure CheckPinnedRoot(const Root:String);
const
  Pin='1f1bf676eeac605e065035d9dd2adaae807f1788';
  Paths:array[0..10] of String=(
    'contracts/language-contract-12.lisp',
    'lib/domains/d1.lisp', 'lib/domains/d10.lisp',
    'lib/domains/d2.lisp', 'lib/domains/d3.lisp',
    'lib/domains/d4.lisp', 'lib/domains/d5.lisp',
    'lib/domains/d6.lisp', 'lib/domains/d7.lisp',
    'lib/domains/d8.lisp', 'lib/domains/d9.lisp');
var Tree,Actual:TStringList;TreeArgs,HashArgs:array of String;
    I:SizeInt;Line:RawByteString;
begin
  if Trim(String(GitOutput(Root,['rev-parse','HEAD'])))<>Pin then
    raise EWideFrontCLI.Create('корінь SENS має інший pinned commit');
  SetLength(TreeArgs,Length(Paths)+4);
  TreeArgs[0]:='ls-tree';TreeArgs[1]:='-r';
  TreeArgs[2]:=Pin;TreeArgs[3]:='--';
  SetLength(HashArgs,Length(Paths)+3);
  HashArgs[0]:='hash-object';HashArgs[1]:='--no-filters';
  HashArgs[2]:='--';
  for I:=Low(Paths) to High(Paths) do begin
    TreeArgs[I+4]:=Paths[I];
    HashArgs[I+3]:=Paths[I];
  end;
  Tree:=TStringList.Create;
  try
    Actual:=TStringList.Create;
    try
      Tree.Text:=String(GitOutput(Root,TreeArgs));
      Actual.Text:=String(GitOutput(Root,HashArgs));
      if (Tree.Count<>Length(Paths)) or (Actual.Count<>Length(Paths)) then
        raise EWideFrontCLI.Create('неповний pinned набір D1–D10 та Contract 12');
      for I:=Low(Paths) to High(Paths) do begin
        Line:=RawByteString(Tree[I]);
        if (Length(Line)<54) or
           (Copy(Line,1,12)<>'100644 blob ') or
           (Line[53]<>#9) or
           (Copy(Line,54,Length(Line)-53)<>RawByteString(Paths[I])) or
           (Length(Actual[I])<>40) or
           (Copy(Line,13,40)<>RawByteString(Actual[I])) then
          raise EWideFrontCLI.Create(
            'вміст pinned SENS відрізняється від Git tree: '+Paths[I]);
      end;
    finally Actual.Free end;
  finally Tree.Free end;
end;

function AuthorityRoot:RawByteString;
var P:String;
begin
  if ParamCount=3 then Exit('external/sens');
  if (ParamCount<>5) or
     (RawByteString(ParamStr(4))<>UA('--корінь-sens')) then
    raise EWideFrontCLI.Create('потрібен явний --корінь-sens');
  P:=ParamStr(5);
  if (P='') or (Length(P)>4096) or (P[1]<>'/') then
    raise EWideFrontCLI.Create('корінь SENS має бути абсолютним шляхом');
  P:=ExcludeTrailingPathDelimiter(ExpandFileName(P));
  if (not DirectoryExists(P)) or
     (not FileExists(P+'/contracts/language-contract-12.lisp')) then
    raise EWideFrontCLI.Create('немає фізичного каталогу контракту SENS 12.0');
  CheckPinnedRoot(P);
  Result:=RawByteString(P);
end;

procedure Run;
var Source,Image,OnDisk,Mode,Root:RawByteString;G:TELFGeometry;
begin
  if ((ParamCount<>3) and (ParamCount<>5)) or
     (ExtractFileExt(ParamStr(3))<>'.elf') then
    raise EWideFrontCLI.Create(
      'виклик: senswidefrontelf --скомпілювати-фізичну-форму|--звірити-походження джерело.sens машина.elf [--корінь-sens /absolute/external/sens]');
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
  Root:=AuthorityRoot;
  Source:=ReadPhysical(ParamStr(2));
  Image:=BuildVerifiedWideELF(Source,Root);
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
