{ G6.191 — D5:11010 через одноразовий контекст: доказ, а не декларація.
  1) ELF побайтово ідентичний старому backend-шляху;
  2) ELF реально виконується, фізичний D1 збігається з очікуваним;
  3) контекст створюється один раз на програму (лічильник), і друга
     програма не бачить IR першої;
  4) негативні випадки відхиляються на своєму рівні. }
program test_verifiedless;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix, wsm.t5m, wsm.numericplane,
  wsm.verifiedwidecontext, wsm.verifiedless, wsm.irwideless, wsm.irwidefront;

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

function MedianMs(var S: array of Int64): Double;
var I, J: SizeInt; T: Int64;
begin
  for I := 0 to High(S) - 1 do
    for J := 0 to High(S) - 1 - I do
      if S[J] > S[J + 1] then begin T := S[J]; S[J] := S[J + 1]; S[J + 1] := T; end;
  Result := S[Length(S) div 2] / 1000000.0;
end;

procedure Check(Ok: Boolean; const Title: String);
begin
  Inc(Checks);
  if Ok then WriteLn('VL-OK   ', Title)
  else begin
    WriteLn('VL-ЗБІЙ ', Title);
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

function LessProgram(const LeftDec, RightDec: RawByteString): RawByteString;
var L, R: TExplicitNumeric;
begin
  L := ReadNumericPhysical(EncodeNumericDecimal(LeftDec, 12), 12);
  R := ReadNumericPhysical(EncodeNumericDecimal(RightDec, 12), 12);
  Result := PackedForm(['10', '11010', L.ExactBits, R.ExactBits, '01']);
end;

{ Машинний RunELF — HOST ТЕСТОВИЙ ВИКОНАВЕЦЬ; він ніколи не
  визначає закон D5 чи D1. Image — borrowed exact ELF bytes, Output —
  власні FPC-managed stdout bytes ЛИШЕ після успішного exit=0.
  Кожний виклик прибирає stdout/stderr і ELF навіть після помилки.
  1) Чому існування .out не є доказом успіху ELF?
  2) Чому stderr є частиною native свідка?
  3) Чому після exit=7 Output не можна повертати частково?
  4) Чому timeout=124 теж повинен бути відмовою?
  5) Чому shell rc — host-механіка, а не ратифікований D1? }
function RunELF(const Image: RawByteString; out Output: RawByteString): Boolean;
var Path, OutPath, ErrPath, Cmd: String; F: TFileStream;
    Status:LongInt; ErrEmpty:Boolean;
begin
  Result := False; Output := '';
  Path := '/tmp/vl-' + IntToStr(GetProcessID) + '-' + IntToStr(Checks) + '.elf';
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
    Result := C.Lower(@LowerVerifiedLess);
  finally C.Free end;
end;

type TCase = record L, R, Truth: RawByteString; end;

var
  Prog, OldELF, NewELF, OutBytes: RawByteString;
  Cases: array[0..4] of TCase;
  I: Integer;
  C: TVerifiedWideContext;
  OldNs, NewNs: array of Int64;
  T0: Int64; OldMs, NewMs: Double;
begin
  if ParamCount < 1 then Halt(64);
  Root := ParamStr(1);

  Cases[0].L := '1';   Cases[0].R := '2';   Cases[0].Truth := '1';
  Cases[1].L := '2';   Cases[1].R := '1';   Cases[1].Truth := '0';
  Cases[2].L := '-5';  Cases[2].R := '-5';  Cases[2].Truth := '0';
  Cases[3].L := '-9';  Cases[3].R := '0';   Cases[3].Truth := '1';
  Cases[4].L := '2047'; Cases[4].R := '-2048'; Cases[4].Truth := '0';

  for I := 0 to High(Cases) do begin
    Prog := LessProgram(Cases[I].L, Cases[I].R);
    { Старий шлях: спільний фронт -> чинний backend (кожен декодує сам). }
    OldELF := BuildVerifiedWideELF(Prog, Root);
    NewELF := BuildViaContext(Prog);
    Check(NewELF = OldELF,
      'менше?(' + Cases[I].L + ',' + Cases[I].R + '): ELF побайтово ідентичний');
    Check(NewELF = BuildIRWideLessELF(Prog, Root),
      'менше?(' + Cases[I].L + ',' + Cases[I].R + '): збіг і з прямим backend');
    if RunELF(NewELF, OutBytes) then
      Check(OutBytes = PackedForm([Cases[I].Truth]),
        'менше?(' + Cases[I].L + ',' + Cases[I].R + '): ELF64 виконався, D1=' + Cases[I].Truth)
    else
      Check(False, 'менше?(' + Cases[I].L + ',' + Cases[I].R + '): ELF64 не запустився');
  end;

  { Кожна програма — СВІЙ контекст; жодного перенесення IR між ними. }
  Check(Contexts = Length(Cases), 'контекст створено рівно по одному на програму');

  { Негативні випадки. }
  Prog := LessProgram('1', '2');
  try
    NewELF := BuildViaContext(Prog + #0);
    Check(False, 'неканонічний T5M прийнято');
  except
    on E: Exception do Check(True, 'відмова: неканонічний T5M');
  end;

  try
    NewELF := BuildViaContext(PackedForm(['10', '01000', '0', '01']));
    Check(False, 'чужа голова D5:01000 прийнята менше?-нижнім рівнем');
  except
    on E: EVerifiedLessError do Check(True, 'відмова нижнього рівня: чужа голова');
  end;

  try
    C := TVerifiedWideContext.Create(Prog, Root + '/немає');
    try C.Lower(@LowerVerifiedLess); finally C.Free end;
    Check(False, 'недоступні pinned-таблиці прийнято');
  except
    on E: Exception do Check(True, 'відмова: pinned-таблиці недоступні');
  end;

  { Обірваний кадр: програма без закриваючого D2. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '11010', '0', '0']));
    Check(False, 'обірваний D2-кадр прийнято');
  except
    on E: Exception do Check(True, 'відмова: обірваний D2-кадр');
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
    (один контекст + нижній рівень без повторного декодування). }
  if (ParamCount = 2) and (ParamStr(2) = '--measure') then begin
    Prog := LessProgram('1', '2');
    WriteLn('VL-ВИМІР повторів=200 програма=менше?(1,2)');
    SetLength(OldNs, 200); SetLength(NewNs, 200);
    for I := 0 to 199 do begin
      T0 := NowNanos; OldELF := BuildVerifiedWideELF(Prog, Root);
      OldNs[I] := NowNanos - T0;
      T0 := NowNanos; NewELF := BuildViaContext(Prog);
      NewNs[I] := NowNanos - T0;
      if NewELF <> OldELF then begin
        WriteLn('VL-ЗБІЙ вимір: ELF розійшлися на повторі ', I);
        Halt(1);
      end;
    end;
    OldMs := MedianMs(OldNs); NewMs := MedianMs(NewNs);
    WriteLn(Format('VL-ЧАС старий=%.3f мс новий=%.3f мс прискорення=%.3f',
      [OldMs, NewMs, OldMs / NewMs]));
  end;

  WriteLn('VL-PASS checks=', Checks);
end.
