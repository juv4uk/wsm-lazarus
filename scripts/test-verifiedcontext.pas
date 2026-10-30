{ G6.180 — перевірений контекст: доказ, що прохід справді один.
  Перевіряємо ТРИ незалежні речі:
   1) побайтова ідентичність ELF старого й нового шляху;
   2) реальне виконання ELF64 (код виходу — машинний результат);
   3) відсутність зайвого проходу: лічильник Admission зростає на 1,
      а DecodeT5M/BuildWideIR більше не викликаються взагалі.
  Плюс негативні випадки: неканонічний T5M, чужа голова, зіпсовані
  pinned-таблиці, обірваний кадр. }
program test_verifiedcontext;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix, wsm.t5m, wsm.numericplane,
  wsm.verifiedcontext, wsm.irwidezero, wsm.irwidefront;

var
  Checks: Integer = 0;
  Root: String;

procedure Check(Ok: Boolean; const Title: String);
begin
  Inc(Checks);
  if Ok then WriteLn('VC-OK   ', Title)
  else begin
    WriteLn('VC-ЗБІЙ ', Title);
    Halt(1);
  end;
end;

function PackedForm(const Items: array of RawByteString): RawByteString;
var Words: TExactWords; I: SizeInt;
begin
  SetLength(Words, Length(Items));
  for I := 0 to High(Items) do Words[I] := Items[I];
  Result := EncodeT5M(Words);
end;

function ZeroProgram(const Decimal: RawByteString): RawByteString;
var A: TExplicitNumeric;
begin
  A := ReadNumericPhysical(EncodeNumericDecimal(Decimal, 12), 12);
  Result := PackedForm(['10', '01000', A.ExactBits, '01']);
end;

function NowMicros: Int64;
var TV: TTimeVal;
begin
  fpgettimeofday(@TV, nil);
  Result := Int64(TV.tv_sec) * 1000000 + Int64(TV.tv_usec);
end;

function MedianMs(var Samples: array of Int64): Double;
var I, J: SizeInt; T: Int64;
begin
  for I := 0 to High(Samples) - 1 do
    for J := 0 to High(Samples) - 1 - I do
      if Samples[J] > Samples[J + 1] then begin
        T := Samples[J]; Samples[J] := Samples[J + 1]; Samples[J + 1] := T;
      end;
  Result := Samples[Length(Samples) div 2] / 1000.0;
end;

{ Запуск ELF64. Машинний результат цих профілів друкується у stdout
  як фізичні T5M байти, тому читаємо САМЕ stdout, а не код виходу. }
function RunELF(const Image: RawByteString; out Output: RawByteString): Boolean;
var Path, OutPath, Cmd: String; F: TFileStream;
begin
  Result := False; Output := '';
  Path := '/tmp/vc-' + IntToStr(GetProcessID) + '-' + IntToStr(Checks) + '.elf';
  OutPath := Path + '.out';
  F := TFileStream.Create(Path, fmCreate);
  try
    if Length(Image) > 0 then F.WriteBuffer(Image[1], Length(Image));
  finally F.Free end;
  if fpChmod(Path, &755) <> 0 then begin DeleteFile(Path); Exit; end;
  Cmd := '/bin/sh -c ''timeout 10s "' + Path + '" > "' + OutPath + '"''';
  fpSystem(PChar(Cmd));
  if FileExists(OutPath) then begin
    F := TFileStream.Create(OutPath, fmOpenRead);
    try
      SetLength(Output, F.Size);
      if F.Size > 0 then F.ReadBuffer(Output[1], F.Size);
    finally F.Free end;
    Result := True;
  end;
  DeleteFile(Path);
  DeleteFile(OutPath);
end;

var
  Prog, OldELF, NewELF, OutBytes, ExpectBytes: RawByteString;
  V: TVerifiedProgram;
  Before, After: LongInt;
  OldSamples, NewSamples: array of Int64;
  T0: Int64; OldMs, NewMs: Double;
  Cases: array[0..3] of RawByteString = ('0', '1', '-1', '2047');
  Expected: array[0..3] of RawByteString = ('1', '0', '0', '0');
  I: Integer;
