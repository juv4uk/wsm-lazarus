{ G5.26 — суто механічне виконання фізичного пакета у pinned Core4.
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
uses wsm.t5m, wsm.d2source;

function Ukr(const S:UnicodeString):RawByteString;
begin Result:=RawByteString(UTF8Encode(S)) end;

function ExecuteCore4Packet(Runtime:TCore4Runtime;
  const Physical:RawByteString):RawByteString;
var
  SourceWords,OneForm,SingleAnswer,AllAnswers:TExactWords;
  Doc:TD2Document;
  I,J,FirstWord,LastWord,FormCount:SizeInt;
  AnswerPhysical:RawByteString;
begin
  if Runtime=nil then
    raise ECore4PacketError.Create(Ukr('пакет не має pinned Core4 runtime'));
  { Це канонічний фізичний T5M, не конкатенація packed bytes.
    Довжина кожного точного слова та D2 рамки зберігаються. }
  DecodeT5M(Physical,SourceWords);
  Doc:=ParseD2WordsWide(SourceWords);
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
          Ukr('пакет: форма=')+IntToStr(I+1)+
          Ukr(' початок-слово=')+IntToStr(Doc.Roots[I].WordIndex)+
          ' '+E.Message);
      end;
    end;
    { Ніяких часткових виходів: усе складається локально до Result. }
    Result:=EncodeT5M(AllAnswers);
  finally Doc.Free end;
end;

end.
