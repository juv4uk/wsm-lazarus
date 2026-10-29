{ G6.53: перевірений приватний EIR1 допускає фізичне виконання
  ТИХ САМИХ байтів .sens чинним D3-виконавцем.
  EIR1 є доказом структури, а НЕ executable IR / lowering / новим
  доменним законом. .lisp не приймається як машинний канон. }
program sensirvykon;
{$mode objfpc}{$H+}{$codepage utf8}

uses SysUtils, Classes, wsm.t5m, wsm.bind, wsm.exactir,
  wsm.exactirwire, wsm.exactirguard, wsm.binaryexec;

const
  MaxWireBytes: Int64 = 16 + 4*MaxExactIRNodes + 46*MaxExactIRNodes;

type EIRExecutionError = class(Exception);

{ Path/ExpectedExtension — borrowed host strings, MaxBytes — межа байтів;
  результат — власний RawByteString рівно з прочитаними фізичними байтами.
  TFileStream існує тільки під час read; жодних текстових проєкцій. }
function ReadLimited(const Path, ExpectedExtension: String;
  MaxBytes: Int64): RawByteString;
var Stream: TFileStream;
begin
  if LowerCase(ExtractFileExt(Path)) <> ExpectedExtension then
    raise EIRExecutionError.Create('потрібен фізичний файл '+ExpectedExtension);
  Stream := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size < 1) or (Stream.Size > MaxBytes) then
      raise EIRExecutionError.Create('фізичний файл порожній або завеликий');
    SetLength(Result, SizeInt(Stream.Size));
    Stream.ReadBuffer(Result[1], Length(Result));
  finally Stream.Free; end;
end;

{ Physical — canonical T5M, Wire — приватні EIR1 bytes, IR — власний
  TExactIR з декодера. Таблиці належать тільки синхронному виклику.
  Спершу повне byte-for-byte фізичне походження/guard, ПОТІМ виконавець.
  Єдиний результат — T5M-байти від чинного native D3, без виклику з IR.
  Питання: 1) Чому EIR1 не є мовною програмою?
  2) Навіщо порівнювати з тим самим .sens, а не з іншою проєкцією?
  3) Що захищає від підробленого ParentIndex?
  4) Коли можна друкувати фізичні байти у stdout? }
procedure Run;
var
  Physical, Wire, Answer: RawByteString;
  Tables: TDomainSet;
  IR: TExactIR;
  Stats: TExactIRGuardStats;
  Engine: TBinaryExecutor;
  Sink: THandleStream;
begin
  if (ParamCount <> 3) or
    (ParamStr(1) <> '--перевірити-та-виконати') then
    raise EIRExecutionError.Create(
      'використання: sensirvykon --перевірити-та-виконати вхід.sens вхід.eir');
  Physical := ReadLimited(ParamStr(2), '.sens', MAX_T5M_FILE_BYTES);
  Wire := ReadLimited(ParamStr(3), '.eir', MaxWireBytes);
  LoadPinnedDomains('external/sens', Tables);
  DecodePinnedExactIR(Physical, Tables, Wire, IR);
  VerifyExactIRStructure(IR, Stats);
  if (Stats.Nodes<>Length(IR.Nodes)) or
     (Stats.Roots<>Length(IR.Roots)) or
     (Stats.BoundLeaves<>IR.BoundLeaves) then
    raise EIRExecutionError.Create('порушено фізичну цілісність IR');
  Engine := TBinaryExecutor.Create('external/sens');
  try
    { Важливо: виконується саме Physical, НЕ приватний EIR1.
      Це з'єднує дві чинні механіки, але НЕ виконує lowering/codegen. }
    Answer := Engine.ExecutePhysicalT5M(Physical);
  finally Engine.Free; end;
  if (Length(Answer)<1) or (Length(Answer)>MAX_T5M_FILE_BYTES) then
    raise EIRExecutionError.Create('неприпустима фізична відповідь D3');
  { Жодного stdout до повної верифікації та успіху evaluator. }
  Sink := THandleStream.Create(TextRec(Output).Handle);
  try Sink.WriteBuffer(Answer[1], Length(Answer));
  finally Sink.Free; end;
end;

begin
  try Run;
  except
    on E: EBinaryExecutionError do begin
      WriteLn(StdErr, 'ПЕРЕВІРЕНИЙ-IR-ВІДХИЛЕНО слово=',E.WordIndex,
        ' ',E.Message);
      ExitCode:=2;
    end;
    on E: Exception do begin
      WriteLn(StdErr,'ПЕРЕВІРЕНИЙ-IR-ВІДХИЛЕНО: ',E.Message);
      ExitCode:=2;
    end;
  end;
end.
