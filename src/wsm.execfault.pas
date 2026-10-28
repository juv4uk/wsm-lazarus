{ Фізична діагностика помилки вже злитого двійкового D3-виконавця.
  ЖОДНИХ нових семантичних правил: час і значення виконання визначає
  wsm.binaryexec; точні координати тритів/байтів — wsm.physloc.
  Той самий байт може містити частини КІЛЬКОХ фізичних слів. }
unit wsm.execfault;
{$mode objfpc}{$H+}
interface
uses SysUtils, wsm.binaryexec, wsm.physloc;
type
  ELocatedExecutionFault=class(Exception)
  public
    WordIndex: SizeInt;    { 1-based word/EOF; 0 = немає відомого слова }
    HasPhysicalSpan: Boolean;
    Span: TPhysicalWordSpan; { якщо HasPhysicalSpan, 0-based half-open }
    constructor CreateAt(const Problem: String; AtWord: SizeInt;
      Found: Boolean; const Position: TPhysicalWordSpan);
  end;

function ExecuteWithPhysicalLocation(const Physical: RawByteString;
  Executor: TBinaryExecutor): RawByteString;

implementation
uses wsm.t5m;
constructor ELocatedExecutionFault.CreateAt(const Problem: String;
  AtWord: SizeInt; Found: Boolean; const Position: TPhysicalWordSpan);
begin
  inherited Create(Problem);
  WordIndex:=AtWord;
  HasPhysicalSpan:=Found;
  Span:=Position;
end;

function ExecuteWithPhysicalLocation(const Physical: RawByteString;
  Executor: TBinaryExecutor): RawByteString;
var
  Words: TExactWords;
  Spans: TPhysicalWordSpans;
  Where: TPhysicalWordSpan;
  Found: Boolean;
begin
  if Executor=nil then
    raise ELocatedExecutionFault.CreateAt(
      #$D0#$B2#$D1#$96#$D0#$B4#$D1#$81#$D1#$83#$D1#$82#$D0#$BD#$D1#$96#$D0#$B9#$20#$D0#$BD#$D0#$B0#$D1#$82#$D0#$B8#$D0#$B2#$D0#$BD#$D0#$B8#$D0#$B9#$20#$D0#$B4#$D0#$B2#$D1#$96#$D0#$B9#$D0#$BA#$D0#$BE#$D0#$B2#$D0#$B8#$D0#$B9#$20#$D0#$B2#$D0#$B8#$D0#$BA#$D0#$BE#$D0#$BD#$D0#$B0#$D0#$B2#$D0#$B5#$D1#$86#$D1#$8C,
      0,False,Default(TPhysicalWordSpan));
  try
    { На УСПІХУ тільки вже наявний evaluator, зайвого decode немає. }
    Result:=Executor.ExecutePhysical(Physical);
  except
    on Failure:EBinaryExecutionError do begin
      Found:=False;
      Where:=Default(TPhysicalWordSpan);
      { 0 ніколи не маскуємо під нібито точну адресу. Проблеми
        транспорту можуть взагалі не мати слова/тритового місця. }
      if Failure.WordIndex>0 then begin
        try
          { Reuse перевіреного codec+span, а не новий T5M reader. }
          DecodeT5MWithLocations(Physical,Words,Spans);
          Where:=LocatePhysicalWord(Physical,Spans,Failure.WordIndex);
          Found:=True;
        except
          on E:ET5MError do Found:=False;
          on E:EPhysicalLocationError do Found:=False;
        end;
      end;
      raise ELocatedExecutionFault.CreateAt(
        Failure.Message,Failure.WordIndex,Found,Where);
    end;
  end;
end;
end.
