{ G6.200 — D5:10111 «частка» через одноразовий контекст: доказ, а не декларація.
  1) ELF побайтово ідентичний і старому шляху BuildVerifiedWideELF,
     і прямому BuildIRWideQuotELF на кожній з 6 програм;
  2) ELF реально виконується, фізичний D12 у stdout дорівнює 1
     (машинний профіль частки допускає лише рівні ненульові D12);
  3) контекст створюється рівно один раз на програму (лічильник);
  4) сім негативних випадків відхиляються на своєму рівні, зокрема
     ДІЛЕННЯ НА НУЛЬ — і саме там, де його відхиляє чинний backend.

  Кожен літерал тут загорнуто в String(...), а фізичні RawByteString
  операнди — у Str(): інакше FPC 3.2.2 стискає константу до ShortString
  і на етапі компіляції замінює кирилицю на '?'. Це суто косметика
  звіту, жодного впливу на перевірки. }
program test_verifiedquot;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix, wsm.t5m, wsm.numericplane,
  wsm.verifiedwidecontext, wsm.verifiedquot, wsm.irwidequot,
  wsm.irwidefront;

var
  Checks: Integer = 0;
  Root: String;
  Contexts: LongInt = 0;

function Str(const X: RawByteString): String;
begin
  Result := X;
end;

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
  if Ok then WriteLn(String('VQ-OK   '), Title)
  else begin
    WriteLn(String('VQ-ЗБІЙ '), Title);
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

{ Фізична D5:10111(D12,D12) програма: D2-кадр, pinned-голова,
  два точні opaque W12, закриваючий D2. }
function QuotProgram(const LeftDec, RightDec: RawByteString): RawByteString;
var L, R: TExplicitNumeric;
begin
  L := ReadNumericPhysical(EncodeNumericDecimal(LeftDec, 12), 12);
  R := ReadNumericPhysical(EncodeNumericDecimal(RightDec, 12), 12);
  Result := PackedForm(['10', '10111', L.ExactBits, R.ExactBits, '01']);
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
  Path := '/tmp/vq-' + IntToStr(GetProcessID) + '-' + IntToStr(Checks) + '.elf';
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
    Result := C.Lower(@LowerVerifiedQuot);
  finally C.Free end;
end;

{ Чи відхиляє програму чинний backend — потрібно, щоб негативний
  очікуваний результат НЕ був вигаданий новим unit-ом. }
function OldBackendRejects(const Prog: RawByteString): Boolean;
begin
  try
    BuildIRWideQuotELF(Prog, Root);
    Result := False;
  except
    on E: Exception do Result := True;
  end;
end;

type TCase = record L, R, Wanted: RawByteString; Width: SizeInt; end;

var
  Prog, OldELF, NewELF, DirectELF, OutBytes, WantBytes: RawByteString;
  Cases: array[0..5] of TCase;
  I: Integer;
  C: TVerifiedWideContext;
  OldNs, NewNs: array of Int64;
  T0: Int64; OldMs, NewMs, OldNsMed, NewNsMed: Double;
  NewRejected: Boolean;
  Title: String;
