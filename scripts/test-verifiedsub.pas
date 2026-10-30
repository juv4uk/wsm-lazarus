{ G6.192 — D5:01011 «відняти» через одноразовий контекст: доказ, а не декларація.
  1) ELF побайтово ідентичний і старому шляху BuildVerifiedWideELF,
     і прямому BuildIRWideSubELF на кожній з 7 програм;
  2) ELF реально виконується, фізичний D1 у stdout збігається з
     незалежно закріпленим очікуваним D12/D24;
  3) контекст створюється рівно один раз на програму (лічильник);
  4) п'ять негативних випадків відхиляються на своєму рівні. }
program test_verifiedsub;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix, wsm.t5m, wsm.numericplane,
  wsm.numericsub, wsm.verifiedwidecontext, wsm.verifiedsub, wsm.irwidesub,
  wsm.irwidefront;

var
  Checks: Integer = 0;
  Root: String;
  Contexts: LongInt = 0;

function NowNanos: Int64;
var TV: TTimeVal;
begin
  fpgettimeofday(@TV, nil);
  Result := Int64(TV.tv_sec) * 1000000000 + Int64(TV.tv_usec) * 1000;
end;

{ Медіана в НАНОСЕКУНДАХ; друкуємо і нс, і мс. }
function MedianNs(var S: array of Int64): Double;
var I, J: SizeInt; T: Int64;
begin
  for I := 0 to High(S) - 1 do
    for J := 0 to High(S) - 1 - I do
      if S[J] > S[J + 1] then begin T := S[J]; S[J] := S[J + 1]; S[J + 1] := T; end;
  if Length(S) mod 2 = 1 then
    Result := S[Length(S) div 2]
  else
    Result := (S[Length(S) div 2 - 1] + S[Length(S) div 2]) / 2.0;
end;

procedure Check(Ok: Boolean; const Title: String);
begin
  Inc(Checks);
  if Ok then WriteLn('VS-OK   ', Title)
  else begin
    WriteLn('VS-ЗБІЙ ', Title);
    Halt(1);
  end;
end;

function PackedForm(const Items: array of RawByteString): RawByteString;
var W: TExactWords; I: SizeInt;
begin
  SetLength(W, Length(Items));
  for I := 0 to High(Items) do W[I] := Items[I];
  Result := EncodeT5M(W);
end;

{ Фізична D5:01011(D12,D12) програма: D2-кадр, pinned-голова,
  два точні opaque W12, закриваючий D2. }
function SubProgram(const LeftDec, RightDec: RawByteString): RawByteString;
var L, R: TExplicitNumeric;
begin
  L := ReadNumericPhysical(EncodeNumericDecimal(LeftDec, 12), 12);
  R := ReadNumericPhysical(EncodeNumericDecimal(RightDec, 12), 12);
  Result := PackedForm(['10', '01011', L.ExactBits, R.ExactBits, '01']);
end;

{ Очікуваний stdout — незалежно закріплене десяткове значення,
  закодоване pinned numeric plane у конкретній ширині. }
function ExpectedStdout(const Wanted: RawByteString; Width: SizeInt): RawByteString;
var N: TExplicitNumeric;
begin
  N := ReadNumericPhysical(EncodeNumericDecimal(Wanted, Width), Width);
  Result := PackedForm([N.ExactBits]);
end;

function RunELF(const Image: RawByteString; out Output: RawByteString): Boolean;
var Path, OutPath, ErrPath, Cmd: String; F: TFileStream;
    Status:LongInt; ErrEmpty:Boolean;
