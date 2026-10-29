{ G4.34 — кілька фізичних D2-коренів із повними складеними відповідями.
  Немає нового обчислювача: закони виконує лише pinned TCore4Runtime. }
unit wsm.core4multiroot;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.core4runtime;
type ECore4MultiRootError=class(Exception);
function ExecuteCore4Roots(Runtime:TCore4Runtime;
  const Physical:RawByteString):RawByteString;
{ ЗАВЖДИ після реального ExecuteCore4Roots. Індекс — тільки host
  1-based позиція результату; ніколи не SENS D12+ число/виклик. }
function SelectCore4Result(const Physical:RawByteString;
  OneBasedIndex:SizeInt):RawByteString;
implementation
uses Classes, wsm.t5m, wsm.d2source, wsm.physloc,
  wsm.t5madmission{$IFDEF UNIX}, cwstring{$ENDIF};
const MaxRoots=64;

function SourcePosition(const Physical:RawByteString;
  const Spans:TPhysicalWordSpans; Word:SizeInt):String;
var At:TPhysicalWordSpan;
begin
  At:=LocatePhysicalWord(Physical,Spans,Word);
  Result:='слово='+IntToStr(At.WordIndex)+
    ' трити=['+IntToStr(At.TritStart)+','+IntToStr(At.TritEnd)+
    ') байти=['+IntToStr(At.ByteStart)+','+IntToStr(At.ByteEnd)+')';
  if At.IsEOF then Result:=Result+' EOF=так'
  else Result:=Result+' EOF=ні';
end;

{ G4.39: викликається ВИКЛЮЧНО після ET5MError існуючого
  DecodeT5MWithLocations. Це НЕ другий reader успішного потоку.
  InputPhysical — borrowed власником виклику RawByteString у packed T5M;
  Stream і необов'язковий TD2Document — локальні owned ресурси.
  Жодні часткові слова, позиції чи Core4-відповіді не публікуються.
  Відображення: ByteOffset/TritOffset 0-based, WordIndex 1-based.
  Питання: 1) Чому адресний preflight лише в негативному шляху?
  2) Чому W24 не дає числового D24?
  3) Чому ми використовуємо початкові байти без перепакування?
  4) Хто звільняє потік і TD2Document при пізній помилці? }
procedure RaiseLocatedT5MFailure(const InputPhysical:RawByteString;
  const DecoderReason:String);
var InputStream:TMemoryStream; UnusedDocument:TD2Document;
    UnusedSpans:TPhysicalWordSpans;
begin
  UnusedDocument:=nil;
  InputStream:=TMemoryStream.Create;
  try
    InputStream.WriteBuffer(InputPhysical[1],Length(InputPhysical));
    InputStream.Position:=0;
    try
      UnusedDocument:=ReadCheckedD2WideLocatedStream(InputStream,UnusedSpans);
    except
      on E:ET5MAdmissionError do
        raise ECore4MultiRootError.Create(
          'вхід T5M: байт='+IntToStr(E.ByteOffset)+
          ' трит='+IntToStr(E.TritOffset)+
          ' слово='+IntToStr(E.WordIndex)+' '+E.Message);
    end;
  finally
    UnusedDocument.Free;
    InputStream.Free;
  end;
  { Якщо preflight не знайшов саме транспортної помилки, зберігаємо
    оригінальну відмову декодера, а не вгадуємо її адресу. }
  raise ECore4MultiRootError.Create('вхід T5M: '+DecoderReason);
end;

{ Physical — позичені канонічні байти T5M; Runtime — позичене
  довгоживуче середовище pinned Core4. Вихід — новий RawByteString:
  усі фізичні результати як незалежні D2-корені. Жодна часткова
  відповідь не публікується; тимчасові TD2Document звільняються.
  Один D2-список не можна сплющувати до атома або вгадувати як число. }
function ExecuteCore4Roots(Runtime:TCore4Runtime;
  const Physical:RawByteString):RawByteString;
var
  SourceWords,Part,ResponseWords,AllWords:TExactWords;
  Spans:TPhysicalWordSpans;
  SourceDoc,ReplyDoc:TD2Document;
  First,Finish,I,J,UsedWords,Capacity,NextCapacity,UsedTrits,CandidateTrits:SizeInt;
  ReplyPhysical:RawByteString;
