{ G6 / #848. Лише host-профілювальник, НЕ новий SENS evaluator.
  Точні фізичні .sens беруться з чинного 16-формового генератора.
  Кожен режим викликає вже існуючі FPC механізми без зміни законів.
  Запитання:
  1) Чому тривалість окремих режимів не слід складати в час компіляції?
  2) Чому W12 не перетворюється на число?
  3) Хто володіє Words/Spans/IR після кожної ітерації?
  4) Чому відмова повинна завершувати профіль замість пропуску форми? }
program test_once_ir_stage_profile;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, wsm.t5m, wsm.physloc, wsm.wideir,
     wsm.wideirguard, wsm.bind;

const
  FormCount = 16;
  Iterations = 64;
type
  TForms = array[1..FormCount] of RawByteString;

function ReadPhysical(const Path: String): RawByteString;
var F: TFileStream; N: Int64;
begin
  Result := '';
  F := TFileStream.Create(Path, fmOpenRead or fmShareDenyWrite);
  try
    N := F.Size;
    if (N < 1) or (N > 65536) then
      raise Exception.Create('фізичний файл порожній або завеликий');
    SetLength(Result, SizeInt(N));
    F.ReadBuffer(Result[1], SizeInt(N));
  finally
    F.Free;
  end;
end;

function FixtureName(I: SizeInt): String;
begin
  if I < 10 then Result := '0' + IntToStr(I) + '.sens'
  else Result := IntToStr(I) + '.sens';
end;

procedure Run;
var
  Mode, Folder: String;
  Forms: TForms;
  Tables: TDomainSet;
  Words: TExactWords;
  Spans: TPhysicalWordSpans;
  IR: TWideIR;
  Stats: TWideIRGuardStats;
  I, J, R, Repeats: SizeInt;
  Calls, Witness: QWord;
  Started, Elapsed: QWord;
begin
  if ParamCount <> 2 then
    raise Exception.Create('виклик: профілювальник <pinned|decode|locations|wideir|guard> <каталог .sens>');
  Mode := ParamStr(1);
  Folder := IncludeTrailingPathDelimiter(ParamStr(2));
  if (Mode <> 'pinned') and (Mode <> 'decode') and
     (Mode <> 'locations') and (Mode <> 'wideir') and (Mode <> 'guard') then
    raise Exception.Create('невідомий режим профілювання');
  for I := 1 to FormCount do begin
    Forms[I] := ReadPhysical(Folder + FixtureName(I));
    for J := 1 to I-1 do
      if Forms[I] = Forms[J] then
        raise Exception.Create('повторна фізична програма у свідках');
  end;
  { Для чотирьох етапів один раз готуємо pinned набір ДО запуску
    мікропрофілю. У режимі pinned кожне завантаження — окреме.
    Root залишається тим самим pinned external/sens, не новим registry. }
  if Mode <> 'pinned' then
    LoadPinnedDomains('external/sens', Tables);
  if Mode = 'pinned' then Repeats := 1
  else Repeats := Iterations;
  Calls := 0;
  Witness := 0;
  Started := GetTickCount64;
  for I := 1 to FormCount do begin
    if Mode = 'guard' then
      BuildWideIR(Forms[I], Tables, IR);
    for R := 1 to Repeats do begin
      if Mode = 'pinned' then begin
        LoadPinnedDomains('external/sens', Tables);
        Witness := Witness + QWord(Length(Tables[3]));
      end else if Mode = 'decode' then begin
        DecodeT5M(Forms[I], Words);
        Witness := Witness + QWord(Length(Words));
      end else if Mode = 'locations' then begin
        DecodeT5MWithLocations(Forms[I], Words, Spans);
        if Length(Words) <> Length(Spans) then
          raise Exception.Create('слова і фізичні адреси розійшлися');
        Witness := Witness + QWord(Length(Spans));
      end else if Mode = 'wideir' then begin
        BuildWideIR(Forms[I], Tables, IR);
        Witness := Witness + QWord(Length(IR.Nodes));
      end else begin
        VerifyWideIRStructure(IR, Stats);
        if Stats.Nodes <> Length(IR.Nodes) then
          raise Exception.Create('невірна статистика перевіреного IR');
        Witness := Witness + QWord(Stats.Nodes);
      end;
      Inc(Calls);
    end;
  end;
  Elapsed := GetTickCount64 - Started;
  if (Calls <> QWord(FormCount) * QWord(Repeats)) or (Witness = 0) then
    raise Exception.Create('неповний профільний прохід');
  { elapsed_ms — грубий внутрішній час. Сирий host-wall ns незалежно
    фіксує Python; ці метрики НЕ рівнозначні CPU/енергії/JIT. }
  Writeln('PROFILE_STAGE_OK mode=', Mode,
          ' forms=', FormCount, ' calls=', Calls,
          ' witness=', Witness, ' elapsed_ms=', Elapsed);
end;

begin
  try
    Run;
  except
    on E: Exception do begin
      Writeln(ErrOutput, 'ПРОФІЛЬ-ВІДМОВА: ', E.Message);
      Halt(2);
    end;
  end;
end.
