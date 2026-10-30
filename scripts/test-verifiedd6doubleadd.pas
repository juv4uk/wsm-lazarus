{ G6.210 — D6:001110 «подвійне додавання» через одноразовий
  перевірений контекст: доказ, а не декларація.
  1) ELF побайтово ідентичний і старому шляху BuildVerifiedWideELF,
     і прямому BuildIRDoubleAddELF на кожній з 8 програм;
  2) ELF реально виконується, фізичний D12 у stdout дорівнює значенню
     незалежного host-обчислення (v+1+1);
  3) контекст створюється рівно один раз на програму (лічильник);
  4) сім негативних випадків відхиляються на своєму рівні, зокрема
     pinned, але ЧУЖА D6-голова D6:010100 «остача» на місці зовнішньої
     голови подвійного додавання.

  Кожен літерал тут загорнуто в String(...), а фізичні RawByteString
  операнди — у Str(): інакше FPC 3.2.2 стискає константу до ShortString
  і на етапі компіляції замінює кирилицю на '?'. Це суто косметика
  звіту, жодного впливу на перевірки. }
program test_verifiedd6doubleadd;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Classes, BaseUnix, Unix, wsm.t5m, wsm.numericplane,
  wsm.numericadd, wsm.verifiedwidecontext, wsm.verifiedd6doubleadd,
  wsm.ird6doubleadd, wsm.irwidefront;

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
  if Ok then WriteLn(String('VDA-OK   '), Title)
  else begin
    WriteLn(String('VDA-ЗБІЙ '), Title);
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

{ Точний opaque D12 атом із десяткового значення: pinned numeric plane,
  не саморобне двійкове кодування. }
function Atom12(const Decimal: RawByteString): RawByteString;
begin
  Result := ReadNumericPhysical(EncodeNumericDecimal(Decimal, 12), 12).ExactBits;
end;

{ Фізична вкладена D6:001110(D6:001110(D12)) програма: зовнішній D2-кадр,
  зовнішня pinned-голова, вкладений D2-кадр, внутрішня pinned-голова,
  один точний opaque W12, два закриваючі D2. }
function DoubleAddProgram(const Decimal: RawByteString): RawByteString;
begin
  Result := PackedForm(['10', '001110', '10', '001110', Atom12(Decimal), '01', '01']);
end;

{ НЕЗАЛЕЖНЕ host-обчислення очікуваного результату: два звичайні
  додавання одиниці до LongInt, жодним чином не походить із нового
  unit-а, зі старого backend чи з ELF. }
function ExpectedValue(V: LongInt): LongInt;
begin
  Result := (V + 1) + 1;
end;

function ExpectedStdout(V: LongInt): RawByteString;
begin
  Result := PackedForm([Atom12(IntToStr(V))]);
end;

function RunELF(const Image: RawByteString; out Output: RawByteString): Boolean;
var Path, OutPath, ErrPath, Cmd: String; F: TFileStream;
    Status: LongInt; ErrEmpty: Boolean;
begin
  Result := False; Output := '';
  Path := '/tmp/vda-' + IntToStr(GetProcessID) + '-' + IntToStr(Checks) + '.elf';
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
    F := TFileStream.Create(ErrPath, fmOpenRead or fmShareDenyWrite);
    try ErrEmpty := F.Size = 0; finally F.Free end;
    if not ErrEmpty then Exit;
    F := TFileStream.Create(OutPath, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Output, SizeInt(F.Size));
      if F.Size > 0 then F.ReadBuffer(Output[1], F.Size);
    finally F.Free end;
    Result := True;
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
    Result := C.Lower(@LowerVerifiedD6DoubleAdd);
  finally C.Free end;
end;

var
  Prog, OldELF, NewELF, DirectELF, OutBytes, WantBytes: RawByteString;
  Values: array[0..7] of Integer;
  I, V, Want: Integer;
  C: TVerifiedWideContext;
  OldNs, NewNs: array of Int64;
  T0: Int64; OldMs, NewMs, OldNsMed, NewNsMed: Double;
  Title: String;