begin
  Result := False; Output := '';
  Path := '/tmp/vs-' + IntToStr(GetProcessID) + '-' + IntToStr(Checks) + '.elf';
  OutPath := Path + '.out';
  ErrPath := Path + '.err';
  { Однаковий PID/порядок тестів не повинен успадкувати старі свідки. }
  DeleteFile(OutPath); DeleteFile(ErrPath);
  try
    F := TFileStream.Create(Path, fmCreate);
    try
      if Length(Image) > 0 then F.WriteBuffer(Image[1], Length(Image));
    finally F.Free end;
    if fpChmod(Path, &755) <> 0 then Exit;
    Cmd := '/bin/sh -c ''timeout 10s "' + Path +
           '" > "' + OutPath + '" 2> "' + ErrPath + '"''';
    Status := fpSystem(PChar(Cmd));
    { Shell або native fault може створити .out ПЕРЕД fatal exit.
      Вимагаємо одночасно exit=0, stdout і stderr розміром 0. }
    if (Status <> 0) or (not FileExists(OutPath)) or
       (not FileExists(ErrPath)) then Exit;
    F:=TFileStream.Create(ErrPath,fmOpenRead or fmShareDenyWrite);
    try ErrEmpty:=F.Size=0; finally F.Free end;
    if not ErrEmpty then Exit;
    F := TFileStream.Create(OutPath, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Output, SizeInt(F.Size));
      if F.Size > 0 then F.ReadBuffer(Output[1], F.Size);
    finally F.Free end;
    Result:=True;
  finally
    DeleteFile(Path);
    DeleteFile(OutPath);
    DeleteFile(ErrPath);
  end;
end;

function BuildViaContext(const Prog: RawByteString): RawByteString;
var C: TVerifiedWideContext;
begin
  C := TVerifiedWideContext.Create(Prog, Root);
  try
    Inc(Contexts);
    Result := C.Lower(@LowerVerifiedSub);
  finally C.Free end;
end;

type TCase = record L, R, Wanted: RawByteString; Width: SizeInt; end;

var
  Prog, OldELF, NewELF, DirectELF, OutBytes, WantBytes: RawByteString;
  Cases: array[0..6] of TCase;
  I: Integer;
  C: TVerifiedWideContext;
  OldNs, NewNs: array of Int64;
  T0: Int64; OldMs, NewMs, OldNsMed, NewNsMed: Double;
