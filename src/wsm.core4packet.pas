{ G5.26/G5.28 — суто механічне виконання фізичного пакета у pinned Core4.
  T5M/D2 задає межі кореневих форм, усі закони виконує TCore4Runtime.
  Одна відповідь публікується лише після успіху всіх 1..64 форм.
  Це НЕ загальний evaluator і НЕ транзакція мовного середовища. }
unit wsm.core4packet;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses SysUtils, wsm.core4runtime;

const MaxCore4ChannelForms = 64;
type ECore4PacketError = class(Exception);
function ExecuteCore4Packet(Runtime:TCore4Runtime;
  const Physical:RawByteString):RawByteString;

implementation
uses wsm.t5m, wsm.d2source, wsm.physloc;

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

{ Відображення тільки host-координат ОРИГІНАЛЬНОГО T5M.
  Spans — перевірені 1-based exact слова, 0-based half-open трити/байти.
  Немає нового SENS predicate чи семантичного dispatch. }
function FailureLocation(const Physical:RawByteString;
  const Spans:TPhysicalWordSpans; WordIndex:SizeInt):RawByteString;
var At:TPhysicalWordSpan;
begin
  At:=LocatePhysicalWord(Physical,Spans,WordIndex);
  Result:=Ukr('слово=')+IntToStr(At.WordIndex)+
    Ukr(' трити=[')+IntToStr(At.TritStart)+','+
      IntToStr(At.TritEnd)+')'+
    Ukr(' байти=[')+IntToStr(At.ByteStart)+','+
      IntToStr(At.ByteEnd)+')'+
    Ukr(' EOF=');
  if At.IsEOF then Result:=Result+Ukr('так')
  else Result:=Result+Ukr('ні');
end;

function ExecuteCore4Packet(Runtime:TCore4Runtime;
  const Physical:RawByteString):RawByteString;
var
  SourceWords,OneForm,SingleAnswer,AllAnswers:TExactWords;
  Doc:TD2Document;
  Spans:TPhysicalWordSpans;
  I,J,FirstWord,LastWord,FormCount:SizeInt;
  AnswerPhysical:RawByteString;
begin
  if Runtime=nil then
    raise ECore4PacketError.Create(Ukr('пакет не має pinned Core4 runtime'));
  { Це канонічний фізичний T5M, не конкатенація packed bytes.
    Довжина кожного точного слова та D2 рамки зберігаються. }
  { Повна перевірка канонічності та фізичних координат перед D2.
    При пізній синтаксичній відмові не публікуємо результатів. }
  DecodeT5MWithLocations(Physical,SourceWords,Spans);
  try
    Doc:=ParseD2WordsWide(SourceWords);
  except on E:ED2SourceError do
    raise ECore4PacketError.Create(
      Ukr('пакет: синтаксис D2 ')+
      FailureLocation(Physical,Spans,E.WordIndex)+' '+E.Message);
  end;
  try
    FormCount:=Length(Doc.Roots);
    if (FormCount<1) or (FormCount>MaxCore4ChannelForms) then
      raise ECore4PacketError.Create(
        Ukr('кількість фізичних форм поза межею 1..64'));
    SetLength(AllAnswers,FormCount);
    for I:=0 to FormCount-1 do begin
      { WordIndex і EndWordIndexExclusive — 1-based фізичні
        half-open межі з уже перевіреного D2 AST. }
      FirstWord:=Doc.Roots[I].WordIndex-1;
      LastWord:=Doc.Roots[I].EndWordIndexExclusive-1;
      if (FirstWord<0) or (LastWord<=FirstWord) or
         (LastWord>Length(SourceWords)) then
        raise ECore4PacketError.Create(
          Ukr('неприпустимі фізичні межі Core4-пакета'));
      SetLength(OneForm,LastWord-FirstWord);
      for J:=0 to High(OneForm) do
        OneForm[J]:=SourceWords[FirstWord+J];
      try
        { Єдина семантична операція: вже існуючий pinned runtime. }
        AnswerPhysical:=Runtime.ExecutePhysicalCall(EncodeT5M(OneForm));
        DecodeT5M(AnswerPhysical,SingleAnswer);
        if (Length(SingleAnswer)<>1) or
           (EncodeT5M(SingleAnswer)<>AnswerPhysical) then
          raise ECore4PacketError.Create(
            Ukr('форма не повернула один канонічний exact результат'));
        AllAnswers[I]:=SingleAnswer[0];
      except on E:Exception do
        raise ECore4PacketError.Create(
          Ukr('пакет: форма=')+IntToStr(I+1)+Ukr(' початок-')+
          FailureLocation(Physical,Spans,Doc.Roots[I].WordIndex)+
          ' '+E.Message);
      end;
    end;
    { Ніяких часткових виходів: усе складається локально до Result. }
    Result:=EncodeT5M(AllAnswers);
  finally Doc.Free end;
end;

end.