begin
  Result:='';SourceDoc:=nil;ReplyDoc:=nil;AllWords:=nil;
  UsedWords:=0;Capacity:=0;UsedTrits:=0;
  if Runtime=nil then
    raise ECore4MultiRootError.Create('відсутнє середовище pinned Core4');
  if (Length(Physical)<1) or (Length(Physical)>MAX_T5M_FILE_BYTES) then
    raise ECore4MultiRootError.Create('фізичне джерело поза межею T5M');
  try
    DecodeT5MWithLocations(Physical,SourceWords,Spans);
  except
    on E:ET5MError do RaiseLocatedT5MFailure(Physical,E.Message);
  end;
  if EncodeT5M(SourceWords)<>Physical then
    raise ECore4MultiRootError.Create('неканонічний фізичний потік');
  try
    SourceDoc:=ParseD2WordsWide(SourceWords);
  except
    on E:ED2SourceError do
      raise ECore4MultiRootError.Create(
        'вхід D2: '+SourcePosition(Physical,Spans,E.WordIndex)+' '+E.Message);
  end;
  try
    if (Length(SourceDoc.Roots)<1) or (Length(SourceDoc.Roots)>MaxRoots) then
      raise ECore4MultiRootError.Create('дозволено 1..64 фізичні форми');
    for I:=0 to High(SourceDoc.Roots) do begin
      First:=SourceDoc.Roots[I].WordIndex-1;
      Finish:=SourceDoc.Roots[I].EndWordIndexExclusive-1;
      if (First<0) or (Finish<=First) or (Finish>Length(SourceWords)) then
        raise ECore4MultiRootError.Create('пошкоджено межі D2-кореня');
      SetLength(Part,Finish-First);
      for J:=0 to High(Part) do Part[J]:=SourceWords[First+J];
      try
        ReplyPhysical:=Runtime.ExecutePhysicalCall(EncodeT5M(Part));
        DecodeT5M(ReplyPhysical,ResponseWords);
        if (Length(ResponseWords)=0) or
           (EncodeT5M(ResponseWords)<>ReplyPhysical) then
          raise ECore4MultiRootError.Create('неканонічна відповідь Core4');
        ReplyDoc:=ParseD2WordsWide(ResponseWords);
        try
          if Length(ReplyDoc.Roots)<>1 then
            raise ECore4MultiRootError.Create('Core4 повернув не один D2-корінь');
        finally FreeAndNil(ReplyDoc) end;
        { Фізична квота рахується в точних тритах T5M: біт кожного
          exact-слова + один роздільник між сусідніми словами.
          Жодна ширина сама по собі не дає доменної семантики. }
        if Length(ResponseWords)>MaxD2Words-UsedWords then
          raise ECore4MultiRootError.Create('сукупна відповідь перевищила межу D2');
        CandidateTrits:=UsedTrits;
        for J:=0 to High(ResponseWords) do begin
          if (UsedWords>0) or (J>0) then begin
            if CandidateTrits>=MAX_T5M_FILE_BYTES*5 then
              raise ECore4MultiRootError.Create('сукупна відповідь перевищила межу T5M');
            Inc(CandidateTrits);
          end;
          if Length(ResponseWords[J])>MAX_T5M_FILE_BYTES*5-CandidateTrits then
            raise ECore4MultiRootError.Create('сукупна відповідь перевищила межу T5M');
          Inc(CandidateTrits,Length(ResponseWords[J]));
        end;
        { Геометрична місткість — жодного повторного повного копіювання
          масиву після кожного кореня. Публікація лише після всіх коренів. }
        if UsedWords+Length(ResponseWords)>Capacity then begin
          NextCapacity:=Capacity;
          if NextCapacity=0 then NextCapacity:=16;
          while NextCapacity<UsedWords+Length(ResponseWords) do begin
            if NextCapacity>MaxD2Words div 2 then
              NextCapacity:=MaxD2Words
            else
              NextCapacity:=NextCapacity*2;
          end;
          SetLength(AllWords,NextCapacity);
          Capacity:=NextCapacity;
        end;
        for J:=0 to High(ResponseWords) do
          AllWords[UsedWords+J]:=ResponseWords[J];
        Inc(UsedWords,Length(ResponseWords));
        UsedTrits:=CandidateTrits;
      except
        on E:Exception do
          raise ECore4MultiRootError.Create(
            'форма='+IntToStr(I+1)+' '+
            SourcePosition(Physical,Spans,SourceDoc.Roots[I].WordIndex)+
            ' '+E.Message);
      end;
    end;
    { Надлишкова місткість ніколи не потрапляє у фізичний T5M. }
    SetLength(AllWords,UsedWords);
    Result:=EncodeT5M(AllWords);
    if Length(Result)>MAX_T5M_FILE_BYTES then
      raise ECore4MultiRootError.Create('фізична відповідь поза межею T5M');
  finally SourceDoc.Free end;
end;
{ Physical — позичена, уже ВИКОНАНА й канонічна відповідь Core4;
  OneBasedIndex — host порядковий індекс, не SENS домен чи opcode.
  Result — нові керовані FPC байти T5M ЛИШЕ одного повного кореня.
  TD2Document належить цьому виклику і звільняється навіть при відмові.
  Копіюємо слова разом із 10/01 рамкою, не значення без меж.
  Невдала перевірка НЕ публікує частковий Result і НЕ виконує форм. }
function SelectCore4Result(const Physical:RawByteString;
  OneBasedIndex:SizeInt):RawByteString;
var Words,Selected:TExactWords;Doc:TD2Document;
    First,Finish,I:SizeInt;
begin
  Result:='';Doc:=nil;
  if (OneBasedIndex<1) or (OneBasedIndex>MaxRoots) then
    raise ECore4MultiRootError.Create('індекс відповіді поза межами 1..64');
  if (Length(Physical)<1) or (Length(Physical)>MAX_T5M_FILE_BYTES) then
    raise ECore4MultiRootError.Create('фізична відповідь поза межею T5M');
  DecodeT5M(Physical,Words);
  if (Length(Words)=0) or (EncodeT5M(Words)<>Physical) then
    raise ECore4MultiRootError.Create('неканонічний результат T5M');
  Doc:=ParseD2WordsWide(Words);
  try
    if (Length(Doc.Roots)<1) or (Length(Doc.Roots)>MaxRoots) or
       (OneBasedIndex>Length(Doc.Roots)) then
      raise ECore4MultiRootError.Create('індекс відповіді відсутній серед D2-коренів');
    First:=Doc.Roots[OneBasedIndex-1].WordIndex-1;
    Finish:=Doc.Roots[OneBasedIndex-1].EndWordIndexExclusive-1;
    if (First<0) or (Finish<=First) or (Finish>Length(Words)) then
      raise ECore4MultiRootError.Create('пошкоджено межі вибраного D2-кореня');
    SetLength(Selected,Finish-First);
    for I:=0 to High(Selected) do Selected[I]:=Words[First+I];
    Result:=EncodeT5M(Selected);
    if (Length(Result)<1) or (Length(Result)>MAX_T5M_FILE_BYTES) then
      raise ECore4MultiRootError.Create('вибраний результат поза межею T5M');
  finally
    Doc.Free;
  end;
end;
end.