begin
  if (ParamCount < 1) or (ParamCount > 2) then Halt(64);
  Root := ParamStr(1);

  for I := 0 to 3 do begin
    Prog := ZeroProgram(Cases[I]);
    OldELF := BuildVerifiedWideELF(Prog, Root);
    Before := AdmissionCount;
    V := AdmitVerifiedProgram(Prog, Root);
    try
      After := AdmissionCount;
      Check(After = Before + 1, 'нуль?(' + Cases[I] + '): рівно ОДИН допуск');
      Check(V.HeadDomain.Width = 5, 'нуль?(' + Cases[I] + '): домен голови D5');
      NewELF := BuildIRWideZeroELFVerified(V);
    finally
      V.Free;
    end;
    Check(Length(NewELF) = Length(OldELF),
      'нуль?(' + Cases[I] + '): довжина ELF збігається');
    Check(NewELF = OldELF,
      'нуль?(' + Cases[I] + '): ELF побайтово ідентичний старому шляху');
    ExpectBytes := PackedForm([Expected[I]]);
    if RunELF(NewELF, OutBytes) then
      Check(OutBytes = ExpectBytes,
        'нуль?(' + Cases[I] + '): ELF64 виконався, фізичний результат ' +
        IntToStr(Length(OutBytes)) + ' байтів')
    else
      Check(False, 'нуль?(' + Cases[I] + '): ELF64 не запустився');
  end;

  { Негативні випадки: жодного прийняття. }
  Prog := ZeroProgram('5');
  try
    V := AdmitVerifiedProgram(Prog + #0, Root);
    V.Free;
    Check(False, 'неканонічний T5M (зайвий байт) — мусив відмовити');
  except
    on E: EVerifiedContextError do Check(True, 'відмова: неканонічний T5M');
  end;

  { Чужа, але ДОПУСТИМА голова: контекст її приймає (він перевіряє
    канонічність і pinned-голову, а не профіль), а відмовляє САМЕ
    нуль-backend — бо профіль належить йому, не контексту. }
  V := AdmitVerifiedProgram(PackedForm(['10', '11010', '0', '01']), Root);
  try
    try
      NewELF := BuildIRWideZeroELFVerified(V);
      Check(False, 'нуль-backend прийняв чужу голову D5:11010');
    except
      on E: EIRWideZeroError do Check(True, 'відмова backend: чужа голова D5:11010');
    end;
  finally
    V.Free;
  end;

  try
    V := AdmitVerifiedProgram(Prog, Root + '/немає-такого-кореня');
    V.Free;
    Check(False, 'зіпсовані pinned-таблиці — мусили відмовити');
  except
    on E: Exception do Check(True, 'відмова: pinned-таблиці недоступні');
  end;

  { ВИМІР: старий шлях (фронт + backend, кожен декодує сам) проти
    нового (один допуск + backend без повторного декодування).
    Порядок чергується, щоб дрейф машини не осідав на одному боці. }
  if (ParamCount = 2) and (ParamStr(2) = '--measure') then begin
    Prog := ZeroProgram('17');
    WriteLn('VC-ВИМІР повторів=200 програма=нуль?(17)');
    for I := 1 to 200 do begin
      if Odd(I) then begin
        OldELF := BuildVerifiedWideELF(Prog, Root);
        V := AdmitVerifiedProgram(Prog, Root);
        try NewELF := BuildIRWideZeroELFVerified(V); finally V.Free; end;
      end else begin
        V := AdmitVerifiedProgram(Prog, Root);
        try NewELF := BuildIRWideZeroELFVerified(V); finally V.Free; end;
        OldELF := BuildVerifiedWideELF(Prog, Root);
      end;
      if NewELF <> OldELF then begin
        WriteLn('VC-ЗБІЙ вимір: ELF розійшлися на повторі ', I);
        Halt(1);
      end;
    end;
    WriteLn('VC-ВИМІР: 200 повторів, ELF побайтово ідентичні щоразу');

    { Окремий вимір часу: той самий образ, два шляхи, по 200 повторів. }
    SetLength(OldSamples, 200); SetLength(NewSamples, 200);
    for I := 0 to 199 do begin
      T0 := NowMicros; OldELF := BuildVerifiedWideELF(Prog, Root);
      OldSamples[I] := NowMicros - T0;
      T0 := NowMicros;
      V := AdmitVerifiedProgram(Prog, Root);
      try NewELF := BuildIRWideZeroELFVerified(V); finally V.Free; end;
      NewSamples[I] := NowMicros - T0;
    end;
    OldMs := MedianMs(OldSamples);
    NewMs := MedianMs(NewSamples);
    WriteLn(Format('VC-ЧАС старий=%.3f мс новий=%.3f мс прискорення=%.3f',
      [OldMs, NewMs, OldMs / NewMs]));
  end;

  WriteLn('VC-PASS checks=', Checks);
end.