begin
  if ParamCount < 1 then Halt(64);
  Root := ParamStr(1);

  { Вісім фізичних програм: обидві межі signed D12 входять явно,
    а 2045 і 2046 лишають проміжний результат усередині D12. }
  Values[0] := -2048; Values[1] := -2046; Values[2] := -5;   Values[3] := 0;
  Values[4] := 1;     Values[5] := 127;   Values[6] := 512;  Values[7] := 2045;

  for I := 0 to High(Values) do begin
    V := Values[I];
    Prog := DoubleAddProgram(IntToStr(V));
    Title := String('подвійне-додавання(') + IntToStr(V) + ')';
    { Старий шлях: спільний фронт -> чинний backend (кожен декодує сам). }
    OldELF := BuildVerifiedWideELF(Prog, Root);
    NewELF := BuildViaContext(Prog);
    Check(NewELF = OldELF,
      Title + String(': ELF побайтово ідентичний старому шляху'));
    DirectELF := BuildIRDoubleAddELF(Prog, Root);
    Check(NewELF = DirectELF,
      Title + String(': збіг і з прямим backend'));
    Want := ExpectedValue(V);
    WantBytes := ExpectedStdout(Want);
    if RunELF(NewELF, OutBytes) then
      Check(OutBytes = WantBytes,
        Title + String(': ELF64 виконався, D12=') + IntToStr(Want))
    else
      Check(False, Title + String(': ELF64 не запустився'));
  end;

  { Кожна програма — СВІЙ контекст; жодного перенесення IR між ними. }
  Check(Contexts = Length(Values),
    String('контекст створено рівно по одному на програму'));

  { Негатив 1: неканонічний T5M. }
  Prog := DoubleAddProgram('5');
  try
    NewELF := BuildViaContext(Prog + #0);
    Check(False, String('неканонічний T5M прийнято'));
  except
    on E: Exception do Check(True, String('відмова: неканонічний T5M'));
  end;

  { Негатив 2: pinned, але ЧУЖА D6-голова D6:010100 «остача» на місці
    зовнішньої голови. Контекст її приймає (вона справді pinned), тому
    відмова мусить прийти саме від профільного нижнього рівня. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '010100', '10', '001110',
      Atom12('1'), '01', '01']));
    Check(False, String('pinned, але чужа D6:010100 зовнішня голова прийнята'));
  except
    on E: EVerifiedD6DoubleAddError do
      Check(True, String('відмова нижнього рівня: зовнішня голова D6:010100 не є подвійним додаванням'));
  end;

  { Негатив 3: чужа pinned-голова у ВКЛАДЕНІЙ позиції (D6:110101 «найменше»). }
  try
    NewELF := BuildViaContext(PackedForm(['10', '001110', '10', '110101',
      Atom12('1'), '01', '01']));
    Check(False, String('pinned, але чужа вкладена голова D6:110101 прийнята'));
  except
    on E: EVerifiedD6DoubleAddError do
      Check(True, String('відмова нижнього рівня: вкладена голова D6:110101 не є подвійним додаванням'));
  end;

  { Негатив 4: обірваний кадр без зовнішнього закриваючого D2. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '001110', '10', '001110',
      Atom12('1'), '01']));
    Check(False, String('обірваний D2-кадр прийнято'));
  except
    on E: Exception do Check(True, String('відмова: обірваний D2-кадр'));
  end;

  { Негатив 5: D1 замість D12 — ширина сама по собі не є допуском. }
  try
    NewELF := BuildViaContext(PackedForm(['10', '001110', '10', '001110',
      '1', '01', '01']));
    Check(False, String('D1-листок прийнято як D12'));
  except
    on E: EVerifiedD6DoubleAddError do
      Check(True, String('відмова нижнього рівня: D1-листок не є D12'));
  end;

  { Негатив 6: числова межа профілю. 2047 + 1 виходить за signed D12,
    тому чинний AddNumericPhysical дає D24, і це мусить бути відхилено,
    а не мовчки звужено. Відмовляє саме НЕЗМІНЕНИЙ числовий plane
    (ENumericPlaneError), тобто жодного власного Wrap12 тут немає. }
  try
    NewELF := BuildViaContext(DoubleAddProgram('2047'));
    Check(False, String('вихід за D12 на першому додаванні прийнято'));
  except
    on E: ENumericPlaneError do
      Check(True, String('відмова нижнього рівня: перше додавання вийшло за D12'));
    on E: EVerifiedD6DoubleAddError do
      Check(True, String('відмова нижнього рівня: перше додавання вийшло за D12'));
  end;

  { Негатив 7: недоступні pinned-таблиці. }
  Prog := DoubleAddProgram('5');
  try
    C := TVerifiedWideContext.Create(Prog, Root + '/немає');
    try C.Lower(@LowerVerifiedD6DoubleAdd); finally C.Free end;
    Check(False, String('недоступні pinned-таблиці прийнято'));
  except
    on E: Exception do Check(True, String('відмова: pinned-таблиці недоступні'));
  end;

  { ВИМІР: старий шлях (фронт + backend, кожен декодує сам) проти нового
    (один контекст + нижній рівень без повторного декодування T5M
    і без повторної побудови WideIR). }
  if (ParamCount = 2) and (ParamStr(2) = '--measure') then begin
    Prog := DoubleAddProgram('1234');
    WriteLn(String('VDA-ВИМІР повторів=200 програма=подвійне-додавання(1234)'));
    SetLength(OldNs, 200); SetLength(NewNs, 200);
    for I := 0 to 199 do begin
      T0 := NowNanos; OldELF := BuildVerifiedWideELF(Prog, Root);
      OldNs[I] := NowNanos - T0;
      T0 := NowNanos; NewELF := BuildViaContext(Prog);
      NewNs[I] := NowNanos - T0;
      if NewELF <> OldELF then begin
        WriteLn(String('VDA-ЗБІЙ вимір: ELF розійшлися на повторі '), I);
        Halt(1);
      end;
    end;
    OldNsMed := MedianNs(OldNs); NewNsMed := MedianNs(NewNs);
    OldMs := OldNsMed / 1000000.0; NewMs := NewNsMed / 1000000.0;
    WriteLn(Format(String('VDA-МЕДІАНА-НС старий=%.0f новий=%.0f'),
      [OldNsMed, NewNsMed]));
    WriteLn(Format(String('VD6-ЧАС старий=%.3f мс новий=%.3f мс прискорення=%.3f'),
      [OldMs, NewMs, OldMs / NewMs]));
  end;

  WriteLn(String('VDA-PASS checks='), Checks);
end.
