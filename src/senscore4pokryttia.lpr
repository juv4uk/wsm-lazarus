{ G4.43: перепис pinned Core4 для вимірювання ЗАВАНТАЖЕННЯ, не семантики.
  Вхідна .lisp є лише українською людською проєкцією.
  Ідентичність законів та виконання не виводяться з написання «визначити».
  Лише чинний TCore4Runtime допускає початкові bindings із фізичного .sens.
  Doc і Runtime локальні owned об'єкти, звільняються навіть після відмови.
  Питання: чому «визначити» не є semantic dispatch? Хто підтвердив 3?
  Чи означає 3/1223 повну підтримку? Чому W24 не означає D24 число? }
program senscore4pokryttia;
{$mode objfpc}{$H+}
uses SysUtils, Classes, wsm.core4source, wsm.source, wsm.core4runtime,
  wsm.t5m, wsm.d2source;

{ G4.46: декодування ВЖЕ чинним транспортом і структурний допуск
  кожного фізичного D2-кореня вже чинним широким D2 reader.
  MaxD2Words обмежує ОДИН корінь, не всю бібліотеку з 278857 слів.
  RootBoundary лише відокремлює D2:10 ... D2:01 пакети, а всі
  правила структури (включно з D2:11 крапковою парою) належать
  ParseD2WordsWide. Немає тут декодера, evaluator чи законів. }
function PhysicalCensus(const RepoRoot:String; ExpectedRoots:SizeInt):RawByteString;
const MaxCensusWords=500000; { бюджет аудиту, не мовний закон }
var
  FileName:String;
  F:TFileStream;
  Physical:RawByteString;
  Words,Segment:TExactWords;
  Doc:TD2Document;
  Start,I,Depth,Count,RootSize:SizeInt;
begin
  Result:='';
  FileName:=IncludeTrailingPathDelimiter(ExpandFileName(RepoRoot))+
    'external'+PathDelim+'sens'+PathDelim+'lib'+PathDelim+'core4.sens';
  F:=TFileStream.Create(FileName,fmOpenRead or fmShareDenyWrite);
  try
    if (F.Size<=0) or (F.Size>MAX_T5M_FILE_BYTES) then
      raise Exception.Create('неприпустимий розмір фізичного Core4');
    SetLength(Physical,SizeInt(F.Size));
    F.ReadBuffer(Physical[1],Length(Physical));
  finally
    F.Free;
  end;
  DecodeT5M(Physical,Words);
  if (Length(Words)<1) or (Length(Words)>MaxCensusWords) then
    raise Exception.Create('фізичний Core4 перевищує бюджет слів');
  Start:=-1;
  Depth:=0;
  Count:=0;
  Doc:=nil;
  for I:=0 to High(Words) do begin
    if (Depth=0) and (Words[I]='00') then
      Continue; { той самий D2:00 SkipSeparators, що й у чинному reader }
    if Depth=0 then begin
      if Words[I]<>'10' then
        raise Exception.Create('новий фізичний корінь Core4 не є D2-списком, слово '+
          IntToStr(I+1));
      Start:=I;
    end;
    if Words[I]='10' then Inc(Depth)
    else if Words[I]='01' then begin
      Dec(Depth);
      if Depth<0 then raise Exception.Create('зайве D2-закриття у Core4');
    end;
    if (Depth>MaxD2SyntaxDepth) then
      raise Exception.Create('надмірна вкладеність фізичного Core4');
    if Depth=0 then begin
      RootSize:=I-Start+1;
      if (RootSize>MaxD2Words) then
        raise Exception.Create('фізична форма Core4 понад бюджет D2 reader');
      Segment:=Copy(Words,Start,RootSize);
      { Парсер НЕ бачить частини іншого кореня; його власність обмежена
        поточною перевіркою і звільняється до наступного кореня. }
      Doc:=ParseD2WordsWide(Segment);
      try
        if (Length(Doc.Roots)<>1) or
           (Doc.Roots[0].Kind<>dkList) then
          raise Exception.Create('фізична форма Core4 не є одним D2-списком');
      finally
        FreeAndNil(Doc);
      end;
      Inc(Count);
      if Count>ExpectedRoots then
        raise Exception.Create('фізичних форм Core4 більше, ніж в укр проєкції');
      Start:=-1;
    end;
  end;
  if (Depth<>0) or (Start<>-1) then
    raise Exception.Create('пізній незакритий фізичний D2-корінь Core4');
  if Count<>ExpectedRoots then
    raise Exception.Create('кількість фізичних і українських коренів розходиться');
  Result:=' форм-фізично='+IntToStr(Count)+
    ' слів-фізично='+IntToStr(Length(Words));