begin
  if ParamCount < 1 then Halt(64);
  Root := ParamStr(1);

  Cases[0].L := '1';     Cases[0].R := '2';     Cases[0].Wanted := '-1';    Cases[0].Width := 12;
  Cases[1].L := '7';     Cases[1].R := '-7';    Cases[1].Wanted := '14';    Cases[1].Width := 12;
  Cases[2].L := '12';    Cases[2].R := '12';    Cases[2].Wanted := '0';     Cases[2].Width := 12;
  Cases[3].L := '23';    Cases[3].R := '10';    Cases[3].Wanted := '13';    Cases[3].Width := 12;
  Cases[4].L := '-2048'; Cases[4].R := '1';     Cases[4].Wanted := '-2049'; Cases[4].Width := 24;
  Cases[5].L := '2047';  Cases[5].R := '-2048'; Cases[5].Wanted := '4095';  Cases[5].Width := 24;
  Cases[6].L := '-3';    Cases[6].R := '0';     Cases[6].Wanted := '-3';    Cases[6].Width := 12;

  for I := 0 to High(Cases) do begin
    Prog := SubProgram(Cases[I].L, Cases[I].R);
    { Самоперевірка таблиці: закріплена числова драбина має дати саме
      те десяткове значення, яке ми оголосили очікуваним. }
    Check(SubtractNumericPhysical(
            EncodeNumericDecimal(Cases[I].L, 12),
            EncodeNumericDecimal(Cases[I].R, 12), 12) =
          EncodeNumericDecimal(Cases[I].Wanted, Cases[I].Width),
      'відняти(' + Cases[I].L + ',' + Cases[I].R + '): еталон = ' + Cases[I].Wanted);
    { Старий шлях: спільний фронт -> чинний backend (кожен декодує сам). }
    OldELF := BuildVerifiedWideELF(Prog, Root);
    NewELF := BuildViaContext(Prog);
    Check(NewELF = OldELF,
      'відняти(' + Cases[I].L + ',' + Cases[I].R + '): ELF побайтово ідентичний старому шляху');
    DirectELF := BuildIRWideSubELF(Prog, Root);
    Check(NewELF = DirectELF,
      'відняти(' + Cases[I].L + ',' + Cases[I].R + '): збіг і з прямим backend');
    WantBytes := ExpectedStdout(Cases[I].Wanted, Cases[I].Width);
    if RunELF(NewELF, OutBytes) then
      Check(OutBytes = WantBytes,
        'відняти(' + Cases[I].L + ',' + Cases[I].R + '): ELF64 виконався, D1=' +
        Cases[I].Wanted + ' (D' + IntToStr(Cases[I].Width) + ')')
    else
      Check(False, 'відняти(' + Cases[I].L + ',' + Cases[I].R + '): ELF64 не запустився');
  end;

  { Кожна програма — СВІЙ контекст; жодного перенесення IR між ними. }
  Check(Contexts = Length(Cases), 'контекст створено рівно по одному на програму');

  { Негативні випадки. }
  Prog := SubProgram('1', '2');
  try
    NewELF := BuildViaContext(Prog + #0);
    Check(False, 'неканонічний T5M прийнято');
  except
    on E: Exception do Check(True, 'відмова: неканонічний T5M');
  end;

  try
    NewELF := BuildViaContext(PackedForm(['10', '01000', '0', '0', '01']));
    Check(False, 'чужа pinned-голова D5:01000 прийнята віднімання-нижнім рівнем');
  except
    on E: EVerifiedSubError do Check(True, 'відмова нижнього рівня: чужа pinned-голова');
  end;

  try
    C := TVerifiedWideContext.Create(Prog, Root + '/немає');
    try C.Lower(@LowerVerifiedSub); finally C.Free end;
    Check(False, 'недоступні pinned-таблиці прийнято');
  except
    on E: Exception do Check(True, 'відмова: pinned-таблиці недоступні');
  end;

  { Обірваний кадр: програма без закриваючого D2. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '01011', '0', '0']));
    Check(False, 'обірваний D2-кадр прийнято');
  except
    on E: Exception do Check(True, 'відмова: обірваний D2-кадр');
  end;

  { D1 замість D12: ширина сама по собі не є числовим допуском. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '01011', '1',
      ReadNumericPhysical(EncodeNumericDecimal('1', 12), 12).ExactBits, '01']));
    Check(False, 'D1-операнд прийнято як D12');
  except
    on E: EVerifiedSubError do Check(True, 'відмова нижнього рівня: D1-операнд не є D12');
  end;

  { Два реальні host executable-негативи: обидва створюють stdout,
    отже старий "існує .out" тест помилково вважав би їх успішними.
    Ці fixtures НЕ є SENS source і ніколи не йдуть у compiler. }
  Check(not RunELF('#!/bin/sh'+#10+'printf bad'+#10+'exit 7'+#10,
        OutBytes),'виконуваний файл зі stdout та exit=7 відхилено');
  Check(OutBytes='','після exit=7 немає часткового machine stdout');
  Check(not RunELF('#!/bin/sh'+#10+'printf bad'+#10+
        'printf error >&2'+#10+'exit 0'+#10,OutBytes),
        'виконуваний файл зі stdout і stderr відхилено');
  Check(OutBytes='','після stderr немає часткового machine stdout');

  { ВИМІР: старий шлях (фронт + backend, кожен декодує сам) проти нового
    (один контекст + нижній рівень без повторного декодування T5M
    і без повторної побудови WideIR). }
  if (ParamCount = 2) and (ParamStr(2) = '--measure') then begin
    Prog := SubProgram('1', '2');
    WriteLn('VS-ВИМІР повторів=200 програма=відняти(1,2)');
    SetLength(OldNs, 200); SetLength(NewNs, 200);
    for I := 0 to 199 do begin
      T0 := NowNanos; OldELF := BuildVerifiedWideELF(Prog, Root);
      OldNs[I] := NowNanos - T0;
      T0 := NowNanos; NewELF := BuildViaContext(Prog);
      NewNs[I] := NowNanos - T0;
      if NewELF <> OldELF then begin
        WriteLn('VS-ЗБІЙ вимір: ELF розійшлися на повторі ', I);
        Halt(1);
      end;
    end;
    OldNsMed := MedianNs(OldNs); NewNsMed := MedianNs(NewNs);
    OldMs := OldNsMed / 1000000.0; NewMs := NewNsMed / 1000000.0;
    WriteLn(Format('VS-МЕДІАНА-НС старий=%.0f новий=%.0f', [OldNsMed, NewNsMed]));
    WriteLn(Format('VS-ЧАС старий=%.3f мс новий=%.3f мс прискорення=%.3f',
      [OldMs, NewMs, OldMs / NewMs]));
  end;

  WriteLn('VS-PASS checks=', Checks);
end.