begin
  if ParamCount < 1 then Halt(64);
  Root := ParamStr(1);

  { Машинний профіль частки: лише рівні ненульові signed D12,
    тому відповідь завжди 1 — але її рахує CQO/IDIV під час запуску. }
  Cases[0].L := '1';     Cases[0].R := '1';     Cases[0].Wanted := '1'; Cases[0].Width := 12;
  Cases[1].L := '5';     Cases[1].R := '5';     Cases[1].Wanted := '1'; Cases[1].Width := 12;
  Cases[2].L := '-7';    Cases[2].R := '-7';    Cases[2].Wanted := '1'; Cases[2].Width := 12;
  Cases[3].L := '-2048'; Cases[3].R := '-2048'; Cases[3].Wanted := '1'; Cases[3].Width := 12;
  Cases[4].L := '2047';  Cases[4].R := '2047';  Cases[4].Wanted := '1'; Cases[4].Width := 12;
  Cases[5].L := '1234';  Cases[5].R := '1234';  Cases[5].Wanted := '1'; Cases[5].Width := 12;

  for I := 0 to High(Cases) do begin
    Prog := QuotProgram(Cases[I].L, Cases[I].R);
    Title := String('частка(') + Str(Cases[I].L) + ',' + Str(Cases[I].R) + ')';
    { Старий шлях: спільний фронт -> чинний backend (кожен декодує сам). }
    OldELF := BuildVerifiedWideELF(Prog, Root);
    NewELF := BuildViaContext(Prog);
    Check(NewELF = OldELF,
      Title + String(': ELF побайтово ідентичний старому шляху'));
    DirectELF := BuildIRWideQuotELF(Prog, Root);
    Check(NewELF = DirectELF,
      Title + String(': збіг і з прямим backend'));
    WantBytes := ExpectedStdout(Cases[I].Wanted, Cases[I].Width);
    if RunELF(NewELF, OutBytes) then
      Check(OutBytes = WantBytes,
        Title + String(': ELF64 виконався, D12=') + Str(Cases[I].Wanted) +
        String(' (ширина ') + IntToStr(Cases[I].Width) + ')')
    else
      Check(False, Title + String(': ELF64 не запустився'));
  end;

  { Кожна програма — СВІЙ контекст; жодного перенесення IR між ними. }
  Check(Contexts = Length(Cases),
    String('контекст створено рівно по одному на програму'));

  { Негатив 1: неканонічний T5M. }
  Prog := QuotProgram('5', '5');
  try
    NewELF := BuildViaContext(Prog + #0);
    Check(False, String('неканонічний T5M прийнято'));
  except
    on E: Exception do Check(True, String('відмова: неканонічний T5M'));
  end;

  { Негатив 2: чужа pinned-голова. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '01011', '0', '0', '01']));
    Check(False, String('чужа pinned-голова D5:01011 прийнята частка-нижнім рівнем'));
  except
    on E: EVerifiedQuotError do
      Check(True, String('відмова нижнього рівня: чужа pinned-голова'));
  end;

  { Негатив 3: недоступні pinned-таблиці. }
  try
    C := TVerifiedWideContext.Create(Prog, Root + '/немає');
    try C.Lower(@LowerVerifiedQuot); finally C.Free end;
    Check(False, String('недоступні pinned-таблиці прийнято'));
  except
    on E: Exception do Check(True, String('відмова: pinned-таблиці недоступні'));
  end;

  { Негатив 4: обірваний кадр без закриваючого D2. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '10111', '0', '0']));
    Check(False, String('обірваний D2-кадр прийнято'));
  except
    on E: Exception do Check(True, String('відмова: обірваний D2-кадр'));
  end;

  { Негатив 5: D1 замість D12 — ширина сама по собі не є допуском. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '10111', '1',
      ReadNumericPhysical(EncodeNumericDecimal('1', 12), 12).ExactBits, '01']));
    Check(False, String('D1-операнд прийнято як D12'));
  except
    on E: EVerifiedQuotError do
      Check(True, String('відмова нижнього рівня: D1-операнд не є D12'));
  end;

  { Негатив 6: ДІЛЕННЯ НА НУЛЬ. Очікування не вигадане: спершу
    переконуємось, що його відхиляє ЧИННИЙ backend, і лише потім
    вимагаємо такої ж відмови від нового нижнього рівня. }
  Prog := QuotProgram('5', '0');
  Check(OldBackendRejects(Prog),
    String('чинний backend відхиляє ділення на нуль (5,0)'));
  NewRejected := False;
  NewELF := '';
  try
    NewELF := BuildViaContext(Prog);
  except
    on E: Exception do NewRejected := True;
  end;
  Check(NewRejected, String('новий контекст теж відхиляє ділення на нуль (5,0)'));
  Check(NewELF = '',
    String('після відмови ділення на нуль немає жодних байтів ELF'));

  { Негатив 7: нерівні операнди — так само, як у чинному backend. }
  Prog := QuotProgram('5', '3');
  Check(OldBackendRejects(Prog),
    String('чинний backend відхиляє нерівні операнди (5,3)'));
  NewRejected := False;
  try
    NewELF := BuildViaContext(Prog);
  except
    on E: Exception do NewRejected := True;
  end;
  Check(NewRejected, String('новий контекст теж відхиляє нерівні операнди (5,3)'));

  { Два реальні host executable-негативи: обидва створюють stdout,
    отже тест "існує .out" помилково вважав би їх успішними.
    Ці fixtures НЕ є SENS source і ніколи не йдуть у compiler. }
  Check(not RunELF('#!/bin/sh'+#10+'printf bad'+#10+'exit 7'+#10, OutBytes),
    String('виконуваний файл зі stdout та exit=7 відхилено'));
  Check(OutBytes='', String('після exit=7 немає часткового machine stdout'));
  Check(not RunELF('#!/bin/sh'+#10+'printf bad'+#10+
        'printf error >&2'+#10+'exit 0'+#10,OutBytes),
        String('виконуваний файл зі stdout і stderr відхилено'));
  Check(OutBytes='', String('після stderr немає часткового machine stdout'));

  { ВИМІР: старий шлях (фронт + backend, кожен декодує сам) проти нового
    (один контекст + нижній рівень без повторного декодування T5M
    і без повторної побудови WideIR). }
  if (ParamCount = 2) and (ParamStr(2) = '--measure') then begin
    Prog := QuotProgram('5', '5');
    WriteLn(String('VQ-ВИМІР повторів=200 програма=частка(5,5)'));
    SetLength(OldNs, 200); SetLength(NewNs, 200);
    for I := 0 to 199 do begin
      T0 := NowNanos; OldELF := BuildVerifiedWideELF(Prog, Root);
      OldNs[I] := NowNanos - T0;
      T0 := NowNanos; NewELF := BuildViaContext(Prog);
      NewNs[I] := NowNanos - T0;
      if NewELF <> OldELF then begin
        WriteLn(String('VQ-ЗБІЙ вимір: ELF розійшлися на повторі '), I);
        Halt(1);
      end;
    end;
    OldNsMed := MedianNs(OldNs); NewNsMed := MedianNs(NewNs);
    OldMs := OldNsMed / 1000000.0; NewMs := NewNsMed / 1000000.0;
    WriteLn(Format(String('VQ-МЕДІАНА-НС старий=%.0f новий=%.0f'),
      [OldNsMed, NewNsMed]));
    WriteLn(Format(String('VQ-ЧАС старий=%.3f мс новий=%.3f мс прискорення=%.3f'),
      [OldMs, NewMs, OldMs / NewMs]));
  end;

  WriteLn(String('VQ-PASS checks='), Checks);
end.