end;

function Perepys(const Root:String; FullPhysical:Boolean):RawByteString;
var
  Doc:TSourceDocument;
  Runtime:TCore4Runtime;
  I,Total,Lexical,BodyLists,BodyAtoms,BodyStrings,BodyOther,Loaded:SizeInt;
  PhysicalExtra:RawByteString;
  N,Body:TSourceNode;
begin
  Result:='';
  Doc:=nil;
  Runtime:=nil;
  try
    { Borrowed text bytes live in this call; Doc owns all parsed nodes. }
    Doc:=ReadUkrainianSource(ReadPinnedCore4(Root));
    Total:=Length(Doc.Forms);
    if Total=0 then raise Exception.Create('порожній український Core4');
    Lexical:=0;
    BodyLists:=0;BodyAtoms:=0;BodyStrings:=0;BodyOther:=0;
    for I:=0 to High(Doc.Forms) do begin
      N:=Doc.Forms[I];
      { ЛИШЕ структурне українське написання для статистики.
        Не допускає і не виконує ні D4, ні один похідний закон. }
      if (N.Kind=skList) and (Length(N.Children)>0) and
         (N.Children[0].Kind=skAtom) and
         (N.Children[0].Text='визначити') then begin
        Inc(Lexical);
        if Length(N.Children)<>3 then begin
          Inc(BodyOther);
          Continue;
        end;
        Body:=N.Children[2];
        case Body.Kind of
          skList:Inc(BodyLists);
          skAtom:Inc(BodyAtoms);
          skString:Inc(BodyStrings);
        end;
      end;
    end;
    { Runtime фізично читає pinned lib/core4.sens і допускає перші
      канонічні D2-форми. Це НЕ виконання всіх визначень джерела. }
    Runtime:=TCore4Runtime.Create(Root);
    Loaded:=Runtime.BindingCount;
    if (Loaded<1) or (Lexical<Loaded) then
      raise Exception.Create('лексичний і фізичний Core4 не узгоджені');
    PhysicalExtra:='';
    if FullPhysical then PhysicalExtra:=PhysicalCensus(Root,Total);
    Result:='CORE4-ПЕРЕПИС-ГАРАЗД форм-укр='+IntToStr(Total)+
      ' визначень-укр='+IntToStr(Lexical)+
      ' тіл-списків='+IntToStr(BodyLists)+
      ' тіл-атомів='+IntToStr(BodyAtoms)+
      ' тіл-рядків='+IntToStr(BodyStrings)+
      ' тіл-інших='+IntToStr(BodyOther)+
      ' завантажено-фізично='+IntToStr(Loaded)+
      PhysicalExtra+
      ' виконання-всіх=не-доведено'+LineEnding;
  finally
    Runtime.Free;
    Doc.Free;
  end;
end;

var Answer:RawByteString;
begin
  if (ParamCount<>2) or
     ((ParamStr(1)<>'--перепис') and (ParamStr(1)<>'--перепис-фізичний')) then begin
    WriteLn(StdErr,'CORE4-ПЕРЕПИС-ВІДМОВА: команда --перепис | --перепис-фізичний корінь');
    ExitCode:=64;
  end else begin
    try
      Answer:=Perepys(ParamStr(2),ParamStr(1)='--перепис-фізичний');
      Write(Answer); { атомарний stdout лише після повного допуску }
      ExitCode:=0;
    except
      on E:Exception do begin
        WriteLn(StdErr,'CORE4-ПЕРЕПИС-ВІДМОВА: ',E.Message);
        ExitCode:=2;
      end;
    end;
  end;
end.
